import { Sparkles } from 'lucide-react'
import { useAbilityMap } from '../hooks/useAbilities'

/** Small pill row for a creature's abilities -- shown on the stat card (Inventory/Battle picker)
 *  and marketplace listing cards. Falls back to the raw key while the catalog is still loading so
 *  the row never flashes empty-then-populated. */
export function AbilityBadges({ abilities }: { abilities?: string[] }) {
  const catalog = useAbilityMap()
  if (!abilities || abilities.length === 0) return null

  return (
    <div className="flex flex-wrap gap-1 border-t border-dashed border-border pt-1.5">
      {abilities.map((key) => {
        const info = catalog.get(key)
        return (
          <span
            key={key}
            title={info?.description}
            className="hud-num flex items-center gap-1 rounded-full border border-border bg-surface-2 px-1.5 py-0.5 text-[9px] font-bold text-text-muted"
          >
            <Sparkles size={9} style={{ color: 'var(--color-brand-yellow)' }} />
            {info?.name ?? key}
          </span>
        )
      })}
    </div>
  )
}
