// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    Script de despliegue para KipuBankV3
    ------------------------------------
    ✔ Compatible con Foundry (forge script)
    ✔ Transmite transacciones usando --broadcast
    ✔ Incluye logs de dirección del contrato
    ✔ Parámetros configurables para Sepolia o cualquier red
*/

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {

    // --- Direcciones reales para SEPOLIA (pueden ajustarse para otra red) ---

    // 🟦 Feed ETH/USD de Chainlink (8 decimales)
    address constant SEPOLIA_CHAINLINK_ETH_USD =
        0x694AA1769357215DE4FAC081bf1f309aDC325306;

    // 🟩 USDC en Sepolia (Circle)
    address constant SEPOLIA_USDC =
        0x07865c6E87B9F70255377e024ace6630C1Eaa37F;

    // 🔵 Router Uniswap V2 (Fork de Sushiswap para Sepolia)
    // Si usás otro router, cambiar aquí
    address constant SEPOLIA_UNISWAPV2_ROUTER =
        0x1B02Da8Cb0d097eB8D57A175b88c7D8b47997506;


    // --- Parámetros configurables ---
    uint256 constant INITIAL_BANK_CAP_USDC = 100_000 * 1e6; // 100k USDC (6 dec)
    uint256 constant INITIAL_WITHDRAWAL_LIMIT_USDC = 2_000 * 1e6; // 2k USDC


    function run() external {
        // 1) Cargar clave privada desde .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2) Iniciar broadcast
        vm.startBroadcast(deployerPrivateKey);

        // 3) Desplegar contrato
        KipuBankV3 kipuBank = new KipuBankV3(
            SEPOLIA_UNISWAPV2_ROUTER,
            SEPOLIA_CHAINLINK_ETH_USD,
            SEPOLIA_USDC,
            INITIAL_BANK_CAP_USDC,
            INITIAL_WITHDRAWAL_LIMIT_USDC
        );

        // 4) Log
        console.log("========================================");
        console.log("🚀 KipuBankV3 desplegado correctamente");
        console.log("📍 Dirección del contrato:", address(kipuBank));
        console.log("========================================");

        // 5) Terminar broadcast
        vm.stopBroadcast();
    }
}

