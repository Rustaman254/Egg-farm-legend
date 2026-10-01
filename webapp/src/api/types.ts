export interface Creature {
  tokenId: number
  ownerAddress: string
  species: number
  rarity: number
  breedCount: number
  happiness: number
  careScore: number
  hunger: number
  birthTime: string
  lastFedAt: string
  lastEggAt?: string
  isDead: boolean
  abilities?: string[]
  /** Juvenile period: this creature exists as a real NFT (feedable/battleable/breedable) but
   *  CreatureNFT reverts any transfer of it until maturesAt -- so it can't be listed on the
   *  Marketplace until isMature is true. See CreatureNFT.sol's maturationDuration/isMature. */
  maturesAt: string
  isMature: boolean
  /** This individual's own name (Pokemon-nickname-style, e.g. "Prisma") -- species stays the
   *  type ("Chicken"); nickname is what makes it unique. Auto-generated at birth, renameable by
   *  the owner. See config/constants.ts's displayName(). */
  nickname?: string
}

export interface AbilityInfo {
  key: string
  name: string
  description: string
  minRarity: number
  atkMult: number
  defMult: number
  hpMult: number
  lifesteal?: number
  thorns?: number
  berserker?: boolean
  firstStrike?: boolean
}

export interface Egg {
  tokenId: number
  ownerAddress: string
  rarity: number
  species: number
  hatchTime: string
  parent1?: number
  parent2?: number
  isRotten: boolean
  isHatched: boolean
  laidAt: string
  isHatchable: boolean
  /** As of the last hourly Incubation Service sweep -- use estimatedCareLevel() for a smoother
   *  real-time display between sweeps; the on-chain tx is always the actual authority. */
  careLevel: number
  lastCaredAt?: string
  /** See Creature.nickname -- set the moment the egg is laid, so "Chicken (Prisma)" is true from
   *  the egg stage onward, and carried over to the creature it hatches into. */
  nickname?: string
}

export interface FarmSnapshot {
  creatures: Creature[]
  eggs: Egg[]
  feedBalance: string
  /** Live native (ETH/ARB) wallet balance, in wei, read straight from chain on every farm fetch. */
  nativeBalanceWei: string
  xp: number
  farmerLevel: number
}

export type TaskCategory = 'game' | 'ecosystem' | 'partner'

export interface GameTask {
  taskId: string
  title: string
  description: string
  category: TaskCategory
  creatorAddress?: string
  checkType: string
  contractAddress?: string
  expiresAt?: string
  currentCount: number
  targetCount: number
  completedAt?: string
  rewardClaimed: boolean
  rewardFeed: string
  /** Only meaningful when creatorAddress is set (a partner quest): how much $FEED its creator
   *  has funded so far. A claim fails once this drops below rewardFeed -- see handleFundTask. */
  fundedFeed?: string
}

export interface Listing {
  listingId: number
  nftContract: string
  tokenId: number
  kind: 'egg' | 'creature'
  sellerAddress: string
  priceWei: string
  isActive: boolean
  listedAt: string
  soldAt?: string
  rarity?: number
  species?: number
  careScore?: number
  happiness?: number
  buyerAddress?: string
  abilities?: string[]
  /** See Creature.nickname. */
  nickname?: string
  /** Set on exactly one listing in the general browse view -- see api.handleListListings's
   *  markHotListing. Never set on a seller-scoped ("my listings") fetch. */
  hot?: boolean
}

export interface DexEntry {
  species: number
  discovered: boolean
  discoveredAt?: string
  ownedCount: number
}

export interface EggOdds {
  rareUpChancePct: number
  rottenChancePct: number
  sameChancePct: number
}

export interface BattleResult {
  won: boolean
  playerSpecies: number
  playerLevel: number
  playerHp: number
  playerMaxHp: number
  playerAbilities?: string[]
  opponentSpecies: number
  opponentRarity: number
  opponentLevel: number
  opponentHp: number
  opponentMaxHp: number
  opponentAbilities?: string[]
  rounds: number
  log: string[]
  rewardFeed: string
  xpAwarded: number
  txHash?: string
  wagerWei?: string
  wagerWon?: boolean
  escrowResolveTx?: string
}

export interface OnlinePlayer {
  wallet: string
  battling: boolean
}

export interface ChallengeSummary {
  id: number
  challengerWallet: string
  challengerCreatureTokenId: number
  challengerSpecies: number
  challengerRarity: number
  challengerLevel: number
  status: 'open' | 'completed' | 'cancelled' | 'expired'
  challengedWallet?: string
  opponentWallet?: string
  winnerWallet?: string
  rounds?: number
  log?: string[]
  rewardFeed?: string
  wagerWei: string
  escrowConfirmed: boolean
  createdAt: string
  expiresAt: string
  resolvedAt?: string
}

export interface FeedPackage {
  id: string
  kg: number
  feedWhole: number
  priceWei: string
}

export interface WagerActivityEntry {
  challengeId: number
  opponentWallet: string
  wagerWei: string
  won: boolean
  escrowResolveTx?: string
  resolvedAt: string
}

export interface PlatformTxEntry {
  source: 'wager_rake' | 'quest_funding' | 'feed_shop'
  nativeAmountWei: string
  feedAmount: string
  taskId?: string
  createdAt: string
}

