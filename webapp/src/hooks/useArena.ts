import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { acceptBattleEscrow, cancelBattleEscrow, createBattleEscrow } from '../blockchain/actions'
import { api } from '../api/client'
import type { ChallengeSummary } from '../api/types'

/** Pings presence every 20s while the Battle Arena page is open -- no websocket, just "have we
 *  heard from this wallet in the last 60s" (see the backend's arena_presence table). */
export function useArenaHeartbeat(wallet: string | undefined) {
  useEffect(() => {
    if (!wallet) return
    api.arenaHeartbeat(wallet).catch(() => {})
    const interval = setInterval(() => {
      api.arenaHeartbeat(wallet).catch(() => {})
    }, 20_000)
    return () => clearInterval(interval)
  }, [wallet])
}

export function useOnlinePlayers() {
  return useQuery({
    queryKey: ['arena', 'online'],
    queryFn: api.arenaOnline,
    refetchInterval: 8_000,
  })
}

export function useOpenChallenges() {
  return useQuery({
    queryKey: ['arena', 'challenges'],
    queryFn: api.openChallenges,
    refetchInterval: 5_000,
  })
}

/** Polls the challenger's own posted challenges so they notice (client-side diff on `status`)
 *  when one gets accepted and resolved -- a fallback alongside the "challenge_resolved" websocket
 *  push (see usePlayerSocket) for whatever a dropped connection missed. */
export function useMyChallenges(wallet: string | undefined) {
  return useQuery({
    queryKey: ['challenges', 'mine', wallet ?? ''],
    queryFn: () => api.myChallenges(wallet!),
    enabled: !!wallet,
    refetchInterval: 5_000,
  })
}

/** Direct challenges addressed to this wallet -- a fallback alongside the "challenge_received"
 *  websocket push for whatever arrived while disconnected/on first load. */
export function useIncomingChallenges(wallet: string | undefined) {
  return useQuery({
    queryKey: ['challenges', 'incoming', wallet ?? ''],
    queryFn: () => api.incomingChallenges(wallet!),
    enabled: !!wallet,
    refetchInterval: 10_000,
  })
}

function invalidateArena(queryClient: ReturnType<typeof useQueryClient>, wallet: string | undefined) {
  queryClient.invalidateQueries({ queryKey: ['arena', 'challenges'] })
  queryClient.invalidateQueries({ queryKey: ['challenges', 'mine', wallet ?? ''] })
  queryClient.invalidateQueries({ queryKey: ['challenges', 'incoming', wallet ?? ''] })
  queryClient.invalidateQueries({ queryKey: ['farm', wallet ?? ''] })
  queryClient.invalidateQueries({ queryKey: ['tasks', wallet ?? ''] })
  queryClient.invalidateQueries({ queryKey: ['leaderboard', 'battlers'] })
}

/** Posts a challenge, and for a wagered one also stakes it on BattleEscrow and confirms the
 *  stake with the backend -- three steps behind one call, since a wager isn't "open" to anyone
 *  until it's actually funded on-chain. If the on-chain step fails after the challenge row is
 *  created (wallet rejection, etc.), the row is left as an unfunded challenge the player can
 *  retry funding from "Awaiting Your Stake" (see useMyChallenges + FundChallengeBanner). */
export function useCreateChallenge(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({
      creatureTokenId,
      challengedWallet,
      wagerWei,
    }: {
      creatureTokenId: number
      challengedWallet?: string
      wagerWei?: string
    }) => {
      const challenge = await api.createChallenge(wallet!, creatureTokenId, { challengedWallet, wagerWei })
      if (wagerWei && wagerWei !== '0') {
        await createBattleEscrow(challenge.id, BigInt(wagerWei))
        return api.confirmEscrow(wallet!, challenge.id)
      }
      return challenge
    },
    onSuccess: () => invalidateArena(queryClient, wallet),
  })
}

/** Funds a challenge's escrow after CreateChallenge succeeded but the on-chain step didn't (or
 *  hasn't happened yet) -- the retry path for FundChallengeBanner. */
export function useFundChallenge(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (challenge: ChallengeSummary) => {
      await createBattleEscrow(challenge.id, BigInt(challenge.wagerWei))
      return api.confirmEscrow(wallet!, challenge.id)
    },
    onSuccess: () => invalidateArena(queryClient, wallet),
  })
}

export function useAcceptChallenge(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ challenge, creatureTokenId }: { challenge: ChallengeSummary; creatureTokenId: number }) => {
      if (challenge.wagerWei !== '0') {
        await acceptBattleEscrow(challenge.id, BigInt(challenge.wagerWei))
      }
      return api.acceptChallenge(wallet!, challenge.id, creatureTokenId)
    },
    onSuccess: () => invalidateArena(queryClient, wallet),
  })
}

export function useCancelChallenge(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (challenge: ChallengeSummary) => {
      if (challenge.wagerWei !== '0' && challenge.escrowConfirmed) {
        await cancelBattleEscrow(challenge.id)
      }
      return api.cancelChallenge(wallet!, challenge.id)
    },
    onSuccess: () => invalidateArena(queryClient, wallet),
  })
}
