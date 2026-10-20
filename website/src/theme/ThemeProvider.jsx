import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'

const STORAGE_KEY = 'yeshen-theme'
const MODES = ['light', 'dark', 'system']

const ThemeContext = createContext(null)

/** 读取系统偏好 */
function getSystemTheme() {
  if (typeof window === 'undefined' || !window.matchMedia) return 'light'
  return window.matchMedia('(prefers-color-scheme: dark)').matches
    ? 'dark'
    : 'light'
}

/** 读取本地存储的主题模式，非法值回落到 system */
function getStoredMode() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return MODES.includes(saved) ? saved : 'system'
  } catch {
    return 'system'
  }
}

export function ThemeProvider({ children }) {
  const [mode, setModeState] = useState(getStoredMode)
  const [systemTheme, setSystemTheme] = useState(getSystemTheme)

  // 跟随系统时，监听系统主题变化
  useEffect(() => {
    if (!window.matchMedia) return
    const query = window.matchMedia('(prefers-color-scheme: dark)')
    const onChange = (e) => setSystemTheme(e.matches ? 'dark' : 'light')
    query.addEventListener('change', onChange)
    return () => query.removeEventListener('change', onChange)
  }, [])

  const resolved = mode === 'system' ? systemTheme : mode

  // 写入 <html data-theme> 与 theme-color
  useEffect(() => {
    const root = document.documentElement
    root.setAttribute('data-theme', resolved)

    const meta = document.querySelector('meta[name="theme-color"]')
    if (meta)
      meta.setAttribute('content', resolved === 'dark' ? '#170f11' : '#ffffff')
  }, [resolved])

  const setMode = useCallback((next) => {
    if (!MODES.includes(next)) return
    setModeState(next)
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch {
      /* 隐私模式下 localStorage 可能不可用，忽略即可 */
    }
  }, [])

  // 在 light → dark → system 之间循环，供单键切换使用
  const cycleMode = useCallback(() => {
    setMode(MODES[(MODES.indexOf(mode) + 1) % MODES.length])
  }, [mode, setMode])

  const value = useMemo(
    () => ({ mode, resolved, setMode, cycleMode, modes: MODES }),
    [mode, resolved, setMode, cycleMode],
  )

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
}

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme 必须在 ThemeProvider 内使用')
  return ctx
}
