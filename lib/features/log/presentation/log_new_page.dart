import 'package:flutter/material.dart';

import 'log_page.dart';

/// 手动补录某一晚。
///
/// 能力原先是「记录」Tab 的正文，现在降级成二级页——它没有消失，只是不再占一个
/// 标签位。入口在回顾页底部，以及会话时长越界时的说明层里。
class LogNewPage extends StatelessWidget {
  const LogNewPage({super.key});

  @override
  Widget build(BuildContext context) => const LogPage();
}
