import { Flame, Heart, Lock } from 'lucide-react'
import { battleStats, levelForCareScore } from '../config/battleStats'
import { displayName, RARITY_COLORS, RARITY_LABELS, speciesEmoji } from '../config/constants'
import { canLayEgg, eggCooldownRemainingMs, timeUntilMatureMs, type Creature } from '../api/types'
import { RarityIcon } from './RarityIcon'

function formatCooldown(ms: number): string {
  const hours = Math.floor(ms / 3_600_000)
  if (hours > 0) return `${hours}h`
  return `${Math.max(1, Math.floor(ms / 60_000))}m`
}

/** Compact Pokemon-TCG-styled card for the Farm dashboard's horizontal "My Creatures" row. */
export function CreatureTicker({
  creature,
  onFeed,
  onCollectEgg,
  feeding,
  collecting,
}: {
  creature: Creature
  onFeed: () => void
  onCollectEgg: () => void
  feeding?: boolean
  collecting?: boolean
}) {
  const rarityColor = RARITY_COLORS[creature.rarity] ?? RARITY_COLORS[1]
  const cooldownMs = eggCooldownRemainingMs(creature)
  const canLay = canLayEgg(creature)
  const stats = battleStats(creature.species, creature.rarity, creature.careScore)
  const level = levelForCareScore(creature.careScore)
  const matureMs = timeUntilMatureMs(creature)

  return (
    <div className="card-pop-sm flex w-[172px] shrink-0 flex-col gap-2 rounded-2xl border-[3px] bg-surface p-3" style={{ borderColor: rarityColor }}>
      <div className="flex items-center gap-2">
        <RarityIcon rarity={creature.rarity} emoji={speciesEmoji(creature.species)} species={creature.species} size="sm" />
        <div className="min-w-0 flex-1 leading-tight">
          <div className="truncate font-display text-xs font-bold">{displayName(creature.species, creature.nickname)}</div>
          <div className="flex items-center gap-1 font-mono text-[9px] font-bold tracking-wide text-text-faint uppercase">
            {RARITY_LABELS[creature.rarity]}
            <span style={{ color: 'var(--color-up)' }}>&middot; Lv{level}</span>
          </div>
        </div>
        <div className="hud-num shrink-0 rounded-lg px-1.5 py-0.5 text-[10px] text-white" style={{ background: 'var(--color-down)' }}>
          HP {stats.hp}
        </div>
      </div>

      <div className="flex items-center justify-between rounded-lg bg-surface-2 px-2 py-1">
        <span className="text-[10px] font-bold text-text-muted">Hunger</span>
        <span className="hud-num text-sm" style={{ color: creature.hunger <= 20 ? 'var(--color-down)' : creature.hunger <= 50 ? 'var(--color-warn)' : 'var(--color-up)' }}>
          {creature.hunger}
        </span>
      </div>

      <div className="flex justify-between font-mono text-[10px] text-text-faint">
        <span className="flex items-center gap-1">
          <Heart size={10} /> {creature.happiness}
        </span>
        <span>Bred {creature.breedCount}/7</span>
      </div>

      {matureMs > 0 && (
        <div className="flex items-center gap-1 rounded-lg px-2 py-1 font-mono text-[9px] font-bold" style={{ background: 'var(--color-surface-2)', color: 'var(--color-warn)' }}>
          <Lock size={9} /> Matures in {formatCooldown(matureMs)}
        </div>
      )}

      <div className="grid grid-cols-2 gap-1.5 pt-0.5">
        <button
          type="button"
          disabled={feeding || creature.hunger >= 100}
          title={creature.hunger >= 100 ? "It's already full" : undefined}
          onClick={onFeed}
          className="rounded-lg bg-surface-2 py-1.5 text-[11px] font-bold text-text transition-colors hover:bg-border disabled:opacity-50"
        >
          {feeding ? '...' : creature.hunger >= 100 ? 'Full' : 'Feed'}
        </button>
        <button
          type="button"
          disabled={!canLay || collecting}
          onClick={onCollectEgg}
          className="flex items-center justify-center gap-1 rounded-lg py-1.5 text-[11px] font-bold text-white disabled:bg-surface-2 disabled:text-text-faint"
          style={{ background: !canLay || collecting ? undefined : 'var(--color-brand-red)' }}
        >
          <Flame size={11} /> {collecting ? '...' : canLay ? 'Egg' : formatCooldown(cooldownMs)}
        </button>
      </div>
    </div>
  )
}
