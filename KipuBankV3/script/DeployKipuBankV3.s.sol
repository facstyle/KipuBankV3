// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

/// @title DeployKipuBankV3 - Script de despliegue para KipuBankV3 usando Foundry.
/// @notice Lee parámetros de entorno y despliega el contrato en la red configurada.
contract DeployKipuBankV3 is Script {
    function run() external {
        // 🔐 Clave privada para el deployer (debe estar en .env)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 📌 Parámetros del constructor
        address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");
        address usdc = vm.envAddress("USDC_ADDRESS");
        uint256 bankCapUSDC = vm.envUint("BANK_CAP_USDC"); // ej: 100_000e6

        vm.startBroadcast(deployerPrivateKey);

        KipuBankV3 kipu = new KipuBankV3(
            uniswapRouter,
            usdc,
            bankCapUSDC
        );

        console2.log("KipuBankV3 desplegado en:", address(kipu));

        vm.stopBroadcast();
    }
}
