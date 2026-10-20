/**
 * 线性 SVG 图标集（24×24 网格，stroke 风格）。
 * 统一 currentColor，尺寸由 size 控制。不使用 emoji 作为图标。
 */

function Svg({ size = 20, strokeWidth = 1.75, children, ...props }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...props}
    >
      {children}
    </svg>
  )
}

/* --- 通用 --- */

export const ArrowRight = (p) => (
  <Svg {...p}>
    <path d="M5 12h14M13 6l6 6-6 6" />
  </Svg>
)

export const Check = (p) => (
  <Svg {...p}>
    <path d="M20 6 9 17l-5-5" />
  </Svg>
)

export const Close = (p) => (
  <Svg {...p}>
    <path d="M18 6 6 18M6 6l12 12" />
  </Svg>
)

export const Menu = (p) => (
  <Svg {...p}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </Svg>
)

export const ChevronDown = (p) => (
  <Svg {...p}>
    <path d="m6 9 6 6 6-6" />
  </Svg>
)

export const Play = (p) => (
  <Svg {...p}>
    <path d="M7 4.5v15l12-7.5-12-7.5Z" />
  </Svg>
)

export const Star = ({ size = 16, ...p }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="currentColor"
    aria-hidden="true"
    focusable="false"
    {...p}
  >
    <path d="m12 2.5 2.9 5.9 6.6.9-4.8 4.6 1.2 6.5L12 17.3 6.1 20.4l1.2-6.5-4.8-4.6 6.6-.9L12 2.5Z" />
  </svg>
)

export const Quote = (p) => (
  <Svg {...p}>
    <path d="M9 6C6.2 7.3 4.5 9.9 4.5 13v5h6v-6H7.8c0-2 1-3.4 2.7-4.3L9 6ZM19.5 6c-2.8 1.3-4.5 3.9-4.5 7v5h6v-6h-2.7c0-2 1-3.4 2.7-4.3L19.5 6Z" />
  </Svg>
)

/* --- 主题 --- */

export const Sun = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
  </Svg>
)

export const Moon = (p) => (
  <Svg {...p}>
    <path d="M20 14.2A8.5 8.5 0 0 1 9.8 4a8.5 8.5 0 1 0 10.2 10.2Z" />
  </Svg>
)

export const Monitor = (p) => (
  <Svg {...p}>
    <rect x="2.5" y="4" width="19" height="13" rx="2" />
    <path d="M9 20.5h6M12 17v3.5" />
  </Svg>
)

/* --- 语言 --- */

export const Globe = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M3 12h18M12 3a15 15 0 0 1 0 18 15 15 0 0 1 0-18Z" />
  </Svg>
)

/* --- 睡眠功能 --- */

export const Clock = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7v5l3 2" />
  </Svg>
)

export const Waves = (p) => (
  <Svg {...p}>
    <path d="M2 8.5c2 0 2.5-2 4-2s2 2 4 2 2.5-2 4-2 2 2 4 2 2.5-2 4-2" />
    <path d="M2 15.5c2 0 2.5-2 4-2s2 2 4 2 2.5-2 4-2 2 2 4 2 2.5-2 4-2" />
  </Svg>
)

export const Mic = (p) => (
  <Svg {...p}>
    <rect x="9" y="2.5" width="6" height="11" rx="3" />
    <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3.5" />
  </Svg>
)

export const AudioLines = (p) => (
  <Svg {...p}>
    <path d="M3 12h1.5M7.5 7.5v9M12 4.5v15M16.5 8.5v7M21 11.5v1" />
  </Svg>
)

export const Chart = (p) => (
  <Svg {...p}>
    <path d="M3 3v16a2 2 0 0 0 2 2h16" />
    <path d="M7 15l3.5-4 3 2.5L20 7" />
  </Svg>
)

export const Layers = (p) => (
  <Svg {...p}>
    <path d="m12 3 9 5-9 5-9-5 9-5Z" />
    <path d="m3 13 9 5 9-5" />
  </Svg>
)

export const Alarm = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="13" r="7.5" />
    <path d="M12 9.5V13l2.5 1.5M5 3.5 2.5 6M19 3.5 21.5 6" />
  </Svg>
)

/* --- 设备 --- */

export const Smartphone = (p) => (
  <Svg {...p}>
    <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
    <path d="M10.5 18.5h3" />
  </Svg>
)

export const Tablet = (p) => (
  <Svg {...p}>
    <rect x="4" y="2.5" width="16" height="19" rx="2.5" />
    <path d="M10.5 18.5h3" />
  </Svg>
)

export const Battery = (p) => (
  <Svg {...p}>
    <rect x="2" y="7.5" width="16" height="9" rx="2" />
    <path d="M21 10.5v3" />
    <path d="M5 10.5v3" />
  </Svg>
)

/* --- 隐私 --- */

export const Lock = (p) => (
  <Svg {...p}>
    <rect x="4.5" y="10.5" width="15" height="10" rx="2.5" />
    <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
  </Svg>
)

export const Shield = (p) => (
  <Svg {...p}>
    <path d="M12 3l7.5 3v5.5c0 4.6-3.1 8.6-7.5 9.5-4.4-.9-7.5-4.9-7.5-9.5V6L12 3Z" />
    <path d="m9 12 2 2 4-4" />
  </Svg>
)

export const DeviceLocal = (p) => (
  <Svg {...p}>
    <rect x="3" y="4.5" width="18" height="12" rx="2" />
    <path d="M8 20.5h8M12 16.5v4" />
    <path d="M9.5 10.5 12 13l2.5-2.5" />
  </Svg>
)

export const Trash = (p) => (
  <Svg {...p}>
    <path d="M4 7h16M10 7V5.5a1.5 1.5 0 0 1 1.5-1.5h1A1.5 1.5 0 0 1 14 5.5V7" />
    <path d="M6.5 7l.8 12a2 2 0 0 0 2 1.9h5.4a2 2 0 0 0 2-1.9l.8-12" />
  </Svg>
)

/* --- 品牌（第三方应用商店） --- */

export const AppleLogo = ({ size = 20, ...p }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="currentColor"
    aria-hidden="true"
    {...p}
  >
    <path d="M16.36 12.72c-.02-2.2 1.8-3.26 1.88-3.31-1.02-1.5-2.62-1.7-3.19-1.73-1.36-.14-2.65.8-3.34.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.18-1.54 2.67-.39 6.62 1.11 8.79.73 1.06 1.6 2.25 2.74 2.21 1.1-.04 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.08 2.66-2.14.83-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.32-3.5zM14.2 6.3c.6-.74 1.01-1.75.9-2.77-.87.04-1.93.58-2.56 1.31-.56.65-1.05 1.69-.92 2.68.97.08 1.96-.49 2.58-1.22z" />
  </svg>
)

export const GooglePlayLogo = ({ size = 20, ...p }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="currentColor"
    aria-hidden="true"
    {...p}
  >
    <path d="M3.6 2.3a1 1 0 0 0-.6.92v17.56a1 1 0 0 0 .6.92l9.66-9.7L3.6 2.3Zm10.5 8.44 2.83-2.84-9.6-5.5 6.77 8.34Zm0 2.52-6.77 8.34 9.6-5.5-2.83-2.84Zm1.3-1.26 3.2 1.83c.9.52.9 1.82 0 2.34l-3.2 1.83-3.06-3.06 3.06-2.94Z" />
  </svg>
)
