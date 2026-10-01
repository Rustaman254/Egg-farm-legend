import { ClipboardList, Globe, Plus, ShieldCheck, Users } from 'lucide-react'
import { useState, type CSSProperties } from 'react'
import { formatUnits } from 'viem'
import { ErrorBanner } from '../components/Banner'
import { CreateQuestModal } from '../components/CreateQuestModal'
import { ApiError } from '../api/client'
import { useFundTask } from '../hooks/useFeedShop'
import { useClaimTask, useCreateTask, useRecordLogin, useTasks } from '../hooks/useTasks'
import type { GameTask, TaskCategory } from '../api/types'

// Must match the backend's FEED_PER_NATIVE_UNIT (see backend/.env) -- how much $FEED funding 1
// ARB buys for a partner quest's reward pool.
const FEED_PER_NATIVE_UNIT = 100

const EMOJI_BY_TASK_ID: Record<string, string> = {
  feed_3_times: '🌾',
  collect_1_egg: '🥚',
  daily_login: '📅',
  list_1_item: '🏷️',
  play_minigame: '⚔️',
  breed_1_creature: '🧬',
  tend_1_egg: '🩺',
  win_3_battles: '🏆',
  arb_holder: '💰',
  active_wallet: '⚡',
  arb_token_holder: '🏛️',
  arb_token_received: '📥',
  arbitrum_veteran: '🎖️',
}

const EMOJI_BY_CATEGORY: Record<TaskCategory, string> = { game: '🎮', ecosystem: '🌐', partner: '🤝' }

const ONCHAIN_LABEL_BY_CHECK_TYPE: Record<string, string> = {
  manual: 'in-game event',
  native_balance: 'ETH balance check',
  token_balance: 'token balance check',
  tx_count: 'transaction count',
  token_received: 'token transfer received',
  contract_event: 'contract activity',
  view_function: 'onchain value check',
  named_event: 'specific action verified',
}

const CATEGORY_META: Record<TaskCategory, { label: string; icon: typeof Globe; hint: string }> = {
  game: { label: 'Farm Tasks', icon: ShieldCheck, hint: 'Verified onchain' },
  ecosystem: { label: 'Arbitrum Ecosystem', icon: Globe, hint: 'Verified via Arbitrum' },
  partner: { label: 'Community Quests', icon: Users, hint: 'Created by other players and protocols' },
}

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

/** A Pokemon-TCG-styled task card: colored border by status, circular icon badge with a holo
 *  sweep once claimable, dashed-rule stat row, and a footer action -- mirrors CreatureCard /
 *  ListingCard so tasks read as the same kind of collectible object as the rest of the game. */
