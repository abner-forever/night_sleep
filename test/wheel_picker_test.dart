import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/wheel_picker.dart';

/// 滚轮的回归用例。
///
/// 病灶不在滚动，而在父子之间那条**单行道**：`showAppSheet` 的 `pageBuilder`
/// 拿到的是调用点构造好的那一个 `child` 实例，弹层打开后父层 `setState` 也送不进来
/// （`log_page` / 睡眠设置页 / 会话页三处都是这个形状）。所以多列的当前值必须由
/// picker 自己拿着——此前它读的是上一次 build 解析出的值，先滚 A 列再滚 B 列，
/// B 列的回调就会拿**旧的** A 去拼新值：草稿里 A 被弹回去，点「完成」一提交就露馅。
///
/// 搭台时刻意**照着真实调用点的形状**——`value` 是一个局部变量、靠 `onChanged`
/// 回写，而不是把 picker 包在会重建的父组件里。包进 `StatefulBuilder` 之类会重建的
/// 宿主，病灶就被遮掉了，用例会空跑通过。
void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required Future<bool?> Function(BuildContext context) open,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  /// 滚第 [column] 列 [steps] 格（正数向上、负数向下）。
  ///
  /// 位移取**整数倍行距**：`tester.drag` 的整段位移都会进到滚动里（实测：44px 行距
  /// 拖 88px 恰好落在第 2 格，拖 154px 则停在 3.5 格、四舍五入变成第 4 格），所以
  /// 整数倍是唯一没有歧义的落点，别「补半格」去对抗不存在的起手损耗。
  Future<void> spin(WidgetTester tester, int column, int steps) async {
    await tester.drag(
      find.byType(WheelColumn).at(column),
      Offset(0, -WheelColumn.itemExtent * steps),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapDone(WidgetTester tester) async {
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
  }

  /// 弹层里的第 [column] 列当前列着几行。
  int columnItemCount(WidgetTester tester, int column) {
    final view = tester.widget<ListWheelScrollView>(
      find.descendant(
        of: find.byType(WheelColumn).at(column),
        matching: find.byType(ListWheelScrollView),
      ),
    );
    return (view.childDelegate as ListWheelChildBuilderDelegate)
        .estimatedChildCount!;
  }

  /// 选中行底色那一条画在哪。
  Rect bandRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('wheel-selection-band')));

  Color bandColor(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('wheel-selection-band')),
    );
    return (box.decoration as BoxDecoration).color!;
  }

  /// 当下主题里的浅强调色——断言底色取自令牌，而不是写死的色值。
  Color accentSoftOf(WidgetTester tester) =>
      AppTokens.of(tester.element(find.byType(WheelColumn).first)).accentSoft;

  testWidgets('先滚小时再滚分钟：点「完成」拿到的是新小时', (tester) async {
    var draft = '23:00';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '起床闹钟',
        child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
      ),
    );

    await spin(tester, 0, -2); // 23 → 21
    await spin(tester, 1, 3); // :00 → :03

    expect(draft, '21:03', reason: '滚分钟时若用的是旧的小时，草稿会写成 23:03');

    await tapDone(tester);
    expect(draft, '21:03', reason: '点「完成」后小时不许弹回 23');
  });

  testWidgets('先滚分钟再滚小时：分钟不被冲掉', (tester) async {
    var draft = '23:00';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '起床闹钟',
        child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
      ),
    );

    await spin(tester, 1, 3); // :00 → :03
    await spin(tester, 0, -2); // 23 → 21

    expect(draft, '21:03', reason: '滚小时时若用的是旧的分钟，分钟会被吃回 00');
  });

  testWidgets('只滚小时：点「完成」生效', (tester) async {
    var draft = '23:00';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '起床闹钟',
        child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
      ),
    );

    await spin(tester, 0, -2);

    await tapDone(tester);
    expect(draft, '21:00', reason: '这条路径本来就对，别在修另一条时弄坏它');
  });

  testWidgets('先滚年再滚月：年不被旧值冲掉，日列跟着收窄', (tester) async {
    var draft = '2026-01-31';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '选择日期',
        child: AppDatePicker(
          value: draft,
          now: DateTime(2026, 6, 15),
          onChanged: (value) => draft = value,
        ),
      ),
    );

    await spin(tester, 0, 1); // 2026 → 2027
    await spin(tester, 1, 1); // 1月 → 2月

    expect(draft, '2027-02-28', reason: '滚月份时若用的是旧的年，草稿会退回 2026-02-28');
    expect(columnItemCount(tester, 2), 28,
        reason: '2 月只有 28 天，日列必须跟着年月重新生成，否则轮子上还列着 31 天');

    await tapDone(tester);
    expect(draft, '2027-02-28');
  });

  testWidgets('小时滚过 23 会绕回 00，分钟同理', (tester) async {
    var draft = '23:50';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '起床闹钟',
        child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
      ),
    );

    await spin(tester, 0, 1); // 23 → 00
    expect(draft, '00:50', reason: '滚到底就停住的话，这里还是 23:50');

    await spin(tester, 1, 20); // :50 绕一圈到 :10
    expect(draft, '00:10');
  });

  testWidgets('从 00 往回滚会绕到 23:59 一侧', (tester) async {
    var draft = '00:00';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '起床闹钟',
        child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
      ),
    );

    await spin(tester, 0, -1); // 00 → 23
    expect(draft, '23:00', reason: '往回滚到底就停住的话，这里还是 00:00');
    await spin(tester, 1, -1); // :00 → :59
    expect(draft, '23:59', reason: '两列都跨过边界之后，另一列不许被冲掉');

    await tapDone(tester);
    expect(draft, '23:59');
  });

  testWidgets('选中行的底色落在正中间那一行，高度就是行距', (tester) async {
    var draft = '23:00';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '起床闹钟',
        child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
      ),
    );

    final column = tester.getRect(find.byType(WheelColumn).first);
    final band = bandRect(tester);
    final sheet = tester.getRect(find.byType(PickerSheet));

    expect(band.height, 36, reason: '行距从原型的 44 收紧到 36，滚一行更省力');
    expect(band.center.dy, column.center.dy,
        reason: '底色必须压在正中间那一行上，也就是当前选中的那一行');
    expect(bandColor(tester), accentSoftOf(tester),
        reason: '底色用的是令牌里的浅强调色，与标签条选中态同一支');
    expect(band.width, greaterThan(column.width), reason: '横条要托住所有列，不能只盖住一列');
    expect(band.width, lessThan(sheet.width / 2),
        reason: '横条贴合数字，不许在宽屏上拉成一条横贯整个弹层的带子');
  });

  testWidgets('日期列不循环：年的两头就是两头', (tester) async {
    var draft = '2026-06-15';
    await pumpHost(
      tester,
      open: (context) => showPickerSheet(
        context: context,
        title: '选择日期',
        child: AppDatePicker(
          value: draft,
          now: DateTime(2026, 6, 15),
          onChanged: (value) => draft = value,
        ),
      ),
    );

    // 五年窗口是 2024–2028，2026 在中间；往下滚 5 格会越过窗口下沿。
    await spin(tester, 0, -5);
    expect(draft, startsWith('2024-'),
        reason: '日期不循环——「2024 年再往前」没有意义，不该绕到 2028');
  });
}
