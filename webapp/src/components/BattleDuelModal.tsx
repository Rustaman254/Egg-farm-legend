import { useEffect, useState } from 'react'
import { formatUnits } from 'viem'
import { speciesEmoji } from '../config/constants'
import { RarityIcon } from './RarityIcon'

export interface DuelSide {
  label: string
  species: number
  rarity: number
  level: number
  hp: number
  maxHp: number
}

function HpBar({ current, max, color }: { current: number; max: number; color: string }) {
  const pct = max === 0 ? 0 : Math.max(0, Math.min(100, (current / max) * 100))
  return (
    <div className="h-3 w-full overflow-hidden rounded-full border-2 border-border bg-surface-2">
      <div className="h-full rounded-full transition-all duration-1000 ease-out" style={{ width: `${pct}%`, background: color }} />
    </div>
  )
}

/** Full-screen "gamified" duel reveal: a brief VS face-off, then the HP bars drain and the round
 *  log steps in line by line. Used for the PvE Fight result, the PvP AcceptChallenge result, and
 *  (via polling) whenever a challenger discovers their own posted challenge got accepted. */
export function BattleDuelModal({
  you,
  opponent,
  won,
  rounds,
  log,
  rewardFeed,
  xpAwarded,
  wagerWei,
  wagerWon,
  onClose,
}: {
  you: DuelSide
  opponent: DuelSide
  won: boolean
  rounds: number
  log: string[]
  rewardFeed: string
  xpAwarded?: number
  wagerWei?: string
  wagerWon?: boolean
  onClose: () => void
}) {
  const [phase, setPhase] = useState<'vs' | 'reveal'>('vs')
  const [revealed, setRevealed] = useState(0)
  const [damageApplied, setDamageApplied] = useState(false)
  const rewardWhole = Number(formatUnits(BigInt(rewardFeed || '0'), 18))
  const wagerEth = wagerWei && wagerWei !== '0' ? Number(formatUnits(BigInt(wagerWei), 18)) : 0

  useEffect(() => {
    const toReveal = setTimeout(() => setPhase('reveal'), 1100)
    return () => clearTimeout(toReveal)
  }, [])

  useEffect(() => {
    if (phase !== 'reveal') return
    const startDamage = setTimeout(() => setDamageApplied(true), 150)
    const timer = setInterval(() => {
      setRevealed((n) => {
        if (n >= log.length) {
          clearInterval(timer)
          return n
        }
        return n + 1
      })
    }, 300)
    return () => {
      clearTimeout(startDamage)
      clearInterval(timer)
    }
  }, [phase, log.length])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm" onClick={phase === 'reveal' ? onClose : undefined}>
      {phase === 'vs' ? (
        <div className="flex w-full max-w-lg items-center justify-center gap-4">
          <div className="flex flex-1 flex-col items-center gap-2 duel-slide-left">
            <RarityIcon rarity={you.rarity} emoji={speciesEmoji(you.species)} species={you.species} size="lg" />
            <div className="text-center text-sm font-bold text-white">{you.label}</div>
            <div className="hud-num text-xs text-white/70">Lv{you.level}</div>
          </div>
          <div className="font-display text-3xl font-extrabold text-white duel-pop" style={{ color: 'var(--color-brand-yellow)' }}>
            VS
          </div>
          <div className="flex flex-1 flex-col items-center gap-2 duel-slide-right">
            <RarityIcon rarity={opponent.rarity} emoji={speciesEmoji(opponent.species)} species={opponent.species} size="lg" />
            <div className="text-center text-sm font-bold text-white">{opponent.label}</div>
            <div className="hud-num text-xs text-white/70">Lv{opponent.level}</div>
          </div>
        </div>
      ) : (
        <div
          className="card-pop w-full max-w-md rounded-2xl border-[3px] bg-surface p-5"
          style={{ borderColor: won ? 'var(--color-up)' : 'var(--color-down)' }}
          onClick={(e) => e.stopPropagation()}
        >
          <div className="text-center">
            <div className="font-display text-2xl font-extrabold" style={{ color: won ? 'var(--color-up)' : 'var(--color-down)' }}>
              {won ? 'Victory!' : 'Defeated...'}
            </div>
            {won && (
              <div className="hud-num mt-1 text-sm" style={{ color: 'var(--color-brand-yellow)' }}>
                +{rewardWhole.toFixed(0)} FEED {xpAwarded ? `· +${xpAwarded} XP` : ''}
              </div>
            )}
            {wagerEth > 0 && (
              <div className="hud-num mt-1 text-xs" style={{ color: wagerWon ? 'var(--color-up)' : 'var(--color-down)' }}>
                {wagerWon ? `Won the ${wagerEth} ETH wager!` : `Lost your ${wagerEth} ETH wager.`}
              </div>
            )}
          </div>

          <div className="mt-4 grid grid-cols-2 gap-4">
            <div className="flex flex-col items-center gap-1.5">
              <RarityIcon rarity={you.rarity} emoji={speciesEmoji(you.species)} species={you.species} size="md" />
              <div className="text-xs font-bold">{you.label}</div>
              <HpBar current={damageApplied ? you.hp : you.maxHp} max={you.maxHp} color="var(--color-up)" />
              <div className="hud-num text-[11px] text-text-faint">
                {you.hp}/{you.maxHp} HP
              </div>
            </div>
            <div className="flex flex-col items-center gap-1.5">
              <RarityIcon rarity={opponent.rarity} emoji={speciesEmoji(opponent.species)} species={opponent.species} size="md" />
              <div className="text-xs font-bold">{opponent.label}</div>
              <HpBar current={damageApplied ? opponent.hp : opponent.maxHp} max={opponent.maxHp} color="var(--color-down)" />
              <div className="hud-num text-[11px] text-text-faint">
                {opponent.hp}/{opponent.maxHp} HP
              </div>
            </div>
          </div>

          <div className="mt-4 flex max-h-40 flex-col gap-1 overflow-y-auto rounded-xl bg-surface-2 p-3 font-mono text-xs">
            {log.slice(0, revealed).map((line, i) => (
              <div key={i} className="text-text-muted">
                {line}
              </div>
            ))}
          </div>
          <div className="mt-1 text-center font-mono text-[10px] text-text-faint">{rounds} rounds</div>

          <button
            type="button"
            onClick={onClose}
            className="mt-4 w-full rounded-full py-2.5 text-sm font-bold text-white"
            style={{ background: 'var(--color-brand-red)' }}
          >
            Continue
          </button>
        </div>
      )}
    </div>
  )
}
