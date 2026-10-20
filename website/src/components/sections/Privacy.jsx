import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import { DeviceLocal, Lock, Trash } from '../ui/Icons.jsx'
import './Privacy.css'

const ICONS = [DeviceLocal, Lock, Trash]

export default function Privacy() {
  const { t, tList } = useI18n()
  const items = tList('privacy.items')

  return (
    <section className="section" id="privacy">
      <div className="container privacy__grid">
        <Reveal className="privacy__intro">
          <span className="eyebrow">{t('privacy.eyebrow')}</span>
          <h2 className="section-title">{t('privacy.title')}</h2>
          <p className="section-subtitle">{t('privacy.subtitle')}</p>
        </Reveal>

        <ul className="privacy__items">
          {items.map((item, i) => {
            const Icon = ICONS[i] ?? Lock
            return (
              <Reveal
                as="li"
                key={item.title}
                delay={i * 70}
                className="privacy-item"
              >
                <span className="privacy-item__icon">
                  <Icon size={18} />
                </span>
                <div>
                  <h3 className="privacy-item__title">{item.title}</h3>
                  <p className="privacy-item__desc">{item.desc}</p>
                </div>
              </Reveal>
            )
          })}
        </ul>
      </div>
    </section>
  )
}
