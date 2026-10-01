import { Swords, Users, X } from 'lucide-react'
import { formatEther, parseEther } from 'viem'
import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { BattleDuelModal, type DuelSide } from '../components/BattleDuelModal'
import { ErrorBanner } from '../components/Banner'
import { CreatureCard } from '../components/CreatureCard'
import { RarityIcon } from '../components/RarityIcon'
import { SectionHeader } from '../components/SectionHeader'
import { battleStats, levelForCareScore } from '../config/battleStats'
import { RARITY_COLORS, RARITY_LABELS, speciesEmoji, speciesName } from '../config/constants'
import {
  useAcceptChallenge,
  useArenaHeartbeat,
  useCancelChallenge,
  useCreateChallenge,
  useFundChallenge,
  useMyChallenges,
  useOnlinePlayers,
  useOpenChallenges,
} from '../hooks/useArena'
import { useBattleHistory, useFightBattle } from '../hooks/useBattle'
import { useFarm } from '../hooks/useFarm'
import type { BattleResult, ChallengeSummary } from '../api/types'

const MAX_WAGER_ETH = 1
const WAGER_STEP_ETH = 0.01

function wagerEth(wagerWei: string | undefined): number {
  return wagerWei && wagerWei !== '0' ? Number(formatEther(BigInt(wagerWei))) : 0
}

function wagerToWei(eth: number): string {
  return eth > 0 ? parseEther(eth.toFixed(2)).toString() : '0'
}

/** Small +/- stepper for setting an ETH/ARB wager, shared by the open-board post flow and the
 *  direct-challenge-a-player flow. Capped at 1 ETH to match the backend's maxWagerWei -- real
 *  native currency, unlike the old $FEED wager, so the cap is much tighter. */
function WagerStepper({ value, onChange }: { value: number; onChange: (next: number) => void }) {
  const round = (n: number) => Math.round(n * 100) / 100
  return (
    <div className="flex items-center gap-2 rounded-full border-2 border-border bg-surface-2 px-3 py-1.5">
      <span className="text-[10px] font-bold text-text-faint uppercase">Wager</span>
      <button
        type="button"
        onClick={() => onChange(Math.max(0, round(value - WAGER_STEP_ETH)))}
        className="hud-num flex h-5 w-5 items-center justify-center rounded-full bg-surface text-xs font-bold"
      >
        -
      </button>
      <span className="hud-num min-w-[4.5rem] text-center text-xs font-bold" style={{ color: value > 0 ? 'var(--color-brand-yellow)' : undefined }}>
        {value.toFixed(2)} ETH
      </span>
      <button
        type="button"
        onClick={() => onChange(Math.min(MAX_WAGER_ETH, round(value + WAGER_STEP_ETH)))}
        className="hud-num flex h-5 w-5 items-center justify-center rounded-full bg-surface text-xs font-bold"
      >
        +
      </button>
    </div>
  )
}

function timeAgo(iso: string): string {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (seconds < 60) return 'just now'
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
  return `${Math.floor(seconds / 86400)}d ago`
}

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

function wildLabel(species: number): string {
  return `Wild ${speciesName(species)}`
}

function CreaturePicker({
  creatures,
  selected,
  onSelect,
}: {
  creatures: NonNullable<ReturnType<typeof useFarm>['data']>['creatures']
  selected: number | null
  onSelect: (tokenId: number) => void
}) {
  return (
    <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-6">
      {creatures.map((c) => {
        const rarityColor = RARITY_COLORS[c.rarity] ?? RARITY_COLORS[1]
        const isSelected = c.tokenId === selected
        return (
          <button
            key={c.tokenId}
            type="button"
            onClick={() => onSelect(c.tokenId)}
            className="card-pop-sm flex flex-col items-center gap-1 rounded-2xl border-[3px] bg-surface p-2 transition-transform active:scale-[0.97]"
            style={{ borderColor: isSelected ? 'var(--color-brand-blue)' : rarityColor }}
          >
            <RarityIcon rarity={c.rarity} emoji={speciesEmoji(c.species)} species={c.species} size="sm" />
            <div className="truncate text-[10px] font-bold">{speciesName(c.species)}</div>
            <div className="font-mono text-[8px] text-text-faint uppercase">
              {RARITY_LABELS[c.rarity]} &middot; Lv{levelForCareScore(c.careScore)}
            </div>
          </button>
        )
      })}
    </div>
  )
}

