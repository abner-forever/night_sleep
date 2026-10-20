import BrandedQrCode from './BrandedQrCode.jsx'
import { useI18n } from '../../i18n/index.jsx'
import './QrCode.css'

/**
 * 下载二维码。
 *
 * 始终渲染为「深色模块 + 白色底」——反色二维码在部分扫码器上识别率会下降，
 * 因此即便在深色主题下也保留白色底板，保证可扫。
 */
export default function QrCode({ value, label, size = 148 }) {
  const { t } = useI18n()

  return (
    <figure className="qr">
      <div className="qr__box" style={{ '--qr-size': `${size}px` }}>
        <BrandedQrCode
          value={value}
          size={size}
          title={t('download.qrAlt').replace('{platform}', label ?? '')}
        />
      </div>
      {label ? <figcaption className="qr__label">{label}</figcaption> : null}
    </figure>
  )
}
