import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'
import zhCN from './locales/zh-CN.js'

export const LOCALES = [{ code: 'zh-CN', label: '简体中文', short: '简' }]

const DICT = { 'zh-CN': zhCN }
const FALLBACK = 'zh-CN'
const STORAGE_KEY = 'yeshen-locale'

const I18nContext = createContext(null)

/** 从浏览器语言推断最接近的受支持语言 */
function detectLocale() {
  if (typeof navigator === 'undefined') return FALLBACK
  const list = navigator.languages?.length
    ? navigator.languages
    : [navigator.language]
  for (const raw of list) {
    if (!raw) continue
    const tag = raw.toLowerCase()
    if (tag.startsWith('zh')) {
      // zh-TW / zh-HK / zh-Hant 归为繁体，其余归为简体
      if (tag.includes('tw') || tag.includes('hk') || tag.includes('hant'))
        return FALLBACK
      return 'zh-CN'
    }
    if (tag.startsWith('en')) return FALLBACK
  }
  return FALLBACK
}

function getInitialLocale() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved && DICT[saved]) return saved
  } catch {
    /* ignore */
  }
  return detectLocale()
}

/** 按 'a.b.c' 路径取值 */
function resolve(dict, path) {
  return path
    .split('.')
    .reduce((acc, key) => (acc == null ? undefined : acc[key]), dict)
}

export function I18nProvider({ children }) {
  const [locale, setLocaleState] = useState(getInitialLocale)

  const setLocale = useCallback((next) => {
    if (!DICT[next]) return
    setLocaleState(next)
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch {
      /* ignore */
    }
  }, [])

  // 同步 <html lang> 与页面标题
  useEffect(() => {
    document.documentElement.lang = locale
    const title = resolve(DICT[locale], 'meta.title')
    if (title) document.title = title
  }, [locale])

  /**
   * t('hero.title') —— 当前语言缺失时回落到简体中文，再缺则原样返回 key，
   * 便于开发期发现漏翻。
   */
  const t = useCallback(
    (path) => {
      const value = resolve(DICT[locale], path)
      if (value !== undefined) return value
      const fallback = resolve(DICT[FALLBACK], path)
      return fallback !== undefined ? fallback : path
    },
    [locale],
  )

  /** 取数组型文案（列表渲染用），同样带回落 */
  const tList = useCallback(
    (path) => {
      const value = resolve(DICT[locale], path)
      if (Array.isArray(value)) return value
      const fallback = resolve(DICT[FALLBACK], path)
      return Array.isArray(fallback) ? fallback : []
    },
    [locale],
  )

  const value = useMemo(
    () => ({ locale, setLocale, t, tList, locales: LOCALES }),
    [locale, setLocale, t, tList],
  )

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n() {
  const ctx = useContext(I18nContext)
  if (!ctx) throw new Error('useI18n 必须在 I18nProvider 内使用')
  return ctx
}
