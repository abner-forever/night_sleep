import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../night_scene.dart';
import '../night_style.dart';

/// 「夜景氛围」选择器：横向滚动的八张预览卡。两态共用同一排卡，只差外壳。
///
/// - `compact: true`（**进行中**）：整块浮在场景之上的一层半透明卡里，对应原型激活态的
///   `.sleep-scene-picker-compact`；标题行在那一态是隐藏的
///   （`.sleep-scene-picker-compact .sleep-scene-picker-title { display: none }`）。
/// - `compact: false`（**入睡前**）：住在 `sleep-control-deck` 里，**不画自己的卡片**
///   （deck 自带描边与模糊），多一行标题「夜景氛围 / 左右滑动切换」，
///   卡片左右可滚到 deck 边缘（原型用 `margin-inline: -16px` 抵消 deck 的内边距）。
class NightScenePicker extends StatelessWidget {
  const NightScenePicker({
    super.key,
    required this.scene,
    required this.onChanged,
    this.compact = true,
  });

  final NightScene scene;
  final ValueChanged<NightScene> onChanged;

  /// 进行中态的紧凑外壳。默认值保住既有调用点（会话页中央那一排）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 标签随系统字号增高，给横向列表同步留高，避免大字体时被固定高度裁切。
    final labelExtra = (MediaQuery.textScalerOf(context).scale(10) - 10)
            .clamp(0.0, double.infinity) *
        1.2;
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 3),
        decoration: BoxDecoration(
          color: NightStyle.fieldFill,
          borderRadius: BorderRadius.circular(NightStyle.pickerRadius),
          border: Border.all(color: NightStyle.pickerStroke),
        ),
        child: SizedBox(
          height: NightStyle.scenePreviewHeight + 34 + labelExtra,
          child: _list(const EdgeInsets.fromLTRB(12, 5, 12, 10)),
        ),
      );
    }

    // deck 内的排版：标题左缩进 16 + 2（标题行自己的 2）、上 16；列表自带左右 16、
    // 上 5、下 10，于是卡片贴着 deck 的内边缘起滚。窄屏（`max-width: 390px`）时
    // deck 的内边距收到 13，这里的两个数跟着减 3（15 / 13）。
    final narrow = NightStyle.narrowDeck(context);
    final titleGutter = narrow ? 15.0 : 18.0;
    final listGutter = narrow ? NightStyle.narrowGutter : NightStyle.deckGutter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(titleGutter, 16, titleGutter, 10),
          child: Row(
            children: [
              Row(
                children: [
                  AppIcons.sparkle(
                    size: 15,
                    color: NightStyle.pickerTitleInk,
                    strokeWidth: 1.6,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    '夜景氛围',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NightStyle.pickerTitleInk,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                '左右滑动切换',
                style: TextStyle(
                  fontSize: 10,
                  color: NightStyle.pickerHintInk,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: NightStyle.scenePreviewHeight + 33 + labelExtra,
          child: _list(EdgeInsets.fromLTRB(listGutter, 5, listGutter, 10)),
        ),
      ],
    );
  }

  Widget _list(EdgeInsets padding) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: NightScene.values.length,
      separatorBuilder: (_, __) => const SizedBox(width: 9),
      itemBuilder: (context, index) {
        final option = NightScene.values[index];
        return NightSceneChoice(
          scene: option,
          selected: option == scene,
          onTap: () {
            AppHaptics.select();
            onChanged(option);
          },
        );
      },
    );
  }
}

/// 一张场景预览卡：64×42 的缩略图 + 底下一行标签。
///
/// 尺寸与选中态逐条取自 `.sleep-scene-choice` / `.sleep-scene-preview`：
/// 宽 68、卡 64×42 圆角 13、选中时描边 `rgba(174,190,255,.72)` + 一圈外发光 +
/// **绕中心缩到 .98**（最终生效层，见下面 `transform` 那处的注释），文字换成 `#c4d0ff`。
class NightSceneChoice extends StatelessWidget {
  const NightSceneChoice({
    super.key,
    required this.scene,
    required this.selected,
    required this.onTap,
  });

  final NightScene scene;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        label: scene.label,
        // 卡片里的标签 `Text` 会再生成一份语义，不排掉的话读屏会把「银河」念两遍。
        excludeSemantics: true,
        child: SizedBox(
          width: NightStyle.scenePreviewWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.ease,
                width: NightStyle.scenePreviewWidth,
                height: NightStyle.scenePreviewHeight,
                // 选中态是 `transform: scale(.98)`——**最终生效层**（index.css:1789）
                // 覆盖了早期那层的 `translateY(-2px)`（index.css:1590），v1.0 读错层
                // 那次留下的同一类偏差。CSS 的 transform 默认绕中心缩放，而 Container
                // 的 transform 默认绕左上角（`transformAlignment` 为 null 时），
                // 所以这一项必须显式给，否则卡片会往左上缩。
                transform: Matrix4.diagonal3Values(
                  selected ? .98 : 1,
                  selected ? .98 : 1,
                  1,
                ),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: scene.previewGradient,
                  image: DecorationImage(
                    image: AssetImage(scene.photoAsset),
                    fit: BoxFit.cover,
                    colorFilter: const ColorFilter.mode(
                        Color(0x663478F6), BlendMode.srcATop),
                  ),
                  borderRadius: BorderRadius.circular(NightStyle.previewRadius),
                  border: Border.all(
                    color: selected
                        ? NightStyle.selectedStroke
                        : NightStyle.previewStroke,
                  ),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: NightStyle.selectedGlow,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    for (final dot in scene.previewDots)
                      Align(
                        alignment: dot,
                        child: const SizedBox(
                          width: 2,
                          height: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: NightStyle.previewDot,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                scene.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // 固定行高：不固定的话标签会继承 Material 3 的 1.43 行高，
                  // 42 的缩略图 + 6 的间距 + 14 的文字撑破这一排算好的 61px，
                  // 布局无论主题如何都得稳。
                  height: 1.2,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color:
                      selected ? NightStyle.selectedInk : NightStyle.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
