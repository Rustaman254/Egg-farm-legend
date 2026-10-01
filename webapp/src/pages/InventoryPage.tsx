import { Lock, Package, Pencil } from 'lucide-react'
import { useState } from 'react'
import { formatEther } from 'viem'
import { EggCard } from '../components/EggCard'
import { ErrorBanner } from '../components/Banner'
import { ListItemModal } from '../components/ListItemModal'
import { RarityIcon } from '../components/RarityIcon'
import { SectionHeader } from '../components/SectionHeader'
import { useDiscardRottenEgg, useFarm, useHatchEgg, useSetCreatureNickname, useSetEggNickname, useSpeedUpHatch, useTendEgg } from '../hooks/useFarm'
import { useListItem } from '../hooks/useMarketplace'
import { displayName, HATCH_SPEEDUP_PRICE_PER_HOUR_ETH, RARITY_LABELS, speciesEmoji } from '../config/constants'
import { timeUntilHatchMs, timeUntilMatureMs } from '../api/types'

function promptRename(currentName: string): string | null {
  const next = prompt(`Rename to (max 24 characters):`, currentName)
  if (next === null) return null
  const trimmed = next.trim()
  return trimmed.length > 0 ? trimmed.slice(0, 24) : null
}

function formatDuration(ms: number): string {
  const hours = Math.floor(ms / 3_600_000)
  if (hours > 0) return `${hours}h`
  return `${Math.max(1, Math.floor(ms / 60_000))}m`
}

