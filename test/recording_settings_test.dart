import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/app_settings.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/settings/presentation/sleep_settings_page.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/night_recorder.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/clip_journal.dart';

/// 只回答「给不给权限」的假录音服务。
///
/// 录音这条链路一个测试都不该碰真麦克风（规格 §五 / plan Task 5），所以从 provider
/// 上换掉整个 [NightRecorder]，只留 [ensurePermission] 这一个会被设置页用到的接口。
class _FakeNightRecorder implements NightRecorder {
  _FakeNightRecorder({this.grants = true});

  /// 权限闸口的回答。false = 用户拒了。
  bool grants;
  int permissionCalls = 0;

  final ValueNotifier<NightRecordingStatus> _status =
      ValueNotifier(const NightRecordingStatus.idle());

  @override
  ValueListenable<NightRecordingStatus> get status => _status;

  @override
  Stream<ClipDraft> get closedClips => const Stream.empty();

  @override
  Future<bool> ensurePermission() async {
    permissionCalls++;
    return grants;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _status.dispose();
}

/// 假的片段文件仓库：不落盘，只记「量到多少」与「删过没有」。
///
/// 真 `ClipFileStore` 要 `path_provider` 的平台通道；这里继承它、只覆写设置页会用到的
/// 两个方法，基类的构造参数不会被触碰。
class _FakeClipStore extends ClipFileStore {
  _FakeClipStore({this.bytes = 0, this.throwOnRead = false})
      : super(baseDirectory: () async => Directory.systemTemp);

  int bytes;

  /// 模拟读不到占用（目录权限、IO 异常等）。
  bool throwOnRead;

  int deleteAllCalls = 0;

  @override
  Future<int> totalBytes() async {
    if (throwOnRead) throw const FileSystemException('读不到占用');
    return bytes;
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCalls++;
    bytes = 0;
  }
}

class _FakeLauncher implements AppSettingsLauncher {
  int opened = 0;

