import { useState } from 'react'
import { useI18n } from '../../i18n/index.jsx'
import { useTheme } from '../../theme/ThemeProvider.jsx'
import Reveal from '../ui/Reveal.jsx'
import DeviceFrame from '../visuals/DeviceFrame.jsx'
import PhoneScreen from '../visuals/PhoneScreen.jsx'
import { Smartphone, Tablet } from '../ui/Icons.jsx'
import './Devices.css'

export default function Devices() {
  const { t, tList } = useI18n()
  const { resolved } = useTheme()
  const screens = tList('devices.screens')
  const [activeScreen, setActiveScreen] = useState('home')
  const selected = screens.find((screen) => screen.id === activeScreen)

  return (
    <section className="section section--lg section--alt" id="devices">
      <div className="container">
        <Reveal className="section-head section-head--center">
          <span className="eyebrow">{t('devices.eyebrow')}</span>
          <h2 className="section-title">{t('devices.title')}</h2>
          <p className="section-subtitle">{t('devices.subtitle')}</p>
        </Reveal>

        <Reveal className="devices__controls">
          <div className="devices__choices" role="group" aria-label="选择预览页面">
            {screens.map((screen) => (
              <button
                key={screen.id}
                type="button"
                aria-pressed={activeScreen === screen.id}
                onClick={() => setActiveScreen(screen.id)}
              >
                {screen.label}
              </button>
            ))}
          </div>
          <p className="devices__theme-note">
            {activeScreen === 'session' || activeScreen === 'sounds'
              ? '睡前会话始终使用深色夜景'
              : `${resolved === 'dark' ? '深色界面' : '浅色界面'} · 可在导航栏切换主题`}
          </p>
        </Reveal>

        <div className="devices__stage" aria-label={`${selected.label}的手机与平板预览`}>
          <Reveal className="devices__item devices__item--phone">
            <div className="devices__frame">
              <DeviceFrame type="phone">
                <PhoneScreen screen={activeScreen} />
              </DeviceFrame>
            </div>
            <div className="devices__meta">
              <span className="devices__tag">
                <Smartphone size={14} />
                {activeScreen === 'session' || activeScreen === 'sounds'
                  ? 'iPhone · 睡前会话'
                  : 'iPhone · 底部导航'}
              </span>
              <h3 className="devices__title">{selected.phoneTitle}</h3>
              <p className="devices__desc">{selected.phoneDesc}</p>
            </div>
          </Reveal>

          <Reveal className="devices__item devices__item--tablet" delay={100}>
            <div className="devices__frame">
              <DeviceFrame type="tablet">
                <PhoneScreen screen={activeScreen} device="tablet" />
              </DeviceFrame>
            </div>
            <div className="devices__meta">
              <span className="devices__tag">
                <Tablet size={14} />
                iPad · 自适应宽屏
              </span>
              <h3 className="devices__title">{selected.tabletTitle}</h3>
              <p className="devices__desc">{selected.tabletDesc}</p>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  )
}