export function InventoryPage({ wallet }: { wallet: string }) {
  const { data: farm, isLoading, error } = useFarm(wallet)
  const hatch = useHatchEgg(wallet)
  const discard = useDiscardRottenEgg(wallet)
  const tend = useTendEgg(wallet)
  const speedUp = useSpeedUpHatch(wallet)
  const renameEgg = useSetEggNickname(wallet)
  const renameCreature = useSetCreatureNickname(wallet)
  const listItem = useListItem()
  const [actingOn, setActingOn] = useState<number | null>(null)
  const [listTarget, setListTarget] = useState<{ isEgg: boolean; tokenId: number } | null>(null)

  if (isLoading) {
    return <div className="flex h-64 items-center justify-center text-text-faint">Loading inventory...</div>
  }
  if (error) {
    return <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>
  }

  const eggs = farm?.eggs ?? []
  const creatures = farm?.creatures ?? []

  return (
    <div className="mx-auto max-w-2xl">
      <SectionHeader icon={Package} title="Inventory" />

      <h2 className="mb-2 flex items-center gap-1.5 font-mono text-xs font-bold uppercase tracking-wide" style={{ color: 'var(--color-brand-red)' }}>
        🥚 Unhatched Eggs ({eggs.length})
      </h2>
      {eggs.length === 0 ? (
        <p className="mb-6 text-sm text-text-muted">No eggs yet -- feed your Animoras and collect one!</p>
      ) : (
        <div className="mb-6 flex flex-col gap-2">
          {eggs.map((egg) => (
            <EggCard
              key={egg.tokenId}
              egg={egg}
              busy={(hatch.isPending || discard.isPending) && actingOn === egg.tokenId}
              tending={tend.isPending && actingOn === egg.tokenId}
              speedingUp={speedUp.isPending && actingOn === egg.tokenId}
              onHatch={() => {
                setActingOn(egg.tokenId)
                hatch.mutate(egg.tokenId)
              }}
              onDiscard={() => {
                if (!confirm('Discard this rotten egg? This cannot be undone.')) return
                setActingOn(egg.tokenId)
                discard.mutate(egg.tokenId)
              }}
              onTend={() => {
                setActingOn(egg.tokenId)
                tend.mutate(egg.tokenId)
              }}
              onSpeedUp={() => {
                const hours = Math.ceil(timeUntilHatchMs(egg) / 3_600_000)
                const costWei = BigInt(Math.round(hours * HATCH_SPEEDUP_PRICE_PER_HOUR_ETH * 1e18))
                if (!confirm(`Pay ${formatEther(costWei)} ETH to skip the rest of this egg's incubation?`)) return
                setActingOn(egg.tokenId)
                speedUp.mutate({ tokenId: egg.tokenId, priceWei: costWei })
              }}
              onList={() => setListTarget({ isEgg: true, tokenId: egg.tokenId })}
              onRename={() => {
                const nickname = promptRename(egg.nickname ?? '')
                if (nickname) renameEgg.mutate({ tokenId: egg.tokenId, nickname })
              }}
            />
          ))}
        </div>
      )}

      <h2 className="mb-2 flex items-center gap-1.5 font-mono text-xs font-bold uppercase tracking-wide" style={{ color: 'var(--color-brand-red)' }}>
        🐾 Animoras ({creatures.length})
      </h2>
      {creatures.length === 0 ? (
        <p className="text-sm text-text-muted">No Animoras yet -- visit the Farm tab to buy one.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {creatures.map((creature) => {
            const matureMs = timeUntilMatureMs(creature)
            return (
              <div key={creature.tokenId} className="card-pop-sm flex items-center gap-3 rounded-2xl border-[3px] border-border bg-surface p-3">
                <RarityIcon rarity={creature.rarity} emoji={speciesEmoji(creature.species)} species={creature.species} size="sm" />
                <div className="flex-1">
                  <div className="flex items-center gap-1 font-display font-bold">
                    <span className="truncate">{displayName(creature.species, creature.nickname)}</span>
                    <span className="text-text-faint">#{creature.tokenId}</span>
                    <button
                      type="button"
                      onClick={() => {
                        const nickname = promptRename(creature.nickname ?? '')
                        if (nickname) renameCreature.mutate({ tokenId: creature.tokenId, nickname })
                      }}
                      className="shrink-0 text-text-faint hover:text-text"
                    >
                      <Pencil size={11} />
                    </button>
                  </div>
                  <div className="text-xs font-semibold" style={{ color: 'var(--color-brand-red)' }}>
                    {RARITY_LABELS[creature.rarity]}
                  </div>
                  <div className="text-xs text-text-muted">
                    Bred {creature.breedCount}/7 &middot; Hunger {creature.hunger}% &middot; Happiness {creature.happiness}%
                  </div>
                </div>
                {matureMs > 0 ? (
                  <span
                    className="flex items-center gap-1 rounded-full px-3 py-1.5 text-xs font-bold"
                    style={{ color: 'var(--color-warn)', background: 'var(--color-surface-2)' }}
                    title="Battle it while it matures to raise its stats before you can list it"
                  >
                    <Lock size={12} /> {formatDuration(matureMs)}
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={() => setListTarget({ isEgg: false, tokenId: creature.tokenId })}
                    className="rounded-full px-3 py-1.5 text-xs font-bold text-white"
                    style={{ background: 'var(--color-brand-blue)' }}
                  >
                    List
                  </button>
                )}
              </div>
            )
          })}
        </div>
      )}

      {listTarget && (
        <ListItemModal
          isEgg={listTarget.isEgg}
          tokenId={listTarget.tokenId}
          submitting={listItem.isPending}
          onClose={() => !listItem.isPending && setListTarget(null)}
          onSubmit={(priceArb) =>
            listItem.mutate(
              { isEgg: listTarget.isEgg, tokenId: listTarget.tokenId, priceArb },
              { onSuccess: () => setListTarget(null) },
            )
          }
        />
      )}

      {hatch.error && <ErrorBanner message={(hatch.error as Error).message} />}
      {discard.error && <ErrorBanner message={(discard.error as Error).message} />}
      {tend.error && <ErrorBanner message={(tend.error as Error).message} />}
      {speedUp.error && <ErrorBanner message={(speedUp.error as Error).message} />}
      {renameEgg.error && <ErrorBanner message={(renameEgg.error as Error).message} />}
      {renameCreature.error && <ErrorBanner message={(renameCreature.error as Error).message} />}
      {listItem.error && <ErrorBanner message={(listItem.error as Error).message} />}
    </div>
  )
}
