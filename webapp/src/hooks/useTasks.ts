import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useRef } from 'react'
import { api } from '../api/client'

function tasksQueryKey(wallet: string) {
  return ['tasks', wallet] as const
}

export function useTasks(wallet: string | undefined) {
  return useQuery({
    queryKey: tasksQueryKey(wallet ?? ''),
    queryFn: () => api.listTasks(wallet!),
    enabled: !!wallet,
  })
}

export function useClaimTask(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (taskId: string) => api.claimTask(wallet!, taskId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tasksQueryKey(wallet ?? '') })
      // Task claims award Farmer XP too now -- refresh the farm snapshot so the level badge
      // (fed from /farm) picks up the change immediately.
      queryClient.invalidateQueries({ queryKey: ['farm', wallet ?? ''] })
    },
  })
}

export function useCreateTask(wallet: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: Omit<Parameters<typeof api.createTask>[0], 'creatorAddress'>) =>
      api.createTask({ ...input, creatorAddress: wallet! }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: tasksQueryKey(wallet ?? '') }),
  })
}

/** Records the daily-login streak / completes the daily_login task, once per wallet per mount. */
export function useRecordLogin(wallet: string | undefined) {
  const recorded = useRef<string | undefined>(undefined)
  useEffect(() => {
    if (!wallet || recorded.current === wallet) return
    recorded.current = wallet
    api.recordLogin(wallet).catch(() => {
      // Best-effort: a failed login ping shouldn't block using the app.
    })
  }, [wallet])
}
