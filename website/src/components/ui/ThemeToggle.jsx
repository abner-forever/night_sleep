import { useTheme } from '../../theme/ThemeProvider.jsx'
import { useI18n } from '../../i18n/index.jsx'
import { Monitor, Moon, Sun } from './Icons.jsx'
import './controls.css'

const OPTIONS = [
  { value: 'light', icon: Sun, key: 'theme.light' },
  { value: 'dark', icon: Moon, key: 'theme.dark' },
  { value: 'system', icon: Monitor, key: 'theme.system' },
]

/**
 * 三段式主题切换（浅色 / 深色 / 跟随系统）。
 * 用 radiogroup 语义，键盘可用方向键切换。
 */
export default function ThemeToggle({ className = '' }) {
  const { mode, setMode } = useTheme()
  const { t } = useI18n()

  const onKeyDown = (e) => {
    const index = OPTIONS.findIndex((o) => o.value === mode)
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
      e.preventDefault()
      setMode(OPTIONS[(index + 1) % OPTIONS.length].value)
    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
      e.preventDefault()
      setMode(OPTIONS[(index - 1 + OPTIONS.length) % OPTIONS.length].value)
    }
  }

  return (
    <div
      className={`segmented ${className}`.trim()}
      role="radiogroup"
      aria-label={t('theme.label')}
      onKeyDown={onKeyDown}
    >
      {OPTIONS.map(({ value, icon: Icon, key }) => (
        <button
          key={value}
          type="button"
          role="radio"
          aria-checked={mode === value}
          aria-label={t(key)}
          title={t(key)}
          tabIndex={mode === value ? 0 : -1}
          className="segmented__btn"
          onClick={() => setMode(value)}
        >
          <Icon size={16} />
        </button>
      ))}
    </div>
  )
}
