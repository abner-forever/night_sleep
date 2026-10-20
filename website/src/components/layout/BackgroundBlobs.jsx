/**
 * 背景柔光斑。固定在视口上，只在透明区块后方透出（z-index: -1）。
 * 纯装饰，对读屏隐藏；减弱动效时由 CSS 直接不渲染（大面积模糊很吃合成性能）。
 */
export default function BackgroundBlobs() {
  return (
    <div className="blobs" aria-hidden="true">
      <span className="blobs__item blobs__item--rose" />
      <span className="blobs__item blobs__item--peach" />
    </div>
  )
}
