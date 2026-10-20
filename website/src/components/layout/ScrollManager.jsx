import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'

/**
 * 路由切换时的滚动处理：
 * - 带 hash（如 /#pricing）→ 滚动到对应区块，偏移量由 CSS scroll-padding-top 处理
 * - 无 hash → 回到顶部
 *
 * 从 /download 跳回首页某个区块时，Home 需要先完成挂载，所以用 rAF 延后一帧再查找。
 */
export default function ScrollManager() {
  const { pathname, search } = useLocation()

  useEffect(() => {
    const id = new URLSearchParams(search).get('section')
    if (id) {
      const frame = requestAnimationFrame(() => {
        const el = document.getElementById(id)
        if (el) el.scrollIntoView({ block: 'start' })
      })
      return () => cancelAnimationFrame(frame)
    }

    window.scrollTo({ top: 0 })
    return undefined
  }, [pathname, search])

  return null
}
