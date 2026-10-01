import { ChevronLeft, ChevronRight, type LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'

export function SectionHeader({
  icon: Icon,
  title,
  action,
  onScrollLeft,
  onScrollRight,
}: {
  icon: LucideIcon
  title: string
  action?: ReactNode
  onScrollLeft?: () => void
  onScrollRight?: () => void
}) {
  return (
    <div className="mb-3 flex items-center gap-2">
      <span className="relative flex h-2 w-2">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-brand-magenta opacity-60 motion-reduce:animate-none" />
        <span className="relative inline-flex h-2 w-2 rounded-full bg-brand-pink" />
      </span>
      <Icon size={15} className="text-brand-pink" strokeWidth={2.5} />
      <h2 className="font-display text-sm font-extrabold tracking-wide uppercase">{title}</h2>
      <div className="ml-auto flex items-center gap-3">
        {action}
        {(onScrollLeft || onScrollRight) && (
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={onScrollLeft}
              className="flex h-7 w-7 items-center justify-center rounded-lg bg-surface-2 text-text-muted hover:text-text"
            >
              <ChevronLeft size={15} />
            </button>
            <button
              type="button"
              onClick={onScrollRight}
              className="flex h-7 w-7 items-center justify-center rounded-lg bg-surface-2 text-text-muted hover:text-text"
            >
              <ChevronRight size={15} />
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
