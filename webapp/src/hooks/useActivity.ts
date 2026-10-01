import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'

export function useActivity(wallet: string | undefined) {
  return useQuery({
    queryKey: ['activity', wallet ?? ''],
    queryFn: () => api.activity(wallet!),
    enabled: !!wallet,
    refetchInterval: 15_000,
  })
}
