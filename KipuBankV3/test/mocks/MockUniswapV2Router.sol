// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/KipuBankV3.sol";
import "./MockERC20.sol";

/// @title MockUniswapV2Router - Router de prueba que hace swaps 1:1 hacia USDC.
contract MockUniswapV2Router is IUniswapV2Router02 {
    address public immutable usdc;
    address public immutable weth;

    constructor(address _usdc, address _weth) {
        usdc = _usdc;
        weth = _weth;
    }

    function WETH() external view override returns (address) {
        return weth;
    }

    // Simula swapExactETHForTokens: convierte 1:1 ETH -> USDC (solo para tests)
    function swapExactETHForTokens(
        uint256,
        address[] calldata,
        address to,
        uint256
    ) external payable override returns (uint256[] memory amounts) {
        // En tests asumimos 1 wei ETH = 1 unidad USDC (independiente de decimales)
        uint256 amountIn = msg.value;
        MockERC20(usdc).transfer(to, amountIn);

        amounts = new uint256;
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }

    // Simula swapExactTokensForTokens: 1:1 tokenIn -> USDC
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external override returns (uint256[] memory amounts) {
        address tokenIn = path[0];

        // Tomar los tokens desde el contrato KipuBankV3
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Enviar USDC 1:1
        MockERC20(usdc).transfer(to, amountIn);

        amounts = new uint256;
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
}
