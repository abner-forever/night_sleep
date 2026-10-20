import { Link } from 'react-router-dom'
import { useI18n } from '../i18n/index.jsx'
import './NotFound.css'

export default function NotFound() {
  const { t } = useI18n()

  return (
    <section className="nf">
      <div className="container nf__inner">
        <p className="nf__code">404</p>
        <h1 className="nf__title">{t('notFound.title')}</h1>
        <p className="nf__desc">{t('notFound.desc')}</p>
        <Link className="btn btn--primary" to="/">
          {t('notFound.action')}
        </Link>
      </div>
    </section>
  )
}
