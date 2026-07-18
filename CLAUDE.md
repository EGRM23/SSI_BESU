# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository extends the **Quorum Dev Quickstart** Besu network with a suite of Solidity smart contracts that model an eVTOL (electric vertical take-off and landing) travel scenario on a local Hyperledger Besu IBFT2/QBFT blockchain.

## Common Commands

### Network lifecycle

```bash
./run.sh       # start all Docker containers (validators, RPC node, explorer, monitoring)
./stop.sh      # stop containers (state preserved)
./resume.sh    # resume a stopped network
./remove.sh    # stop + delete all containers and images
./list.sh      # print service endpoints
```

### Smart contracts

```bash
cd smart_contracts
npm install                              # install dependencies (first time)
npm run compile                          # compile all .sol files → .json artifacts in contracts/
node scripts/deploy_system.js            # deploy all four contracts to the running network
node scripts/smoke_test_full_system.js   # run the end-to-end trip flow
```

`npm run compile` runs `scripts/compile.js`, which uses the bundled `solc` (0.8.10) and writes ABI + bytecode JSON files alongside the `.sol` sources in `contracts/`. The deploy and smoke-test scripts read those JSON artifacts directly — **always recompile after editing any `.sol` file**.

## Architecture

### Network layer (`docker-compose.yml`)

- 4 Besu validator nodes (`validator1–4`) on subnet `172.16.239.11–.14`
- 1 RPC node (`rpcnode`) exposed on `localhost:8545` (HTTP) and `localhost:8546` (WS) — all scripts connect here
- EthSigner proxy on port `18545` (file-based key signing)
- Quorum Explorer on port `25000`, Blockscout on port `26000`
- Prometheus / Grafana / Loki / Promtail for monitoring
- Consensus algorithm is QBFT by default (controlled by `BESU_CONS_ALGO` in `.env`)

### Smart contract layer (`smart_contracts/contracts/`)

Four contracts deployed in dependency order:

| Contract | Role |
|---|---|
| `UserVerification` | Stores which addresses are authorized to fly (`canRide` flag). Issuer address set at construction. |
| `VertiportManagement` | Registers vertiports with runway/parking capacity and enforces availability checks. |
| `EVTOLManagement` | Tracks each eVTOL through a state machine: `PARKED → EXPECTING → IN_USE → PARKED` (plus `MAINTENANCE`). |
| `FlightReservation` | Orchestrator — holds references to the three contracts above and enforces the full trip lifecycle (`REQUESTED → CONFIRMED → IN_PROGRESS → COMPLETED`). Only the `admin` address (the deployer) can call state-changing functions. |

`FlightReservation` is the single entry point for all trip operations. It calls the other three contracts internally; nothing calls `FlightReservation` from another contract.

SSI credential parameters (`userCredential`, `evtolCredential`, `vertiportCredential`) are accepted by the contract interfaces but **not verified on-chain** — verification is mocked (`return true`). They exist as placeholders for a future Aries/Indy integration.

### Scripts layer (`smart_contracts/scripts/`)

- `compile.js` — reads all `.sol` files, compiles with `solc`, writes `<ContractName>.json` artifacts
- `deploy_system.js` — uses `web3` to deploy all four contracts in order, printing addresses; uses hardcoded test account `0x8f2a55...` (Besu dev account)
- `smoke_test_full_system.js` — exercises the full trip flow in 7 steps against already-deployed contracts (addresses must be updated in the script after each deployment)
- `keys.js` — helper for account/key utilities

The deploy account private key (`0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63`) is a well-known Besu dev key with no real value. Do not use it outside this local dev setup.
