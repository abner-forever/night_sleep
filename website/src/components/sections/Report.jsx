import { useI18n } from '../../i18n/index.jsx'
import Reveal from '../ui/Reveal.jsx'
import './Report.css'
export default function Report() {
  const { t, tList } = useI18n()
  return (
    <section className="section section--lg section--alt" id="report">
      <div className="container">
        <Reveal className="section-head section-head--center">
          <span className="eyebrow">{t('report.eyebrow')}</span>
          <h2 className="section-title">{t('report.title')}</h2>
          <p className="section-subtitle">{t('report.subtitle')}</p>
        </Reveal>
        <Reveal className="report-card actual-report">
          <div className="actual-report__copy">
            <span className="eyebrow">从一晚，到每一晚</span>
            <h3>
              记录夜晚的细节，
              <br />
              <span className="gradient-text">也听听自己的感受。</span>
            </h3>
            <p>
              睡眠时间、夜间声音与醒后感受，各自有自己的位置。从记录出发，慢慢找到自己的节奏。
            </p>
            <div className="actual-report__tags">
              <span>本地声音分析</span>
              <span>主观感受回顾</span>
              <span>长期记录导出</span>
            </div>
            <small>
              当前 Android 真机截图 · 包含演示数据
              <br />
              没有睡眠阶段数据时，不会推算深睡、浅睡或 REM。
            </small>
          </div>
          <div className="actual-report__screens">
            {['detail', 'all-data'].map((screen, index) => (
              <img
                key={screen}
                src={`${import.meta.env.BASE_URL}screenshots/${screen}.webp`}
                alt={
                  index === 0
                    ? '睡眠详情与声音记录'
                    : '按周、月、年翻阅历史记录'
                }
                width="720"
                height="1493"
                loading="lazy"
              />
            ))}
          </div>
        </Reveal>
        <div className="report__points">
          {tList('report.points').map((p) => (
            <Reveal className="report-point" key={p.title}>
              <h3 className="report-point__title">{p.title}</h3>
              <p className="report-point__desc">{p.desc}</p>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}
