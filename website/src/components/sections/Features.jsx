import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import {
  Alarm,
  AudioLines,
  Mic,
  Smartphone,
  Tablet,
  Waves,
} from '../ui/Icons.jsx'
import './Features.css'

// 与 locale 中 features.items 的顺序一一对应
const ICONS = [Waves, Mic, AudioLines, AudioLines, Tablet, Alarm]

// 每个功能对应的辅助图示标签（取自同一份文案）
const TAGS = [
  '开始 → 结束',
  '8 种夜景 · 5 种声音',
  '端侧模型',
  '手动标注优先',
  'CSV · JSON',
  '提醒 · 评星',
]

export default function Features() {
  const { t, tList } = useI18n()
  const items = tList('features.items')

  return (
    <section className="section section--lg" id="features">
      <div className="container">
        <Reveal className="section-head section-head--center">
          <span className="eyebrow">{t('features.eyebrow')}</span>
          <h2 className="section-title">{t('features.title')}</h2>
          <p className="section-subtitle">{t('features.subtitle')}</p>
        </Reveal>

        <div className="features__grid">
          {items.map((item, i) => {
            const Icon = ICONS[i] ?? Waves
            return (
              <Reveal key={item.title} delay={i * 60} className="feature">
                <span className="feature__icon">
                  <Icon size={20} />
                </span>
                <h3 className="feature__title">{item.title}</h3>
                <p className="feature__desc">{item.desc}</p>
                <span className="feature__tag">{TAGS[i]}</span>
              </Reveal>
            )
          })}
        </div>
      </div>
    </section>
  )
}
