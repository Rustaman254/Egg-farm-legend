import { ArrowDownRight, ArrowUpRight, LayoutGrid, Plus, Sparkles, Wallet, Wheat } from 'lucide-react'
import { useEffect, useRef, useState, type CSSProperties } from 'react'
import { NavLink } from 'react-router-dom'
import { formatEther, formatUnits } from 'viem'
import { addFeedTokenToWallet } from '../blockchain/actions'
import { ErrorBanner, PendingBanner } from '../components/Banner'
import { CreatureTicker } from '../components/CreatureTicker'
import { SectionHeader } from '../components/SectionHeader'
import { CATEGORY_TILES } from '../config/constants'
import { farmerLevelInfo } from '../config/farmerLevel'
import { useFarm, useFeedCreature, useLayEgg } from '../hooks/useFarm'

/** Tracks how the wallet's native (ETH/ARB) balance has moved since the last time this hook saw
 *  it, persisted in localStorage so the delta survives a page reload (not just this session) --
 *  the "system always checking the wallet" ask this powers is meant to feel continuous, not reset
 *  every time the tab refreshes. Purely a per-viewer display convenience: never read back by
 *  anything else, so it's fine if it's empty in a fresh/private browser. */
function useNativeBalanceDelta(wallet: string, currentWei: string | undefined) {
  const [delta, setDelta] = useState<bigint | null>(null)

  useEffect(() => {
    if (currentWei === undefined) return
    const key = `eggfarm:lastNativeBalance:${wallet.toLowerCase()}`
    let current: bigint
    try {
      current = BigInt(currentWei)
    } catch {
      return
    }
    try {
      const stored = localStorage.getItem(key)
      if (stored) {
        const previous = BigInt(stored)
        if (previous !== current) setDelta(current - previous)
      }
      localStorage.setItem(key, currentWei)
    } catch {
      // localStorage unavailable (private window, blocked site data, etc.) -- delta just won't show.
    }
  }, [wallet, currentWei])

  return delta
}

