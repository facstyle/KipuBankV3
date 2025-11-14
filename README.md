🏦 KipuBankV3 - Banco DeFi con Swaps Automáticos a USDC

**Autor:** Felipe A. Cristaldo  
**Versión:** 3.0  
**Framework:** Foundry  
**Red objetivo:** Sepolia (o testnet compatible con Uniswap V2)

---

## 📌 Resumen Ejecutivo

KipuBankV3 es la evolución del sistema KipuBank desarrollado a lo largo del curso.  
Esta versión integra Uniswap V2 para permitir que los usuarios depositen **ETH, USDC o cualquier ERC-20 compatible con el router**, que automáticamente será convertido a **USDC**, simplificando la contabilidad interna y el control de riesgo.

El contrato trabaja exclusivamente con saldo interno expresado en USDC, manteniendo:

- Control del propietario (`owner`)
- Depósitos y retiros
- Límite global (`bankCapUSDC`)
- Contadores de operaciones
- Manejo explícito de errores personalizados y protección contra reentrancia

---

## 1️⃣ Objetivos del Proyecto

- Manejar cualquier token ERC-20 swappeable a USDC vía UniswapV2.  
- Ejecutar swaps dentro del smart contract al momento del depósito.  
- Preservar la funcionalidad de KipuBankV2 (owner, depósitos, retiros, bank cap).  
- Respetar el **bankCap**: ningún depósito puede exceder la capacidad máxima del banco.  
- Alcanzar un nivel de testeo suficiente usando Foundry.

---

## 2️⃣ Arquitectura del Contrato

Componentes principales:

- `usdc`: token de referencia y unidad única de contabilidad interna.
- `uniswapRouter`: router de UniswapV2 utilizado para los swaps.
- `weth`: token WETH del router.
- `bankCapUSDC`: límite máximo de USDC bajo custodia.
- `totalUSDC`: suma de todos los balances de usuarios.
- `_balancesUSDC[user]`: balance interno por usuario en USDC.
- `isSupportedToken[token]`: mapa de tokens habilitados para depósito (además de ETH y USDC).
- Contadores `depositCount` y `withdrawalCount`.

---

## 3️⃣ Flujo de Depósitos

El usuario llama a:

```solidity
function deposit(address tokenIn, uint256 amount) external payable;
Casos:

tokenIn == address(0) → depósito en ETH

El contrato ejecuta _swapETHForUSDC vía UniswapV2.

tokenIn == address(usdc) → depósito directo en USDC

Se transfiere USDC con _takeUSDCFromUser.

Otro ERC20:

Debe estar habilitado en isSupportedToken[tokenIn].

Se ejecuta _swapERC20ForUSDC vía UniswapV2.

En todos los casos, el resultado final es un monto en USDC (usdcReceived) que se acredita al balance interno del usuario, siempre verificando antes que:

solidity
Copiar código
totalUSDC + usdcReceived <= bankCapUSDC
4️⃣ Flujo de Retiros
Los retiros se realizan exclusivamente en USDC mediante:

solidity
Copiar código
function withdraw(uint256 amountUSDC) external;
Pasos:

Verifica que el usuario tenga saldo suficiente.

Verifica que el contrato tenga liquidez suficiente en USDC.

Actualiza los balances internos y totalUSDC.

Transfiere USDC al usuario utilizando SafeERC20.

5️⃣ Seguridad
ReentrancyGuard en funciones críticas (deposit, withdraw).

SafeERC20 para todas las transferencias de tokens.

Control de acceso mediante Ownable (solo el owner puede cambiar bankCapUSDC y soportar nuevos tokens).

Lista blanca de tokens (setSupportedToken) para evitar depósitos de tokens sin liquidez o maliciosos.

amountOutMin = 0 se mantiene solo en el contexto académico; en producción debe reemplazarse por un cálculo de slippage seguro.

6️⃣ Instrucciones de Despliegue (Foundry)
Instalar dependencias (en el root del proyecto):

bash
Copiar código
forge install OpenZeppelin/openzeppelin-contracts
Configurar variables de entorno (.env):

env
Copiar código
PRIVATE_KEY=0xTU_LLAVE_PRIVADA
UNISWAP_ROUTER=0x...    # Router UniswapV2 de la testnet
USDC_ADDRESS=0x...      # USDC en la red elegida
BANK_CAP_USDC=100000000000  # según decimales de USDC
Ejecutar el script de despliegue:

bash
Copiar código
forge script script/DeployKipuBankV3.s.sol --rpc-url $RPC_URL --broadcast
Guardar la dirección del contrato desplegado y verificarlo en un explorador (Etherscan, Routescan o Blockscout).

7️⃣ Pruebas y Cobertura
Las pruebas están en test/KipuBankV3.t.sol e incluyen:

Depósito de USDC.

Depósito de ERC20 soportado con swap simulado a USDC.

Depósito de ETH.

Respeto del bankCapUSDC.

Retiros válidos e intentos de retiro por encima del balance.

Restricción de funciones onlyOwner.

Errores básicos (monto cero, token no soportado, etc.).

Ejecutar:

bash
Copiar código
forge test
Para ver cobertura:

bash
Copiar código
forge coverage
8️⃣ Análisis de Amenazas (Threat Model)
Riesgos identificados:

Slippage en swaps: en producción debe implementarse amountOutMin con tolerancia razonable y/o TWAPs.

Liquidez insuficiente: el contrato se basa en la liquidez del pool de UniswapV2; el diseño asume pools líquidos para los tokens soportados.

Reentrancy: mitigado con ReentrancyGuard.

Tokens maliciosos: mitigado con allowlist de tokens (setSupportedToken).

Aprobaciones de tokens: el contrato resetea aprobaciones después de usarlas para reducir superficie de ataque.

Pasos faltantes hacia madurez de producción:

Límite de exposición por token y por usuario.

Sistema de pausas de emergencia (Pausable).

Integrar oráculos o TWAP para precios más robustos.

Testing avanzado: fuzzing y property-based testing, cobertura > 90%.

9️⃣ Decisiones de Diseño
Uso de USDC como única unidad de contabilidad → simplifica auditoría y control de riesgo.

No se implementa swap de salida (USDC → otros tokens) para reducir complejidad y superficie de ataque.

La integración con UniswapV2 se limita al flujo necesario para el examen (depósitos → swap → USDC).

Se prioriza claridad de código y seguridad sobre optimizaciones agresivas de gas.

