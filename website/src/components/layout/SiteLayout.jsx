import { Outlet } from 'react-router-dom'
import { useI18n } from '../../i18n/index.jsx'
import Navbar from './Navbar.jsx'
import Footer from './Footer.jsx'
import ScrollManager from './ScrollManager.jsx'
import BackgroundBlobs from './BackgroundBlobs.jsx'

/**
 * 全站外壳：导航 + 内容出口 + 页脚。
 * 独立成组件是为了能使用 i18n hook（Provider 在其上层）。
 */
export default function SiteLayout() {
  const { t } = useI18n()

  return (
    <>
      <BackgroundBlobs />
      <ScrollManager />
      <a
        className="skip-link"
        href="#main"
        onClick={(event) => {
          event.preventDefault()
          document.getElementById('main')?.focus()
        }}
      >
        {t('a11y.skip')}
      </a>
      <Navbar />
      <main id="main" tabIndex="-1">
        <Outlet />
      </main>
      <Footer />
    </>
  )
}