export function FarmPage({ wallet }: { wallet: string }) {
  const { data: farm, isLoading, error } = useFarm(wallet)
  const feed = useFeedCreature(wallet)
  const layEgg = useLayEgg(wallet)
  const [actingOn, setActingOn] = useState<{ tokenId: number; kind: 'feed' | 'egg' } | null>(null)
  const [addingToWallet, setAddingToWallet] = useState(false)
  const tickerRef = useRef<HTMLDivElement>(null)

  const creatures = farm?.creatures ?? []
  const feedBalance = farm ? formatUnits(BigInt(farm.feedBalance), 18) : '0'
  const nativeBalanceDelta = useNativeBalanceDelta(wallet, farm?.nativeBalanceWei)
  const levelInfo = farmerLevelInfo(farm?.xp ?? 0)

  const scrollTicker = (dir: 1 | -1) => tickerRef.current?.scrollBy({ left: dir * 320, behavior: 'smooth' })

  return (
    <div className="mx-auto flex max-w-6xl flex-col gap-8">
      {/* Hero */}
      <div className="card-pop relative overflow-hidden rounded-3xl border-[3px] border-border bg-surface">
        <div className="arcade-grid pointer-events-none absolute inset-0" />
        <div className="relative grid grid-cols-1 gap-6 p-6 sm:p-8 md:grid-cols-[1.3fr_1fr]">
          <div className="flex flex-col justify-center gap-4">
            <div
              className="w-fit rounded-full px-3 py-1 hud-num text-[11px] tracking-wider text-white uppercase"
              style={{ background: 'var(--color-brand-blue)' }}
            >
              ⚡ Live on Arbitrum
            </div>
            <h1 className="font-display text-2xl font-extrabold tracking-tight sm:text-3xl">
              Gotta Breed <span style={{ color: 'var(--color-brand-red)' }}>'Em All</span>
            </h1>
            <p className="max-w-md text-sm text-text-muted">
              Buy an egg, hatch it, and battle it while it matures -- once it's grown you can list it on the
              Marketplace, or breed two Animoras for a new egg. Complete daily tasks for $FEED to keep everyone fed.
            </p>

            <div className="card-pop-sm flex items-center gap-3 rounded-2xl border-2 border-border bg-surface-2 px-3 py-2.5">
              <div
                className="hud-num flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-extrabold text-white"
                style={{ background: 'var(--color-brand-blue)' }}
              >
                {levelInfo.level}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="truncate text-xs font-bold">{levelInfo.title}</span>
                  <span className="hud-num shrink-0 text-[10px] text-text-faint">
                    {levelInfo.xpIntoLevel}/{levelInfo.xpForLevel} XP
                  </span>
                </div>
                <div className="mt-1 h-2 w-full overflow-hidden rounded-full border border-border bg-surface">
                  <div
                    className="h-full rounded-full transition-all duration-500"
                    style={{ width: `${levelInfo.progress * 100}%`, background: 'var(--color-brand-blue)' }}
                  />
                </div>
              </div>
            </div>

            <NavLink
              to="/marketplace?kind=egg"
              className="card-pop-sm w-fit rounded-full px-6 py-3 font-display text-sm font-bold text-white transition-transform active:scale-[0.98]"
              style={{ background: 'var(--color-brand-red)' }}
            >
              Buy an Egg
            </NavLink>
          </div>

          <div
            className="relative flex flex-col justify-center gap-2 overflow-hidden rounded-2xl border-[3px] p-5"
            style={{ borderColor: 'var(--color-brand-yellow)', background: 'color-mix(in srgb, var(--color-brand-yellow) 16%, var(--color-surface))' }}
          >
            <div className="flex items-center gap-1.5 text-[11px] font-bold tracking-wide uppercase" style={{ color: 'var(--color-brand-yellow)' }}>
              <Sparkles size={13} /> Your Balance
            </div>
            <div className="hud-num text-4xl">
              {Number(feedBalance).toFixed(0)} <span className="text-lg text-text-muted">FEED</span>
            </div>
            <p className="text-xs text-text-muted">Earn more by completing tasks and collecting eggs.</p>
            <div className="mt-1 flex flex-wrap items-center gap-3">
              <NavLink to="/tasks" className="w-fit text-xs font-bold hover:underline" style={{ color: 'var(--color-brand-blue)' }}>
                View Tasks &rarr;
              </NavLink>
              <button
                type="button"
                disabled={addingToWallet}
                onClick={() => {
                  setAddingToWallet(true)
                  addFeedTokenToWallet().finally(() => setAddingToWallet(false))
                }}
                className="flex w-fit items-center gap-1 text-xs font-bold hover:underline disabled:opacity-60"
                style={{ color: 'var(--color-brand-red-dark)' }}
              >
                <Plus size={12} /> {addingToWallet ? 'Adding...' : 'Add FEED to Wallet'}
              </button>
            </div>
          </div>
        </div>

        {farm && (
          <div className="relative mx-6 mb-6 flex items-center gap-3 rounded-2xl border-2 border-border bg-surface-2 px-4 py-3 sm:mx-8">
            <Wallet size={18} className="shrink-0" style={{ color: 'var(--color-brand-blue)' }} />
            <div className="min-w-0 flex-1">
              <div className="text-[10px] font-bold tracking-wide text-text-faint uppercase">Wallet Balance</div>
              <div className="hud-num text-lg font-bold">
                {Number(formatEther(BigInt(farm.nativeBalanceWei))).toFixed(4)} <span className="text-xs text-text-muted">ETH</span>
              </div>
            </div>
            {nativeBalanceDelta !== null && nativeBalanceDelta !== 0n && (
              <div
                className="hud-num flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold"
                style={{
                  color: nativeBalanceDelta > 0n ? 'var(--color-up)' : 'var(--color-down)',
                  background: nativeBalanceDelta > 0n ? 'color-mix(in srgb, var(--color-up) 15%, transparent)' : 'color-mix(in srgb, var(--color-down) 15%, transparent)',
                }}
              >
                {nativeBalanceDelta > 0n ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}
                {nativeBalanceDelta > 0n ? '+' : '-'}
                {Number(formatEther(nativeBalanceDelta < 0n ? -nativeBalanceDelta : nativeBalanceDelta)).toFixed(4)} ETH
              </div>
            )}
          </div>
        )}
      </div>

      {/* My Animoras ticker row */}
      <section>
        <SectionHeader
          icon={Wheat}
          title="My Animoras"
          action={
            <NavLink to="/marketplace?kind=egg" className="text-xs font-bold text-brand-pink hover:underline">
              + Buy an Egg
            </NavLink>
          }
          onScrollLeft={() => scrollTicker(-1)}
          onScrollRight={() => scrollTicker(1)}
        />

        {isLoading ? (
          <div className="flex h-32 items-center justify-center text-text-faint">Loading your farm...</div>
        ) : error ? (
          <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>
        ) : creatures.length === 0 ? (
          <div className="flex flex-col items-center gap-3 rounded-2xl border border-border bg-surface p-10 text-center">
            <div className="text-4xl">🐣</div>
            <div className="font-display font-bold">Your farm is empty</div>
            <p className="text-sm text-text-muted">Buy an egg from the Marketplace and hatch your first Animora</p>
            <NavLink to="/marketplace?kind=egg" className="mt-1 rounded-full brand-gradient px-5 py-2.5 text-sm font-bold text-white">
              Buy Your First Egg
            </NavLink>
          </div>
        ) : (
          <div ref={tickerRef} className="scrollbar-none flex gap-3 overflow-x-auto pb-1">
            {creatures.map((creature) => (
              <CreatureTicker
                key={creature.tokenId}
                creature={creature}
                feeding={feed.isPending && actingOn?.tokenId === creature.tokenId && actingOn.kind === 'feed'}
                collecting={layEgg.isPending && actingOn?.tokenId === creature.tokenId && actingOn.kind === 'egg'}
                onFeed={() => {
                  setActingOn({ tokenId: creature.tokenId, kind: 'feed' })
                  feed.mutate(creature.tokenId)
                }}
                onCollectEgg={() => {
                  setActingOn({ tokenId: creature.tokenId, kind: 'egg' })
                  layEgg.mutate(creature.tokenId)
                }}
              />
            ))}
          </div>
        )}
      </section>

      {/* Quick actions category grid */}
      <section>
        <SectionHeader icon={LayoutGrid} title="Quick Actions" />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {CATEGORY_TILES.map((tile) => (
            <NavLink
              key={tile.label}
              to={tile.to}
              className="glossy group relative flex aspect-square flex-col items-center justify-center gap-2 rounded-2xl text-white transition-transform hover:-translate-y-1 hover:scale-[1.02] active:scale-[0.97]"
              style={
                {
                  '--glossy-from': tile.color,
                  '--glossy-to': `color-mix(in srgb, ${tile.color} 60%, black)`,
                } as CSSProperties
              }
            >
              <div className="absolute inset-0 z-[1] bg-black/0 transition-colors group-hover:bg-white/10" />
              <span className="relative z-[2] text-4xl drop-shadow-[0_3px_6px_rgba(0,0,0,0.45)]">{tile.icon}</span>
              <span className="relative z-[2] font-display text-sm font-extrabold tracking-wide uppercase drop-shadow-[0_1px_3px_rgba(0,0,0,0.5)]">
                {tile.label}
              </span>
            </NavLink>
          ))}
        </div>
      </section>

      {(feed.isPending || layEgg.isPending) && (
        <PendingBanner message={layEgg.isPending ? 'Collecting egg...' : 'Feeding...'} />
      )}
      {feed.error && <ErrorBanner message={(feed.error as Error).message} />}
      {layEgg.error && <ErrorBanner message={(layEgg.error as Error).message} />}
    </div>
  )
}
