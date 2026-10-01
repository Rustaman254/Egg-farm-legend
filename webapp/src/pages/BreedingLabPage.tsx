import { Dna, Sparkles } from 'lucide-react'
import { useEffect, useState } from 'react'
import { CreatureCard } from '../components/CreatureCard'
import { ErrorBanner } from '../components/Banner'
import { SectionHeader } from '../components/SectionHeader'
import { useBreedCreatures, useFarm } from '../hooks/useFarm'
import { MAX_RARITY, speciesName } from '../config/constants'

export function BreedingLabPage({ wallet }: { wallet: string }) {
  const { data: farm, isLoading, error } = useFarm(wallet)
  const breed = useBreedCreatures(wallet)
  const [parent1, setParent1] = useState<number | null>(null)
  const [parent2, setParent2] = useState<number | null>(null)
  const [showSuccessToast, setShowSuccessToast] = useState(false)

  useEffect(() => {
    if (!showSuccessToast) return
    const timer = setTimeout(() => setShowSuccessToast(false), 4000)
    return () => clearTimeout(timer)
  }, [showSuccessToast])

  if (isLoading) {
    return <div className="flex h-64 items-center justify-center text-text-faint">Loading Animoras...</div>
  }
  if (error) {
    return <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>
  }

  const breedable = (farm?.creatures ?? []).filter((c) => !c.isDead && c.breedCount < 7)

  if (breedable.length < 2) {
    return (
      <div className="mx-auto max-w-2xl">
        <SectionHeader icon={Dna} title="Breeding Lab" />
        <div className="card-pop rounded-2xl border-[3px] border-border bg-surface p-8 text-center text-text-muted">
          You need at least 2 breedable Animoras (breed count &lt; 7) to use the Breeding Lab.
        </div>
      </div>
    )
  }

  const p1 = breedable.find((c) => c.tokenId === parent1)
  const p2 = breedable.find((c) => c.tokenId === parent2)

  const select = (tokenId: number) => {
    if (tokenId === parent1 || tokenId === parent2) {
      setParent1(null)
      setParent2(null)
    } else if (parent1 === null) {
      setParent1(tokenId)
    } else if (parent2 === null) {
      setParent2(tokenId)
    }
  }

  let prediction = 'Select two parents'
  let interbreeding = false
  if (p1 && p2) {
    const avg = Math.floor((p1.rarity + p2.rarity) / 2)
    const low = Math.min(MAX_RARITY, Math.max(1, avg - 1))
    const high = Math.min(MAX_RARITY, Math.max(1, avg + 2))
    prediction = `Predicted offspring rarity: ${low} - ${high} stars`
    interbreeding = p1.species !== p2.species
  }

  return (
    <div>
      <SectionHeader icon={Dna} title="Breeding Lab" />

      <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-6">
        {breedable.map((creature) => (
          <div key={creature.tokenId} className="relative">
            <CreatureCard
              creature={creature}
              selectable
              selected={creature.tokenId === parent1 || creature.tokenId === parent2}
              onSelect={() => select(creature.tokenId)}
            />
            {creature.tokenId === parent1 && (
              <span
                className="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full border-2 border-white text-[11px] font-bold text-white shadow-md"
                style={{ background: 'var(--color-brand-red)' }}
              >
                1
              </span>
            )}
            {creature.tokenId === parent2 && (
              <span
                className="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full border-2 border-white text-[11px] font-bold text-white shadow-md"
                style={{ background: 'var(--color-brand-blue)' }}
              >
                2
              </span>
            )}
          </div>
        ))}
      </div>

      <div className="card-pop sticky bottom-20 mt-6 rounded-2xl border-[3px] border-border bg-surface p-5 text-center md:bottom-4">
        {p1 && p2 && (
          <div className="mb-2 font-mono text-xs text-text-faint">
            {speciesName(p1.species)} &times; {speciesName(p2.species)}
          </div>
        )}
        <div className="font-display font-bold">{prediction}</div>
        {p1 && p2 && (
          <div
            className="mt-1 flex items-center justify-center gap-1 text-xs font-bold"
            style={{ color: interbreeding ? 'var(--color-brand-red)' : 'var(--color-text-faint)' }}
          >
            {interbreeding ? (
              <>
                <Sparkles size={12} /> Interbreeding: ~60% chance of a brand-new species
              </>
            ) : (
              'Same species: ~20% chance of a mutation, otherwise breeds true'
            )}
          </div>
        )}
        <div className="mt-1 text-xs text-text-muted">Cost: 50+ FEED (scales with breed count) + 0.01 ARB &middot; Incubation 24-72h</div>
        <button
          type="button"
          disabled={!p1 || !p2 || breed.isPending}
          onClick={() =>
            p1 &&
            p2 &&
            breed.mutate(
              { parent1: p1.tokenId, parent2: p2.tokenId },
              {
                onSuccess: () => {
                  setParent1(null)
                  setParent2(null)
                  setShowSuccessToast(true)
                },
              },
            )
          }
          className="card-pop-sm mt-3 w-full rounded-full py-3 font-display font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
          style={{ background: 'var(--color-brand-red)' }}
        >
          {breed.isPending ? 'Breeding...' : 'Breed'}
        </button>
      </div>

      {breed.error && <ErrorBanner message={(breed.error as Error).message} />}
      {showSuccessToast && (
        <div
          className="card-pop fixed inset-x-4 bottom-44 z-40 mx-auto max-w-sm rounded-2xl border-[3px] bg-surface px-4 py-3 text-center text-sm font-bold md:bottom-24"
          style={{ borderColor: 'var(--color-up)', color: 'var(--color-up)' }}
        >
          Breeding started! Check Inventory for the new egg.
        </div>
      )}
    </div>
  )
}
