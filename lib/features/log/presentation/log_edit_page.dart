import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/domain/sleep_entry.dart';
import 'log_page.dart';

/// Route page for correcting an existing night.
///
/// Editing cannot be a mode of the Log *tab*: a tab has nowhere to hang its
/// argument, and a mode that outlives the form leaks into the next visit.
/// Pushing a route instead ties the edit session to the route's lifetime — back,
/// save and system-back all end it, and the tab bar is still there underneath.
class LogEditPage extends StatelessWidget {
  const LogEditPage({super.key, required this.routeArgument});

  /// go_router's `extra`, accepted untyped on purpose. `extra` is not persisted,
  /// so a restored route arrives here without it; the page narrows the type
  /// rather than trusting a cast.
  final Object? routeArgument;

  @override
  Widget build(BuildContext context) {
    final argument = routeArgument;
    if (argument is! SleepEntry) return const _MissingEntry();
    return LogPage(editing: argument);
  }
}

/// Shown when the edit route was reached without a night to edit.
///
/// Falling back to the blank new-record form would be worse than useless: it
/// looks exactly like the edit having discarded the record.
class _MissingEntry extends StatelessWidget {
  const _MissingEntry();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Subpage(
      title: '编辑记录',
      children: [
        EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '没有找到这条记录',
          body: '它可能已被删除。返回后可以重新选择一条记录编辑。',
        ),
      ],
    );
  }
}
