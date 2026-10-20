import './DeviceFrame.css'

/**
 * 设备外壳。phone / tablet 两种形态，内部内容自适应缩放。
 */
export default function DeviceFrame({
  type = 'phone',
  children,
  className = '',
}) {
  return (
    <div className={`device device--${type} ${className}`.trim()}>
      <div className="device__bezel">
        <div className="device__screen">{children}</div>
      </div>
    </div>
  )
}
