import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { payTreasury } from '../blockchain/actions'

export function useFeedShopPackages() {
  return useQuery({
    queryKey: ['feedShop', 'packages'],
    queryFn: api.feedShopPackages,
    staleTime: Infinity,
  })
}

/** Pays the treasury on-chain, then hands the resulting tx hash to the backend to verify and
 *  credit -- the same two-step pattern as fundTask below. */
export function useBuyFeedPackage(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ packageId, priceWei }: { packageId: string; priceWei: string }) => {
      const txHash = await payTreasury(BigInt(priceWei))
      return api.buyFeedPackage(wallet!, packageId, txHash)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['farm', wallet ?? ''] })
    },
  })
}

export function useFundTask() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ taskId, funderAddress, priceWei }: { taskId: string; funderAddress: string; priceWei: string }) => {
      const txHash = await payTreasury(BigInt(priceWei))
      return api.fundTask(taskId, funderAddress, txHash)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tasks'] })
    },
  })
}
