import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import DeviceFrame from '../visuals/DeviceFrame.jsx'
import PhoneScreen from '../visuals/PhoneScreen.jsx'
import { Smartphone, Tablet } from '../ui/Icons.jsx'
import './Devices.css'

export default function Devices() {
  const { t } = useI18n()

  return (
    <section className="section section--lg section--alt" id="devices">
      <div className="container">
        <Reveal className="section-head section-head--center">
          <span className="eyebrow">{t('devices.eyebrow')}</span>
          <h2 className="section-title">{t('devices.title')}</h2>
          <p className="section-subtitle">{t('devices.subtitle')}</p>
        </Reveal>

        <div className="devices__stage">
          <Reveal className="devices__item devices__item--phone">
            <div className="devices__frame">
              <DeviceFrame type="phone">
                <PhoneScreen screen="session" />
              </DeviceFrame>
            </div>
            <div className="devices__meta">
              <span className="devices__tag">
                <Smartphone size={14} />
                {t('devices.phone.tag')}
              </span>
              <h3 className="devices__title">{t('devices.phone.title')}</h3>
              <p className="devices__desc">{t('devices.phone.desc')}</p>
            </div>
          </Reveal>

          <Reveal className="devices__item devices__item--tablet" delay={100}>
            <div className="devices__frame">
              <DeviceFrame type="phone">
                <PhoneScreen screen="stats" />
              </DeviceFrame>
            </div>
            <div className="devices__meta">
              <span className="devices__tag">
                <Tablet size={14} />
                {t('devices.tablet.tag')}
              </span>
              <h3 className="devices__title">{t('devices.tablet.title')}</h3>
              <p className="devices__desc">{t('devices.tablet.desc')}</p>
            </div>
          </Reveal>
        </div>

        <Reveal className="devices__sync" delay={180}>
          <span className="devices__sync-dot" aria-hidden="true" />
          <strong>{t('devices.sync.title')}</strong>
          <span>{t('devices.sync.desc')}</span>
        </Reveal>
      </div>
    </section>
  )
}
