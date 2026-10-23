import './PhoneScreen.css'
import { useTheme } from '../../theme/ThemeProvider.jsx'

const SCREEN_NAMES = {
  home: '首页睡眠概览',
  session: '睡前会话',
  stats: '睡眠统计',
  'all-data': '历史记录',
  detail: '睡眠详情',
  settings: '设置',
  sounds: '白噪音设置',
}

export default function PhoneScreen({ screen = 'home', device = 'phone' }) {
  const { resolved } = useTheme()
  const prefix = device === 'tablet' ? 'ipad-' : ''
  const suffix = resolved === 'dark' ? '-dark' : ''
  return (
    <img
      className="actual-screen"
      src={`${import.meta.env.BASE_URL}screenshots/${prefix}${screen}${suffix}.webp`}
      alt={`夜深 · ${SCREEN_NAMES[screen]} · ${device === 'tablet' ? 'iPad' : 'iPhone'} ${resolved === 'dark' ? '深色' : '浅色'}主题下的模拟器截图，含演示数据`}
      width={device === 'tablet' ? 1000 : 720}
      height={device === 'tablet' ? 1451 : 1565}
      loading={screen === 'home' ? 'eager' : 'lazy'}
      decoding="async"
    />
  )
}
