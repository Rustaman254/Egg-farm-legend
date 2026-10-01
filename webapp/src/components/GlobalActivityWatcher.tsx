import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { RarityIcon } from './RarityIcon'
import { ArrowDownRight, ArrowUpRight, X } from 'lucide-react'
import { formatUnits } from 'viem'
import { speciesEmoji, speciesName } from '../config/constants'
import { useIncomingChallenges } from '../hooks/useArena'
import { usePlayerSocket } from '../hooks/usePlayerSocket'
import { playChallengeChime } from '../lib/sound'
import type { ChallengeSummary, WalletEventPayload } from '../api/types'

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

function wagerEth(wagerWei: string): number {
  return wagerWei && wagerWei !== '0' ? Number(formatUnits(BigInt(wagerWei), 18)) : 0
}

/** Mounted once at the app root (see App.tsx) so live pushes show up and chime no matter which
 *  screen the player is on: someone challenging them to a fight, and now also "the system always
 *  checking your wallet" -- a balance change or a marketplace trade landing. Falls back to the
 *  same 10s poll (useIncomingChallenges) if the websocket can't connect for the arena case; wallet
 *  events have no polling fallback since they're purely a live notification (the underlying data
 *  -- balance, activity log -- is always fetched fresh on its own screen regardless). */
export function GlobalActivityWatcher({ wallet }: { wallet: string }) {
  const navigate = useNavigate()
  const { data: incomingChallenges } = useIncomingChallenges(wallet)
  const [pushed, setPushed] = useState<ChallengeSummary | null>(null)
  const [walletToast, setWalletToast] = useState<WalletEventPayload | null>(null)
  const dismissedRef = useRef<Set<number>>(new Set())
  const walletToastTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  usePlayerSocket(wallet, {
    onChallengeReceived: (challenge) => {
      if (dismissedRef.current.has(challenge.id)) return
      setPushed(challenge)
      playChallengeChime()
    },
    onWalletEvent: (event) => {
      setWalletToast(event)
      if (walletToastTimer.current) clearTimeout(walletToastTimer.current)
      walletToastTimer.current = setTimeout(() => setWalletToast(null), 6_000)
    },
  })

  const current = pushed ?? (incomingChallenges ?? []).find((c) => !dismissedRef.current.has(c.id)) ?? null

  const dismissChallenge = () => {
    if (!current) return
    dismissedRef.current.add(current.id)
    if (pushed?.id === current.id) setPushed(null)
  }

  if (!current && !walletToast) return null

  return (
    <div className="fixed inset-x-4 top-4 z-[60] mx-auto flex max-w-sm flex-col gap-2 sm:inset-x-auto sm:right-4">
      {walletToast && (
        <div
          className="card-pop flex items-center gap-3 rounded-2xl border-[3px] bg-surface p-3"
          style={{ borderColor: walletToast.kind === 'balance_down' ? 'var(--color-down)' : 'var(--color-up)' }}
        >
          {walletToast.kind === 'balance_down' ? (
            <ArrowDownRight size={18} style={{ color: 'var(--color-down)' }} />
          ) : (
            <ArrowUpRight size={18} style={{ color: 'var(--color-up)' }} />
          )}
          <div className="flex-1 text-xs font-bold">{walletToast.message}</div>
          <button type="button" onClick={() => setWalletToast(null)} className="text-text-faint">
            <X size={16} />
          </button>
        </div>
      )}

      {current && (
        <div className="card-pop flex items-center gap-3 rounded-2xl border-[3px] bg-surface p-3" style={{ borderColor: 'var(--color-brand-red)' }}>
          <RarityIcon rarity={current.challengerRarity} emoji={speciesEmoji(current.challengerSpecies)} species={current.challengerSpecies} size="sm" />
          <div className="flex-1">
            <div className="text-xs font-bold">{shortAddress(current.challengerWallet)} wants to fight you!</div>
            <div className="font-mono text-[10px] text-text-faint">
              {speciesName(current.challengerSpecies)} Lv{current.challengerLevel}
              {wagerEth(current.wagerWei) > 0 && (
                <span style={{ color: 'var(--color-brand-yellow)' }}> &middot; {wagerEth(current.wagerWei)} ETH wager</span>
              )}
            </div>
          </div>
          <button
            type="button"
            onClick={() => {
              dismissChallenge()
              navigate('/battle', { state: { acceptChallenge: current } })
            }}
            className="rounded-full px-3 py-1.5 text-xs font-bold text-white"
            style={{ background: 'var(--color-brand-red)' }}
          >
            Accept
          </button>
          <button type="button" onClick={dismissChallenge} className="text-text-faint">
            <X size={16} />
          </button>
        </div>
      )}
    </div>
  )
}
