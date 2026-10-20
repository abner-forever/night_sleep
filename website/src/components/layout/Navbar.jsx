import { useEffect, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { useI18n } from '../../i18n/index.jsx'
import ThemeToggle from '../ui/ThemeToggle.jsx'
import Logo from '../ui/Logo.jsx'
import { ArrowRight, Close, Menu } from '../ui/Icons.jsx'
import './Navbar.css'

// 首页区块锚点。用 Link 而非 <a>，避免整页刷新。
const SECTION_LINKS = [
  { key: 'nav.features', hash: 'features' },
  { key: 'nav.report', hash: 'report' },
  { key: 'nav.devices', hash: 'devices' },
  { key: 'nav.faq', hash: 'faq' },
]

export default function Navbar() {
  const { t } = useI18n()
  const { pathname } = useLocation()
  const [scrolled, setScrolled] = useState(false)
  const [open, setOpen] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  // 路由变化时收起移动端菜单
  useEffect(() => {
    setOpen(false)
  }, [pathname])

  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
    return () => {
      document.body.style.overflow = ''
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (e) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  return (
    <header className={`navbar ${scrolled || open ? 'is-scrolled' : ''}`}>
      <nav className="container navbar__inner" aria-label={t('nav.primary')}>
        <Logo />

        <ul className="navbar__links">
          {SECTION_LINKS.map((link) => (
            <li key={link.hash}>
              <Link className="navbar__link" to={`/?section=${link.hash}`}>
                {t(link.key)}
              </Link>
            </li>
          ))}
        </ul>

        <div className="navbar__actions">
          <ThemeToggle className="navbar__theme" />

          <Link className="btn btn--primary btn--sm navbar__cta" to="/download">
            {t('nav.cta')}
            <ArrowRight size={15} />
          </Link>

          <button
            type="button"
            className="navbar__toggle"
            aria-label={open ? t('nav.closeMenu') : t('nav.openMenu')}
            aria-expanded={open}
            aria-controls="mobile-menu"
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <Close size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </nav>

      <div id="mobile-menu" className="navbar__mobile" hidden={!open}>
        <ul className="navbar__mobile-links">
          {SECTION_LINKS.map((link) => (
            <li key={link.hash}>
              <Link
                to={`/?section=${link.hash}`}
                onClick={() => setOpen(false)}
              >
                {t(link.key)}
              </Link>
            </li>
          ))}
        </ul>

        <div className="navbar__mobile-controls">
          <div className="navbar__mobile-row">
            <span className="navbar__mobile-label">{t('theme.label')}</span>
            <ThemeToggle />
          </div>
        </div>

        <Link
          className="btn btn--primary btn--block"
          to="/download"
          onClick={() => setOpen(false)}
        >
          {t('nav.cta')}
          <ArrowRight size={16} />
        </Link>
      </div>
    </header>
  )
}
