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

/// The real one: iOS / macOS Keychain, Android Keystore via the plugin.
class SecureInsightKeyStore implements InsightKeyStore {
  const SecureInsightKeyStore();

  /// Name of the keychain item. Not a secret; the value is.
  static const String itemKey = 'insight_api_key';

  /// **macOS 上刻意关掉 data protection keychain**，走旧版钥匙串。
  ///
  /// 开着它就必须加 `keychain-access-groups` entitlement，而那个 entitlement
  /// 需要 provisioning profile：插件的 README 明确写了，加了之后构建出来的 app
  /// **只能在构建它的那台 Mac 上启动**。本项目没有 App Group、没有跨应用共享，
  /// 用不上这个能力，却要为此换掉整条签名链——代价远大于收益。
  ///
  /// `mOptions` 只被 macOS 实现读取，其它平台忽略，所以不必按平台分支。
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

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

/// 启动时从钥匙串读出来的值，由 `main()` 覆盖。
///
/// 单独一个 provider、而不是让 notifier 自己在 [Notifier.build] 里异步读：
/// `build()` 必须**同步**返回，异步补值会留下一个窗口——用户正好在这几十毫秒里
/// 打开设置页，输入框是空的，而钥匙串里其实有密钥。放在 `main()` 里 await 一次，
/// 窗口就不存在了。
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

  @override
  String build() {
    final seed = ref.watch(insightApiKeySeedProvider);
    _persisted = seed.trim().isEmpty ? null : seed.trim();
    return seed;
  }

  /// 用户改了输入框。内存立刻生效（请求马上就能用），落盘异步跟上。
  ///
  /// 不做防抖：这里没有 Timer，因此不会在 widget 测试里留下 pending timer；
  /// 而且钥匙串写入是一次很快的平台调用，`_persisted` 挡住重复值之后，
  /// 一个 40 字符的 key 最多写 40 次。
  void update(String value) {
    state = value;
    final trimmed = value.trim();
    if (trimmed == _persisted) return;
    _persisted = trimmed;
    unawaited(_persist(trimmed));
  }

  /// 手动清除（设置页的「清除密钥」）。内存与钥匙串一起清。
  Future<void> clear() async {
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
