import { Link } from 'react-router-dom'
import { SITE } from '../../config/site.js'
import { useI18n } from '../../i18n/index.jsx'
import Logo from '../ui/Logo.jsx'
import './Footer.css'
export default function Footer() {
  const { t } = useI18n()
  const groups = [
    {
      title: '产品',
      links: [
        ['功能总览', '/?section=features'],
        ['睡眠回顾', '/?section=report'],
        ['应用预览', '/?section=devices'],
      ],
    },
    {
      title: '开始使用',
      links: [
        ['下载 Android', '/download'],
        ['使用方式', '/?section=how'],
        ['常见问题', '/?section=faq'],
      ],
    },
    {
      title: '了解夜深',
      links: [
        ['数据与隐私', '/?section=privacy'],
        ['GitHub', SITE.repositoryUrl],
        ['问题反馈', SITE.issuesUrl],
      ],
    },
  ]
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer__top">
          <div className="footer__brand">
            <Logo />
            <p className="footer__desc">{t('footer.desc')}</p>
            <Link className="footer__download" to="/download">
              获取夜深 →
            </Link>
          </div>
          <nav className="footer__columns" aria-label="页脚导航">
            {groups.map((g) => (
              <div key={g.title}>
                <h3 className="footer__col-title">{g.title}</h3>
                <ul className="footer__col-links">
                  {g.links.map(([label, url]) => (
                    <li key={label}>
                      {url.startsWith('https:') ? (
                        <a href={url} target="_blank" rel="noreferrer">
                          {label} ↗
                        </a>
                      ) : (
                        <Link to={url}>{label}</Link>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </nav>
        </div>
        <div className="footer__bottom">
          <p>{t('footer.copyright').replace('{year}', String(SITE.year))}</p>
          <p>本地优先 · Android 先行</p>
        </div>
      </div>
    </footer>
  )
}