function TaskCard({ task, onClaim, claiming, wallet }: { task: GameTask; onClaim: () => void; claiming: boolean; wallet: string }) {
  const emoji = EMOJI_BY_TASK_ID[task.taskId] ?? EMOJI_BY_CATEGORY[task.category]
  const isCompleted = !!task.completedAt
  const isClaimable = isCompleted && !task.rewardClaimed
  const isClaimed = !!task.rewardClaimed
  const progress = task.targetCount === 0 ? 0 : Math.min(1, task.currentCount / task.targetCount)
  const rewardWhole = Number(formatUnits(BigInt(task.rewardFeed), 18))
  const BadgeIcon = CATEGORY_META[task.category].icon
  const accent = isClaimed ? 'var(--color-up)' : isClaimable ? 'var(--color-brand-red)' : 'var(--color-border)'

  const isPartnerQuest = task.category === 'partner' && !!task.creatorAddress
  const fundedWhole = isPartnerQuest ? Number(formatUnits(BigInt(task.fundedFeed ?? '0'), 18)) : 0
  const isUnderfunded = isPartnerQuest && fundedWhole < rewardWhole
  const fundTask = useFundTask()
  const isCreator = isPartnerQuest && task.creatorAddress?.toLowerCase() === wallet.toLowerCase()
  const priceWeiForOneClaim = () => (BigInt(task.rewardFeed) / BigInt(FEED_PER_NATIVE_UNIT)).toString()

  return (
    <div
      className="card-pop-sm flex flex-col items-center gap-2 rounded-2xl border-[3px] bg-surface p-4 text-center"
      style={{ borderColor: accent }}
    >
      <div
        className="glossy relative flex h-16 w-16 items-center justify-center rounded-full border-[3px] text-3xl"
        style={{ borderColor: accent, '--glossy-from': `${accent}cc`, '--glossy-to': `${accent}55`, '--glossy-glow': `${accent}66` } as CSSProperties}
      >
        {emoji}
        {isClaimable && <div className="holo-foil absolute inset-0 rounded-full" />}
      </div>

      <span className="flex items-center gap-0.5 rounded-full bg-surface-2 px-1.5 py-0.5 text-[9px] font-bold tracking-wide text-text-faint uppercase">
        <BadgeIcon size={9} /> {CATEGORY_META[task.category].hint}
      </span>

      <div className="font-display text-sm font-bold leading-tight">{task.title}</div>
      <div className="text-xs text-text-muted">{task.description}</div>

      <div className="mt-1 h-2 w-full overflow-hidden rounded-full border border-border bg-surface-2">
        <div
          className="h-full rounded-full"
          style={{ width: `${progress * 100}%`, background: isCompleted ? 'var(--color-up)' : 'var(--color-brand-red)' }}
        />
      </div>
      <div className="font-mono text-[11px] text-text-faint">
        {task.currentCount}/{task.targetCount} &middot; +{rewardWhole.toFixed(0)} FEED
      </div>
      <div className="border-t border-dashed border-border pt-1.5 font-mono text-[10px] text-text-faint">
        {task.category === 'partner' && task.creatorAddress
          ? `by ${shortAddress(task.creatorAddress)} · ${ONCHAIN_LABEL_BY_CHECK_TYPE[task.checkType] ?? task.checkType}`
          : `from ${ONCHAIN_LABEL_BY_CHECK_TYPE[task.checkType] ?? task.checkType}`}
      </div>

      {isPartnerQuest && (
        <div className="w-full font-mono text-[10px]" style={{ color: isUnderfunded ? 'var(--color-down)' : 'var(--color-up)' }}>
          Funded: {fundedWhole.toFixed(0)} FEED{isUnderfunded ? ' (needs topping up)' : ''}
        </div>
      )}

      <div className="mt-1 w-full">
        {isClaimed ? (
          <span className="flex items-center justify-center gap-1 text-sm font-bold text-up">✓ Claimed</span>
        ) : isUnderfunded ? (
          <button
            type="button"
            disabled={fundTask.isPending}
            onClick={() => fundTask.mutate({ taskId: task.taskId, funderAddress: wallet, priceWei: priceWeiForOneClaim() })}
            className="w-full rounded-full px-4 py-2 text-sm font-bold text-white disabled:opacity-60"
            style={{ background: 'var(--color-brand-blue)' }}
            title={isCreator ? undefined : 'Anyone can top up a quest, not just its creator'}
          >
            {fundTask.isPending ? 'Funding...' : `Fund ${rewardWhole.toFixed(0)} FEED`}
          </button>
        ) : !isCompleted ? (
          <span className="flex items-center justify-center gap-1 text-sm text-text-faint">⏳ In progress</span>
        ) : (
          <button
            type="button"
            disabled={claiming}
            onClick={onClaim}
            className="glow-pulse w-full rounded-full px-4 py-2 text-sm font-bold text-white disabled:animate-none disabled:opacity-60"
            style={{ background: 'var(--color-brand-red)' }}
          >
            {claiming ? '...' : 'Claim'}
          </button>
        )}
      </div>
      {fundTask.error && <div className="w-full text-[10px] font-bold text-down">{(fundTask.error as Error).message}</div>}
    </div>
  )
}

function TaskSection({
  category,
  tasks,
  claim,
  wallet,
}: {
  category: TaskCategory
  tasks: GameTask[]
  claim: ReturnType<typeof useClaimTask>
  wallet: string
}) {
  if (tasks.length === 0) return null
  const meta = CATEGORY_META[category]
  const Icon = meta.icon
  return (
    <div className="mb-6">
      <div className="mb-2 flex items-center gap-1.5 text-[11px] font-bold tracking-wide text-text-faint uppercase">
        <Icon size={12} /> {meta.label}
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {tasks.map((task) => (
          <TaskCard
            key={task.taskId}
            task={task}
            wallet={wallet}
            claiming={claim.isPending && claim.variables === task.taskId}
            onClaim={() => claim.mutate(task.taskId)}
          />
        ))}
      </div>
    </div>
  )
}

