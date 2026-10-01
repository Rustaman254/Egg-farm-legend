import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'

function battleHistoryQueryKey(wallet: string) {
  return ['battles', wallet] as const
}

export function useBattleHistory(wallet: string | undefined) {
  return useQuery({
    queryKey: battleHistoryQueryKey(wallet ?? ''),
    queryFn: () => api.listBattles(wallet!),
    enabled: !!wallet,
  })
}

export function useFightBattle(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (creatureTokenId: number) => api.fightBattle(wallet!, creatureTokenId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: battleHistoryQueryKey(wallet ?? '') })
      queryClient.invalidateQueries({ queryKey: ['farm', wallet ?? ''] })
      queryClient.invalidateQueries({ queryKey: ['tasks', wallet ?? ''] })
    },
  })
}
