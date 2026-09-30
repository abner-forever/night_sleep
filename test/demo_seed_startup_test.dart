import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';
import 'package:night_sleep/core/database/app_database.dart'
    show AppDatabase, SleepRecord, SleepRecordsCompanion;
import 'package:night_sleep/features/sleep/data/demo_seed.dart';

/// 播种失败时向外抛的那句话。断言日志里出现它，等于断言「失败真的发生过、
/// 并且被这里接住了」——否则「没抛异常」这条断言会在「函数压根没走到安装那一步」
/// 时也通过。
const _failure = '模拟播种时的写入失败';

/// 一个「写入必炸」的内存库。
///
/// 底座是真的 `NativeDatabase.memory()`，所以 `allRecords()` 是真实的查询；
/// 只有 `saveRecord` 被换掉——它是 `DemoSeed.install` 的第一条写入，一撞就炸。
/// 用它就能在测试里造出「播种失败」这个在真机上要坏库才能遇到的现场。
class _FailingWriteDatabase extends AppDatabase {
  _FailingWriteDatabase() : super(NativeDatabase.memory());

  int readAttempts = 0;
  int writeAttempts = 0;

  @override
  Future<List<SleepRecord>> allRecords() {
    readAttempts++;
    return super.allRecords();
  }

  @override
  Future<void> saveRecord(SleepRecordsCompanion record) async {
    writeAttempts++;
    throw StateError(_failure);
  }
}

/// 绕过 `saveRecord` 直接落一行，用来构造「库里已经有什么」的现场。
Future<void> _insertRecord(
  AppDatabase database, {
  required String id,
  required String source,
}) {
  return database.into(database.sleepRecords).insert(
        SleepRecordsCompanion.insert(
          id: id,
          startAtUtc: DateTime.utc(2026, 9, 26, 23),
          endAtUtc: DateTime.utc(2026, 9, 27, 7),
          quality: const Value(4),
          source: Value(source),
          createdAt: DateTime.utc(2026, 9, 27, 8),
          updatedAt: DateTime.utc(2026, 9, 27, 8),
        ),
      );
}

void main() {
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs = [];
    originalDebugPrint = debugPrint;
    // 接管日志才能区分「失败了但被接住」和「压根没失败」。
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() => debugPrint = originalDebugPrint);

  group('冷启动安装演示数据', () {
    test('播种失败时不向外抛，失败被接住并留下日志', () async {
      final database = _FailingWriteDatabase();
      addTearDown(database.close);

      // 若这个函数放行了异常，下面这行会把 StateError 抛给测试，用例直接失败。
      await installDemoSeedIfNeeded(database, enabled: true);

      expect(database.writeAttempts, 1, reason: '判据通过后应当真的去安装');
      expect(
        logs,
        hasLength(1),
        reason: '失败必须留下一行日志，否则「不抛」就等于「静默吞掉」',
      );
      expect(logs.single, contains(_failure));
    });

    test('开关关闭时既不查库也不安装', () async {
      final database = _FailingWriteDatabase();
      addTearDown(database.close);

      await installDemoSeedIfNeeded(database, enabled: false);

      expect(database.readAttempts, 0, reason: '关着开关不该白查一次库');
      expect(database.writeAttempts, 0);
      expect(logs, isEmpty);
    });

    test('已有演示行时不再安装', () async {
      final database = _FailingWriteDatabase();
      addTearDown(database.close);
      await _insertRecord(
        database,
        id: 'demo-1',
        source: AppConfig.demoSource,
      );

      await installDemoSeedIfNeeded(database, enabled: true);

      // 这个库一写就炸，所以「没有写」是硬证据：它真的没进安装分支。
      expect(database.writeAttempts, 0);
      expect(logs, isEmpty);
    });

    test('只有真实记录时仍然会安装演示数据', () async {
      final database = _FailingWriteDatabase();
      addTearDown(database.close);
      await _insertRecord(database, id: 'manual-1', source: 'manual');

      await installDemoSeedIfNeeded(database, enabled: true);

      expect(
        database.writeAttempts,
        1,
        reason: '判据是「有没有 demo 行」而不是「表是不是空的」',
      );
      expect(logs, hasLength(1), reason: '这个库里写入必炸，日志说明它走到了安装');
    });
  });
}