export function TasksPage({ wallet }: { wallet: string }) {
  useRecordLogin(wallet)
  const { data: tasks, isLoading, error } = useTasks(wallet)
  const claim = useClaimTask(wallet)
  const createTask = useCreateTask(wallet)
  const [showCreate, setShowCreate] = useState(false)

  const byCategory = (category: TaskCategory) => (tasks ?? []).filter((t) => t.category === category)

  const claimable = (tasks ?? []).filter((t) => !!t.completedAt && !t.rewardClaimed)
  const claimableFeed = claimable.reduce((sum, t) => sum + Number(formatUnits(BigInt(t.rewardFeed), 18)), 0)
  const inProgressCount = (tasks ?? []).filter((t) => !t.completedAt).length

  return (
    <div>
      {/* Hero -- Tasks is the main feature: doing (or creating) quests is how a player actually
          earns $FEED, so it gets the same hero treatment the Farm/Battle Arena pages do rather
          than a plain header. */}
      <div
        className="card-pop relative mb-6 overflow-hidden rounded-3xl border-[3px]"
        style={{ borderColor: 'var(--color-brand-blue)', background: 'linear-gradient(155deg, #0e1a2e 0%, var(--color-surface) 65%)' }}
      >
        <div className="arcade-grid pointer-events-none absolute inset-0" />
        <div
          className="pointer-events-none absolute -top-16 -right-16 h-56 w-56 rounded-full blur-3xl"
          style={{ background: 'radial-gradient(circle, var(--color-brand-blue)33, transparent 70%)' }}
        />
        <div className="relative flex flex-col gap-3 p-6 sm:p-8">
          <span className="hud-num w-fit rounded-full px-3 py-1 text-[11px] tracking-widest text-white uppercase" style={{ background: 'var(--color-brand-blue)' }}>
            <ClipboardList size={12} className="mr-1 inline -translate-y-0.5" /> Main Feature
          </span>
          <h1 className="font-display text-2xl font-extrabold tracking-tight sm:text-3xl">Daily Tasks</h1>
          <p className="max-w-lg text-sm text-text-muted">
            Tasks are verified from real on-chain activity, not self-reported. Community Quests are created by
            other players and protocols the same way -- anyone can launch one to reward activity on their own
            contract. Progress updates automatically; claim mints your $FEED reward.
          </p>
          <div className="mt-1 flex flex-wrap items-center gap-2">
            {claimable.length > 0 && (
              <span
                className="glow-pulse hud-num flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[11px] font-bold text-white"
                style={{ background: 'var(--color-brand-red)' }}
              >
                🎁 {claimable.length} ready to claim &middot; {claimableFeed.toFixed(0)} FEED
              </span>
            )}
            <span className="hud-num flex items-center gap-1.5 rounded-full border border-border bg-surface/70 px-3 py-1 text-[11px] backdrop-blur-sm">
              ⏳ {inProgressCount} in progress
            </span>
            <button
              type="button"
              onClick={() => setShowCreate(true)}
              className="card-pop-sm flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-bold text-white"
              style={{ background: 'var(--color-brand-blue)' }}
            >
              <Plus size={14} /> Create a Quest
            </button>
          </div>
        </div>
      </div>

      {isLoading && <div className="flex h-64 items-center justify-center text-text-faint">Loading tasks...</div>}
      {error && <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>}

      <TaskSection category="game" tasks={byCategory('game')} claim={claim} wallet={wallet} />
      <TaskSection category="ecosystem" tasks={byCategory('ecosystem')} claim={claim} wallet={wallet} />
      <TaskSection category="partner" tasks={byCategory('partner')} claim={claim} wallet={wallet} />

      {claim.error && <ErrorBanner message={(claim.error as Error).message} />}

      {showCreate && (
        <CreateQuestModal
          submitting={createTask.isPending}
          error={createTask.error ? (createTask.error instanceof ApiError ? createTask.error.message : 'Failed to create quest') : undefined}
          onClose={() => !createTask.isPending && setShowCreate(false)}
          onSubmit={(input) => createTask.mutate(input, { onSuccess: () => setShowCreate(false) })}
        />
      )}
    </div>
  )
}
