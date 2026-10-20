import { Link } from 'react-router-dom'
import { SITE } from '../../config/site.js'
import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import StoreButtons from '../download/StoreButtons.jsx'
import QrCode from '../download/QrCode.jsx'
import './CTA.css'

export default function CTA() {
  const { t } = useI18n()

  return (
    <section className="cta" id="download">
      <div className="container">
        <Reveal className="cta__card">
          <div className="cta__content">
            <h2 className="cta__title">{t('cta.title')}</h2>
            <p className="cta__subtitle">{t('cta.subtitle')}</p>

            <StoreButtons size="lg" className="cta__stores" />

            <p className="cta__note">{t('cta.note')}</p>

            <Link className="cta__more" to="/download">
              {t('nav.download')} →
            </Link>
          </div>

          <div className="cta__qr">
            <p className="cta__qr-title">{t('download.scanTitle')}</p>
            <QrCode value={SITE.downloadPageUrl()} label="夜深下载页" />
            <p className="cta__qr-hint">{t('download.scanHint')}</p>
          </div>
        </Reveal>
      </div>
    </section>
  )
}
