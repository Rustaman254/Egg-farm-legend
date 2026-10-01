# EggFarm Legends — High-Level Overview

**One line:** A play-to-earn creature-breeding game on Arbitrum where *care is the strategy* —
keep your creatures fed and happy, and they lay better eggs, breed rarer offspring, and win more
battles.

---

## The pitch

Most play-to-earn games reward whoever spends the most. EggFarm Legends rewards whoever shows up.
Every creature is a real on-chain NFT with real hunger that decays every hour. A neglected
Legendary will lose a fight to a well-kept Common. Players earn $FEED by doing daily tasks and
winning battles, spend it keeping their farm alive, and trade the eggs and creatures they raise
for ARB on an open marketplace.

## The core loop

```
 Buy a creature (ARB) ──▶ Do daily tasks / battle ──▶ Earn $FEED
        ▲                                                 │
        │                                                 ▼
 Sell on Marketplace ◀── Hatch eggs ◀── Collect eggs ◀── Feed creature
        (ARB)              (24–72h)       (every 2h)       (hunger + happiness)
```

1. **Buy** — Starter creatures from the shop: Common 0.02 ARB, Uncommon 0.08, Rare 0.25.
2. **Earn** — Daily task board and Battle Arena wins mint $FEED (ERC-20) and Farmer XP.
3. **Feed** — Hunger drops 10% per hour. Feeding burns $FEED and restores happiness. If a
   creature is left at zero hunger for 24 hours, it starves and dies for good.
4. **Collect eggs** — A creature that is fed and happy (≥40 happiness) can lay an egg every 2 hours.
   Higher happiness means better eggs: above 80 happiness gives a 25% chance of a higher-rarity
   egg and only a 5% chance of a rotten one. Below 30, it's 5% and 25%.
5. **Incubate & hatch** — Eggs hatch in 24h (Common) up to 72h (Legendary). They need tending,
   which costs $FEED, or they can spoil. Players can pay a little ARB to speed up hatching.
6. **Breed** — Pair two creatures in the Breeding Lab. The offspring's rarity and species come
   from both parents. Cost doubles with each breed (50 → 15,300 $FEED), up to 7 breeds per
   creature.
7. **Battle** — PvE duels against wild creatures, or PvP challenges with an optional ARB wager.
   The wager is held on-chain in escrow. Stats come from rarity, care, and abilities.
8. **Trade** — The Marketplace holds listings in escrow for both eggs and creatures and takes a
   2.5% platform fee. Newly minted creatures can't be sold until they mature (1h × rarity).

**Rarity tiers:** Common · Uncommon · Rare · Epic · Legendary, with 8 species per tier (40 total).
**Progression:** Farmer levels go from Novice Farmer up to Legendary Farmer. You earn 1 XP for
every $FEED earned.

## Product surfaces

| Surface | Stack | Screens |
|---|---|---|
| **Mobile** | Flutter + BLoC, WalletConnect v2 | Farm, Tasks, Breeding Lab, Marketplace, Inventory, Battle Arena, Collection, Leaderboard, Activity |
| **Web** | React 19 + Vite, wagmi/viem, MetaMask or any injected wallet | Same feature set in the browser |

Your wallet is your account. There are no usernames or passwords, and every write action (feed,
breed, buy, list, hatch) is signed in the player's own wallet.

## Architecture

```
 Mobile / Web app ──REST (fast reads)──▶ Go API ──▶ Postgres ◀── Event indexers ◀── Arbitrum
        │                                                                              ▲
        └─────────────── writes (feed / breed / buy / list / hatch) via wallet ────────┘
```

- **Smart contracts (Solidity, Foundry)** are the source of truth for everything that matters
  to the game.
  - `CreatureNFT`: hunger, happiness, starvation, egg laying, breeding genetics
  - `EggNFT`: incubation, tending, hatching
  - `FeedToken`: the $FEED ERC-20
  - `Marketplace`: escrow trading
  - `BattleEscrow`: PvP wagers
- **Go backend.** A REST API, plus on-chain indexers that mirror events into Postgres so screens
  load instantly. It also runs:
  - a task and reward service that mints $FEED
  - an hourly hunger and starvation sweep
  - the off-chain battle simulator
  - an RNG mirror that previews egg odds without spending gas
- **Postgres + Redis** as a read cache, run locally with `docker compose`.

## Economy at a glance

| Flow | Direction |
|---|---|
| Shop purchases, breeding fee (0.01 ARB), hatch speed-ups | ARB → treasury |
| Marketplace sales (2.5%), PvP wager rake | ARB fee → treasury |
| Daily tasks, battle wins | $FEED minted to player |
| Feeding, egg tending, breeding | $FEED burned |

New $FEED only comes in through engagement, and it leaves through care, so the token is
naturally balanced by how much players actually play.

## Status

- ✅ 6 contracts with a Foundry test suite (~85% line coverage)
- ✅ Go backend: API, indexers, tasks, hunger cron, battles
- ✅ Flutter mobile app and React web app with full feature sets
- ⏳ Live Arbitrum Sepolia deployment (needs a funded deployer key)
- ⏳ On-device wallet validation
- ⏳ Demo video — script in [`video/SCRIPT.md`](video/SCRIPT.md)

**Known tradeoff:** randomness comes from `block.prevrandao` rather than Chainlink VRF. That's
fine for a hackathon demo but needs hardening before mainnet.
