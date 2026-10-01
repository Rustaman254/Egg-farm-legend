import { API_BASE_URL } from '../config/contracts'
import type {
  AbilityInfo,
  Activity,
  BattleHistoryEntry,
  BattleResult,
  ChallengeSummary,
  DexEntry,
  EggOdds,
  FarmSnapshot,
  FeedPackage,
  GameTask,
  Listing,
  OnlinePlayer,
} from './types'

export class ApiError extends Error {
  statusCode: number

  constructor(statusCode: number, message: string) {
    super(message)
    this.name = 'ApiError'
    this.statusCode = statusCode
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  })
  if (!res.ok) {
    let message = res.statusText
    try {
      const body = (await res.json()) as { error?: string }
      message = body.error ?? message
    } catch {
      // body wasn't JSON; fall back to statusText
    }
    throw new ApiError(res.status, message)
  }
  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

export const api = {
  getFarm: (wallet: string) => request<FarmSnapshot>(`/api/players/${wallet}/farm`),

  recordLogin: (wallet: string) => request<void>(`/api/players/${wallet}/login`, { method: 'POST', body: '{}' }),

  listTasks: (wallet: string) => request<GameTask[]>(`/api/tasks/${wallet}`),

  claimTask: (wallet: string, taskId: string) =>
    request<{ txHash: string }>(`/api/tasks/${wallet}/${taskId}/claim`, { method: 'POST', body: '{}' }),

  createTask: (input: {
    creatorAddress: string
    title: string
    description: string
    checkType: 'token_balance' | 'token_received' | 'view_function' | 'named_event' | 'contract_event'
    contractAddress: string
    thresholdWei?: string
    functionSignature?: string
    outputType?: string
    eventSignature?: string
    walletTopicIndex?: number
    targetCount: number
    rewardFeedWhole: number
    durationDays: number
  }) => request<{ taskId: string }>('/api/tasks/create', { method: 'POST', body: JSON.stringify(input) }),

  previewEggOdds: (happiness: number) => request<EggOdds>(`/api/eggs/preview?happiness=${happiness}`),

  listMarketplaceListings: (kind?: 'egg' | 'creature') =>
    request<Listing[]>(`/api/marketplace/listings${kind ? `?kind=${kind}` : ''}`),

  myListings: (seller: string, kind?: 'egg' | 'creature') =>
    request<Listing[]>(`/api/marketplace/listings?seller=${seller}${kind ? `&kind=${kind}` : ''}`),

  topEarners: () => request<Array<{ wallet: string; sales: number; totalWei: string }>>('/api/leaderboard/top-earners'),

  topBattlers: () => request<Array<{ wallet: string; wins: number; total: number }>>('/api/leaderboard/top-battlers'),

  getDex: (wallet: string) => request<DexEntry[]>(`/api/players/${wallet}/dex`),

  fightBattle: (wallet: string, creatureTokenId: number) =>
    request<BattleResult>(`/api/players/${wallet}/battles`, {
      method: 'POST',
      body: JSON.stringify({ creatureTokenId }),
    }),

  listBattles: (wallet: string) => request<BattleHistoryEntry[]>(`/api/players/${wallet}/battles`),

  activity: (wallet: string) => request<Activity>(`/api/players/${wallet}/activity`),

  arenaHeartbeat: (wallet: string) => request<{ status: string }>(`/api/players/${wallet}/arena/heartbeat`, { method: 'POST', body: '{}' }),

  arenaOnline: () => request<OnlinePlayer[]>('/api/arena/online'),

  openChallenges: () => request<ChallengeSummary[]>('/api/arena/challenges'),

  myChallenges: (wallet: string) => request<ChallengeSummary[]>(`/api/players/${wallet}/challenges`),

  incomingChallenges: (wallet: string) => request<ChallengeSummary[]>(`/api/players/${wallet}/challenges/incoming`),

  createChallenge: (wallet: string, creatureTokenId: number, opts?: { challengedWallet?: string; wagerWei?: string }) =>
    request<ChallengeSummary>(`/api/players/${wallet}/challenges`, {
      method: 'POST',
      body: JSON.stringify({
        creatureTokenId,
        challengedWallet: opts?.challengedWallet ?? '',
        wagerWei: opts?.wagerWei ?? '0',
      }),
    }),

  confirmEscrow: (wallet: string, challengeId: number) =>
    request<ChallengeSummary>(`/api/players/${wallet}/challenges/${challengeId}/confirm-escrow`, { method: 'POST', body: '{}' }),

  acceptChallenge: (wallet: string, challengeId: number, creatureTokenId: number) =>
    request<BattleResult>(`/api/players/${wallet}/challenges/${challengeId}/accept`, {
      method: 'POST',
      body: JSON.stringify({ creatureTokenId }),
    }),

  cancelChallenge: (wallet: string, challengeId: number) =>
    request<{ status: string }>(`/api/players/${wallet}/challenges/${challengeId}/cancel`, { method: 'POST', body: '{}' }),

  abilityCatalog: () => request<AbilityInfo[]>('/api/abilities'),

  feedShopPackages: () => request<FeedPackage[]>('/api/feed-shop/packages'),

  buyFeedPackage: (buyerAddress: string, packageId: string, txHash: string) =>
    request<{ feedCredited: string }>('/api/feed-shop/purchase', {
      method: 'POST',
      body: JSON.stringify({ buyerAddress, packageId, txHash }),
    }),

  fundTask: (taskId: string, funderAddress: string, txHash: string) =>
    request<{ feedCredited: string }>(`/api/tasks/${taskId}/fund`, {
      method: 'POST',
      body: JSON.stringify({ funderAddress, txHash }),
    }),

  setCreatureNickname: (wallet: string, tokenId: number, nickname: string) =>
    request<{ nickname: string }>(`/api/players/${wallet}/creatures/${tokenId}/nickname`, {
      method: 'POST',
      body: JSON.stringify({ nickname }),
    }),

  setEggNickname: (wallet: string, tokenId: number, nickname: string) =>
    request<{ nickname: string }>(`/api/players/${wallet}/eggs/${tokenId}/nickname`, {
      method: 'POST',
      body: JSON.stringify({ nickname }),
    }),
}
