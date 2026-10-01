import { useState } from 'react'

const CHECK_TYPES = [
  {
    value: 'view_function',
    label: 'Read a value (any protocol)',
    hint: 'Call any fn(address) view function on your contract -- staked balance, points, tier, reputation, "isMember" -- and compare it to a threshold. Works for any protocol, not just tokens.',
  },
  {
    value: 'named_event',
    label: 'Called a specific function',
    hint: 'Match one exact event your contract emits (e.g. "Staked", "Swap") with the player in a specific indexed parameter. Precise: proves they did *that* action, not just any action.',
  },
  {
    value: 'token_balance',
    label: 'Hold a token/NFT',
    hint: 'Player must hold at least N of a standard ERC-20 or ERC-721 you specify.',
  },
  {
    value: 'token_received',
    label: 'Receive a token transfer',
    hint: 'Player must receive a transfer of a standard token you specify (e.g. an airdrop or claim).',
  },
  {
    value: 'contract_event',
    label: 'Any activity on a contract',
    hint: "Broadest option: player's wallet must appear in any event your contract emits at all -- use this if you don't want to target one specific action.",
  },
] as const

type CheckType = (typeof CHECK_TYPES)[number]['value']

const OUTPUT_TYPES = ['uint256', 'uint128', 'uint64', 'uint32', 'uint16', 'uint8', 'bool'] as const

const MAX_REWARD = 50
const MAX_TARGET = 10
const MAX_DAYS = 30

const isValidAddress = (v: string) => /^0x[0-9a-fA-F]{40}$/.test(v)
const isValidFunctionSig = (v: string) => /^[A-Za-z_][A-Za-z0-9_]*\(address\)$/.test(v.replace(/\s/g, ''))
const isValidEventSig = (v: string) => /^[A-Za-z_][A-Za-z0-9_]*\([A-Za-z0-9_,[\]]*\)$/.test(v.replace(/\s/g, ''))

