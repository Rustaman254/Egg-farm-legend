import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'

export function useTopEarners() {
  return useQuery({ queryKey: ['leaderboard', 'earners'], queryFn: api.topEarners })
}

export function useTopBattlers() {
  return useQuery({ queryKey: ['leaderboard', 'battlers'], queryFn: api.topBattlers })
}
