import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'

export function useDex(wallet: string | undefined) {
  return useQuery({
    queryKey: ['dex', wallet ?? ''],
    queryFn: () => api.getDex(wallet!),
    enabled: !!wallet,
    staleTime: 30_000,
  })
}
