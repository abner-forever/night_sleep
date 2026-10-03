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
}

class _FakeStore implements InsightKeyStore {
  String? value;
  int writes = 0;
  int clears = 0;
  bool failWrites = false;

  @override
  Future<String?> read() async => value;

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
