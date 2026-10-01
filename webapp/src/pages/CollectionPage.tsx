import { BookOpen } from 'lucide-react'
import { useState } from 'react'
import { SectionHeader } from '../components/SectionHeader'
import { RARITY_COLORS, RARITY_LABELS, speciesEmoji, speciesName } from '../config/constants'
import { useDex } from '../hooks/useDex'
import type { DexEntry } from '../api/types'

const TIER_FILTERS = [
  { label: 'All', tier: undefined },
  { label: 'Common', tier: 1 },
  { label: 'Uncommon', tier: 2 },
  { label: 'Rare', tier: 3 },
  { label: 'Epic', tier: 4 },
  { label: 'Legendary', tier: 5 },
] as const

function tierOf(species: number): number {
  return Math.floor(species / 8) + 1
}

function DexTile({ entry }: { entry: DexEntry }) {
  const tier = tierOf(entry.species)
  const rarityColor = RARITY_COLORS[tier] ?? RARITY_COLORS[1]
  const number = String(entry.species).padStart(3, '0')

  if (!entry.discovered) {
    return (
      <div className="card-pop-sm flex flex-col items-center gap-1.5 rounded-2xl border-[3px] border-border bg-surface-2 p-3 text-center opacity-70">
        <div className="font-mono text-[9px] font-bold text-text-faint">No. {number}</div>
        <div className="flex h-14 w-14 items-center justify-center rounded-full border-[3px] border-dashed border-text-faint text-2xl text-text-faint">
          ?
        </div>
        <div className="font-display text-xs font-bold text-text-faint">???</div>
        <div className="font-mono text-[9px] text-text-faint uppercase">{RARITY_LABELS[tier]}</div>
      </div>
    )
  }

  return (
    <div className="card-pop-sm flex flex-col items-center gap-1.5 rounded-2xl border-[3px] bg-surface p-3 text-center" style={{ borderColor: rarityColor }}>
      <div className="flex w-full items-center justify-between">
        <span className="font-mono text-[9px] font-bold text-text-faint">No. {number}</span>
        {entry.ownedCount > 0 && (
          <span className="hud-num rounded-full px-1.5 text-[9px] text-white" style={{ background: 'var(--color-brand-blue)' }}>
            &times;{entry.ownedCount}
          </span>
        )}
      </div>
      <div
        className="relative flex h-14 w-14 items-center justify-center rounded-full border-[3px] text-2xl"
        style={{ background: `${rarityColor}22`, borderColor: rarityColor }}
      >
        {speciesEmoji(entry.species)}
        {tier >= 4 && <div className="holo-foil absolute inset-0 rounded-full" />}
      </div>
      <div className="font-display text-xs font-bold">{speciesName(entry.species)}</div>
      <div className="font-mono text-[9px] font-bold text-text-faint uppercase">{RARITY_LABELS[tier]}</div>
    </div>
  )
}

export function CollectionPage({ wallet }: { wallet: string }) {
  const { data: dex, isLoading, error } = useDex(wallet)
  const [tierFilter, setTierFilter] = useState<number | undefined>(undefined)

  const entries = dex ?? []
  const discoveredCount = entries.filter((e) => e.discovered).length
  const total = entries.length || 40
  const filtered = tierFilter ? entries.filter((e) => tierOf(e.species) === tierFilter) : entries

  return (
    <div>
      <SectionHeader icon={BookOpen} title="Species Dex" />

      <div className="card-pop-sm mb-5 rounded-2xl border-[3px] bg-surface p-4" style={{ borderColor: 'var(--color-brand-red)' }}>
        <div className="flex items-center justify-between">
          <span className="font-display font-bold">Collection Progress</span>
          <span className="hud-num text-lg" style={{ color: 'var(--color-brand-red)' }}>
            {discoveredCount} / {total}
          </span>
        </div>
        <div className="mt-2 h-3 w-full overflow-hidden rounded-full border border-border bg-surface-2">
          <div
            className="h-full rounded-full transition-all duration-700"
            style={{ width: `${(discoveredCount / total) * 100}%`, background: 'var(--color-brand-red)' }}
          />
        </div>
        <p className="mt-2 text-xs text-text-muted">
          Every species you've ever owned stays in your dex -- selling, breeding away, or losing an Animora to
          starvation never un-discovers it.
        </p>
      </div>

      <div className="mb-4 flex flex-wrap gap-2">
        {TIER_FILTERS.map((f) => (
          <button
            key={f.label}
            type="button"
            onClick={() => setTierFilter(f.tier)}
            className={`rounded-full px-3.5 py-1.5 text-xs font-bold transition-colors ${
              tierFilter === f.tier ? 'text-white' : 'bg-surface-2 text-text-muted hover:text-text'
            }`}
            style={tierFilter === f.tier ? { background: 'var(--color-brand-red)' } : undefined}
          >
            {f.label}
          </button>
        ))}
      </div>

      {isLoading && <div className="flex h-64 items-center justify-center text-text-faint">Loading dex...</div>}
      {error && <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>}

      <div className="grid grid-cols-3 gap-2.5 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
        {filtered.map((entry) => (
          <DexTile key={entry.species} entry={entry} />
        ))}
      </div>
    </div>
  )
}
