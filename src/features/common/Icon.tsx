import { type ReactNode } from 'react'

export type IconName =
  | 'share'
  | 'community'
  | 'group'
  | 'shield'
  | 'user'
  | 'heart'
  | 'signal'
  | 'download'
  | 'bell'

const PATHS: Record<IconName, ReactNode> = {
  share: (
    <>
      <circle cx="18" cy="5" r="3" />
      <circle cx="6" cy="12" r="3" />
      <circle cx="18" cy="19" r="3" />
      <line x1="8.6" y1="13.5" x2="15.4" y2="17.5" />
      <line x1="15.4" y1="6.5" x2="8.6" y2="10.5" />
    </>
  ),
  community: (
    <>
      <path d="M3 21h18" />
      <path d="M5 21V7l8-4v18" />
      <path d="M19 21V11l-6-4" />
      <path d="M9 9v.01M9 13v.01M9 17v.01" />
    </>
  ),
  group: (
    <>
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.9" />
      <path d="M16 3.1a4 4 0 0 1 0 7.8" />
    </>
  ),
  shield: <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />,
  user: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21v-1a8 8 0 0 1 16 0v1" />
    </>
  ),
  heart: (
    <path d="M19 14c1.5-1.6 3-3.5 3-5.6A4.4 4.4 0 0 0 12 5.5 4.4 4.4 0 0 0 2 8.4c0 2.1 1.5 4 3 5.6l7 6.5z" />
  ),
  signal: (
    <>
      <path d="M5 12a7 7 0 0 1 14 0" />
      <path d="M8.5 12a3.5 3.5 0 0 1 7 0" />
      <circle cx="12" cy="12.5" r="1.2" />
    </>
  ),
  download: (
    <>
      <path d="M12 3v12" />
      <path d="M7 10l5 5 5-5" />
      <path d="M5 21h14" />
    </>
  ),
  bell: (
    <>
      <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.7 21a2 2 0 0 1-3.4 0" />
    </>
  ),
}

export function Icon({
  name,
  size = 20,
}: {
  name: IconName
  size?: number
}) {
  return (
    <svg
      className="icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  )
}
