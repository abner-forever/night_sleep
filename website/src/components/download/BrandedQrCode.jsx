import { QRCodeSVG } from 'qrcode.react'
import appIcon from '../../../public/favicon.svg?raw'

// 内嵌图标和白色留白，序列化后栅格化成 JPG 也能完整显示。
const insetIcon = appIcon.replace(/<!--[\s\S]*?-->/g, '').replace('<svg ', '<svg x="8" y="8" width="84" height="84" ')
const logo = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="18" fill="white"/><defs><clipPath id="app-mask"><rect x="8" y="8" width="84" height="84" rx="16"/></clipPath></defs><g clip-path="url(#app-mask)">${insetIcon}</g></svg>`,
)}`

export default function BrandedQrCode({ value, size = 180, title, id }) {
  return (
    <QRCodeSVG
      id={id}
      value={value}
      size={size}
      level="H"
      marginSize={4}
      bgColor="#ffffff"
      fgColor="#171717"
      title={title}
      imageSettings={{
        src: logo,
        width: size * 0.2,
        height: size * 0.2,
        excavate: true,
      }}
    />
  )
}
