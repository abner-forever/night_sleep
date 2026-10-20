import { useEffect, useRef } from 'react'
import { useI18n } from '../../i18n/index.jsx'
import StoreButtons from '../download/StoreButtons.jsx'
import DeviceFrame from '../visuals/DeviceFrame.jsx'
import PhoneScreen from '../visuals/PhoneScreen.jsx'
import Reveal from '../ui/Reveal.jsx'
import { DeviceLocal } from '../ui/Icons.jsx'
import './Hero.css'

const MAX_TILT = 6

export default function Hero() {
  const { t, tList } = useI18n()
  const stats = tList('stats')
  const visualRef = useRef(null)

  // 鼠标视差：仅精确指针设备 + 未开启减弱动效时启用
  useEffect(() => {
    const host = visualRef.current
    if (!host) return
    const device = host.querySelector('.device')
    if (!device) return

    const finePointer = window.matchMedia('(hover: hover) and (pointer: fine)')
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)')
    if (!finePointer.matches || reduced.matches) return

    let frame = 0
    const onMove = (e) => {
      if (frame) return
      // 用 rAF 节流，避免每次 mousemove 都写样式
      frame = requestAnimationFrame(() => {
        frame = 0
        const x = (e.clientX / window.innerWidth - 0.5) * MAX_TILT
        const y = (e.clientY / window.innerHeight - 0.5) * MAX_TILT
        device.style.transform = `rotateY(${x}deg) rotateX(${-y}deg)`
      })
    }

    const onLeave = () => {
      if (frame) cancelAnimationFrame(frame)
      frame = 0
      device.style.transform = ''
    }

    window.addEventListener('mousemove', onMove)
    document.addEventListener('mouseleave', onLeave)
    return () => {
      if (frame) cancelAnimationFrame(frame)
      window.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseleave', onLeave)
      device.style.transform = ''
    }
  }, [])

  return (
    <section className="hero" id="top">
      <div className="container hero__inner">
        <Reveal className="hero__content">
          <h1 className="hero__title">
            {t('hero.titleLead')}
            <span className="gradient-text">{t('hero.titleAccent')}</span>
          </h1>

          <p className="hero__subtitle">{t('hero.subtitle')}</p>

          <StoreButtons size="lg" className="hero__stores" />

          <p className="hero__note">{t('hero.note')}</p>

          <div className="hero__proof">
            <span className="hero__stars" aria-hidden="true">
              <DeviceLocal size={20} />
            </span>
            <p>
              <strong>{t('hero.ratingScore')}</strong> ·{' '}
              {t('hero.ratingSource')}
            </p>
          </div>
        </Reveal>

        <Reveal className="hero__visual" delay={120}>
          {/* 视差作用在这一层：perspective 只对直接子元素生效，
              而 Reveal 内部已占用 ref，不能直接挂到它上面 */}
          <div className="hero__device" ref={visualRef}>
            <DeviceFrame type="phone">
              <PhoneScreen />
            </DeviceFrame>
          </div>
          <p className="hero__caption">{t('hero.previewCaption')}</p>
        </Reveal>
      </div>

      <div className="container">
        <Reveal className="hero__stats" delay={200}>
          {stats.map((s) => (
            <div className="stat" key={s.label}>
              <span className="stat__value">{s.value}</span>
              <span className="stat__label">{s.label}</span>
            </div>
          ))}
        </Reveal>
      </div>
    </section>
  )
}
