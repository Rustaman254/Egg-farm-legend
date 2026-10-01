import { Lock, Pencil, Repeat, Shield, Swords } from 'lucide-react'
import type { CSSProperties } from 'react'
import { appetiteKg, battleStats, levelForCareScore } from '../config/battleStats'
import { displayName, RARITY_COLORS, RARITY_LABELS, speciesEmoji } from '../config/constants'
import {
  canLayEgg,
  conditionLabel,
  CONDITION_COLORS,
  eggCooldownRemainingMs,
  MIN_HAPPINESS_TO_LAY,
  timeUntilMatureMs,
  type Creature,
} from '../api/types'
import { AbilityBadges } from './AbilityBadges'
import { RarityIcon } from './RarityIcon'
import { StatBar } from './StatBar'

function formatCooldown(ms: number): string {
  const hours = Math.floor(ms / 3_600_000)
  if (hours > 0) return `${hours}h`
  return `${Math.max(1, Math.floor(ms / 60_000))}m`
}

/** A Pokemon-TCG-styled card: colored border by rarity/"type", HP badge in the corner,
 *  circular art frame, attack-row stats, and a dex-number footer. Used both as the selectable
 *  Breeding Lab tile and (non-selectable) as a standalone creature card elsewhere. */
export function CreatureCard({
  creature,
  onFeed,
  onCollectEgg,
  feeding,
  collecting,
  selectable,
  selected,
  onSelect,
  onRename,
}: {
  creature: Creature
  onFeed?: () => void
  onCollectEgg?: () => void
  feeding?: boolean
  collecting?: boolean
  selectable?: boolean
  selected?: boolean
  onSelect?: () => void
  onRename?: () => void
}) {
  const rarityColor = RARITY_COLORS[creature.rarity] ?? RARITY_COLORS[1]
  const cooldownMs = eggCooldownRemainingMs(creature)
  const canLay = canLayEgg(creature)
  const stats = battleStats(creature.species, creature.rarity, creature.careScore)
  const level = levelForCareScore(creature.careScore)
  const condition = conditionLabel(creature.happiness, creature.careScore)
  const tooUnhappy = !canLay && creature.hunger > 0 && creature.happiness < MIN_HAPPINESS_TO_LAY && cooldownMs === 0
  const matureMs = timeUntilMatureMs(creature)

  return (
    <div
      className="card-pop relative flex flex-col gap-2 rounded-2xl border-[3px] bg-surface p-3"
      style={{ borderColor: selected ? 'var(--color-brand-blue)' : rarityColor }}
      onClick={selectable ? onSelect : undefined}
      role={selectable ? 'button' : undefined}
    >
      <div className="flex items-start justify-between">
        <div className="min-w-0">
          <div className="flex items-center gap-1 font-display text-sm font-bold">
            <span className="truncate">{displayName(creature.species, creature.nickname)}</span>
            {onRename && (
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onRename()
                }}
                className="shrink-0 text-text-faint hover:text-text"
              >
                <Pencil size={11} />
              </button>
            )}
          </div>
          <div className="flex items-center gap-1.5 font-mono text-[9px] font-bold tracking-wide text-text-faint uppercase">
            {RARITY_LABELS[creature.rarity]}
            <span style={{ color: 'var(--color-up)' }}>&middot; Lv{level}</span>
          </div>
          <div className="mt-0.5 font-mono text-[9px] font-bold uppercase" style={{ color: CONDITION_COLORS[condition] }}>
            {condition}
          </div>
          {matureMs > 0 && (
            <div className="mt-0.5 flex items-center gap-1 font-mono text-[9px] font-bold uppercase" style={{ color: 'var(--color-warn)' }}>
              <Lock size={9} /> Matures in {formatCooldown(matureMs)}
            </div>
          )}
        </div>
        <div
          className="hud-num shrink-0 rounded-lg px-1.5 py-0.5 text-[11px] text-white"
          style={{ background: 'var(--color-down)' }}
        >
          HP {stats.hp}
        </div>
      </div>

      <div
        className="glossy flex items-center justify-center rounded-xl py-3"
        style={{ '--glossy-from': `${rarityColor}55`, '--glossy-to': `${rarityColor}18`, '--glossy-glow': `${rarityColor}66` } as CSSProperties}
      >
        <RarityIcon rarity={creature.rarity} emoji={speciesEmoji(creature.species)} species={creature.species} size="lg" />
      </div>

      <div className="flex flex-col gap-1 border-t border-dashed border-border pt-1.5">
        <div className="flex items-center justify-between text-xs">
          <span className="flex items-center gap-1 font-semibold text-text-muted">
            <Swords size={12} style={{ color: 'var(--color-brand-red)' }} /> Attack
          </span>
          <span className="hud-num">{stats.attack}</span>
        </div>
        <div className="flex items-center justify-between text-xs">
          <span className="flex items-center gap-1 font-semibold text-text-muted">
            <Shield size={12} style={{ color: 'var(--color-brand-blue)' }} /> Defense
          </span>
          <span className="hud-num">{stats.defense}</span>
        </div>
        <div className="flex items-center justify-between text-xs">
          <span className="flex items-center gap-1 font-semibold text-text-muted">
            <Repeat size={12} style={{ color: 'var(--color-text-faint)' }} /> Bred
          </span>
          <span className="hud-num">{creature.breedCount}/7</span>
        </div>
        <div className="flex items-center justify-between text-xs">
          <span className="font-semibold text-text-muted">Appetite</span>
          <span className="hud-num">{appetiteKg(creature.rarity)}kg/meal</span>
        </div>
      </div>

      <div className="flex flex-col gap-1.5 border-t border-border pt-1.5">
        <StatBar label="Hunger" value={creature.hunger} />
        <StatBar label="Happiness" value={creature.happiness} />
      </div>

      <AbilityBadges abilities={creature.abilities} />

      <div className="flex items-center justify-between border-t border-border pt-1.5 font-mono text-[9px] text-text-faint">
        <span>No. {String(creature.species).padStart(3, '0')}</span>
        <span>#{creature.tokenId}</span>
      </div>

      {!selectable && (
        <div className="mt-0.5 grid grid-cols-2 gap-1.5">
          <button
            type="button"
            disabled={feeding || creature.hunger >= 100}
            title={creature.hunger >= 100 ? "It's already full -- feeding costs more the hungrier it is, wait for it to work up an appetite" : undefined}
            onClick={(e) => {
              e.stopPropagation()
              onFeed?.()
            }}
            className="rounded-xl bg-surface-2 py-1.5 text-xs font-bold text-text transition-colors hover:bg-border disabled:opacity-50"
          >
            {feeding ? '...' : creature.hunger >= 100 ? 'Full' : 'Feed'}
          </button>
          <button
            type="button"
            disabled={!canLay || collecting}
            title={tooUnhappy ? `Needs ${MIN_HAPPINESS_TO_LAY}+ happiness to lay -- feed it more` : undefined}
            onClick={(e) => {
              e.stopPropagation()
              onCollectEgg?.()
            }}
            className="rounded-xl py-1.5 text-xs font-bold text-white disabled:bg-surface-2 disabled:text-text-faint"
            style={{ background: !canLay || collecting ? undefined : 'var(--color-brand-red)' }}
          >
            {collecting ? '...' : canLay ? 'Egg' : tooUnhappy ? 'Unhappy' : formatCooldown(cooldownMs)}
          </button>
        </div>
      )}
    </div>
  )
}
