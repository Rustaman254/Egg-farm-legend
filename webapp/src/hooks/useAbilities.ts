import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import type { AbilityInfo } from '../api/types'

/** The ability catalog is fixed game balance data (see backend internal/models/abilities.go) --
 *  fetched once and cached indefinitely rather than re-polled like live game state. */
export function useAbilityCatalog() {
  return useQuery({
    queryKey: ['abilities', 'catalog'],
    queryFn: api.abilityCatalog,
    staleTime: Infinity,
    gcTime: Infinity,
  })
}

export function useAbilityMap(): Map<string, AbilityInfo> {
  const { data } = useAbilityCatalog()
  return new Map((data ?? []).map((a) => [a.key, a]))
}
