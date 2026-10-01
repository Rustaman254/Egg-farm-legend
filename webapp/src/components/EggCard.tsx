import { HeartPulse, Pencil, Zap } from 'lucide-react'
import { eggDisplayName, HATCH_SPEEDUP_PRICE_PER_HOUR_ETH, RARITY_COLORS, RARITY_LABELS, speciesEmoji } from '../config/constants'
import { estimatedCareLevel, timeUntilHatchMs, type Egg } from '../api/types'
import { RarityIcon } from './RarityIcon'

function formatDuration(ms: number): string {
  const hours = Math.floor(ms / 3_600_000)
  const minutes = Math.floor((ms % 3_600_000) / 60_000)
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

/** Whole hours remaining, rounded up -- matches EggNFT.sol's speedUpHatch() cost formula exactly
 *  (it also rounds up to a whole hour), so the price shown here is the price it'll actually charge. */
function hoursRemaining(ms: number): number {
  return Math.ceil(ms / 3_600_000)
}

function careColor(care: number): string {
  if (care <= 20) return 'var(--color-down)'
  if (care < 30) return 'var(--color-warn)'
  return 'var(--color-up)'
}

export function EggCard({
  egg,
  onHatch,
  onDiscard,
  onList,
  onTend,
  onSpeedUp,
  onRename,
  busy,
  tending,
  speedingUp,
}: {
  egg: Egg
  onHatch?: () => void
  onDiscard?: () => void
  onList?: () => void
  onTend?: () => void
  onSpeedUp?: () => void
  onRename?: () => void
  busy?: boolean
  tending?: boolean
  speedingUp?: boolean
}) {
  const rarityColor = RARITY_COLORS[egg.rarity] ?? RARITY_COLORS[1]
  const remaining = timeUntilHatchMs(egg)
  const care = estimatedCareLevel(egg)
  const timerDone = egg.isHatchable || (!egg.isRotten && remaining === 0)
  const blockedByCare = timerDone && !egg.isHatchable && care < 30
  const speedUpCostEth = hoursRemaining(remaining) * HATCH_SPEEDUP_PRICE_PER_HOUR_ETH

  return (
    <div
      className="card-pop-sm flex flex-col gap-2.5 rounded-2xl border-[3px] bg-surface p-3"
      style={{ borderColor: egg.isRotten ? '#8a6a55' : rarityColor }}
    >
      <div className="flex items-center gap-3">
        {egg.isRotten ? (
          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full border-[3px] border-[#8a6a55] bg-surface-2 text-3xl grayscale">
            🥚
          </div>
        ) : (
          <RarityIcon rarity={egg.rarity} emoji={speciesEmoji(egg.species)} species={egg.species} size="md" />
        )}
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 font-display font-bold">
            {egg.isRotten ? (
              'Rotten Egg'
            ) : (
              <>
                <span className="truncate">{eggDisplayName(egg.species)}</span>
                {onRename && (
                  <button type="button" onClick={onRename} className="shrink-0 text-text-faint hover:text-text">
                    <Pencil size={11} />
                  </button>
                )}
              </>
            )}
          </div>
          {!egg.isRotten && (
            <div className="font-mono text-[9px] font-bold tracking-wide text-text-faint uppercase">
              {RARITY_LABELS[egg.rarity]}
              {egg.nickname && <> &middot; "{egg.nickname}"</>}
              {egg.parent1 && egg.parent2 ? ' · bred' : ''}
            </div>
          )}
          {!egg.isRotten && (
            <div className={`text-xs font-semibold ${egg.isHatchable ? 'text-up' : 'text-text-muted'}`}>
              {egg.isHatchable
                ? 'Ready to hatch!'
                : blockedByCare
                  ? 'Timer is up, but care is too low to hatch'
                  : `Hatches in ${formatDuration(remaining)}`}
            </div>
          )}
        </div>
        {egg.isRotten ? (
          <button type="button" disabled={busy} onClick={onDiscard} className="text-sm font-bold text-down disabled:opacity-50">
            Discard
          </button>
        ) : egg.isHatchable ? (
          <button
            type="button"
            disabled={busy}
            onClick={onHatch}
            className="rounded-xl px-4 py-2 text-sm font-bold text-white disabled:opacity-50"
            style={{ background: 'var(--color-brand-red)' }}
          >
            {busy ? '...' : 'Hatch'}
          </button>
        ) : (
          <button type="button" disabled={busy} onClick={onList} className="text-sm font-bold" style={{ color: 'var(--color-brand-blue)' }}>
            List
          </button>
        )}
      </div>

      {!egg.isRotten && (
        <div className="flex items-center gap-2 border-t border-dashed border-border pt-2">
          <HeartPulse size={13} style={{ color: careColor(care) }} />
          <div className="flex-1">
            <div className="h-2 w-full overflow-hidden rounded-full border border-border bg-surface-2">
              <div
                className="h-full rounded-full transition-all duration-500"
                style={{ width: `${care}%`, background: careColor(care) }}
              />
            </div>
          </div>
          <span className="hud-num text-xs" style={{ color: careColor(care) }}>
            {care}
          </span>
          <button
            type="button"
            disabled={tending || care >= 100}
            onClick={onTend}
            className="rounded-lg bg-surface-2 px-2.5 py-1 text-[11px] font-bold text-text transition-colors hover:bg-border disabled:opacity-40"
          >
            {tending ? '...' : 'Tend'}
          </button>
        </div>
      )}

      {!egg.isRotten && !timerDone && onSpeedUp && (
        <button
          type="button"
          disabled={speedingUp}
          onClick={onSpeedUp}
          className="flex items-center justify-center gap-1.5 rounded-xl border-2 py-1.5 text-xs font-bold disabled:opacity-50"
          style={{ borderColor: 'var(--color-brand-yellow)', color: 'var(--color-brand-yellow)' }}
        >
          <Zap size={13} /> {speedingUp ? 'Speeding up...' : `Speed Up -- ${speedUpCostEth.toFixed(3)} ETH`}
        </button>
      )}
    </div>
  )
}
