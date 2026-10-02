import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../night_scene.dart';
import '../night_style.dart';

/// 「夜景氛围」选择器：横向滚动的八张预览卡。
///
/// 整块浮在场景之上的一层半透明卡里（原型激活态的 `.sleep-scene-picker-compact`），
/// 标题行在激活态是隐藏的（`.sleep-scene-picker-compact .sleep-scene-picker-title
/// { display: none }`）——所以这里不画标题，只画那一排卡。
class NightScenePicker extends StatelessWidget {
  const NightScenePicker({
    super.key,
    required this.scene,
    required this.onChanged,
  });

  final NightScene scene;
  final ValueChanged<NightScene> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 3),
      decoration: BoxDecoration(
        color: NightStyle.fieldFill,
        borderRadius: BorderRadius.circular(NightStyle.pickerRadius),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: SizedBox(
        height: NightStyle.scenePreviewHeight + 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
          itemCount: NightScene.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
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
        ),
      ),
    );
  }
}

/// 一张场景预览卡：64×42 的缩略图 + 底下一行标签。
///
/// 尺寸与选中态逐条取自 `.sleep-scene-choice` / `.sleep-scene-preview`：
/// 宽 68、卡 64×42 圆角 13、选中时描边 `rgba(174,190,255,.72)` + 一圈外发光 +
/// 上移 2px，文字换成 `#c4d0ff`。
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
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.ease,
                width: NightStyle.scenePreviewWidth,
                height: NightStyle.scenePreviewHeight,
                transform: Matrix4.translationValues(0, selected ? -2 : 0, 0),
                decoration: BoxDecoration(
                  gradient: scene.previewGradient,
                  borderRadius: BorderRadius.circular(NightStyle.previewRadius),
                  border: Border.all(
                    color: selected
                        ? NightStyle.selectedStroke
                        : const Color(0x17FFFFFF),
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
                              color: Color(0xBFFFFFFF),
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
