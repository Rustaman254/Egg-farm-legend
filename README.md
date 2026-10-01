# EggFarm Legends 🥚🐔

Play-to-earn creature breeding on **Arbitrum**. Buy a creature → complete tasks to earn $FEED →
feed your creature → collect eggs → hatch or sell them for ARB. Built for the Arbitrum Open
House Buildathon.

## Architecture

```
contracts/   Solidity (Foundry) — EggNFT, CreatureNFT, FeedToken, Marketplace
backend/     Go — REST API, on-chain indexers, hunger cron, task/reward system
mobile/      Flutter — Farm / Tasks / Breeding Lab / Marketplace / Inventory screens
webapp/      React + Vite — same 5 screens for the browser, wallet-extension login
```

The contracts are the source of truth for every game-critical value (hunger, ownership,
breed count, rarity). Postgres is a fast, offline-friendly *read cache* that two backend
indexers keep in sync with on-chain events — the app never has to make a full RPC round trip
just to render a screen, but every write (feed, breed, buy, list) goes straight to the chain
through the player's own wallet.

```
Flutter app ──REST (reads)──▶ Go API ──▶ Postgres ◀── indexers ◀── Arbitrum Sepolia
     │                                                                    ▲
     └──────────────── writes (feed/breed/buy/list) via WalletConnect ───┘
```

## 1. Smart contracts (`contracts/`)

Foundry project, Solidity 0.8.24, OpenZeppelin v5.

| Contract | Responsibility |
|---|---|
| `FeedToken.sol` | ERC-20 $FEED. `mintReward` (backend MINTER_ROLE), `burnFeed` (game contracts) |
| `CreatureNFT.sol` | ERC-721 creature. Feeding, lazy 10%/hour hunger decay, starvation/death, spontaneous egg-laying, breeding genetics |
| `EggNFT.sol` | ERC-721 egg. Laid by `CreatureNFT` (breeding) or the backend (spontaneous), hatch/discard |
| `Marketplace.sol` | Escrow-based listing/buying for both NFT types, 2.5% platform fee |

```bash
cd contracts
forge test              # 43 tests, ~85% line coverage
forge coverage --report summary

# Deploy to Arbitrum Sepolia
cp .env.example .env    # fill in PRIVATE_KEY, ARBITRUM_SEPOLIA_RPC_URL, ARBISCAN_API_KEY
forge script script/Deploy.s.sol:Deploy --rpc-url arbitrum_sepolia --broadcast --verify -vvvv
```

The deploy script wires up the circular contract references and role grants (see
`script/Deploy.s.sol`) and prints all four addresses — copy them into `backend/.env` and into
the Flutter `--dart-define` flags below.

**Known tradeoff:** on-chain randomness (egg outcomes, breeding genetics) uses
`block.prevrandao`/timestamp, not Chainlink VRF. Fine for a hackathon demo; flagged in-code as a
pre-mainnet hardening item.

## 2. Backend (`backend/`)

Go, `chi` router, `pgx` for Postgres, `go-ethereum` for chain reads/writes, no code generation
(ABIs are extracted from the Foundry build output and bound at runtime).

```bash
docker compose up -d postgres redis     # from repo root
cd backend
cp .env.example .env                    # paste in the 4 deployed contract addresses
go run ./cmd/server                     # REST API :8080 + Marketplace + game-state indexers
go run ./cmd/worker                     # Hunger Service cron (hourly checkStarvation sweep)
```

- **REST API** — see `openapi.yaml`. Farm state, task board, marketplace listings, egg-odds
  preview.
- **Marketplace indexer** (`internal/services/marketplace`) and **game-state indexer**
  (`internal/services/gamestate`) both poll `Listed/Sold/Cancelled` and
  `CreatureMinted/CreatureFed/CreatureStarved/EggLaid/EggHatched/Transfer/...` events
  respectively, from a per-contract cursor in `indexer_cursor`.
- **Task Service** (`internal/services/task`) tracks daily task progress (UTC-day-keyed rows,
  so "reset" needs no cron) and mints $FEED rewards on claim.
- **Hunger Service** (`internal/services/hunger`, run via `cmd/worker`) sweeps live creatures
  hourly, calls `checkStarvation` on-chain, and would fire a push notification below 30% hunger
  (currently logs; swap `hunger.Notifier` for a real FCM/APNs sender).
- **RNG package** (`internal/services/rng`) mirrors the contract's egg-outcome math so the app
  can preview odds without spending gas, and so the backend can cross-check emitted events.

```bash
go test ./...     # RNG unit tests; DB/chain-dependent services need integration tests against
                   # a real Postgres + testnet, noted as a follow-up
```

## 3. Mobile app (`mobile/`)

Flutter, BLoC (`flutter_bloc`) + clean-ish layering: `core/` (theme, network, blockchain, DI) →
`data/` (models, repositories) → `blocs/` → `presentation/` (5 screens + shared widgets).

```bash
cd mobile
flutter pub get
flutter analyze
flutter test

cp dart_define.example.json dart_define.json   # already has a real WalletConnect project ID;
                                                 # fill in the 4 contract addresses after deploy
flutter run --dart-define-from-file=dart_define.json
```

