import { HashRouter, Route, Routes } from 'react-router-dom'
import { ThemeProvider } from './theme/ThemeProvider.jsx'
import { I18nProvider } from './i18n/index.jsx'
import SiteLayout from './components/layout/SiteLayout.jsx'
import Home from './pages/Home.jsx'
import Download from './pages/Download.jsx'
import NotFound from './pages/NotFound.jsx'
import PrivacyPolicy from './pages/PrivacyPolicy.jsx'

export default function App() {
  return (
    <ThemeProvider>
      <I18nProvider>
        <HashRouter>
          <Routes>
            <Route element={<SiteLayout />}>
              <Route path="/" element={<Home />} />
              <Route path="/download" element={<Download />} />
              <Route path="/privacy" element={<PrivacyPolicy />} />
              <Route path="*" element={<NotFound />} />
            </Route>
          </Routes>
        </HashRouter>
      </I18nProvider>
    </ThemeProvider>
  )
}