export function BattlePage({ wallet }: { wallet: string }) {
  const { data: farm, isLoading, error } = useFarm(wallet)
  const { data: history } = useBattleHistory(wallet)
  const fight = useFightBattle(wallet)
  const [selected, setSelected] = useState<number | null>(null)
  const [duel, setDuel] = useState<{
    you: DuelSide
    opponent: DuelSide
    won: boolean
    rounds: number
    log: string[]
    rewardFeed: string
    xpAwarded?: number
    wagerWei?: string
    wagerWon?: boolean
  } | null>(null)
  const [postWager, setPostWager] = useState(0)

  // Arena: presence + open challenge board. The incoming-direct-challenge toast (websocket push
  // + sound) is handled app-wide by <GlobalActivityWatcher>, not here -- it navigates back to this
  // page with the challenge in router state (see the effect below) when "Accept" is tapped,
  // rather than duplicating a second toast + websocket connection on this page specifically.
  useArenaHeartbeat(wallet)
  const { data: online } = useOnlinePlayers()
  const { data: openChallenges } = useOpenChallenges()
  const { data: myChallenges } = useMyChallenges(wallet)
  const createChallenge = useCreateChallenge(wallet)
  const acceptChallenge = useAcceptChallenge(wallet)
  const cancelChallenge = useCancelChallenge(wallet)
  const fundChallenge = useFundChallenge(wallet)
  const [acceptingChallenge, setAcceptingChallenge] = useState<ChallengeSummary | null>(null)
  const [acceptCreature, setAcceptCreature] = useState<number | null>(null)
  const [challengingPlayer, setChallengingPlayer] = useState<string | null>(null)
  const [challengeCreature, setChallengeCreature] = useState<number | null>(null)
  const [challengeWager, setChallengeWager] = useState(0)
  // Persisted (not just in-memory) so a page reload/revisit never replays an already-seen duel
  // reveal -- this used to reset on every mount, which meant reopening the Battle Arena re-popped
  // up every one of your own past resolved challenges as if a fight had just happened.
  const seenResolvedKey = `eggfarm:seenChallengeResolutions:${wallet.toLowerCase()}`
  const seenResolvedRef = useRef<Set<number>>(
    (() => {
      try {
        const stored = localStorage.getItem(seenResolvedKey)
        return stored ? new Set(JSON.parse(stored)) : new Set()
      } catch {
        return new Set()
      }
    })(),
  )
  const persistSeenResolved = () => {
    try {
      localStorage.setItem(seenResolvedKey, JSON.stringify([...seenResolvedRef.current]))
    } catch {
      // localStorage unavailable (private window, blocked site data, etc.) -- worst case the
      // reveal can repeat once more, still far better than every page load.
    }
  }
  const location = useLocation()
  const navigate = useNavigate()

  useEffect(() => {
    const fromNav = (location.state as { acceptChallenge?: ChallengeSummary } | null)?.acceptChallenge
    if (fromNav) {
      setAcceptingChallenge(fromNav)
      navigate(location.pathname, { replace: true, state: null })
    }
  }, [location.state, location.pathname, navigate])

  const creatures = (farm?.creatures ?? []).filter((c) => !c.isDead)
  const selectedCreature = creatures.find((c) => c.tokenId === selected)
  const stats = selectedCreature ? battleStats(selectedCreature.species, selectedCreature.rarity, selectedCreature.careScore) : null
  const level = selectedCreature ? levelForCareScore(selectedCreature.careScore) : null

  // Auto-popup the gamified VS reveal when a challenge *this wallet issued* gets accepted and
  // resolved by someone else -- the only "you got challenged back" notification available
  // without a push channel: poll, diff status, show once.
  useEffect(() => {
    if (!myChallenges) return
    const freshlyResolved = myChallenges.find(
      (c) => c.status === 'completed' && c.opponentWallet && !seenResolvedRef.current.has(c.id) && c.log && c.log.length > 0,
    )
    if (!freshlyResolved || !freshlyResolved.log || !freshlyResolved.rounds) return
    seenResolvedRef.current.add(freshlyResolved.id)
    persistSeenResolved()
    const youWon = freshlyResolved.winnerWallet?.toLowerCase() === wallet.toLowerCase()
    setDuel({
      you: {
        label: 'You',
        species: freshlyResolved.challengerSpecies,
        rarity: freshlyResolved.challengerRarity,
        level: freshlyResolved.challengerLevel,
        hp: 0,
        maxHp: 1,
      },
      opponent: {
        label: shortAddress(freshlyResolved.opponentWallet!),
        species: freshlyResolved.challengerSpecies,
        rarity: freshlyResolved.challengerRarity,
        level: freshlyResolved.challengerLevel,
        hp: 0,
        maxHp: 1,
      },
      won: youWon,
      rounds: freshlyResolved.rounds,
      log: freshlyResolved.log,
      rewardFeed: freshlyResolved.rewardFeed ?? '0',
    })
    // Note: the challenge board doesn't carry back final HP for the *challenger's* view (the
    // detailed HP numbers live in the accepting side's synchronous Result) -- this reveal still
    // shows the real log and outcome, just without a live-draining HP bar for this side.
  }, [myChallenges, wallet])

  if (isLoading) {
    return <div className="flex h-64 items-center justify-center text-text-faint">Loading your roster...</div>
  }
  if (error) {
    return <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>
  }

  if (creatures.length === 0) {
    return (
      <div className="mx-auto max-w-2xl">
        <SectionHeader icon={Swords} title="Battle Arena" />
        <div className="card-pop rounded-2xl border-[3px] border-border bg-surface p-8 text-center text-text-muted">
          You need at least one living Animora to enter the Battle Arena.
        </div>
      </div>
    )
  }

  const myOpenChallengeIds = new Set((myChallenges ?? []).filter((c) => c.status === 'open').map((c) => c.id))
  const awaitingStake = (myChallenges ?? []).filter((c) => c.status === 'open' && c.wagerWei !== '0' && !c.escrowConfirmed)

  return (
    <div className="mx-auto max-w-3xl">
      {/* Hero -- dark "esports arena" banner, distinct from the farm's warm hero */}
      <div className="card-pop relative mb-6 overflow-hidden rounded-3xl border-[3px]" style={{ borderColor: 'var(--color-brand-red)', background: 'linear-gradient(155deg, #1a0e14 0%, var(--color-surface) 65%)' }}>
        <div className="arcade-grid pointer-events-none absolute inset-0" />
        <div
          className="pointer-events-none absolute -top-16 -right-16 h-56 w-56 rounded-full blur-3xl"
          style={{ background: 'radial-gradient(circle, var(--color-brand-red)33, transparent 70%)' }}
        />
        <div className="relative flex flex-col gap-3 p-6 sm:p-8">
          <div className="flex items-center gap-2">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-brand-red opacity-60 motion-reduce:animate-none" />
              <span className="relative inline-flex h-2 w-2 rounded-full" style={{ background: 'var(--color-brand-red)' }} />
            </span>
            <span className="hud-num text-[11px] font-bold tracking-widest uppercase" style={{ color: 'var(--color-brand-red)' }}>
              Live Arena
            </span>
          </div>
          <h1 className="font-display text-2xl font-extrabold tracking-tight sm:text-3xl">
            <Swords size={22} className="mr-2 inline -translate-y-1" style={{ color: 'var(--color-brand-red)' }} />
            Battle Arena
          </h1>
          <p className="max-w-lg text-sm text-text-muted">
            Fight a wild opponent solo, or challenge another farmer's Animora. Combat uses each side's real
            HP/Attack/Defense -- level (from consistent feeding) matters as much as rarity, so a well-raised Chicken can
            take down a neglected Dragon. Wagers stake ETH/ARB in an on-chain escrow until the duel resolves.
          </p>
          <div className="mt-1 flex flex-wrap gap-2">
            <span className="hud-num flex items-center gap-1.5 rounded-full border border-border bg-surface/70 px-3 py-1 text-[11px] backdrop-blur-sm">
              <Users size={11} style={{ color: 'var(--color-up)' }} /> {online?.length ?? 0} online
            </span>
            <span className="hud-num flex items-center gap-1.5 rounded-full border border-border bg-surface/70 px-3 py-1 text-[11px] backdrop-blur-sm">
              <Swords size={11} style={{ color: 'var(--color-brand-red)' }} /> {openChallenges?.length ?? 0} open challenges
            </span>
          </div>
        </div>
      </div>

      {awaitingStake.length > 0 && (
        <div className="mb-4 flex flex-col gap-2">
          {awaitingStake.map((c) => (
            <div
              key={c.id}
              className="card-pop-sm flex items-center gap-3 rounded-2xl border-[3px] bg-surface p-3"
              style={{ borderColor: 'var(--color-warn)' }}
            >
              <div className="flex-1 text-xs font-bold">
                {wagerEth(c.wagerWei)} ETH wager not yet staked on-chain -- your wallet interaction was interrupted.
              </div>
              <button
                type="button"
                disabled={fundChallenge.isPending}
                onClick={() => fundChallenge.mutate(c)}
                className="rounded-full px-3 py-1.5 text-xs font-bold text-white disabled:opacity-60"
                style={{ background: 'var(--color-warn)' }}
              >
                {fundChallenge.isPending ? 'Staking...' : 'Stake Now'}
              </button>
              <button
                type="button"
                disabled={cancelChallenge.isPending}
                onClick={() => cancelChallenge.mutate(c)}
                className="text-text-faint"
              >
                <X size={16} />
              </button>
            </div>
          ))}
          {fundChallenge.error && <ErrorBanner message={(fundChallenge.error as Error).message} />}
        </div>
      )}

      <CreaturePicker creatures={creatures} selected={selected} onSelect={setSelected} />

      {selectedCreature && stats && level && (
        <div className="card-pop mt-4 flex flex-col gap-4 rounded-2xl border-[3px] border-border bg-surface p-4 sm:flex-row sm:items-start">
          {/* Full stat sheet -- same card used everywhere else in the app, so what you see here is
              exactly what decides the fight: HP/Attack/Defense, bred count, appetite, hunger,
              happiness, and abilities, not just a 3-number summary. */}
          <div className="w-full sm:w-64">
            <CreatureCard creature={selectedCreature} selectable />
          </div>
          <div className="flex flex-1 flex-col gap-3">
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                disabled={fight.isPending}
                onClick={() =>
                  fight.mutate(selectedCreature.tokenId, {
                    onSuccess: (r: BattleResult) =>
                      setDuel({
                        you: { label: speciesName(r.playerSpecies), species: r.playerSpecies, rarity: selectedCreature.rarity, level: r.playerLevel, hp: r.playerHp, maxHp: r.playerMaxHp },
                        opponent: { label: wildLabel(r.opponentSpecies), species: r.opponentSpecies, rarity: r.opponentRarity, level: r.opponentLevel, hp: r.opponentHp, maxHp: r.opponentMaxHp },
                        won: r.won,
                        rounds: r.rounds,
                        log: r.log,
                        rewardFeed: r.rewardFeed,
                        xpAwarded: r.xpAwarded,
                      }),
                  })
                }
                className="card-pop-sm rounded-full px-5 py-2.5 font-display text-sm font-bold text-white disabled:opacity-60"
                style={{ background: 'var(--color-brand-red)' }}
              >
                {fight.isPending ? 'Fighting...' : 'Fight Wild'}
              </button>
              <WagerStepper value={postWager} onChange={setPostWager} />
              <button
                type="button"
                disabled={createChallenge.isPending || myOpenChallengeIds.size >= 3}
                onClick={() => createChallenge.mutate({ creatureTokenId: selectedCreature.tokenId, wagerWei: wagerToWei(postWager) })}
                className="card-pop-sm rounded-full px-5 py-2.5 font-display text-sm font-bold text-white disabled:opacity-60"
                style={{ background: 'var(--color-brand-blue)' }}
                title={myOpenChallengeIds.size >= 3 ? 'You already have 3 open challenges' : undefined}
              >
                {createChallenge.isPending ? 'Posting...' : 'Post Challenge'}
              </button>
            </div>
          </div>
        </div>
      )}

      {fight.error && <ErrorBanner message={(fight.error as Error).message} />}
      {createChallenge.error && <ErrorBanner message={(createChallenge.error as Error).message} />}
      {acceptChallenge.error && <ErrorBanner message={(acceptChallenge.error as Error).message} />}
      {cancelChallenge.error && <ErrorBanner message={(cancelChallenge.error as Error).message} />}

      {/* ---------- Arena: who's online + open challenge board ---------- */}
      <div className="mt-8">
        <div className="mb-2 flex items-center gap-1.5 text-[11px] font-bold tracking-wide text-text-faint uppercase">
          <Users size={12} /> In the Arena ({online?.length ?? 0})
        </div>
        {online && online.filter((p) => p.wallet.toLowerCase() !== wallet.toLowerCase()).length > 0 ? (
          <div className="flex flex-wrap gap-1.5">
            {online
              .filter((p) => p.wallet.toLowerCase() !== wallet.toLowerCase())
              .map((p) => (
                <button
                  key={p.wallet}
                  type="button"
                  onClick={() => {
                    setChallengingPlayer(p.wallet)
                    setChallengeCreature(null)
                    setChallengeWager(0)
                  }}
                  className="card-pop-sm hud-num group flex items-center gap-1.5 rounded-full border-2 border-border bg-surface px-2.5 py-1.5 text-[11px] transition-all active:scale-[0.97] hover:border-[var(--color-brand-red)]"
                  title="Challenge this player"
                >
                  <span className="relative flex h-2 w-2">
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full opacity-60 motion-reduce:animate-none" style={{ background: 'var(--color-up)' }} />
                    <span className="relative inline-flex h-2 w-2 rounded-full" style={{ background: 'var(--color-up)' }} />
                  </span>
                  {shortAddress(p.wallet)}
                  {p.battling && (
                    <span className="rounded-full px-1.5 py-0.5 text-[9px] font-bold text-white" style={{ background: 'var(--color-brand-red)' }}>
                      OPEN
                    </span>
                  )}
                  <Swords size={11} className="text-text-faint transition-colors group-hover:text-[var(--color-brand-red)]" />
                </button>
              ))}
          </div>
        ) : (
          <p className="text-xs text-text-faint">No one else is around right now.</p>
        )}
      </div>

      <div className="mt-5">
        <div className="mb-2 text-[11px] font-bold tracking-wide text-text-faint uppercase">Open Challenges</div>
        {openChallenges && openChallenges.length > 0 ? (
          <div className="flex flex-col gap-2">
            {openChallenges.map((c) => {
              const isMine = c.challengerWallet.toLowerCase() === wallet.toLowerCase()
              return (
                <div
                  key={c.id}
                  className="card-pop-sm flex items-center gap-3 rounded-2xl border-[3px] bg-surface p-3 transition-colors"
                  style={{ borderColor: isMine ? 'var(--color-border)' : 'var(--color-brand-red)' }}
                >
                  <RarityIcon rarity={c.challengerRarity} emoji={speciesEmoji(c.challengerSpecies)} species={c.challengerSpecies} size="sm" />
                  <div className="flex-1">
                    <div className="text-sm font-bold">
                      {speciesName(c.challengerSpecies)} <span style={{ color: 'var(--color-up)' }}>Lv{c.challengerLevel}</span>
                    </div>
                    <div className="font-mono text-[10px] text-text-faint">
                      {isMine ? 'You' : shortAddress(c.challengerWallet)} &middot; {timeAgo(c.createdAt)}
                      {wagerEth(c.wagerWei) > 0 && (
                        <span className="ml-1.5" style={{ color: 'var(--color-brand-yellow)' }}>
                          &middot; {wagerEth(c.wagerWei)} ETH wager
                        </span>
                      )}
                    </div>
                  </div>
                  {isMine ? (
                    <button
                      type="button"
                      disabled={cancelChallenge.isPending}
                      onClick={() => cancelChallenge.mutate(c)}
                      className="flex items-center gap-1 rounded-full border-2 px-3 py-1.5 text-xs font-bold disabled:opacity-60"
                      style={{ borderColor: 'var(--color-down)', color: 'var(--color-down)' }}
                    >
                      <X size={12} /> Cancel
                    </button>
                  ) : (
                    <button
                      type="button"
                      onClick={() => {
                        setAcceptingChallenge(c)
                        setAcceptCreature(null)
                      }}
                      className="rounded-full px-4 py-1.5 text-xs font-bold text-white"
                      style={{ background: 'var(--color-brand-red)' }}
                    >
                      Accept
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        ) : (
          <p className="text-xs text-text-faint">No open challenges -- post one above to start the arena.</p>
        )}
      </div>

      {history && history.length > 0 && (
        <div className="mt-6">
          <div className="mb-2 text-[11px] font-bold tracking-wide text-text-faint uppercase">Recent Battles</div>
          <div className="flex flex-col gap-1.5">
            {history.slice(0, 8).map((h, i) => (
              <div key={i} className="flex items-center justify-between rounded-xl border border-border bg-surface px-3 py-2 text-xs">
                <span className="flex items-center gap-2">
                  <span className="text-lg">{speciesEmoji(h.opponentSpecies)}</span>
                  <span className="font-semibold">vs {speciesName(h.opponentSpecies)}</span>
                </span>
                <span className="font-bold" style={{ color: h.won ? 'var(--color-up)' : 'var(--color-down)' }}>
                  {h.won ? 'Won' : 'Lost'}
                </span>
                <span className="hud-num text-text-faint">{timeAgo(h.createdAt)}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ---------- Accept-challenge creature picker ---------- */}
      {acceptingChallenge && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm md:items-center" onClick={() => setAcceptingChallenge(null)}>
          <div className="card-pop w-full max-w-md rounded-t-3xl border-[3px] border-border bg-surface p-6 md:rounded-3xl" onClick={(e) => e.stopPropagation()}>
            <h2 className="font-display text-lg font-extrabold">
              Accept Challenge from {shortAddress(acceptingChallenge.challengerWallet)}
            </h2>
            <p className="mt-1 text-xs text-text-muted">
              Their {speciesName(acceptingChallenge.challengerSpecies)} (Lv{acceptingChallenge.challengerLevel}) is waiting. Pick your Animora.
            </p>
            {wagerEth(acceptingChallenge.wagerWei) > 0 && (
              <p className="mt-1 text-xs font-bold" style={{ color: 'var(--color-brand-yellow)' }}>
                {wagerEth(acceptingChallenge.wagerWei)} ETH is on the line -- accepting will prompt your wallet to stake it,
                then the winner takes both stakes minus the platform fee.
              </p>
            )}
            <div className="mt-3">
              <CreaturePicker creatures={creatures} selected={acceptCreature} onSelect={setAcceptCreature} />
            </div>
            <div className="mt-4 flex gap-2">
              <button
                type="button"
                disabled={!acceptCreature || acceptChallenge.isPending}
                onClick={() =>
                  acceptChallenge.mutate(
                    { challenge: acceptingChallenge, creatureTokenId: acceptCreature! },
                    {
                      onSuccess: (r) => {
                        const mine = creatures.find((c) => c.tokenId === acceptCreature)
                        setDuel({
                          you: { label: speciesName(r.playerSpecies), species: r.playerSpecies, rarity: mine?.rarity ?? 1, level: r.playerLevel, hp: r.playerHp, maxHp: r.playerMaxHp },
                          opponent: {
                            label: shortAddress(acceptingChallenge.challengerWallet),
                            species: r.opponentSpecies,
                            rarity: r.opponentRarity,
                            level: r.opponentLevel,
                            hp: r.opponentHp,
                            maxHp: r.opponentMaxHp,
                          },
                          won: r.won,
                          rounds: r.rounds,
                          log: r.log,
                          rewardFeed: r.rewardFeed,
                          xpAwarded: r.xpAwarded,
                          wagerWei: r.wagerWei,
                          wagerWon: r.wagerWon,
                        })
                        setAcceptingChallenge(null)
                      },
                    },
                  )
                }
                className="flex-1 rounded-full py-2.5 text-sm font-bold text-white disabled:opacity-60"
                style={{ background: 'var(--color-brand-red)' }}
              >
                {acceptChallenge.isPending ? 'Fighting...' : 'Fight!'}
              </button>
              <button type="button" onClick={() => setAcceptingChallenge(null)} className="rounded-full px-4 py-2.5 text-sm font-bold text-text-muted">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ---------- Challenge a specific online player ---------- */}
      {challengingPlayer && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm md:items-center" onClick={() => setChallengingPlayer(null)}>
          <div className="card-pop w-full max-w-md rounded-t-3xl border-[3px] border-border bg-surface p-6 md:rounded-3xl" onClick={(e) => e.stopPropagation()}>
            <h2 className="font-display text-lg font-extrabold">Challenge {shortAddress(challengingPlayer)}</h2>
            <p className="mt-1 text-xs text-text-muted">
              They'll get a live notification. Pick your Animora and, if you want, stake some ETH/ARB on the line.
            </p>
            <div className="mt-3">
              <CreaturePicker creatures={creatures} selected={challengeCreature} onSelect={setChallengeCreature} />
            </div>
            <div className="mt-3 flex justify-center">
              <WagerStepper value={challengeWager} onChange={setChallengeWager} />
            </div>
            <div className="mt-4 flex gap-2">
              <button
                type="button"
                disabled={!challengeCreature || createChallenge.isPending}
                onClick={() =>
                  createChallenge.mutate(
                    { creatureTokenId: challengeCreature!, challengedWallet: challengingPlayer, wagerWei: wagerToWei(challengeWager) },
                    { onSuccess: () => setChallengingPlayer(null) },
                  )
                }
                className="flex-1 rounded-full py-2.5 text-sm font-bold text-white disabled:opacity-60"
                style={{ background: 'var(--color-brand-blue)' }}
              >
                {createChallenge.isPending ? 'Sending...' : 'Send Challenge'}
              </button>
              <button type="button" onClick={() => setChallengingPlayer(null)} className="rounded-full px-4 py-2.5 text-sm font-bold text-text-muted">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {duel && <BattleDuelModal {...duel} onClose={() => setDuel(null)} />}
    </div>
  )
}
