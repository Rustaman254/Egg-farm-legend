/** Farmer (player) leveling. Must mirror the backend's internal/api farmerLevelForXP exactly --
 *  XP is awarded 1:1 with every whole $FEED reward (task claims, battle wins), and level N->N+1
 *  costs 100*N XP -- a plain linear ramp (level 2 at 100 XP, level 10 at 4,500 cumulative). */
const TITLES: Array<{ minLevel: number; title: string }> = [
  { minLevel: 1, title: 'Novice Farmer' },
  { minLevel: 5, title: 'Skilled Farmer' },
  { minLevel: 10, title: 'Ranch Hand' },
  { minLevel: 20, title: 'Master Breeder' },
  { minLevel: 35, title: 'Egg Baron' },
  { minLevel: 50, title: 'Legendary Farmer' },
]

export function xpForNextFarmerLevel(level: number): number {
  return 100 * level
}

export interface FarmerLevelInfo {
  level: number
  title: string
  xpIntoLevel: number
  xpForLevel: number
  progress: number // 0-1
}

export function farmerLevelInfo(xp: number): FarmerLevelInfo {
  let level = 1
  let remaining = xp
  while (remaining >= xpForNextFarmerLevel(level)) {
    remaining -= xpForNextFarmerLevel(level)
    level++
  }
  const xpForLevel = xpForNextFarmerLevel(level)
  const title = [...TITLES].reverse().find((t) => level >= t.minLevel)?.title ?? TITLES[0].title
  return { level, title, xpIntoLevel: remaining, xpForLevel, progress: xpForLevel === 0 ? 0 : remaining / xpForLevel }
}
