import type { CSSProperties } from 'react'
import { RARITY_COLORS } from '../config/constants'

/** Free, no-key, deterministic SVG avatar generator (https://www.dicebear.com) -- "fun-emoji"
 *  gives every species a distinct, cheerful cartoon mascot face (closer to a game-lobby character
 *  than a sci-fi bot), seeded so the same species always renders the same way app-wide.
 *  backgroundColor ties it into the rarity ring color so the art and the badge read as one glossy
 *  object instead of two mismatched pieces. */
function dicebearUrl(species: number, rarity: number): string {
  const bg = (RARITY_COLORS[rarity] ?? RARITY_COLORS[1]).replace('#', '')
  return `https://api.dicebear.com/9.x/fun-emoji/svg?seed=species-${species}&backgroundColor=${bg}&backgroundType=gradientLinear&radius=50`
}

/** Wraps a creature/egg avatar in a glossy game-lobby-styled medallion: a saturated gradient
 *  disc in the rarity's color with a diagonal shine streak, a solid ring, plus a holo shimmer
 *  sweep for Epic/Legendary and (for Legendary) a slow ambient glow -- the "foil card" treatment.
 *  Pass `species` for a real creature (renders a generated avatar); omit it (eggs, generic
 *  placeholders) to fall back to the plain emoji. */
export function RarityIcon({
  rarity,
  emoji,
  species,
  size = 'md',
}: {
  rarity: number
  emoji: string
  species?: number
  size?: 'sm' | 'md' | 'lg'
}) {
  const color = RARITY_COLORS[rarity] ?? RARITY_COLORS[1]
  const dims = size === 'lg' ? 'h-20 w-20 text-5xl' : size === 'sm' ? 'h-10 w-10 text-xl' : 'h-14 w-14 text-3xl'
  const foil = rarity >= 4
  const legendary = rarity === 5

  return (
    <div className={`relative flex ${dims} shrink-0 items-center justify-center rounded-full`}>
      {legendary && (
        <div
          className="glow-pulse absolute -inset-1.5 rounded-full blur-md"
          style={{ background: `radial-gradient(circle, ${color}aa, transparent 70%)` }}
        />
      )}
      <div
        className="glossy relative flex h-full w-full items-center justify-center rounded-full border-[3px]"
        style={
          {
            borderColor: color,
            boxShadow: `0 0 0 2px ${color}33`,
            '--glossy-from': `${color}77`,
            '--glossy-to': `${color}2a`,
            '--glossy-glow': `${color}55`,
          } as CSSProperties
        }
      >
        {species != null ? (
          <img src={dicebearUrl(species, rarity)} alt="" className="h-full w-full scale-110" draggable={false} />
        ) : (
          emoji
        )}
        {foil && <div className="holo-foil absolute inset-0 rounded-full" />}
      </div>
    </div>
  )
}
