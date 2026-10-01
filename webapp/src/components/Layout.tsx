import { Activity, BookOpen, Dna, LogOut, Package, Sprout, Store, ClipboardList, Swords, Trophy } from 'lucide-react'
import type { ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { farmerLevelInfo } from '../config/farmerLevel'
import { useFarm } from '../hooks/useFarm'
import { useWallet } from '../hooks/useWallet'

const SIDEBAR_ITEMS = [
  { to: '/', label: 'Tasks', icon: ClipboardList, end: true },
  { to: '/farm', label: 'Farm', icon: Sprout },
  { to: '/breeding', label: 'Breeding Lab', icon: Dna },
  { to: '/battle', label: 'Battle Arena', icon: Swords },
  { to: '/marketplace', label: 'Marketplace', icon: Store },
  { to: '/inventory', label: 'Inventory', icon: Package },
  { to: '/collection', label: 'Species Dex', icon: BookOpen },
  { to: '/leaderboard', label: 'Leaderboard', icon: Trophy },
  { to: '/activity', label: 'Activity', icon: Activity },
]

// Tasks is the main feature -- doing/creating tasks is how a player actually earns $FEED, so it
// gets the home route ("/") and stays visually distinct (uppercase, own styling below) from the
// rest of the top nav rather than just another icon link.
const TOP_NAV_ITEMS = [
  { to: '/farm', label: 'Farm', icon: Sprout },
  { to: '/battle', label: 'Battle', icon: Swords },
  { to: '/marketplace', label: 'Market', icon: Store },
  { to: '/collection', label: 'Dex', icon: BookOpen },
]

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

export function Layout({ wallet, children }: { wallet: string; children: ReactNode }) {
  const { disconnect } = useWallet()
  const { data: farm } = useFarm(wallet)
  const levelInfo = farmerLevelInfo(farm?.xp ?? 0)

  return (
    <div className="flex min-h-svh bg-bg text-text">
      {/* Icon sidebar */}
      <aside className="sticky top-0 hidden h-svh w-[76px] shrink-0 flex-col items-center gap-2 border-r border-border bg-surface py-5 sm:flex">
        <div className="mb-4 flex h-10 w-10 items-center justify-center overflow-hidden rounded-full border-[3px] border-white shadow-[inset_0_0_0_3px_var(--color-ink)]" style={{ background: 'var(--color-brand-red)' }}>
          <img src="/logo.png" alt="EggFarm Legend" className="h-full w-full scale-125 object-cover" draggable={false} />
        </div>
        <nav className="flex flex-1 flex-col items-center gap-1.5">
          {SIDEBAR_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              title={item.label}
              className={({ isActive }) =>
                `flex h-11 w-11 items-center justify-center rounded-xl transition-all ${
                  isActive ? 'text-white' : 'text-text-faint hover:bg-surface-2 hover:text-text'
                }`
              }
              style={({ isActive }) => (isActive ? { background: 'var(--color-brand-red)' } : undefined)}
            >
              <item.icon size={20} strokeWidth={2.25} />
            </NavLink>
          ))}
        </nav>
        <button
          type="button"
          onClick={() => disconnect()}
          title="Disconnect wallet"
          className="flex h-11 w-11 items-center justify-center rounded-xl text-text-faint transition-colors hover:bg-surface-2 hover:text-down"
        >
          <LogOut size={19} strokeWidth={2.25} />
        </button>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Top bar */}
        <header className="sticky top-0 z-30 text-white" style={{ background: 'var(--color-brand-red)' }}>
          <div className="flex items-center gap-4 px-4 py-3 sm:px-6">
            <div className="flex items-center gap-2 sm:hidden">
              <div className="flex h-8 w-8 items-center justify-center overflow-hidden rounded-full border-2 border-white">
                <img src="/logo.png" alt="EggFarm Legend" className="h-full w-full scale-125 object-cover" draggable={false} />
              </div>
            </div>
            <span className="hidden font-display text-lg font-extrabold tracking-tight sm:block">
              Egg<span style={{ color: 'var(--color-brand-yellow)' }}>Farm</span>
            </span>

            <nav className="ml-2 hidden items-center gap-1 md:flex">
              {TOP_NAV_ITEMS.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  className={({ isActive }) =>
                    `flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-bold transition-colors ${
                      isActive ? 'bg-white/20' : 'text-white/80 hover:bg-white/10 hover:text-white'
                    }`
                  }
                >
                  <item.icon size={15} strokeWidth={2.25} />
                  {item.label}
                </NavLink>
              ))}
              <NavLink
                to="/"
                end
                className={({ isActive }) =>
                  `rounded-full px-3 py-1.5 text-sm font-extrabold tracking-wide uppercase transition-colors ${
                    isActive ? 'bg-white/20' : 'text-white/80 hover:bg-white/10 hover:text-white'
                  }`
                }
              >
                Tasks
              </NavLink>
            </nav>

            <div className="ml-auto flex items-center gap-2">
              <div
                className="hidden items-center gap-1.5 rounded-full px-3 py-1.5 sm:flex"
                style={{ background: 'var(--color-brand-red-dark)' }}
                title={`${levelInfo.title} · ${levelInfo.xpIntoLevel}/${levelInfo.xpForLevel} XP to next level`}
              >
                <span className="hud-num text-xs font-bold" style={{ color: 'var(--color-brand-yellow)' }}>
                  Lv{levelInfo.level}
                </span>
                <div className="h-1.5 w-14 overflow-hidden rounded-full bg-white/20">
                  <div className="h-full rounded-full" style={{ width: `${levelInfo.progress * 100}%`, background: 'var(--color-brand-yellow)' }} />
                </div>
              </div>
              <button
                type="button"
                onClick={() => disconnect()}
                className="rounded-full px-4 py-2 font-mono text-xs font-bold text-white"
                style={{ background: 'var(--color-brand-red-dark)' }}
                title="Disconnect wallet"
              >
                {shortAddress(wallet)}
              </button>
            </div>
          </div>
        </header>

        <main className="flex-1 px-4 py-5 pb-24 sm:px-6 sm:pb-6">{children}</main>
      </div>

      {/* Mobile bottom nav (sidebar collapses below sm) */}
      <nav className="fixed inset-x-0 bottom-0 z-30 flex border-t border-border bg-surface/95 backdrop-blur sm:hidden">
        {SIDEBAR_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              `flex flex-1 flex-col items-center gap-1 py-2.5 text-[9px] font-bold uppercase tracking-wide ${
                isActive ? '' : 'text-text-faint'
              }`
            }
            style={({ isActive }) => (isActive ? { color: 'var(--color-brand-red)' } : undefined)}
          >
            <item.icon size={18} strokeWidth={2.25} />
            {item.label}
          </NavLink>
        ))}
      </nav>
    </div>
  )
}
