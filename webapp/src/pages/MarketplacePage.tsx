import { Flame, Shield, Store, Swords, Wheat } from 'lucide-react'
import type { CSSProperties } from 'react'
import { useSearchParams } from 'react-router-dom'
import { formatEther } from 'viem'
import { battleStats, levelForCareScore } from '../config/battleStats'
import { AbilityBadges } from '../components/AbilityBadges'
import { ErrorBanner, PendingBanner } from '../components/Banner'
import { RarityIcon } from '../components/RarityIcon'
import { SectionHeader } from '../components/SectionHeader'
import { displayName, eggDisplayName, RARITY_COLORS, RARITY_LABELS, speciesEmoji } from '../config/constants'
import { useBuyFeedPackage, useFeedShopPackages } from '../hooks/useFeedShop'
import { useBuyListing, useCancelListing, useListings, useMyListings } from '../hooks/useMarketplace'
import { CONDITION_COLORS, conditionLabel, type FeedPackage, type Listing } from '../api/types'

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

function FilterChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${
        active ? 'text-white' : 'bg-surface-2 text-text-muted hover:text-text'
      }`}
      style={active ? { background: 'var(--color-brand-red)' } : undefined}
    >
      {label}
    </button>
  )
}

/** A Pokemon-TCG-styled listing card: rarity-colored border, HP-style price badge, circular art
 *  frame with a holo sweep for Epic/Legendary items, and a dex-number footer -- the marketplace
 *  as a binder page of cards for sale. */
function ListingCard({
  listing,
  isMine,
  onBuy,
  onCancel,
  busy,
}: {
  listing: Listing
  isMine: boolean
  onBuy: () => void
  onCancel: () => void
  busy: boolean
}) {
  const priceArb = formatEther(BigInt(listing.priceWei))
  const hasArt = listing.rarity != null
  const rarityColor = hasArt ? (RARITY_COLORS[listing.rarity!] ?? RARITY_COLORS[1]) : 'var(--color-text-faint)'
  const emoji = listing.species != null ? speciesEmoji(listing.species) : listing.kind === 'egg' ? '🥚' : '🐔'
  const label =
    listing.species == null
      ? listing.kind === 'egg'
        ? 'Egg'
        : 'Animora'
      : listing.kind === 'egg'
        ? eggDisplayName(listing.species)
        : displayName(listing.species, listing.nickname)
  const stats = listing.kind === 'creature' && hasArt ? battleStats(listing.species!, listing.rarity!, listing.careScore ?? 0) : null
  const level = listing.kind === 'creature' ? levelForCareScore(listing.careScore ?? 0) : null
  const condition = listing.kind === 'creature' ? conditionLabel(listing.happiness ?? 0, listing.careScore ?? 0) : null

  return (
    <div className="card-pop-sm relative flex flex-col gap-2.5 rounded-2xl border-[3px] bg-surface p-3" style={{ borderColor: listing.hot ? 'var(--color-brand-yellow)' : rarityColor }}>
      {listing.hot && (
        <div
          className="hud-num absolute -top-2.5 left-3 flex items-center gap-1 rounded-full px-2 py-0.5 text-[9px] font-bold text-white"
          style={{ background: 'var(--color-brand-yellow)' }}
        >
          <Flame size={10} /> HOT
        </div>
      )}
      <div className="flex items-start justify-between">
        <div className="min-w-0">
          <div className="truncate font-display text-sm font-bold">{label}</div>
          {hasArt && (
            <div className="flex items-center gap-1.5 font-mono text-[9px] font-bold tracking-wide text-text-faint uppercase">
              {RARITY_LABELS[listing.rarity!]}
              {listing.kind === 'egg' && listing.nickname && <>&middot; "{listing.nickname}"</>}
              {level && <span style={{ color: 'var(--color-up)' }}>&middot; Lv{level}</span>}
              {stats && <span style={{ color: 'var(--color-down)' }}>&middot; HP {stats.hp}</span>}
            </div>
          )}
          {condition && (
            <div className="mt-0.5 font-mono text-[9px] font-bold uppercase" style={{ color: CONDITION_COLORS[condition] }}>
              {condition}
            </div>
          )}
        </div>
        <div className="hud-num shrink-0 rounded-lg px-1.5 py-0.5 text-[11px] text-white" style={{ background: 'var(--color-brand-blue)' }}>
          {priceArb} ARB
        </div>
      </div>

      <div
        className="glossy flex items-center justify-center rounded-xl py-3"
        style={{ '--glossy-from': `${rarityColor}55`, '--glossy-to': `${rarityColor}18`, '--glossy-glow': `${rarityColor}66` } as CSSProperties}
      >
        {hasArt ? (
          <RarityIcon rarity={listing.rarity!} emoji={emoji} species={listing.kind === 'creature' ? listing.species ?? undefined : undefined} size="lg" />
        ) : (
          <div className="flex h-20 w-20 items-center justify-center rounded-full border-[3px] border-border bg-surface-2 text-5xl">
            {emoji}
          </div>
        )}
      </div>

      {stats && (
        <div className="flex flex-col gap-1 border-t border-dashed border-border pt-1.5">
          <div className="flex items-center justify-between text-xs">
            <span className="flex items-center gap-1 font-semibold text-text-muted">
              <Swords size={12} style={{ color: 'var(--color-brand-red)' }} /> Attack
            </span>
            <span className="hud-num">{stats.attack}</span>
          </div>
          <div className="flex items-center justify-between text-xs">
            <span className="flex items-center gap-1 font-semibold text-text-muted">
              <Shield size={12} style={{ color: 'var(--color-brand-blue)' }} /> Defense
            </span>
            <span className="hud-num">{stats.defense}</span>
          </div>
        </div>
      )}

      {listing.kind === 'creature' && <AbilityBadges abilities={listing.abilities} />}

      <div className="flex items-center justify-between border-t border-dashed border-border pt-1.5 text-xs">
        <span className="font-semibold text-text-muted">Seller</span>
        <span className="hud-num text-[11px]">{isMine ? 'You' : shortAddress(listing.sellerAddress)}</span>
      </div>

      <div className="flex items-center justify-between border-t border-border pt-1.5 font-mono text-[9px] text-text-faint">
        <span>{hasArt ? `No. ${String(listing.species).padStart(3, '0')}` : 'No. ???'}</span>
        <span>#{listing.tokenId}</span>
      </div>

      {!listing.isActive ? (
        <div
          className="w-full rounded-xl py-1.5 text-center text-xs font-bold"
          style={{ color: listing.soldAt ? 'var(--color-up)' : 'var(--color-text-faint)', background: 'var(--color-surface-2)' }}
        >
          {listing.soldAt ? `Sold to ${shortAddress(listing.buyerAddress ?? '')}` : 'Cancelled'}
        </div>
      ) : isMine ? (
        <button
          type="button"
          disabled={busy}
          onClick={onCancel}
          className="w-full rounded-xl border-2 py-1.5 text-xs font-bold disabled:opacity-60"
          style={{ borderColor: 'var(--color-down)', color: 'var(--color-down)' }}
        >
          {busy ? '...' : 'Cancel'}
        </button>
      ) : (
        <button
          type="button"
          disabled={busy}
          onClick={onBuy}
          className="w-full rounded-xl py-1.5 text-xs font-bold text-white disabled:opacity-60"
          style={{ background: 'var(--color-brand-red)' }}
        >
          {busy ? '...' : 'Buy'}
        </button>
      )}
    </div>
  )
}

function FeedPackageCard({ pkg, onBuy, busy }: { pkg: FeedPackage; onBuy: () => void; busy: boolean }) {
  const priceArb = formatEther(BigInt(pkg.priceWei))
  return (
    <div className="card-pop-sm flex flex-col items-center gap-2 rounded-2xl border-[3px] bg-surface p-4" style={{ borderColor: 'var(--color-brand-yellow)' }}>
      <Wheat size={36} style={{ color: 'var(--color-brand-yellow)' }} />
      <div className="font-display text-lg font-extrabold">{pkg.kg}kg bag</div>
      <div className="hud-num text-sm" style={{ color: 'var(--color-up)' }}>
        {pkg.feedWhole} FEED
      </div>
      <div className="text-xs text-text-faint">{priceArb} ARB</div>
      <button
        type="button"
        disabled={busy}
        onClick={onBuy}
        className="mt-1 w-full rounded-full py-2 text-xs font-bold text-white disabled:opacity-60"
        style={{ background: 'var(--color-brand-red)' }}
      >
        {busy ? 'Buying...' : 'Buy'}
      </button>
    </div>
  )
}

export function MarketplacePage({ wallet }: { wallet: string }) {
  const [searchParams, setSearchParams] = useSearchParams()
  const kindParam = searchParams.get('kind')
  const kind = kindParam === 'egg' || kindParam === 'creature' ? kindParam : undefined
  const showFeedShop = kindParam === 'feed'
  const showMine = kindParam === 'mine'

  const { data: browseListings, isLoading: browseLoading, error: browseError } = useListings(showFeedShop || showMine ? undefined : kind)
  const { data: myListings, isLoading: mineLoading, error: mineError } = useMyListings(showMine ? wallet : undefined, undefined)
  const listings = showMine ? myListings : browseListings
  const isLoading = showMine ? mineLoading : browseLoading
  const error = showMine ? mineError : browseError
  const buy = useBuyListing()
  const cancel = useCancelListing()
  const { data: feedPackages } = useFeedShopPackages()
  const buyFeed = useBuyFeedPackage(wallet)

  return (
    <div>
      <SectionHeader icon={Store} title="Marketplace" />

      <div className="mb-4 flex flex-wrap gap-2">
        <FilterChip label="All" active={kind === undefined && !showFeedShop && !showMine} onClick={() => setSearchParams({})} />
        <FilterChip label="🥚 Eggs" active={kind === 'egg'} onClick={() => setSearchParams({ kind: 'egg' })} />
        <FilterChip label="🐉 Animoras" active={kind === 'creature'} onClick={() => setSearchParams({ kind: 'creature' })} />
        <FilterChip label="🌾 Feed" active={showFeedShop} onClick={() => setSearchParams({ kind: 'feed' })} />
        <FilterChip label="🧺 My Listings" active={showMine} onClick={() => setSearchParams({ kind: 'mine' })} />
      </div>

      {showFeedShop ? (
        <>
          <p className="mb-4 -mt-2 text-xs text-text-muted">
            Pre-made bags of $FEED, paid for in ARB straight to the platform treasury -- an instant top-up if you don't want to
            wait on tasks or battles.
          </p>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {(feedPackages ?? []).map((pkg) => (
              <FeedPackageCard
                key={pkg.id}
                pkg={pkg}
                busy={buyFeed.isPending && buyFeed.variables?.packageId === pkg.id}
                onBuy={() => buyFeed.mutate({ packageId: pkg.id, priceWei: pkg.priceWei })}
              />
            ))}
          </div>
          {buyFeed.isPending && <PendingBanner message="Buying..." />}
          {buyFeed.error && <ErrorBanner message={(buyFeed.error as Error).message} />}
        </>
      ) : (
        <>
          {isLoading && <div className="flex h-64 items-center justify-center text-text-faint">Loading listings...</div>}
          {error && <div className="rounded-2xl border border-border bg-surface p-6 text-center text-down">{(error as Error).message}</div>}
          {!isLoading && !error && (listings ?? []).length === 0 && (
            <div className="rounded-2xl border border-border bg-surface p-8 text-center text-text-muted">
              {showMine ? "You haven't listed anything yet." : 'No listings yet. Be the first to sell!'}
            </div>
          )}

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {(listings ?? []).map((listing) => (
              <ListingCard
                key={listing.listingId}
                listing={listing}
                isMine={listing.sellerAddress.toLowerCase() === wallet.toLowerCase()}
                busy={
                  (buy.isPending && buy.variables?.listingId === listing.listingId) ||
                  (cancel.isPending && cancel.variables === listing.listingId)
                }
                onBuy={() => buy.mutate(listing)}
                onCancel={() => cancel.mutate(listing.listingId)}
              />
            ))}
          </div>

          {(buy.isPending || cancel.isPending) && <PendingBanner message={buy.isPending ? 'Buying...' : 'Cancelling...'} />}
          {buy.error && <ErrorBanner message={(buy.error as Error).message} />}
          {cancel.error && <ErrorBanner message={(cancel.error as Error).message} />}
        </>
      )}
    </div>
  )
}
