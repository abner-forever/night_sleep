import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_menu_field.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import 'widgets/settings_footnote.dart';

/// 外观（`/settings/appearance`）。
///
/// v3.5 起外观从设置根页收进这一页：根页只剩导航行，具体控件在这里。
/// 选择器也照新版原型从分段控件换成了**行内下拉菜单**。
///
/// 三种模式的取值（`system` / `light` / `dark`）是 `AppSettings.themeMode` 的
/// 既有口径，写库与读回都不变——换的只是控件形态。
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  /// 下拉里的三个选项，顺序与原型一致（跟随系统 / 浅色 / 深色）。
  static const _modes = ['system', 'light', 'dark'];
  static const _labels = ['跟随系统', '浅色', '深色'];

  /// 当前模式在触发器与下拉里显示的文字。
  static String labelFor(String themeMode) =>
      _labels[_modes.indexOf(themeMode).clamp(0, _labels.length - 1)];

  /// 当前模式在行里的一句解释。
  static String subtitleFor(String themeMode) => switch (themeMode) {
        'dark' => '夜间更柔和，减少屏幕亮度',
        'light' => '始终使用明亮外观',
        _ => '随设备外观自动切换',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final themeMode =
        ref.watch(settingsProvider).valueOrNull?.themeMode ?? 'system';
    final label = labelFor(themeMode);

    return Subpage(
      title: '外观',
      backLabel: '设置',
      children: [
        const SectionHeader('显示模式'),
        IosListGroup(
          quiet: true,
          children: [
            IosListItem(
              // 这一行本身不可点：真正能点的是右侧那枚下拉触发器。
              haptic: false,
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    size: 36,
                    child: AppIcons.sparkle(
                      size: 18,
                      color: tokens.accent,
                      strokeWidth: 1.8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '显示模式',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleFor(themeMode),
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppMenuField(
                    expand: false,
                    minWidth: 108,
                    value: label,
                    options: _labels,
                    selected: label,
                    onPick: (index) =>
                        ref.read(databaseProvider).updateSettings(
                              AppSettingsCompanion(
                                themeMode: Value(_modes[index]),
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SettingsFootnote('选择「跟随系统」后，外观会随设备的浅色或深色模式自动变化。'),
      ],
    );
  }
}