Screens: **Farm** (grid of creatures, animated hunger/happiness bars, one-tap Feed/Collect Egg),
**Tasks** (daily board, one-tap claim), **Breeding Lab** (tap two parents, predicted rarity
range, breed), **Marketplace** (browse/buy/list/cancel), **Inventory** (eggs with hatch
countdown, creatures, list-for-sale).

Wallet connection is WalletConnect v2 (`walletconnect_flutter_v2`) — every write (feed, breed,
purchase, list, buy, hatch) is calldata encoded with `web3dart` and signed by the player's own
wallet app; the app never touches a private key. The WalletConnect Cloud project ID is already
set in `dart_define.example.json` (`e25dc196e76047fbbb7faf02bfbcd916`) — project IDs are public
client identifiers, not secrets, so it's safe to commit.

**Still needs an on-device wallet (e.g. MetaMask mobile) to exercise the full connect → approve
→ sign flow** — that loop can't be validated headlessly, so test it on a real device against
Arbitrum Sepolia before demo day.

## 4. Web app (`webapp/`)

React 19 + Vite + TypeScript, Tailwind CSS, `wagmi`/`viem` for wallet + contract calls,
`@tanstack/react-query` for server state, `react-router-dom` for the 5 routes. Same feature set
as the mobile app, same backend, browser-native login.

```bash
cd webapp
npm install
cp .env.example .env    # paste in the 4 deployed contract addresses
npm run dev              # http://localhost:5173
npm run build             # type-checks (tsc -b) then produces dist/
npm run lint
```

**Login/signup is the browser wallet extension** — MetaMask or any other injected EIP-1193
wallet (Rabby, Coinbase Wallet extension, etc.) configured for Arbitrum. There's no separate
username/password: connecting the wallet *is* the account. The app requests the
`arbitrumSepolia` chain (421614) specifically; if the wallet is on a different network the app
shows a "Switch network" prompt (`useSwitchChain`) instead of silently calling the wrong chain.

Every write (feed, breed, purchase, list, buy, hatch, cancel) is built with `wagmi`'s
`writeContract`/`waitForTransactionReceipt` actions against the same ABI fragments as the mobile
app (`src/config/abis.ts`, kept hand-in-sync with `mobile/lib/core/blockchain/contract_abis.dart`)
— the wallet extension's own popup is the only place a transaction is approved.

Routes: `/` Farm, `/tasks` Tasks, `/breeding` Breeding Lab, `/marketplace` Marketplace,
`/inventory` Inventory — top nav on desktop, bottom tab bar on mobile widths.

## Local dev quick start

```bash
git clone <repo> && cd EggFarm_Legend
docker compose up -d postgres redis
cd contracts && forge script script/Deploy.s.sol:Deploy --rpc-url arbitrum_sepolia --broadcast
# copy the 4 printed addresses into backend/.env, webapp/.env, and the mobile --dart-define flags
cd ../backend && go run ./cmd/server &  go run ./cmd/worker &
cd ../webapp && npm install && npm run dev &
cd ../mobile && flutter run --dart-define=... (see above)
```

## Deployment

| Part | Host | Config |
|---|---|---|
| Web app | Vercel | `vercel.json` (services mode, `webapp` service, SPA fallback) |
| API (`cmd/server`) + indexers + arena WebSocket | Render web service, always-on | `render.yaml` → `eggfarm-api` |
| Background jobs (`cmd/worker`) | Render background worker | `render.yaml` → `eggfarm-worker` |
| Postgres 16 | Render Postgres | `render.yaml` → `eggfarm-db` |

The backend isn't on Vercel because it is long-running by design. The API process polls the chain
every 10–15s (marketplace and game-state indexers, wallet watcher), the worker runs six more
loops, and the arena WebSocket hub keeps its connections in memory. Vercel functions suspend
between requests, so all of that would stall.

1. **Backend:** Render dashboard → New → Blueprint → this repo. Fill in the prompted contract
   addresses, `DEPLOY_BLOCK`, `TREASURY_ADDRESS` and `BACKEND_SIGNER_PRIVATE_KEY`. Every deploy
   runs `eggfarm-migrate` (`backend/cmd/migrate`) first, which applies `backend/migrations/*.sql`
   once each.
2. **Web app:** import the repo into Vercel and set the `VITE_*` variables from
   `webapp/.env.example`, with `VITE_API_BASE_URL` set to the `eggfarm-api` URL (e.g.
   `https://eggfarm-api.onrender.com`).
3. **Mobile:** set `API_BASE_URL` in `mobile/dart_define.json` to the same `eggfarm-api` URL.

Keep `eggfarm-api` at **one instance**. The indexers run inside it, so a second instance would
process every event twice.

## What's left for the hackathon submission

- [x] 4 contracts, deployable to Arbitrum Sepolia, 43 passing tests
- [x] Go backend: REST API, 2 event indexers, task/reward system, hunger cron
- [x] Postgres schema + docker-compose for local Postgres/Redis
- [x] Flutter app: all 5 screens, BLoC architecture, offline-friendly reads, WalletConnect wiring
- [x] React web app: all 5 screens, MetaMask/injected-wallet login, wagmi/viem contract calls
- [ ] Actual testnet deployment (needs a funded Arbitrum Sepolia deployer key)
- [ ] On-device WalletConnect validation against a real wallet app (mobile) and a real browser
      wallet extension against Arbitrum Sepolia (webapp)
- [ ] 60s demo video and 5-slide pitch deck (see `docs/pitch/`)
=======
