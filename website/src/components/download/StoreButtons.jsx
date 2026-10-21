import { Link } from 'react-router-dom'
import { AppleLogo, ArrowRight, Smartphone } from '../ui/Icons.jsx'
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
        <small>正式版下载</small>
        <strong>Android APK</strong>
      </span>
    </Link>
  )
}
export function IosStoreButton({ size = 'md' }) {
  return (
    <button
      type="button"
      className={`store-btn store-btn--${size}`}
      disabled
      aria-label="iOS 下载暂缓支持"
    >
      <AppleLogo size={size === 'lg' ? 26 : 22} />
      <span className="store-btn__text">
        <small>iOS · 暂缓支持</small>
        <strong>App Store</strong>
      </span>
    </button>
  )
}
export default function StoreButtons({ size = 'md', className = '' }) {
  return (
    <div className={`store-buttons ${className}`}>
      <StoreButton size={size} />
      <Link className="btn btn--outline" to="/download?section=beta-download">Beta 测试版</Link>
      <IosStoreButton size={size} />
      <Link className="btn btn--outline" to="/?section=devices">
        看看应用 <ArrowRight size={17} />
      </Link>
    </div>
  )
}
