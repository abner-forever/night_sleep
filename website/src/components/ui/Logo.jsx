import { Link } from 'react-router-dom'
import './controls.css'
export default function Logo({ compact = false }) {
  return (
    <Link
      to="/"
      className={`logo ${compact ? 'logo--compact' : ''}`}
      aria-label="夜深首页"
    >
      <img
        className="yeshen-logo"
        src={`${import.meta.env.BASE_URL}favicon.svg`}
        width="42"
        height="42"
        alt=""
      />
      <span className="logo__text">
        <span className="logo__name">夜深</span>
        {!compact && <span className="logo__sub">NIGHT SLEEP</span>}
      </span>
    </Link>
  )
}
