// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    Tests base de KipuBankV3
    ------------------------
    ✔ Compatible con Foundry
    ✔ Usa mocks para USDC y UniswapV2Router
    ✔ Cubre despliegue, depósitos, límites y roles
    ✔ Extensible para llegar al 50% de coverage
*/

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockUniswapV2Router.sol";

contract KipuBankV3Test is Test {
    // ──────────────────────────────────────────────────────────────
    // Variables
    // ──────────────────────────────────────────────────────────────
    address owner;
    address user;
    address attacker;

    MockERC20 usdc;
    MockERC20 tokenA;
    MockUniswapV2Router router;

    KipuBankV3 kipuBank;

    // Bank cap inicial (en USDC, 6 decimales)
    uint256 constant BANK_CAP = 100_000e6;
    uint256 constant WITHDRAW_LIMIT = 2_000e6;

    // Mock address for Chainlink feed (solo placeholder)
    address constant ETH_USD_FEED = address(1111);


    // ──────────────────────────────────────────────────────────────
    // Setup
    // ──────────────────────────────────────────────────────────────
    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        attacker = makeAddr("attacker");

        // Crear tokens mock
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tokenA = new MockERC20("TokenA", "TKA", 18);

        // Crear router mock (simula swaps 1:1)
        router = new MockUniswapV2Router(address(usdc));

        // Deploy del contrato
        kipuBank = new KipuBankV3(
            address(router),
            ETH_USD_FEED,
            address(usdc),
            BANK_CAP,
            WITHDRAW_LIMIT
        );

        // Darle USDC al router mock
        usdc.mint(address(router), 1_000_000e6);
    }

    // ──────────────────────────────────────────────────────────────
    // Tests básicos de despliegue
    // ──────────────────────────────────────────────────────────────
    function testDeployment() public {
        assertEq(kipuBank.bankCap(), BANK_CAP, "BankCap incorrecto");
        assertEq(kipuBank.withdrawalLimit(), WITHDRAW_LIMIT, "WithdrawalLimit incorrecto");
        assertEq(kipuBank.owner(), owner, "Owner incorrecto");
    }

    // ──────────────────────────────────────────────────────────────
    // Test depósito de ETH (convertido a USDC en la lógica final)
    // ──────────────────────────────────────────────────────────────
    function testDepositETH() public {
        // User deposita 1 ETH
        vm.deal(user, 1 ether);

        vm.prank(user);
        kipuBank.depositNative{ value: 1 ether }();

        // Debe haberse acreditado en USDC después del swap
        uint256 bal = kipuBank.balanceOf(user);
        assertGt(bal, 0, "El balance debería aumentar");
    }

    // ──────────────────────────────────────────────────────────────
    // Test depósito directo de USDC
    // ──────────────────────────────────────────────────────────────
    function testDepositUSDC() public {
        usdc.mint(user, 1000e6);

        vm.startPrank(user);
        usdc.approve(address(kipuBank), 1000e6);
        kipuBank.depositUSDC(1000e6);
        vm.stopPrank();

        assertEq(kipuBank.balanceOf(user), 1000e6);
    }

    // ──────────────────────────────────────────────────────────────
    // Test depósito de token arbitrario (TKA)
    // ──────────────────────────────────────────────────────────────
    function testDepositTokenAConvertedToUSDC() public {
        // Registrar token A como soportado
        vm.prank(owner);
        kipuBank.addSupportedToken(address(tokenA));

        // User recibe token A
        tokenA.mint(user, 5 ether);

        // User lo aprueba y deposita
        vm.startPrank(user);
        tokenA.approve(address(kipuBank), 5 ether);
        kipuBank.depositToken(address(tokenA), 5 ether);
        vm.stopPrank();

        // Después del swap debe acreditarse en USDC
        assertGt(kipuBank.balanceOf(user), 0, "El balance USDC debe aumentar");
    }

    // ──────────────────────────────────────────────────────────────
    // Test bankCap
    // ──────────────────────────────────────────────────────────────
    function testBankCapLimit() public {
        usdc.mint(user, 200_000e6); // excede cap

        vm.startPrank(user);
        usdc.approve(address(kipuBank), 200_000e6);
        vm.expectRevert();
        kipuBank.depositUSDC(200_000e6);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────
    // Test retiro
    // ──────────────────────────────────────────────────────────────
    function testWithdrawUSDC() public {
        usdc.mint(user, 5000e6);

        vm.startPrank(user);
        usdc.approve(address(kipuBank), 5000e6);
        kipuBank.depositUSDC(5000e6);

        kipuBank.withdrawUSDC(2000e6);

        assertEq(kipuBank.balanceOf(user), 3000e6);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────
    // Test acceso del owner
    // ──────────────────────────────────────────────────────────────
    function testOwnerOnlyFunctions() public {
        // attacker intenta agregar tokens
        vm.prank(attacker);
        vm.expectRevert();
        kipuBank.addSupportedToken(address(1234));
    }

    // ──────────────────────────────────────────────────────────────
    // Test errores
    // ──────────────────────────────────────────────────────────────
    function testDepositZeroAmountShouldFail() public {
        vm.startPrank(user);
        usdc.mint(user, 100e6);
        usdc.approve(address(kipuBank), 100e6);
        vm.expectRevert();
        kipuBank.depositUSDC(0);
        vm.stopPrank();
    }
}
