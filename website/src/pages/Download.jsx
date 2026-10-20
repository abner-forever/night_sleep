import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { loadDownload, RELEASES_PAGE } from '../config/download.mjs'
import { SITE } from '../config/site.js'
import { useI18n } from '../i18n/index.jsx'
import Reveal from '../components/ui/Reveal.jsx'
import { IosStoreButton } from '../components/download/StoreButtons.jsx'
import BrandedQrCode from '../components/download/BrandedQrCode.jsx'
import { AppleLogo, ArrowRight, Smartphone } from '../components/ui/Icons.jsx'
import './Download.css'
export default function Download() {
  const { t, tList } = useI18n()
  const [state, setState] = useState({ loading: true, download: null })
  const [copied, setCopied] = useState(false)
  const [retry, setRetry] = useState(0)
  useEffect(() => {
    let active = true
    loadDownload({ refresh: retry > 0 }).then((result) => {
      if (active) setState({ loading: false, ...result })
    })
    return () => { active = false }
  }, [retry])
  const pageUrl = SITE.downloadPageUrl(),
    qrUrl = state.download?.url ?? pageUrl
  return (
    <div className="dl">
      <section className="dl__hero">
        <div className="container">
          <Reveal className="dl__head">
            <span className="eyebrow">{t('download.eyebrow')}</span>
            <h1 className="dl__title">
              从今晚开始，<span className="gradient-text">好好休息</span>
            </h1>
            <p className="dl__subtitle">{t('download.subtitle')}</p>
          </Reveal>
          <Reveal className="dl-card android-download">
            <header className="dl-card__head">
              <span className="dl-card__icon">
                <Smartphone size={24} />
              </span>
              <div>
                <h2 className="dl-card__name">夜深 Android</h2>
                <p className="dl-card__store">
                  Android 7.0+ · 无需账号 · APK 安装
                </p>
              </div>
            </header>
            <div className="dl-card__body">
              <div className="dl-card__actions">
                <span className="release-badge">
                  {state.download
                    ? `Android ${state.download.channel === 'stable' ? '正式版本' : 'Beta 版本'} · v${state.download.version}`
                    : 'Beta 版本准备中'}
                </span>
                <h3>
                  {state.download
                    ? '从第一晚，开始记录。'
                    : 'Android 版本准备中'}
                </h3>
                <p>
                  {state.download
                    ? `${(state.download.size / 1024 / 1024).toFixed(1)} MB · 直接下载 APK`
                    : '安装包正在构建与验证。公开下载开放后，这里会提供 APK 和对应二维码。'}
                </p>
                {state.download ? (
                  <a
                    className="btn btn--primary btn--lg"
                    href={state.download.url}
                  >
                    下载 APK <ArrowRight size={18} />
                  </a>
                ) : (
                  <button disabled className="btn btn--primary btn--lg">
                    {state.loading ? '正在检查版本…' : state.failed ? '暂时无法获取版本' : '尚未开放公开下载'}
                  </button>
                )}
                {state.failed && (
                  <p className="dl-card__req" role="status">
                    {state.download ? '暂时无法检查更新，当前显示最近获取的版本。' : '请稍后重试，或前往 GitHub 查看发布版本。'}
                    {' '}<a href={RELEASES_PAGE} target="_blank" rel="noopener noreferrer">GitHub Releases ↗</a>
                    {' '}<button type="button" className="qr-download" onClick={() => {
                      setState((current) => ({ ...current, loading: true, failed: false }))
                      setRetry((value) => value + 1)
                    }}>重新检查</button>
                  </p>
                )}
                {state.download && (
                  <p className="dl-card__req">
                    早期版本使用测试签名。升级到长期签名版本前，请先导出记录，再卸载旧版并重新安装。
                    本次安装、整夜录音与升级覆盖尚未完成真机验证。
                  </p>
                )}
                {state.download && (
                  <details className="checksum">
                    <summary>查看 SHA-256 校验值</summary>
                    <code>{state.download.sha256}</code>
                  </details>
                )}
              </div>
              <figure className="qr">
                <div className="qr__box">
                  <BrandedQrCode
                    id="download-qr"
                    value={qrUrl}
                    size={180}
                    title={
                      state.download
                        ? 'Android APK 下载二维码'
                        : '夜深下载页面二维码'
                    }
                  />
                </div>
                <figcaption className="qr__label">
                  {state.download ? '扫码下载 Android APK' : '扫码打开此下载页'}
                  <small>
                    {state.download
                      ? '请使用系统浏览器下载'
                      : '此码用于访问页面，当前不提供 APK'}
                  </small>
                </figcaption>
                <a className="qr-save" href={qrUrl}>
                  打开对应链接 ↗
                </a>
                <button
                  className="qr-download"
                  onClick={() => {
                    const svg = document.getElementById('download-qr')
                    if (!svg) return
                    const url = URL.createObjectURL(
                      new Blob([new XMLSerializer().serializeToString(svg)], {
                        type: 'image/svg+xml',
                      }),
                    )
                    const a = document.createElement('a')
                    a.href = url
                    a.download = 'yeshen-download-qr.svg'
                    a.click()
                    setTimeout(() => URL.revokeObjectURL(url), 1000)
                  }}
                >
                  保存二维码 ↓
                </button>
              </figure>
            </div>
          </Reveal>
          <Reveal className="dl-card ios-download">
            <header className="dl-card__head">
              <span className="dl-card__icon">
                <AppleLogo size={24} />
              </span>
              <div>
                <h2 className="dl-card__name">夜深 iOS</h2>
                <p className="dl-card__store">
                  App Store · 暂缓支持
                </p>
              </div>
            </header>
            <IosStoreButton size="lg" />
          </Reveal>
          <Reveal className="download-reminder">
            <div>
              <h3>也可以把页面留给稍后的自己。</h3>
              <p role="status" aria-live="polite">
                {copied
                  ? '链接已复制。'
                  : '下载地址会在此页更新，收藏页面即可。'}
              </p>
            </div>
            <button
              className="btn btn--outline"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(pageUrl)
                  setCopied(true)
                } catch {
                  window.prompt('复制下载页地址', pageUrl)
                }
              }}
            >
              复制下载页链接
            </button>
          </Reveal>
        </div>
      </section>
      <section className="section section--alt">
        <div className="container">
          <Reveal className="section-head section-head--center">
            <h2 className="section-title">{t('download.steps.title')}</h2>
          </Reveal>
          <ol className="dl__steps">
            {tList('download.steps.items').map((step, index) => (
              <Reveal
                as="li"
                className="dl-step"
                key={step.title}
                delay={index * 80}
              >
                <span className="dl-step__num">
                  {String(index + 1).padStart(2, '0')}
                </span>
                <h3 className="dl-step__title">{step.title}</h3>
                <p className="dl-step__desc">{step.desc}</p>
              </Reveal>
            ))}
          </ol>
          <Reveal className="dl__back">
            <Link to="/" className="dl__back-link">
              ← 返回首页
            </Link>
          </Reveal>
        </div>
      </section>
    </div>
  )
}