  @override
  Future<void> open() async => opened++;
}

void main() {
  late AppDatabase database;
  late StreamController<AppSetting> settingsStream;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    settingsStream = StreamController<AppSetting>.broadcast();
  });

  tearDown(() async {
    await settingsStream.close();
    await database.close();
  });

  AppSetting settings({bool soundEnabled = false}) => AppSetting(
        id: 'default',
        themeMode: 'system',
        sleepGoalMinutes: 480,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: null,
        wakeReminderEnabled: false,
        wakeReminderMinutes: null,
        soundRecordingEnabled: soundEnabled,
        onboarded: true,
        insightProvider: null,
        insightModel: null,
      );

  Future<void> pumpSettings(
    WidgetTester tester, {
    required _FakeNightRecorder recorder,
    required _FakeClipStore store,
    _FakeLauncher? launcher,
  }) async {
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          // 不订阅 drift 的 `watch*` 流：它靠定时器驱动，假时钟不推进会留下 pending
          // timer（见 pages_widget_test.dart 文件头）。用法与既有测试一致。
          sleepEntriesProvider.overrideWith((ref) => const []),
          settingsProvider.overrideWith((ref) => settingsStream.stream),
          nightRecorderProvider.overrideWithValue(recorder),
          clipFileStoreProvider.overrideWithValue(store),
          if (launcher != null)
            appSettingsLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SleepSettingsPage()),
        ),
      ),
    );
    // 首帧之后再投初值：broadcast 流不重放。
    settingsStream.add(settings());
    await tester.pumpAndSettle();
  }

  /// 设置页里前两个开关是就寝 / 起床提醒，第三个是夜间声音录制。
  Finder recordingToggle() => find.byType(IosToggle).at(2);

  String? toastOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      ).read(toastProvider);

  /// 造一条真实的录音片段行（`source = 'recording'`）挂在一条睡眠记录下。
  Future<void> seedRecordingClip() async {
    await database.into(database.sleepRecords).insert(
          SleepRecordsCompanion.insert(
            id: 'rec-1',
            startAtUtc: DateTime.utc(2026, 9, 26, 23),
            endAtUtc: DateTime.utc(2026, 9, 27, 7),
            createdAt: DateTime.utc(2026, 9, 26, 23),
            updatedAt: DateTime.utc(2026, 9, 27, 7),
          ),
        );
    await database.into(database.soundClips).insert(
          SoundClipsCompanion.insert(
            id: 'clip-1',
            recordId: 'rec-1',
            kind: 'snore',
            startedAtUtc: DateTime.utc(2026, 9, 27, 1),
            durationMs: 3200,
          ),
        );
  }

  testWidgets('副标题与真实能力一致，不再是「尚未接入录音」', (tester) async {
    final recorder = _FakeNightRecorder();
    final store = _FakeClipStore();
    await pumpSettings(tester, recorder: recorder, store: store);

    // 产品红线：那句「尚未接入录音，开关只保存偏好」现在是一句假话，必须消失。
    expect(find.textContaining('尚未接入录音'), findsNothing);
    expect(find.textContaining('开关只保存偏好'), findsNothing);

    expect(find.text('录下有声响的片段，由你听过之后自己标注'), findsOneWidget);
    // 另一条红线：不许声称能自动检测打鼾 / 梦话。
    expect(find.textContaining('检测打鼾、梦话并生成洞察'), findsNothing);
  });

  testWidgets('权限通过时拨开关写入偏好', (tester) async {
    final recorder = _FakeNightRecorder(grants: true);
    final store = _FakeClipStore();
    await pumpSettings(tester, recorder: recorder, store: store);

    await tester.tap(recordingToggle());
    await tester.pumpAndSettle();

    expect(recorder.permissionCalls, 1, reason: '打开前必须先申请麦克风权限');
    expect((await database.getSettings()).soundRecordingEnabled, isTrue);
  });

  testWidgets('权限被拒时不写库、开关回弹并给出「去系统设置」', (tester) async {
    final recorder = _FakeNightRecorder(grants: false);
    final store = _FakeClipStore();
    final launcher = _FakeLauncher();
    await pumpSettings(
      tester,
      recorder: recorder,
      store: store,
      launcher: launcher,
    );

    await tester.tap(recordingToggle());
    await tester.pumpAndSettle();

    expect((await database.getSettings()).soundRecordingEnabled, isFalse,
        reason: '被拒时不得写入一个开着却录不了音的偏好');
    // 开关回弹：界面读的是偏好，偏好没变，显示仍是关。
    expect(tester.widget<IosToggle>(recordingToggle()).value, isFalse);

    expect(find.textContaining('未获得麦克风权限'), findsOneWidget);
    await tester.tap(find.textContaining('未获得麦克风权限'));
    await tester.pumpAndSettle();
    expect(launcher.opened, 1, reason: '「去系统设置」必须跳到应用设置页，不是通知那一页');
  });

  testWidgets('删除全部录音：确认后片段行与文件都没了', (tester) async {
    await seedRecordingClip();
    final recorder = _FakeNightRecorder();
    final store = _FakeClipStore(bytes: 4096);
    await pumpSettings(tester, recorder: recorder, store: store);

    expect(await database.allRecordingClips(), hasLength(1),
        reason: '前提：库里有一条片段');

    await tester.tap(find.text('删除全部录音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await database.allRecordingClips(), isEmpty);
    expect(store.deleteAllCalls, 1, reason: '文件也要删掉，不能只在库里清行');
    expect(toastOf(tester), contains('已删除全部录音片段'));
  });

  testWidgets('删除全部录音：取消后片段行与文件都还在', (tester) async {
    await seedRecordingClip();
    final recorder = _FakeNightRecorder();
    final store = _FakeClipStore(bytes: 4096);
    await pumpSettings(tester, recorder: recorder, store: store);

    await tester.tap(find.text('删除全部录音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await database.allRecordingClips(), hasLength(1));
    expect(store.deleteAllCalls, 0);
  });

  testWidgets('占用读不到时显示「暂时读不到占用」而不是「0 B」', (tester) async {
    final recorder = _FakeNightRecorder();
    final store = _FakeClipStore(throwOnRead: true);
    await pumpSettings(tester, recorder: recorder, store: store);

    expect(find.text('暂时读不到占用'), findsOneWidget);
    // 读不到不能编一个 0 B：那会让人以为已经清干净了。
    expect(find.textContaining('0 B'), findsNothing);
    expect(find.text('还没有录到片段'), findsNothing);
  });

  testWidgets('占用读得到时显示真实大小', (tester) async {
    final recorder = _FakeNightRecorder();
    final store = _FakeClipStore(bytes: 2048);
    await pumpSettings(tester, recorder: recorder, store: store);

    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.text('暂时读不到占用'), findsNothing);
  });

  test('iOS 跳转地址落在本应用的系统设置页', () {
    // iOS：`app-settings:` 就是本应用那一页，麦克风开关就在上面。
    expect(
      UrlAppSettingsLauncher.uriFor(TargetPlatform.iOS).toString(),
      'app-settings:',
    );
  });
}
