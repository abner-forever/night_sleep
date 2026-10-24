import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/settings/data/insight_credentials.dart';

/// Where the API key is allowed to live.
///
/// The spec allows exactly one place (platform secure storage) and forbids three
/// (SQLite, logs, exports). The export side is pinned in
/// `sleep_export_test.dart`; what is pinned here is that memory and the store
/// stay in step — a key that only reaches memory would quietly vanish on the
/// next launch, which is the bug this whole round exists to fix.
void main() {
  late _FakeStore store;

  setUp(() => store = _FakeStore());

  ProviderContainer containerWith({String seed = ''}) {
    final container = ProviderContainer(
      overrides: [
        insightKeyStoreProvider.overrideWithValue(store),
        insightApiKeySeedProvider.overrideWithValue(seed),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('启动时把上次存下的密钥读进来', () {
    final container = containerWith(seed: 'sk-from-keychain');
    expect(container.read(insightApiKeyProvider), 'sk-from-keychain');
  });

  test('输入后写进钥匙串，并且立刻对请求可见', () async {
    final container = containerWith();
    expect(container.read(insightApiKeyProvider), isEmpty);

    container.read(insightApiKeyProvider.notifier).update('sk-new-key');
    // 内存立刻生效——查询余额、连通性测试就在同一次运行里用它。
    expect(container.read(insightApiKeyProvider), 'sk-new-key');

    await pumpEventQueue();
    expect(store.value, 'sk-new-key');
  });

  test('值没变就不重复写钥匙串', () async {
    final container = containerWith(seed: 'sk-seed');
    final notifier = container.read(insightApiKeyProvider.notifier);

    notifier.update('sk-seed');
    notifier.update('sk-seed');
    await pumpEventQueue();
    expect(store.writes, 0, reason: '没有变化就不该产生写入');

    notifier.update('sk-changed');
    await pumpEventQueue();
    expect(store.writes, 1);
  });

  test('清空输入等于从钥匙串删掉，不留一个空串条目', () async {
    final container = containerWith(seed: 'sk-seed');
    container.read(insightApiKeyProvider.notifier).update('');

    await pumpEventQueue();
    expect(store.value, isNull);
  });

  test('clear 把内存与钥匙串一起清掉', () async {
    final container = containerWith(seed: 'sk-seed');
    await container.read(insightApiKeyProvider.notifier).clear();

    expect(container.read(insightApiKeyProvider), isEmpty);
    expect(store.value, isNull);
    expect(store.clears, 1);
  });

  test('钥匙串写失败不影响这次运行可用', () async {
    store.failWrites = true;
    final container = containerWith();
    container.read(insightApiKeyProvider.notifier).update('sk-still-usable');

    expect(container.read(insightApiKeyProvider), 'sk-still-usable');
    await pumpEventQueue();
  });

  // 冷启动优化（2026-10-24）后密钥不再在 `main()` 里同步读：`flutter_secure_storage`
  // 第一次读在 MIUI 上要几百毫秒，改由 `load()` 在首帧之后补。下面这组钉住补读的
  // 三条边界——尤其是「机器不能覆盖人」那一条。
  group('load 补读钥匙串', () {
    test('读到就补进内存，且不再写回一遍', () async {
      store.value = 'sk-late';
      final container = containerWith();
      expect(container.read(insightApiKeyProvider), isEmpty);

      await container.read(insightApiKeyProvider.notifier).load();

      expect(container.read(insightApiKeyProvider), 'sk-late');
      expect(store.writes, 0, reason: '从钥匙串读出来的值不该再写回去');
    });

    test('用户已经输入过就不覆盖', () async {
      store.value = 'sk-from-keychain';
      final container = containerWith();
      final notifier = container.read(insightApiKeyProvider.notifier);

      notifier.update('sk-user-typed');
      await notifier.load();

      expect(container.read(insightApiKeyProvider), 'sk-user-typed');
    });

    test('读到空值保持为空，也不碰钥匙串', () async {
      final container = containerWith();

      await container.read(insightApiKeyProvider.notifier).load();

      expect(container.read(insightApiKeyProvider), isEmpty);
      expect(store.writes, 0);
      expect(store.clears, 0);
    });

    test('只读一次', () async {
      final container = containerWith();
      final notifier = container.read(insightApiKeyProvider.notifier);

      await notifier.load();
      await notifier.load();

      expect(store.reads, 1);
    });
  });
}

class _FakeStore implements InsightKeyStore {
  String? value;
  int reads = 0;
  int writes = 0;
  int clears = 0;
  bool failWrites = false;

  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('keychain unavailable');
    writes++;
    this.value = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}
