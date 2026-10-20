import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import './HowItWorks.css'

export default function HowItWorks() {
  const { t, tList } = useI18n()
  const steps = tList('how.steps')

  return (
    <section className="section" id="how">
      <div className="container">
        <Reveal className="section-head section-head--center">
          <span className="eyebrow">{t('how.eyebrow')}</span>
          <h2 className="section-title">{t('how.title')}</h2>
          <p className="section-subtitle">{t('how.subtitle')}</p>
        </Reveal>

        <ol className="how__steps">
          {steps.map((step, i) => (
            <Reveal
              as="li"
              key={step.title}
              delay={i * 90}
              className="how-step"
            >
              <span className="how-step__num">
                {String(i + 1).padStart(2, '0')}
              </span>
              <h3 className="how-step__title">{step.title}</h3>
              <p className="how-step__desc">{step.desc}</p>
            </Reveal>
          ))}
        </ol>
      </div>
    </section>
  )
}
