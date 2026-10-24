import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the API key lives between runs.
///
/// The spec (§7 / M4 第 3 条) requires the platform's secure storage and forbids
/// this value reaching SQLite, logs or exports. An interface rather than a bare
/// call to the plugin so tests can run without a platform channel — and so the
/// "where does the key go" question has exactly one answer in the codebase.
abstract interface class InsightKeyStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// 通过插件使用 iOS Keychain / Android Keystore。
class SecureInsightKeyStore implements InsightKeyStore {
  const SecureInsightKeyStore();

  /// Name of the keychain item. Not a secret; the value is.
  static const String itemKey = 'insight_api_key';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 读不出来（钥匙串不可用、条目被 ACL 拦下）与「没有密钥」在这里是同一种结果：
  /// 没配置。抛出去只会让应用起不来，而这两种情况下界面要说的话一模一样。
  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: itemKey);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String value) =>
      _storage.write(key: itemKey, value: value);

  @override
  Future<void> clear() => _storage.delete(key: itemKey);
}

/// 可以整体替换的存储实现（测试用内存版）。
final insightKeyStoreProvider =
    Provider<InsightKeyStore>((ref) => const SecureInsightKeyStore());

/// 可选的首启值：测试注入，或调用方已经同步拿到了密钥。生产路径上它是空的。
///
/// **密钥不再在 `main()` 里同步读。** `flutter_secure_storage` 第一次 `read()` 在
/// 小米 9 + Android 11 上要 **~860ms**（Keystore 初始化），而它原先卡在 `runApp`
/// 之前——那正是冷启动白屏的一部分。现在由 [InsightApiKeyNotifier.load] 在开屏
/// 播完之后补读；那时界面已经可交互，但用户还要点进设置、再进「洞察服务」，
/// 比这 860ms 长得多。
///
/// 原来那条「必须 await 一次，否则输入框会先空一下」的约束仍然成立，只是兜底换了
/// 地方：读取完成前用户走不到那个输入框，而就算走到了，
/// [InsightApiKeyNotifier.load] 也只在**用户没动过输入框**时才写入。
final insightApiKeySeedProvider = Provider<String>((ref) => '');

/// The API key for the current run.
///
/// Two places at once, on purpose: memory for the UI and every request, and the
/// key store so it survives a restart. Both are updated together, and a failed
/// write never breaks typing — this run keeps working, the next one just needs
/// the key again.
///
/// Two rules that must not be relaxed:
///
///  * **Never write it anywhere else.** No SQLite column, no log line, no export
///    field. The one storage location is [InsightKeyStore]; a second one is how
///    a credential escapes.
///  * **Never put it in a string that gets printed** — no `toString`, no error
///    message, no debug dump of this provider's state.
final insightApiKeyProvider =
    NotifierProvider<InsightApiKeyNotifier, String>(InsightApiKeyNotifier.new);

class InsightApiKeyNotifier extends Notifier<String> {
  /// 上一次已经落盘的值，用来判断「这次改动要不要真的写钥匙串」。
  String? _persisted;

  /// 钥匙串补读是否已经发起过。只读一次。
  bool _loaded = false;

  /// 用户动过输入框（输入或清除）。**机器不能覆盖人**：动过之后就不再接受补读值。
  bool _userEdited = false;

  @override
  String build() {
    final seed = ref.watch(insightApiKeySeedProvider);
    _persisted = seed.trim().isEmpty ? null : seed.trim();
    return seed;
  }

  /// 从钥匙串补读一次，**在开屏播完之后调用**（见 [insightApiKeySeedProvider]）。
  ///
  /// 幂等。三种情况直接放弃：已经读过、用户动过输入框、内存里已经有值。
  /// 读到空值也放弃——「没有密钥」是正常状态，不需要再写一遍空串。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (_userEdited || state.isNotEmpty) return;

    final stored =
        (await ref.read(insightKeyStoreProvider).read())?.trim() ?? '';
    // await 期间用户可能已经打开设置页开始输入，再判一次。
    if (stored.isEmpty || _userEdited || state.isNotEmpty) return;

    state = stored;
    _persisted = stored;
  }

  /// 用户改了输入框。内存立刻生效（请求马上就能用），落盘异步跟上。
  ///
  /// 不做防抖：这里没有 Timer，因此不会在 widget 测试里留下 pending timer；
  /// 而且钥匙串写入是一次很快的平台调用，`_persisted` 挡住重复值之后，
  /// 一个 40 字符的 key 最多写 40 次。
  void update(String value) {
    _userEdited = true;
    state = value;
    final trimmed = value.trim();
    if (trimmed == _persisted) return;
    _persisted = trimmed;
    unawaited(_persist(trimmed));
  }

  /// 手动清除（设置页的「清除密钥」）。内存与钥匙串一起清。
  Future<void> clear() async {
    _userEdited = true;
    state = '';
    _persisted = null;
    try {
      await ref.read(insightKeyStoreProvider).clear();
    } on Object {
      // 清不掉也只是下次启动又读出来；不写日志。
    }
  }

  Future<void> _persist(String value) async {
    try {
      final store = ref.read(insightKeyStoreProvider);
      if (value.isEmpty) {
        await store.clear();
      } else {
        await store.write(value);
      }
    } on Object {
      // 存不进去不该打断输入：这一次运行照旧可用，只是下次启动要重填。
      // 刻意不记日志——这是密钥。
    }
  }
}
