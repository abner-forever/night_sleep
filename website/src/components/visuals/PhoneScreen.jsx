import './PhoneScreen.css'
export default function PhoneScreen({ screen = 'home' }) {
  return (
    <img
      className="actual-screen"
      src={`${import.meta.env.BASE_URL}screenshots/${screen}.webp`}
      alt={`夜深 ${screen === 'session' ? '睡前会话' : screen === 'stats' ? '统计' : '睡眠概览'} · Android 真机截图，含演示数据`}
      width="720"
      height={screen === 'session' ? 1512 : 1493}
      loading={screen === 'home' ? 'eager' : 'lazy'}
    />
  )
}
