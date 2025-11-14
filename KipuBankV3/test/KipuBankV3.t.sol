// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockUniswapV2Router.sol";

contract KipuBankV3Test is Test {
    address owner;
    address user;
    address otherUser;

    MockERC20 usdc;
    MockERC20 tokenA;
    MockUniswapV2Router router;
    KipuBankV3 kipu;

    uint256 constant BANK_CAP = 100_000e6; // 100k USDC (6 dec)
    address constant WETH_DUMMY = address(0x1111);

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        otherUser = makeAddr("otherUser");

        // Crear tokens mock
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tokenA = new MockERC20("TokenA", "TKA", 18);

        // Crear router mock y darle USDC para simular liquidez
        router = new MockUniswapV2Router(address(usdc), WETH_DUMMY);
        usdc.mint(address(router), 1_000_000e6);

        // Deploy KipuBankV3
        kipu = new KipuBankV3(address(router), address(usdc), BANK_CAP);

        // Marcar tokenA como soportado
        kipu.setSupportedToken(address(tokenA), true);

        // Fondos iniciales para usuarios
        usdc.mint(user, 10_000e6);
        tokenA.mint(user, 1_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        TESTS DE DESPLIEGUE
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(kipu.bankCapUSDC(), BANK_CAP, "BankCap incorrecto");
        assertEq(kipu.getUSDCAddress(), address(usdc), "USDC incorrecto");
        assertEq(kipu.owner(), owner, "Owner incorrecto");
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: DEPÓSITO USDC DIRECTO
    //////////////////////////////////////////////////////////////*/

    function testDepositUSDC() public {
        vm.startPrank(user);
        usdc.approve(address(kipu), 1_000e6);
        kipu.deposit(address(usdc), 1_000e6);
        vm.stopPrank();

        uint256 bal = kipu.getBalanceUSDC(user);
        assertEq(bal, 1_000e6);
        assertEq(kipu.getTotalUSDC(), 1_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: DEPÓSITO ERC20 + SWAP
    //////////////////////////////////////////////////////////////*/

    function testDepositSupportedTokenSwapsToUSDC() public {
        vm.startPrank(user);
        tokenA.approve(address(kipu), 500e18);
        kipu.deposit(address(tokenA), 500e18);
        vm.stopPrank();

        uint256 bal = kipu.getBalanceUSDC(user);
        assertGt(bal, 0, "El balance en USDC debe aumentar");
    }

    function testDepositUnsupportedTokenReverts() public {
        address unsupported = makeAddr("unsupported");
        vm.startPrank(user);
        vm.expectRevert(); // ErrTokenNotSupported
        kipu.deposit(unsupported, 100e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: DEPÓSITO EN ETH
    //////////////////////////////////////////////////////////////*/

    function testDepositETH() public {
        vm.deal(user, 1 ether);

        vm.startPrank(user);
        kipu.deposit{value: 1 ether}(address(0), 0);
        vm.stopPrank();

        uint256 bal = kipu.getBalanceUSDC(user);
        assertGt(bal, 0, "El balance en USDC debe aumentar tras depositar ETH");
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: BANK CAP
    //////////////////////////////////////////////////////////////*/

    function testBankCapLimit() public {
        // subir bankCap a un valor chico para test
        kipu.setBankCapUSDC(1_000e6);

        usdc.mint(otherUser, 10_000e6);

        vm.startPrank(otherUser);
        usdc.approve(address(kipu), 10_000e6);

        // primer depósito dentro del límite
        kipu.deposit(address(usdc), 500e6);

        // segundo depósito excede bankCap
        vm.expectRevert(); // ErrBankCapExceeded
        kipu.deposit(address(usdc), 600e6);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: RETIROS
    //////////////////////////////////////////////////////////////*/

    function testWithdrawUSDC() public {
        vm.startPrank(user);
        usdc.approve(address(kipu), 2_000e6);
        kipu.deposit(address(usdc), 2_000e6);

        // retirar una parte
        kipu.withdraw(500e6);
        vm.stopPrank();

        uint256 bal = kipu.getBalanceUSDC(user);
        assertEq(bal, 1_500e6);
    }

    function testWithdrawMoreThanBalanceReverts() public {
        vm.startPrank(user);
        usdc.approve(address(kipu), 1_000e6);
        kipu.deposit(address(usdc), 1_000e6);

        vm.expectRevert(); // ErrInsufficientUserBalance
        kipu.withdraw(2_000e6);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: OWNER-ONLY
    //////////////////////////////////////////////////////////////*/

    function testOnlyOwnerCanSetSupportedToken() public {
        address newToken = makeAddr("newToken");
        vm.prank(user);
        vm.expectRevert(); // Ownable: caller is not the owner
        kipu.setSupportedToken(newToken, true);
    }

    function testOwnerCanSetBankCap() public {
        kipu.setBankCapUSDC(50_000e6);
        assertEq(kipu.bankCapUSDC(), 50_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: ERRORES BÁSICOS
    //////////////////////////////////////////////////////////////*/

    function testDepositZeroAmountReverts() public {
        vm.startPrank(user);
        usdc.approve(address(kipu), 1_000e6);
        vm.expectRevert(); // ErrZeroAmount
        kipu.deposit(address(usdc), 0);
        vm.stopPrank();
    }
}
