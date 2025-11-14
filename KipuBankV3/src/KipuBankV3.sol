// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Interfaz mínima del router de Uniswap V2 necesaria para KipuBankV3.
interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @title KipuBankV3 - Banco DeFi con integración UniswapV2 y contabilidad en USDC.
/// @author Felipe
/// @notice Permite depositar ETH o cualquier ERC20 con par a USDC en Uniswap V2,
///         swappear internamente a USDC y llevar la contabilidad en ese token.
/// @dev Preserva la lógica principal de KipuBankV2 (owner, depósitos, retiros y bankCap),
///      agregando integración con Uniswap V2. Diseñado para ser usado y testeado con Foundry.
contract KipuBankV3 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                EVENTOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emite un evento cuando un usuario deposita y se le acredita USDC.
    /// @param user Dirección del usuario que deposita.
    /// @param tokenIn Token original que el usuario depositó (address(0) para ETH).
    /// @param amountIn Monto del token original depositado.
    /// @param usdcReceived Monto de USDC acreditado después del swap (o directo si era USDC).
    event Deposit(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 usdcReceived
    );

    /// @notice Emite un evento cuando un usuario retira USDC.
    /// @param user Dirección del usuario que retira.
    /// @param amountUSDC Monto de USDC retirado.
    event Withdrawal(address indexed user, uint256 amountUSDC);

    /// @notice Emite un evento cuando se actualiza el bankCap.
    /// @param newBankCapUSDC Nuevo límite máximo del banco expresado en USDC (decimales de USDC).
    event BankCapUpdated(uint256 newBankCapUSDC);

    /// @notice Emite un evento cuando se habilita o deshabilita un token ERC20 para depósito.
    /// @param token Dirección del token.
    /// @param isSupported Si el token está habilitado o no.
    event SupportedTokenUpdated(address indexed token, bool isSupported);

    /*//////////////////////////////////////////////////////////////
                                ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Se lanza cuando el monto es cero.
    error ErrZeroAmount();

    /// @notice Se lanza cuando se envía ETH pero no se esperaba, o viceversa.
    error ErrInvalidETHValue();

    /// @notice Se lanza cuando un token no está soportado para depósito.
    error ErrTokenNotSupported(address token);

    /// @notice Se lanza cuando el límite del banco (bankCap) sería superado.
    error ErrBankCapExceeded(uint256 currentTotalUSDC, uint256 attemptedIncrease, uint256 bankCapUSDC);

    /// @notice Se lanza cuando el contrato no tiene suficiente USDC para un retiro.
    error ErrInsufficientLiquidity(uint256 requested, uint256 available);

    /// @notice Se lanza cuando el usuario intenta retirar más USDC del que posee.
    error ErrInsufficientUserBalance(uint256 requested, uint256 userBalance);

    /*//////////////////////////////////////////////////////////////
                            VARIABLES DE ESTADO
    //////////////////////////////////////////////////////////////*/

    /// @notice Dirección del token USDC usado como unidad de contabilidad.
    IERC20 public immutable usdc;

    /// @notice Dirección del router de Uniswap V2 utilizado para los swaps.
    IUniswapV2Router02 public immutable uniswapRouter;

    /// @notice Dirección del token WETH asociado al router.
    address public immutable weth;

    /// @notice Límite máximo de USDC que el banco puede custodiar en total (suma de todos los balances de usuarios).
    /// @dev Expresado en unidades de USDC (ej: si USDC tiene 6 decimales, bankCap está en esos mismos decimales).
    uint256 public bankCapUSDC;

    /// @notice Suma de todos los balances de usuarios en USDC.
    uint256 public totalUSDC;

    /// @notice Balance interno de cada usuario en USDC.
    mapping(address => uint256) private _balancesUSDC;

    /// @notice Tokens ERC20 que están habilitados para depósito (además de USDC y ETH).
    /// @dev Esto actúa como allowlist para evitar errores con tokens sin pool a USDC.
    mapping(address => bool) public isSupportedToken;

    /// @notice Contador de depósitos exitosos.
    uint256 public depositCount;

    /// @notice Contador de retiros exitosos.
    uint256 public withdrawalCount;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _usdc Dirección del contrato USDC en la red correspondiente.
    /// @param _uniswapRouter Dirección del router de Uniswap V2.
    /// @param _bankCapUSDC Límite total inicial del banco expresado en USDC.
    constructor(
        address _usdc,
        address _uniswapRouter,
        uint256 _bankCapUSDC
    ) {
        if (_usdc == address(0) || _uniswapRouter == address(0)) {
            revert ErrInvalidETHValue(); // reutilizamos para "dirección inválida"
        }
        if (_bankCapUSDC == 0) revert ErrZeroAmount();

        usdc = IERC20(_usdc);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        weth = IUniswapV2Router02(_uniswapRouter).WETH();
        bankCapUSDC = _bankCapUSDC;

        // Opcional: habilitar USDC como token soportado "directo"
        isSupportedToken[_usdc] = true;
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCIONES PÚBLICAS (USUARIO)
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposita ETH o un token ERC20, que será convertido a USDC y acreditado al usuario.
    /// @dev
    /// - Si `tokenIn == address(0)`, se asume depósito en ETH vía `msg.value`.
    /// - Si `tokenIn == address(usdc)`, se acredita USDC directo sin swap.
    /// - Si es otro ERC20, se swappea TOKEN -> USDC usando Uniswap V2.
    /// @param tokenIn Dirección del token que se deposita (address(0) para ETH).
    /// @param amount Cantidad del token a depositar (ignorada para ETH, se usa msg.value).
    function deposit(address tokenIn, uint256 amount)
        external
        payable
        nonReentrant
    {
        uint256 usdcReceived;

        if (tokenIn == address(0)) {
            // Depósito en ETH
            if (msg.value == 0) revert ErrZeroAmount();
            if (amount != 0) revert ErrInvalidETHValue();

            usdcReceived = _swapETHForUSDC(msg.value);
            _afterDeposit(msg.sender, tokenIn, msg.value, usdcReceived);
        } else {
            // Depósito en ERC20
            if (amount == 0) revert ErrZeroAmount();
            if (msg.value != 0) revert ErrInvalidETHValue();

            if (tokenIn == address(usdc)) {
                // Depósito directo en USDC (sin swap)
                usdcReceived = _takeUSDCFromUser(amount);
                _afterDeposit(msg.sender, tokenIn, amount, usdcReceived);
            } else {
                // Depósito en otro ERC20 que se va a swappear a USDC
                if (!isSupportedToken[tokenIn]) revert ErrTokenNotSupported(tokenIn);
                usdcReceived = _swapERC20ForUSDC(tokenIn, amount);
                _afterDeposit(msg.sender, tokenIn, amount, usdcReceived);
            }
        }
    }

    /// @notice Retira USDC de la cuenta interna del usuario.
    /// @param amountUSDC Monto de USDC a retirar.
    function withdraw(uint256 amountUSDC) external nonReentrant {
        if (amountUSDC == 0) revert ErrZeroAmount();

        uint256 userBalance = _balancesUSDC[msg.sender];
        if (amountUSDC > userBalance) {
            revert ErrInsufficientUserBalance(amountUSDC, userBalance);
        }

        uint256 contractUSDC = usdc.balanceOf(address(this));
        if (amountUSDC > contractUSDC) {
            revert ErrInsufficientLiquidity(amountUSDC, contractUSDC);
        }

        // Effects
        unchecked {
            _balancesUSDC[msg.sender] = userBalance - amountUSDC;
            totalUSDC -= amountUSDC;
            ++withdrawalCount;
        }

        // Interactions
        usdc.safeTransfer(msg.sender, amountUSDC);

        emit Withdrawal(msg.sender, amountUSDC);
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCIONES SOLO OWNER (ADMIN)
    //////////////////////////////////////////////////////////////*/

    /// @notice Actualiza el límite máximo (bankCap) del banco expresado en USDC.
    /// @param newBankCapUSDC Nuevo bankCap en unidades de USDC.
    function setBankCapUSDC(uint256 newBankCapUSDC) external onlyOwner {
        if (newBankCapUSDC == 0) revert ErrZeroAmount();
        bankCapUSDC = newBankCapUSDC;
        emit BankCapUpdated(newBankCapUSDC);
    }

    /// @notice Habilita o deshabilita un token ERC20 para depósito y posterior swap a USDC.
    /// @param token Dirección del token a actualizar.
    /// @param supported true para habilitar, false para deshabilitar.
    function setSupportedToken(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert ErrTokenNotSupported(token);
        isSupportedToken[token] = supported;
        emit SupportedTokenUpdated(token, supported);
    }

    /// @notice Permite al owner rescatar tokens ERC20 que no formen parte de los balances contables (ej. polvo).
    /// @dev No afecta los balances internos en USDC; debe usarse con criterio.
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCIONES DE VISTA (VIEW)
    //////////////////////////////////////////////////////////////*/

    /// @notice Devuelve el balance interno del usuario en USDC.
    /// @param user Dirección del usuario.
    function getBalanceUSDC(address user) external view returns (uint256) {
        return _balancesUSDC[user];
    }

    /// @notice Devuelve el total de USDC contable del banco (suma de balances de usuarios).
    function getTotalUSDC() external view returns (uint256) {
        return totalUSDC;
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCIONES INTERNAS (SWAPS)
    //////////////////////////////////////////////////////////////*/

    /// @dev Lógica común post-depósito: verifica bankCap, actualiza balances y emite evento.
    function _afterDeposit(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 usdcReceived
    ) internal {
        if (usdcReceived == 0) revert ErrZeroAmount();

        // Verificar bankCap antes de impactar estado global
        uint256 newTotal = totalUSDC + usdcReceived;
        if (newTotal > bankCapUSDC) {
            revert ErrBankCapExceeded(totalUSDC, usdcReceived, bankCapUSDC);
        }

        // Effects
        totalUSDC = newTotal;
        unchecked {
            _balancesUSDC[user] += usdcReceived;
            ++depositCount;
        }

        emit Deposit(user, tokenIn, amountIn, usdcReceived);
    }

    /// @dev Toma USDC directamente del usuario (sin usar Uniswap).
    /// @param amountUSDC Monto de USDC que se transfiere desde el usuario.
    /// @return usdcReceived Monto efectivo recibido por el contrato.
    function _takeUSDCFromUser(uint256 amountUSDC) internal returns (uint256 usdcReceived) {
        uint256 beforeBal = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amountUSDC);
        uint256 afterBal = usdc.balanceOf(address(this));
        usdcReceived = afterBal - beforeBal;
    }

    /// @dev Swappea ETH por USDC usando Uniswap V2. El ETH entra vía msg.value.
    /// @param amountETH Monto de ETH recibido.
    /// @return usdcReceived Monto de USDC recibido.
    function _swapETHForUSDC(uint256 amountETH) internal returns (uint256 usdcReceived) {
        address;
        path[0] = weth;
        path[1] = address(usdc);

        uint256 beforeBal = usdc.balanceOf(address(this));

        // amountOutMin = 0 en versión demo (para producción: calcular slippage seguro)
        uniswapRouter.swapExactETHForTokens{value: amountETH}(
            0,
            path,
            address(this),
            block.timestamp + 15 minutes
        );

        uint256 afterBal = usdc.balanceOf(address(this));
        usdcReceived = afterBal - beforeBal;
    }

    /// @dev Swappea un ERC20 arbitrario por USDC usando Uniswap V2.
    /// @param tokenIn Dirección del token que el usuario depositó.
    /// @param amountIn Monto del token a swappear.
    /// @return usdcReceived Monto de USDC recibido.
    function _swapERC20ForUSDC(address tokenIn, uint256 amountIn)
        internal
        returns (uint256 usdcReceived)
    {
        IERC20 token = IERC20(tokenIn);

        // Transferir el token desde el usuario al contrato
        token.safeTransferFrom(msg.sender, address(this), amountIn);

        // Aprobar al router para hacer el swap
        token.safeApprove(address(uniswapRouter), 0);
        token.safeApprove(address(uniswapRouter), amountIn);

        address;
        path[0] = tokenIn;
        path[1] = address(usdc);

        uint256 beforeBal = usdc.balanceOf(address(this));

        // amountOutMin = 0 en versión demo (para producción: calcular slippage seguro)
        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp + 15 minutes
        );

        uint256 afterBal = usdc.balanceOf(address(this));
        usdcReceived = afterBal - beforeBal;

        // Reset de aprobación para minimizar superficie de ataque
        token.safeApprove(address(uniswapRouter), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVER/FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Permite al contrato recibir ETH (por seguridad, por si el router reembolsa ETH).
    receive() external payable {}

    fallback() external payable {}
}

