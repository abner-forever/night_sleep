import { useState } from 'react'
import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import { ChevronDown } from '../ui/Icons.jsx'
import './FAQ.css'

export default function FAQ() {
  const { t, tList } = useI18n()
  const items = tList('faq.items')
  const [openIndex, setOpenIndex] = useState(0)

  const toggle = (i) => setOpenIndex((current) => (current === i ? -1 : i))

  return (
    <section className="section" id="faq">
      <div className="container container--narrow">
        <Reveal className="section-head section-head--center">
          <span className="eyebrow">{t('faq.eyebrow')}</span>
          <h2 className="section-title">{t('faq.title')}</h2>
          <p className="section-subtitle">{t('faq.subtitle')}</p>
        </Reveal>

        <div className="faq__list">
          {items.map((item, i) => {
            const isOpen = openIndex === i

            return (
              <Reveal
                key={item.q}
                delay={i * 40}
                className={`faq-item ${isOpen ? 'is-open' : ''}`}
              >
                <h3 className="faq-item__heading">
                  <button
                    type="button"
                    className="faq-item__trigger"
                    aria-expanded={isOpen}
                    aria-controls={`faq-panel-${i}`}
                    id={`faq-trigger-${i}`}
                    onClick={() => toggle(i)}
                  >
                    <span>{item.q}</span>
                    <span className="faq-item__icon" aria-hidden="true">
                      <ChevronDown size={17} />
                    </span>
                  </button>
                </h3>

                <div
                  id={`faq-panel-${i}`}
                  role="region"
                  aria-labelledby={`faq-trigger-${i}`}
                  className="faq-item__panel"
                >
                  <div className="faq-item__panel-inner">
                    <p>{item.a}</p>
                  </div>
                </div>
              </Reveal>
            )
          })}
        </div>
      </div>
    </section>
  )
}
