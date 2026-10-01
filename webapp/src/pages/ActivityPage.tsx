import { Activity as ActivityIcon, ArrowDownLeft, ArrowDownRight, ArrowUpRight, Coins, Wallet } from 'lucide-react'
import { formatEther, formatUnits } from 'viem'
import { SectionHeader } from '../components/SectionHeader'
import { speciesEmoji, speciesName } from '../config/constants'
import { useActivity } from '../hooks/useActivity'
import type { PlatformTxEntry } from '../api/types'

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

function timeAgo(iso: string): string {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (seconds < 60) return 'just now'
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
  return `${Math.floor(seconds / 86400)}d ago`
}

const PLATFORM_TX_LABEL: Record<PlatformTxEntry['source'], { label: string; icon: typeof Coins }> = {
  wager_rake: { label: 'Platform fee (wager)', icon: ArrowUpRight },
  quest_funding: { label: 'Funded a quest', icon: ArrowUpRight },
  feed_shop: { label: 'Bought FEED', icon: ArrowDownLeft },
}

export function ActivityPage({ wallet }: { wallet: string }) {
  const { data, isLoading, error } = useActivity(wallet)

  return (
    <div className="mx-auto max-w-3xl">
      <SectionHeader icon={ActivityIcon} title="Activity" />
      <p className="mb-5 -mt-2 text-xs text-text-muted">
        Everything that's moved $FEED or ETH/ARB on your account: live wallet balance changes and marketplace trades,
        battle results, wagered duels, and your own purchases/payments (Feed Shop, quest funding, wager fees).
      </p>

      {isLoading && <div className="flex h-64 items-center justify-center text-text-faint">Loading activity...</div>}
      {error && <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>}

      {data && (
        <div className="flex flex-col gap-8">
          <section>
            <div className="mb-2 flex items-center gap-1.5 text-[11px] font-bold tracking-wide text-text-faint uppercase">
              <ActivityIcon size={12} /> Wallet Activity
            </div>
            {data.walletEvents.length === 0 ? (
              <p className="text-xs text-text-faint">Nothing's happened to your wallet yet -- this fills in live as you play.</p>
            ) : (
              <div className="flex flex-col gap-1.5">
                {data.walletEvents.map((e) => {
                  const isDown = e.kind === 'balance_down'
                  return (
                    <div key={e.id} className="flex items-center justify-between rounded-xl border border-border bg-surface px-3 py-2 text-xs">
                      <span className="flex items-center gap-2">
                        {isDown ? (
                          <ArrowDownRight size={12} style={{ color: 'var(--color-down)' }} />
                        ) : (
                          <ArrowUpRight size={12} style={{ color: 'var(--color-up)' }} />
                        )}
                        <span className="font-semibold">{e.message}</span>
                      </span>
                      <span className="hud-num text-text-faint">{timeAgo(e.createdAt)}</span>
                    </div>
                  )
                })}
              </div>
            )}
          </section>

          <section>
            <div className="mb-2 flex items-center gap-1.5 text-[11px] font-bold tracking-wide text-text-faint uppercase">
              <Wallet size={12} /> Wagered Duels
            </div>
            {data.wagers.length === 0 ? (
              <p className="text-xs text-text-faint">No wagered duels yet.</p>
            ) : (
              <div className="flex flex-col gap-1.5">
                {data.wagers.map((w) => (
                  <div key={w.challengeId} className="flex items-center justify-between rounded-xl border border-border bg-surface px-3 py-2 text-xs">
                    <span className="flex items-center gap-2">
                      <span className={w.won ? 'text-up' : 'text-down'}>{w.won ? '▲' : '▼'}</span>
                      <span className="font-semibold">vs {shortAddress(w.opponentWallet)}</span>
                    </span>
                    <span className="hud-num font-bold" style={{ color: w.won ? 'var(--color-up)' : 'var(--color-down)' }}>
                      {w.won ? '+' : '-'}
                      {formatEther(BigInt(w.wagerWei))} ETH
                    </span>
                    <span className="hud-num text-text-faint">{timeAgo(w.resolvedAt)}</span>
                  </div>
                ))}
              </div>
            )}
          </section>

          <section>
            <div className="mb-2 flex items-center gap-1.5 text-[11px] font-bold tracking-wide text-text-faint uppercase">
              <Coins size={12} /> Payments
            </div>
            {data.platformTx.length === 0 ? (
              <p className="text-xs text-text-faint">No Feed Shop purchases or quest funding payments yet.</p>
            ) : (
              <div className="flex flex-col gap-1.5">
                {data.platformTx.map((tx, i) => {
                  const meta = PLATFORM_TX_LABEL[tx.source]
                  const Icon = meta.icon
                  const feedWhole = Number(formatUnits(BigInt(tx.feedAmount || '0'), 18))
                  return (
                    <div key={i} className="flex items-center justify-between rounded-xl border border-border bg-surface px-3 py-2 text-xs">
                      <span className="flex items-center gap-2">
                        <Icon size={12} className="text-text-faint" />
                        <span className="font-semibold">{meta.label}</span>
                      </span>
                      <span className="hud-num text-text-muted">
                        {tx.nativeAmountWei !== '0' && `${formatEther(BigInt(tx.nativeAmountWei))} ETH`}
                        {tx.nativeAmountWei !== '0' && feedWhole > 0 && ' · '}
                        {feedWhole > 0 && `+${feedWhole.toFixed(0)} FEED`}
                      </span>
                      <span className="hud-num text-text-faint">{timeAgo(tx.createdAt)}</span>
                    </div>
                  )
                })}
              </div>
            )}
          </section>

          <section>
            <div className="mb-2 text-[11px] font-bold tracking-wide text-text-faint uppercase">Recent Battles</div>
            {data.battles.length === 0 ? (
              <p className="text-xs text-text-faint">No battles yet -- head to the Battle Arena.</p>
            ) : (
              <div className="flex flex-col gap-1.5">
                {data.battles.map((h, i) => (
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
            )}
          </section>
        </div>
      )}
    </div>
  )
}
