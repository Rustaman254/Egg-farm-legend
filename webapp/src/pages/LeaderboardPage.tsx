import { Swords, Trophy } from 'lucide-react'
import { useState } from 'react'
import { formatEther } from 'viem'
import { SectionHeader } from '../components/SectionHeader'
import { useTopBattlers, useTopEarners } from '../hooks/useLeaderboard'

type Tab = 'battlers' | 'earners'

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

function medalColor(rank: number): string {
  if (rank === 0) return 'var(--color-brand-yellow)'
  if (rank === 1) return '#c0c0c0'
  if (rank === 2) return '#cd7f32'
  return 'var(--color-text-faint)'
}

function Row({ rank, address, isMe, primary, secondary }: { rank: number; address: string; isMe: boolean; primary: string; secondary: string }) {
  return (
    <div
      className="card-pop-sm flex items-center gap-3 rounded-xl border-2 bg-surface px-3 py-2.5"
      style={{ borderColor: isMe ? 'var(--color-brand-blue)' : 'var(--color-border)' }}
    >
      <div className="hud-num flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white" style={{ background: medalColor(rank) }}>
        {rank + 1}
      </div>
      <div className="flex-1">
        <div className="hud-num text-sm font-bold">
          {shortAddress(address)} {isMe && <span style={{ color: 'var(--color-brand-blue)' }}>(You)</span>}
        </div>
        <div className="text-[11px] text-text-muted">{secondary}</div>
      </div>
      <div className="hud-num text-sm font-bold" style={{ color: 'var(--color-brand-red-dark)' }}>
        {primary}
      </div>
    </div>
  )
}

export function LeaderboardPage({ wallet }: { wallet: string }) {
  const [tab, setTab] = useState<Tab>('battlers')
  const { data: battlers, isLoading: loadingBattlers } = useTopBattlers()
  const { data: earners, isLoading: loadingEarners } = useTopEarners()

  return (
    <div className="mx-auto max-w-2xl">
      <SectionHeader icon={Trophy} title="Leaderboard" />

      <div className="mb-4 flex gap-2">
        <button
          type="button"
          onClick={() => setTab('battlers')}
          className={`flex items-center gap-1.5 rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${tab === 'battlers' ? 'text-white' : 'bg-surface-2 text-text-muted hover:text-text'}`}
          style={tab === 'battlers' ? { background: 'var(--color-brand-red)' } : undefined}
        >
          <Swords size={13} /> Top Trainers
        </button>
        <button
          type="button"
          onClick={() => setTab('earners')}
          className={`flex items-center gap-1.5 rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${tab === 'earners' ? 'text-white' : 'bg-surface-2 text-text-muted hover:text-text'}`}
          style={tab === 'earners' ? { background: 'var(--color-brand-red)' } : undefined}
        >
          <Trophy size={13} /> Top Traders
        </button>
      </div>

      {tab === 'battlers' && (
        <>
          {loadingBattlers && <div className="flex h-32 items-center justify-center text-text-faint">Loading...</div>}
          {!loadingBattlers && (!battlers || battlers.length === 0) && (
            <div className="rounded-2xl border border-border bg-surface p-8 text-center text-text-muted">
              No battles fought yet. Be the first champion in the Battle Arena!
            </div>
          )}
          <div className="flex flex-col gap-2">
            {(battlers ?? []).map((b, i) => (
              <Row
                key={b.wallet}
                rank={i}
                address={b.wallet}
                isMe={b.wallet.toLowerCase() === wallet.toLowerCase()}
                primary={`${b.wins} wins`}
                secondary={`${b.total} battles fought`}
              />
            ))}
          </div>
        </>
      )}

      {tab === 'earners' && (
        <>
          {loadingEarners && <div className="flex h-32 items-center justify-center text-text-faint">Loading...</div>}
          {!loadingEarners && (!earners || earners.length === 0) && (
            <div className="rounded-2xl border border-border bg-surface p-8 text-center text-text-muted">
              No sales yet. List something on the Marketplace to get on the board!
            </div>
          )}
          <div className="flex flex-col gap-2">
            {(earners ?? []).map((e, i) => (
              <Row
                key={e.wallet}
                rank={i}
                address={e.wallet}
                isMe={e.wallet.toLowerCase() === wallet.toLowerCase()}
                primary={`${Number(formatEther(BigInt(e.totalWei))).toFixed(2)} ARB`}
                secondary={`${e.sales} sale${e.sales === 1 ? '' : 's'}`}
              />
            ))}
          </div>
        </>
      )}
    </div>
  )
}