export function CreateQuestModal({
  onClose,
  onSubmit,
  submitting,
  error,
}: {
  onClose: () => void
  onSubmit: (input: {
    title: string
    description: string
    checkType: CheckType
    contractAddress: string
    thresholdWei?: string
    functionSignature?: string
    outputType?: string
    eventSignature?: string
    walletTopicIndex?: number
    targetCount: number
    rewardFeedWhole: number
    durationDays: number
  }) => void
  submitting: boolean
  error?: string
}) {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [checkType, setCheckType] = useState<CheckType>('view_function')
  const [contractAddress, setContractAddress] = useState('')
  const [thresholdWhole, setThresholdWhole] = useState('1')
  const [functionSignature, setFunctionSignature] = useState('')
  const [outputType, setOutputType] = useState<(typeof OUTPUT_TYPES)[number]>('uint256')
  const [eventSignature, setEventSignature] = useState('')
  const [walletTopicIndex, setWalletTopicIndex] = useState(1)
  const [targetCount, setTargetCount] = useState(1)
  const [rewardFeedWhole, setRewardFeedWhole] = useState(10)
  const [durationDays, setDurationDays] = useState(7)

  const contractOk = isValidAddress(contractAddress)
  const needsThreshold = checkType === 'token_balance' || (checkType === 'view_function' && outputType !== 'bool')
  const checkSpecificOk =
    checkType === 'view_function'
      ? isValidFunctionSig(functionSignature)
      : checkType === 'named_event'
        ? isValidEventSig(eventSignature)
        : true
  const canSubmit = title.trim() && description.trim() && contractOk && checkSpecificOk && !submitting

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm md:items-center" onClick={onClose}>
      <div
        className="card-pop max-h-[90vh] w-full max-w-md overflow-y-auto rounded-t-3xl border-[3px] border-border bg-surface p-6 md:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="font-display text-xl font-extrabold">Create a Quest</h2>
        <p className="mt-1 text-xs text-text-muted">
          Reward players for activity on your protocol. Goes live immediately as a "Community Quest" -- no
          approval needed, but reward/target/duration are capped so the board can't be spammed.
        </p>

        <label htmlFor="quest-title" className="mt-4 block text-xs font-semibold text-text-muted">
          Title
        </label>
        <input
          id="quest-title"
          type="text"
          maxLength={80}
          placeholder="Stake on MyProtocol"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text placeholder:text-text-faint focus:outline-none"
        />

        <label htmlFor="quest-desc" className="mt-3 block text-xs font-semibold text-text-muted">
          Description
        </label>
        <textarea
          id="quest-desc"
          maxLength={280}
          rows={2}
          placeholder="Stake at least 100 tokens on MyProtocol"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          className="mt-1 w-full resize-none rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text placeholder:text-text-faint focus:outline-none"
        />

        <label htmlFor="quest-check" className="mt-3 block text-xs font-semibold text-text-muted">
          Verification method
        </label>
        <select
          id="quest-check"
          value={checkType}
          onChange={(e) => setCheckType(e.target.value as CheckType)}
          className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text focus:outline-none"
        >
          {CHECK_TYPES.map((c) => (
            <option key={c.value} value={c.value}>
              {c.label}
            </option>
          ))}
        </select>
        <p className="mt-1 text-[11px] text-text-faint">{CHECK_TYPES.find((c) => c.value === checkType)?.hint}</p>

        <label htmlFor="quest-contract" className="mt-3 block text-xs font-semibold text-text-muted">
          Contract address
        </label>
        <input
          id="quest-contract"
          type="text"
          placeholder="0x..."
          value={contractAddress}
          onChange={(e) => setContractAddress(e.target.value)}
          className="mt-1 w-full rounded-xl border-2 bg-surface-2 px-3 py-2 font-mono text-sm text-text placeholder:text-text-faint focus:outline-none"
          style={{ borderColor: contractAddress && !contractOk ? 'var(--color-down)' : undefined }}
        />

        {checkType === 'view_function' && (
          <>
            <label htmlFor="quest-fn-sig" className="mt-3 block text-xs font-semibold text-text-muted">
              Function signature
            </label>
            <input
              id="quest-fn-sig"
              type="text"
              placeholder="stakedAmount(address)"
              value={functionSignature}
              onChange={(e) => setFunctionSignature(e.target.value)}
              className="mt-1 w-full rounded-xl border-2 bg-surface-2 px-3 py-2 font-mono text-sm text-text placeholder:text-text-faint focus:outline-none"
              style={{ borderColor: functionSignature && !isValidFunctionSig(functionSignature) ? 'var(--color-down)' : undefined }}
            />
            <p className="mt-1 text-[11px] text-text-faint">Must take exactly one `address` argument, e.g. balanceOf(address).</p>

            <label htmlFor="quest-output-type" className="mt-3 block text-xs font-semibold text-text-muted">
              Return type
            </label>
            <select
              id="quest-output-type"
              value={outputType}
              onChange={(e) => setOutputType(e.target.value as typeof outputType)}
              className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text focus:outline-none"
            >
              {OUTPUT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </>
        )}

        {checkType === 'named_event' && (
          <>
            <label htmlFor="quest-event-sig" className="mt-3 block text-xs font-semibold text-text-muted">
              Event signature (canonical, types only)
            </label>
            <input
              id="quest-event-sig"
              type="text"
              placeholder="Staked(address,uint256)"
              value={eventSignature}
              onChange={(e) => setEventSignature(e.target.value)}
              className="mt-1 w-full rounded-xl border-2 bg-surface-2 px-3 py-2 font-mono text-sm text-text placeholder:text-text-faint focus:outline-none"
              style={{ borderColor: eventSignature && !isValidEventSig(eventSignature) ? 'var(--color-down)' : undefined }}
            />
            <p className="mt-1 text-[11px] text-text-faint">
              All parameter types in declaration order, no names or "indexed" keywords -- exactly the form used to
              compute the event's topic hash.
            </p>

            <label htmlFor="quest-wallet-topic" className="mt-3 block text-xs font-semibold text-text-muted">
              Which indexed parameter is the player's wallet?
            </label>
            <select
              id="quest-wallet-topic"
              value={walletTopicIndex}
              onChange={(e) => setWalletTopicIndex(Number(e.target.value))}
              className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text focus:outline-none"
            >
              <option value={1}>1st indexed parameter</option>
              <option value={2}>2nd indexed parameter</option>
              <option value={3}>3rd indexed parameter</option>
            </select>
          </>
        )}

        {needsThreshold && (
          <>
            <label htmlFor="quest-threshold" className="mt-3 block text-xs font-semibold text-text-muted">
              Minimum amount (whole tokens/units)
            </label>
            <input
              id="quest-threshold"
              type="number"
              min="1"
              value={thresholdWhole}
              onChange={(e) => setThresholdWhole(e.target.value)}
              className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text focus:outline-none"
            />
          </>
        )}

        <div className="mt-3 grid grid-cols-3 gap-2">
          <div>
            <label htmlFor="quest-target" className="block text-xs font-semibold text-text-muted">
              Target (max {MAX_TARGET})
            </label>
            <input
              id="quest-target"
              type="number"
              min="1"
              max={MAX_TARGET}
              value={targetCount}
              onChange={(e) => setTargetCount(Math.min(MAX_TARGET, Math.max(1, Number(e.target.value))))}
              className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-2 py-2 text-sm text-text focus:outline-none"
            />
          </div>
          <div>
            <label htmlFor="quest-reward" className="block text-xs font-semibold text-text-muted">
              FEED (max {MAX_REWARD})
            </label>
            <input
              id="quest-reward"
              type="number"
              min="1"
              max={MAX_REWARD}
              value={rewardFeedWhole}
              onChange={(e) => setRewardFeedWhole(Math.min(MAX_REWARD, Math.max(1, Number(e.target.value))))}
              className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-2 py-2 text-sm text-text focus:outline-none"
            />
          </div>
          <div>
            <label htmlFor="quest-days" className="block text-xs font-semibold text-text-muted">
              Days (max {MAX_DAYS})
            </label>
            <input
              id="quest-days"
              type="number"
              min="1"
              max={MAX_DAYS}
              value={durationDays}
              onChange={(e) => setDurationDays(Math.min(MAX_DAYS, Math.max(1, Number(e.target.value))))}
              className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-2 py-2 text-sm text-text focus:outline-none"
            />
          </div>
        </div>

        {error && <p className="mt-3 text-xs font-semibold text-down">{error}</p>}

        <button
          type="button"
          disabled={!canSubmit}
          onClick={() =>
            onSubmit({
              title: title.trim(),
              description: description.trim(),
              checkType,
              contractAddress,
              thresholdWei: needsThreshold ? (BigInt(Math.max(1, Number(thresholdWhole) || 1)) * 10n ** 18n).toString() : undefined,
              functionSignature: checkType === 'view_function' ? functionSignature.replace(/\s/g, '') : undefined,
              outputType: checkType === 'view_function' ? outputType : undefined,
              eventSignature: checkType === 'named_event' ? eventSignature.replace(/\s/g, '') : undefined,
              walletTopicIndex: checkType === 'named_event' ? walletTopicIndex : undefined,
              targetCount,
              rewardFeedWhole,
              durationDays,
            })
          }
          className="mt-4 w-full rounded-full py-3 font-bold text-white disabled:opacity-60"
          style={{ background: 'var(--color-brand-red)' }}
        >
          {submitting ? 'Creating...' : 'Launch Quest'}
        </button>
        <button type="button" onClick={onClose} className="mt-2 w-full text-center text-sm text-text-muted hover:text-text">
          Cancel
        </button>
      </div>
    </div>
  )
}
