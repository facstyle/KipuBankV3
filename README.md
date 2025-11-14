📘 README.md – KipuBankV3
🏦 KipuBankV3 – Banco DeFi con Swaps Automáticos a USDC

Autor: Felipe A. Cristaldo
Versión: 3.0
Framework: Foundry
Red objetivo: Sepolia (o testnet compatible con Uniswap V2)

📌 Resumen Ejecutivo

KipuBankV3 es la evolución del sistema KipuBank desarrollado a lo largo del curso.
Como mejora principal, esta versión incorpora integración nativa con Uniswap V2, permitiendo que los usuarios depositen ETH, USDC o cualquier ERC-20 compatible con el router, que automáticamente será convertido a USDC, lo que simplifica enormemente la contabilidad interna y aumenta la seguridad del protocolo.

El contrato trabaja exclusivamente con saldo interno expresado en USDC, asegurando consistencia contable y permitiendo aplicar un bankCap centralizado en una única unidad de valor.

A la vez, se conserva toda la lógica fundamental de KipuBankV2:

Control del propietario (owner)

Depósitos y retiros

Protección contra reentrancias

Contadores de operaciones

Manejo explícito de errores personalizados

1️⃣ Objetivos del Proyecto

KipuBankV3 cumple los siguientes puntos requeridos por la consigna:

✔ 1. Manejo de cualquier token ERC-20 swappeable a USDC

Cualquier token que tenga par directo con USDC en Uniswap V2 puede depositarse.

✔ 2. Ejecución automática de swaps

Los depósitos en:

ETH

Otros ERC-20

Son convertidos automáticamente en USDC mediante UniswapV2 Router02.

✔ 3. Consistencia contable internamente en USDC

Esto permite:

Un único mapa de balances

Facilidad de auditoría

Límites (bankCap y retiros) expresados en una sola unidad

✔ 4. Respeto por el bankCap

Ningún depósito incrementará el total del banco por encima del límite.

✔ 5. Preservación de funcionalidades de KipuBankV2

owner

Depósitos / retiros

Balance por usuario

Protección de seguridad

✔ 6. Pruebas en Foundry

El proyecto está diseñado para alcanzar fácilmente +50% de cobertura mediante tests unitarios.

2️⃣ Arquitectura del Contrato
🏗 Componentes principales

El contrato incluye:

USDC como token contable interno
IERC20 public immutable usdc;

Router Uniswap V2
Para ejecutar swaps desde varios tokens hacia USDC.

Token WETH del router
Para routeo de ETH→USDC.

BankCap
Límite máximo permitido de USDC bajo custodia.

Balances internos
Mapeo:
mapping(address => uint256) private _balancesUSDC;

Tokens ERC20 habilitados (allowlist)
Mapa para tokens con pool USDC:
mapping(address => bool) public isSupportedToken;

Contadores de operaciones

depositCount

withdrawalCount

3️⃣ Flujo de Depósitos

Los usuarios pueden depositar:

💠 ETH

→ Se pasa por Uniswap V2 → Se convierte a USDC → Se acredita al usuario.

💠 USDC

→ Se acredita directamente.

💠 Otros ERC-20

→ Verifica si está soportado
→ Hace swap TOKEN → USDC
→ Se acredita al usuario.

4️⃣ Flujo de Retiros

Los retiros se realizan exclusivamente en USDC.
El contrato verifica:

Que el usuario tenga fondos suficientes

Que el contrato posea liquidez suficiente

Que no se trate de reentradas

5️⃣ Seguridad Implementada
🔒 ReentrancyGuard

Previene ataques por reentrancia en depósitos y retiros.

🔒 SafeERC20

Garantiza transferencias seguras, evitando errores silenciosos.

🔒 owner

Las funciones administrativas se restringen al dueño del contrato.

🔒 Permit List (lista blanca de tokens)

Sólo tokens específicos pueden usarse para depósitos (evita ataques con tokens maliciosos).

🔒 amountOutMin=0 solo para entorno académico

En producción debe reemplazarse por slippage seguro.

6️⃣ Instrucciones de Despliegue (Foundry)
1. Instalar dependencias
forge install OpenZeppelin/openzeppelin-contracts

2. Crear archivo de despliegue

/script/DeployKipuBankV3.s.sol

3. Ejecutar deploy
forge script script/DeployKipuBankV3.s.sol --rpc-url $RPC --broadcast --verify

7️⃣ Interacción Básica
💰 Depositar ETH
kipuBankV3.deposit{value: 1 ether}(address(0), 0);

💰 Depositar ERC-20 estándar
token.approve(address(kipuBankV3), amount);
kipuBankV3.deposit(address(token), amount);

💸 Retirar USDC
kipuBankV3.withdraw(500e6); // 500 USDC

8️⃣ Análisis de Amenazas (Threat Model)

Este módulo identifica riesgos reales del protocolo y sus mitigaciones.

🟥 Riesgos Identificados
1. Slippage en swaps

➡ Solución académica: amountOutMin = 0
➡ Producción: debe agregarse slippage controlado.

2. Liquidez insuficiente en el pool

➡ El contrato valida el USDC recibido antes de acreditar.
➡ No se actualizan balances si el swap falla.

3. Reentrancy

➡ Uso de ReentrancyGuard.

4. Tokens maliciosos

➡ Se implementa allowlist isSupportedToken.

5. Aprobaciones infinitas (no seguras)

➡ Se usa approve(0) antes de approve(amount).

6. Oráculo externo NO utilizado

➡ El contrato no depende de oráculos, evitando riesgos de manipulación.

🟩 Madurez y pasos faltantes

Para una versión "production-ready" del protocolo:

Slippage seguro

TWAP oracles para protección contra MEV

Límite por usuario

Sistema de pausas (pausable)

Tests de fuzzing y property-based testing

Cobertura de 90%+

9️⃣ Pruebas y Cobertura

Para alcanzar el 50% mínimo requerido se incluyen tests de:

✔ Depósito ETH
✔ Depósito USDC
✔ Depósito de ERC-20 con swap
✔ Retiro válido
✔ Retiro que falla por falta de balance
✔ Superación del bankCap
✔ Token no soportado
✔ Owner-only functions
✔ Conteo de depósitos y retiros

Ejecutar:

forge test --coverage

🔟 Decisiones de Diseño (Trade-offs)

USDC como única unidad de contabilidad

Simplifica auditoría

Permite bankCap robusto

Evita inconsistencias por decimales distintos

Sin soporte a swaps USDC → otros tokens

Mantiene el protocolo simple

Reduce superficie de ataque

Sin oráculos externos

Evita riesgos de manipulación

UniswapV2 provee el precio de mercado

amountOutMin=0 solo para entorno académico

Máxima compatibilidad

Debe revisarse para producción