export interface WalletEvent {
  id: number
  kind: 'balance_up' | 'balance_down' | 'listing_sold' | 'listing_bought'
  message: string
  amountWei?: string
  createdAt: string
}

export interface Activity {
  battles: BattleHistoryEntry[]
  wagers: WagerActivityEntry[]
  platformTx: PlatformTxEntry[]
  walletEvents: WalletEvent[]
}

export interface WalletEventPayload {
  kind: WalletEvent['kind']
  message: string
  amountWei?: string
  balanceWei?: string
  deltaWei?: string
}

export interface MarketplaceChangedPayload {
  listingId: number
  reason: 'listed' | 'sold' | 'cancelled'
}

/** Envelope for every push over the per-wallet /api/players/{wallet}/ws socket -- arena presence
 *  (challenge_received/resolved), the wallet watcher (wallet_event), and the marketplace indexer
 *  (marketplace_changed, broadcast to every connected wallet, not just one). */
export interface PlayerSocketEvent {
  type: 'challenge_received' | 'challenge_resolved' | 'wallet_event' | 'marketplace_changed'
  payload: ChallengeSummary | { challengeId: number; result: BattleResult } | WalletEventPayload | MarketplaceChangedPayload
}

export interface BattleHistoryEntry {
  creatureTokenId: number
  opponentSpecies: number
  opponentRarity: number
  won: boolean
  rewardFeed: string
  createdAt: string
}

/** A creature has to actually be cared for to lay -- fed recently (hunger > 0) and reasonably
 *  happy (a farmer who lets happiness rot can't just keep cashing in eggs off a miserable
 *  creature). Separate from the happiness-weighted rarity/rotten roll the egg itself gets once
 *  laid (see careDecayPerHour) -- this is the gate on whether laying is possible at all. */
export const MIN_HAPPINESS_TO_LAY = 40

export function canLayEgg(creature: Creature): boolean {
  if (creature.isDead || creature.hunger === 0 || creature.happiness < MIN_HAPPINESS_TO_LAY) return false
  if (!creature.lastEggAt) return true
  const readyAt = new Date(creature.lastEggAt).getTime() + 2 * 60 * 60 * 1000
  return Date.now() >= readyAt
}

export type ConditionLabel = 'Neglected' | 'Poor' | 'Fair' | 'Good' | 'Excellent'

/** A rough "condition" readout for the market -- not a stat, just a legible signal so a buyer can
 *  tell a well-raised creature from a neglected one at a glance (level covers long-run care;
 *  happiness covers whether it's *currently* being looked after). Prices are player-set, but this
 *  is what should shape what a buyer is willing to pay. */
export function conditionLabel(happiness: number, careScore: number): ConditionLabel {
  const level = Math.max(1, Math.min(50, Math.floor(careScore / 20) + 1))
  const score = happiness * 0.6 + Math.min(level, 20) * 2 // level contribution caps out around Lv20
  if (score < 25) return 'Neglected'
  if (score < 45) return 'Poor'
  if (score < 65) return 'Fair'
  if (score < 85) return 'Good'
  return 'Excellent'
}

export const CONDITION_COLORS: Record<ConditionLabel, string> = {
  Neglected: 'var(--color-down)',
  Poor: 'var(--color-warn)',
  Fair: 'var(--color-text-muted)',
  Good: 'var(--color-up)',
  Excellent: 'var(--color-brand-yellow)',
}

export function eggCooldownRemainingMs(creature: Creature): number {
  if (!creature.lastEggAt) return 0
  const readyAt = new Date(creature.lastEggAt).getTime() + 2 * 60 * 60 * 1000
  return Math.max(0, readyAt - Date.now())
}

export function timeUntilHatchMs(egg: Egg): number {
  return Math.max(0, new Date(egg.hatchTime).getTime() - Date.now())
}

/** Ms until a juvenile creature matures (0 once mature) -- see CreatureNFT.sol's isMature/
 *  maturationDuration. A creature can be fed/battled/bred while juvenile, it just can't be
 *  transferred (and therefore not listed on the Marketplace) until this hits 0. */
export function timeUntilMatureMs(creature: Creature): number {
  return Math.max(0, new Date(creature.maturesAt).getTime() - Date.now())
}

export const MIN_CARE_TO_HATCH = 30

/** Mirrors EggNFT.sol's careDecayPerHour: 3 + rarity*2, so rarity 1 -> 5%/hr, rarity 5 -> 13%/hr. */
export function careDecayPerHour(rarity: number): number {
  return 3 + rarity * 2
}

/** Estimates the *current* care level by projecting decay forward from lastCaredAt, since the
 *  backend's cached careLevel is only as fresh as the last hourly Incubation Service sweep. */
export function estimatedCareLevel(egg: Egg): number {
  if (egg.isRotten) return 0
  if (!egg.lastCaredAt) return egg.careLevel
  const elapsedHours = (Date.now() - new Date(egg.lastCaredAt).getTime()) / 3_600_000
  const decayed = Math.floor(elapsedHours * careDecayPerHour(egg.rarity))
  return Math.max(0, 100 - decayed)
}

export function needsCare(egg: Egg): boolean {
  return !egg.isRotten && estimatedCareLevel(egg) < MIN_CARE_TO_HATCH
}
