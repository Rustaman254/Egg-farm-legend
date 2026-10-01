import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import * as chain from '../blockchain/actions'

// The on-chain write confirms well before the backend's indexer has necessarily caught up and
// rewritten Postgres, so refetch after a short delay rather than racing the indexer.
const REFETCH_DELAY_MS = 2000

function farmQueryKey(wallet: string) {
  return ['farm', wallet] as const
}

export function useFarm(wallet: string | undefined) {
  return useQuery({
    queryKey: farmQueryKey(wallet ?? ''),
    queryFn: () => api.getFarm(wallet!),
    enabled: !!wallet,
    refetchInterval: 30_000, // picks up hunger decay / indexer updates while the tab is open
  })
}

function useFarmMutation(wallet: string | undefined) {
  const queryClient = useQueryClient()
  const invalidate = async () => {
    await new Promise((resolve) => setTimeout(resolve, REFETCH_DELAY_MS))
    await queryClient.invalidateQueries({ queryKey: farmQueryKey(wallet ?? '') })
  }
  return { queryClient, invalidate }
}

export function useFeedCreature(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: (tokenId: number) => chain.feedCreature(tokenId),
    onSuccess: invalidate,
  })
}

export function useLayEgg(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: (tokenId: number) => chain.layEgg(tokenId),
    onSuccess: invalidate,
  })
}

export function useHatchEgg(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: (tokenId: number) => chain.hatchEgg(tokenId),
    onSuccess: invalidate,
  })
}

export function useTendEgg(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: (tokenId: number) => chain.tendEgg(tokenId),
    onSuccess: invalidate,
  })
}

export function useDiscardRottenEgg(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: (tokenId: number) => chain.discardRottenEgg(tokenId),
    onSuccess: invalidate,
  })
}

/** Pays ETH to skip some or all of an egg's remaining incubation timer -- see
 *  blockchain/actions.speedUpHatch and EggNFT.sol's speedUpHatch(). */
export function useSpeedUpHatch(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: ({ tokenId, priceWei }: { tokenId: number; priceWei: bigint }) => chain.speedUpHatch(tokenId, priceWei),
    onSuccess: invalidate,
  })
}

/** Renames a creature (a pure backend/DB update -- Species stays the on-chain type, Nickname is
 *  an app-level label, so no wallet signature/tx needed). */
export function useSetCreatureNickname(wallet: string | undefined) {
  const { queryClient, invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: ({ tokenId, nickname }: { tokenId: number; nickname: string }) => api.setCreatureNickname(wallet!, tokenId, nickname),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['listings'] })
      return invalidate()
    },
  })
}

/** Renames an unhatched egg -- same idea as useSetCreatureNickname. */
export function useSetEggNickname(wallet: string | undefined) {
  const { queryClient, invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: ({ tokenId, nickname }: { tokenId: number; nickname: string }) => api.setEggNickname(wallet!, tokenId, nickname),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['listings'] })
      return invalidate()
    },
  })
}

export function useBreedCreatures(wallet: string | undefined) {
  const { invalidate } = useFarmMutation(wallet)
  return useMutation({
    mutationFn: ({ parent1, parent2 }: { parent1: number; parent2: number }) => chain.breedCreatures(parent1, parent2),
    onSuccess: invalidate,
  })
}
