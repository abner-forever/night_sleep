import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../data/app_update_controller.dart';
import '../../domain/app_release.dart';

class AppUpdateSheet extends ConsumerWidget {
  const AppUpdateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final update = ref.watch(appUpdateProvider);
    final release = update.release;
    if (release == null) return const SizedBox.shrink();
    final downloading = update.phase == UpdatePhase.downloading;
    return AppSheet(
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('发现新版本',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary)),
          const SizedBox(height: 8),
          Text(formatAppVersion(release.version),
              style: TextStyle(fontSize: 14, color: tokens.textSecondary)),
          if (release.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(release.notes,
                style: TextStyle(
                    fontSize: 13, height: 1.6, color: tokens.textSecondary)),
          ],
          if (update.message != null || update.busy) ...[
            const SizedBox(height: 16),
            Text(
              downloading
                  ? '正在下载更新…'
                  : update.phase == UpdatePhase.installing
                      ? '正在准备安装…'
                      : update.message ?? '',
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: tokens.textSecondary),
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (update.received / release.size).clamp(0, 1),
              color: tokens.accent,
              backgroundColor: tokens.accentSoft,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: '安装包下载进度',
            ),
            const SizedBox(height: 8),
            Text('${(update.received * 100 / release.size).floor()}%',
                style: TextStyle(fontSize: 12, color: tokens.textMuted)),
          ],
          const SizedBox(height: 20),
          PrimaryAction(
            label: switch (update.phase) {
              UpdatePhase.downloading => '正在下载…',
              UpdatePhase.installing => '正在准备安装…',
              UpdatePhase.permission => '继续安装',
              UpdatePhase.ready => '再次安装',
              UpdatePhase.failed => '重试更新',
              _ => '立即更新',
            },
            onTap: update.busy
                ? null
                : () =>
                    unawaited(ref.read(appUpdateProvider.notifier).update()),
          ),
          Center(
            child: TextButton(
              onPressed: () {
                if (downloading) ref.read(appUpdateProvider.notifier).cancel();
                Navigator.of(context).pop();
              },
              child: Text(downloading ? '取消下载' : '关闭'),
            ),
          ),
        ],
      ),
    );
  }
}
