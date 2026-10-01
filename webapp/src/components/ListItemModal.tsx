import { useState } from 'react'

export function ListItemModal({
  isEgg,
  tokenId,
  onClose,
  onSubmit,
  submitting,
}: {
  isEgg: boolean
  tokenId: number
  onClose: () => void
  onSubmit: (priceArb: string) => void
  submitting: boolean
}) {
  const [price, setPrice] = useState('')

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm md:items-center" onClick={onClose}>
      <div
        className="card-pop w-full max-w-md rounded-t-3xl border-[3px] border-border bg-surface p-6 md:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="font-display text-xl font-extrabold">
          List {isEgg ? 'Egg' : 'Animora'} #{tokenId}
        </h2>
        <p className="mt-1 text-xs text-text-muted">
          Requires two wallet approvals: one to let the marketplace hold your NFT, one to confirm the listing.
        </p>

        <label htmlFor="list-price" className="mt-4 block text-xs font-semibold text-text-muted">
          Price (ARB)
        </label>
        <input
          id="list-price"
          type="number"
          step="0.001"
          min="0"
          placeholder="0.15"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          className="mt-1 w-full rounded-xl border-2 border-border bg-surface-2 px-3 py-2 text-text placeholder:text-text-faint focus:outline-none"
          style={{ borderColor: price ? 'var(--color-brand-red)' : undefined }}
        />

        <button
          type="button"
          disabled={!price || submitting}
          onClick={() => onSubmit(price)}
          className="mt-4 w-full rounded-full brand-gradient py-3 font-bold text-white disabled:opacity-60"
        >
          {submitting ? 'Listing...' : 'List for Sale'}
        </button>
        <button type="button" onClick={onClose} className="mt-2 w-full text-center text-sm text-text-muted hover:text-text">
          Cancel
        </button>
      </div>
    </div>
  )
}
