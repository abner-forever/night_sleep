import { Link } from 'react-router-dom'
import { ArrowRight, Smartphone } from '../ui/Icons.jsx'
import './StoreButtons.css'
export function StoreButton({ size = 'md', className = '' }) {
  return (
    <Link
      className={`store-btn store-btn--${size} ${className}`}
      to="/download"
      aria-label="查看 Android 下载"
    >
      <Smartphone size={size === 'lg' ? 26 : 22} />
      <span className="store-btn__text">
        <small>获取夜深</small>
        <strong>Android APK</strong>
      </span>
    </Link>
  )
}
export default function StoreButtons({ size = 'md', className = '' }) {
  return (
    <div className={`store-buttons ${className}`}>
      <StoreButton size={size} />
      <Link className="btn btn--outline" to="/?section=devices">
        看看应用 <ArrowRight size={17} />
      </Link>
    </div>
  )
}
