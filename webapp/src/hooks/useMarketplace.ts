import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import * as chain from '../blockchain/actions'
import type { Listing } from '../api/types'

const REFETCH_DELAY_MS = 2000

function listingsQueryKey(kind: 'egg' | 'creature' | undefined) {
  return ['listings', kind ?? 'all'] as const
}

export function useListings(kind: 'egg' | 'creature' | undefined) {
  return useQuery({
    queryKey: listingsQueryKey(kind),
    queryFn: () => api.listMarketplaceListings(kind),
    // The websocket push (marketplace_changed, see usePlayerSocket) invalidates this instantly on
    // any Listed/Sold/Cancelled event -- this poll is only the degrade-gracefully fallback for a
    // dropped/blocked socket.
    refetchInterval: 20_000,
  })
}

/** A seller's own listings, active and historical (sold/cancelled) -- unlike useListings, this
 *  never filters to is_active so a player can see what happened to everything they've ever
 *  listed, not just what's still for sale. */
export function useMyListings(wallet: string | undefined, kind: 'egg' | 'creature' | undefined) {
  return useQuery({
    queryKey: ['listings', 'mine', wallet ?? '', kind ?? 'all'],
    queryFn: () => api.myListings(wallet!, kind),
    enabled: !!wallet,
    refetchInterval: 20_000,
  })
}

function useInvalidateListings() {
  const queryClient = useQueryClient()
  return async () => {
    await new Promise((resolve) => setTimeout(resolve, REFETCH_DELAY_MS))
    // Invalidating the shared ['listings'] prefix cascades to every kind-filtered query too.
    await queryClient.invalidateQueries({ queryKey: ['listings'] })
  }
}

export function useBuyListing() {
  const invalidate = useInvalidateListings()
  return useMutation({
    mutationFn: (listing: Listing) => chain.buyListing(listing.listingId, BigInt(listing.priceWei)),
    onSuccess: invalidate,
  })
}

export function useCancelListing() {
  const invalidate = useInvalidateListings()
  return useMutation({
    mutationFn: (listingId: number) => chain.cancelListing(listingId),
    onSuccess: invalidate,
  })
}

export function useListItem() {
  const invalidate = useInvalidateListings()
  return useMutation({
    mutationFn: ({ isEgg, tokenId, priceArb }: { isEgg: boolean; tokenId: number; priceArb: string }) =>
      chain.listOnMarketplace(isEgg, tokenId, chain.arbToWei(priceArb)),
    onSuccess: invalidate,
  })
}
