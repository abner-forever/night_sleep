# 真机天气不可用：地理位置获取方案调研

> 调研日期：2026-10-26
> 触发问题：真机调试时首页显示「天气暂不可用」，日志/服务端提示无法根据请求 IP 定位城市。
> 结论口径：本文对「代码里能读到的事实」与「只能真机验证的推测」分开标注。

## 一、结论摘要

1. **真机拿不到天气的直接原因不是缺定位能力，而是两处开发期断点叠加**：
   - debug 构建的天气基址写死成 `10.0.2.2`（Android **模拟器**访问宿主机的别名），真机上这个地址不存在，请求直接 `SocketException` / 超时；
   - 即使用 `adb reverse` 把请求送进本机 NestJS，请求 IP 是 `127.0.0.1`，被服务端判为私有地址，按设计返回 400「未提供城市参数，且当前请求 IP 无法用于城市级定位」。
2. **服务端「按 IP 定位」只在线上的 Cloudflare 部署里成立**：Worker 会注入 `cf-connecting-ip`，那是公网 IP；本机 NestJS 没有这一层。
3. **推荐方案：用设备系统定位（`geolocator`）拿经纬度，把坐标当 `location` 传给现有接口。** 服务端**不需要改动**——`WeatherQueryDto.location` 的文档已写明支持「经度,纬度」，和风 GeoAPI 的 `location` 参数也确实接受十进制经纬度，返回最近城市名 + 坐标。
4. **不建议把「端侧查公网 IP」作为主路径**：国内移动网络多为运营商大 NAT，出口 IP 常常落在省会；再加一次第三方请求和隐私暴露，收益不匹配。
5. **生产环境另有一个已知坑**（与定位无关但同源）：用户开 VPN/代理时公网 IP 指向境外，GeoAPI 用了 `range: 'cn'`，会查不到城市 → 天气不可用。这条需要单独决定要不要降级。

## 二、现状核查（带代码位置）

天气链路：

```
HomePage → weatherProvider → WeatherService.fetchCurrent()
        → GET {baseUrl}/weather[?location=...]
        → NestJS WeatherController → WeatherService.resolveLocation()
        → ① location 参数 → GeoAPI 城市搜索
           ② WEATHER_DEFAULT_LOCATION
           ③ 请求 IP → ipwho.is → 城市
```

### 断点 1：debug 基址只对模拟器有效

`lib/core/config/app_config.dart:55-73`

```dart
if (debug) {
  return platform == TargetPlatform.android
      ? 'http://10.0.2.2:8080/api'   // ← 模拟器专用别名
      : 'http://localhost:8080/api';
}
```

`10.0.2.2` 是 Android 模拟器把宿主机 `127.0.0.1` 映射出来的虚拟地址。真机上没有这台主机，于是无论家庭 Wi-Fi 还是 USB 调试都会连接失败。`README.md:185-205` 已经写明真机需要 `--dart-define=WEATHER_API_BASE_URL` 覆盖，但没有写「忘覆盖时的表现」——这次的现象就是从这儿来的。

### 断点 2：私有 IP 被服务端主动拒绝

`server/src/weather/weather.service.ts:177-195`

```ts
if (!this.isPublicIp(clientIp)) {
  throw new BadRequestException('未提供城市参数，且当前请求 IP 无法用于城市级定位');
}
```

`isPublicIp`（同文件 `:424-446`）把 `10.x`、`127.x`、`172.16-31.x`、`192.168.x`、`169.254.x`、`100.64-127.x`、`fc/fd/fe80` 全部排除。本地调试的请求 IP 必然落在这些段里，所以**本地服务端永远无法按 IP 定位**，这是有意设计的（避免拿内网地址去查公网库得出垃圾结果），不是 bug。

### 断点 3：`cf-connecting-ip` 只有 Cloudflare 才有

`server/src/weather/weather.controller.ts:44-50`

```ts
const cloudflareIp = request.headers['cf-connecting-ip'];
if (typeof cloudflareIp === 'string' && cloudflareIp.trim()) return cloudflareIp.trim();
return request.ip || request.socket.remoteAddress || '';
```

线上 `beta` / `main` 走 `*.workers.dev`，这条能拿到公网 IP，所以**线上按 IP 定位基本是通的**；本机 NestJS 拿不到，只能退到 `request.ip`（私有地址）。

### 已有能力：接口已经支持坐标

`server/src/weather/dto/weather-query.dto.ts:7-21` 的 `location` 描述是「城市名、Location ID、Adcode 或**经度,纬度**」，且 `lookupLocation()`（`weather.service.ts:197-222`）把 `location` 原样传给 `/geo/v2/city/lookup`。和风官方文档确认该接口接受 `location=116.41,39.92` 形式的十进制坐标，并返回最近城市的 `name/lat/lon`。

**也就是说：客户端只要拿到经纬度，拼成 `121.47,31.23` 传上去，城市名、天气、三天预报全会正常返回，服务端一行不用改。**

### 当前客户端完全没有定位能力

- `pubspec.yaml` 无 `geolocator` / `geocoding` / 任何地图 SDK；
- `android/app/src/main/AndroidManifest.xml` 无 `ACCESS_COARSE_LOCATION` / `ACCESS_FINE_LOCATION`；
- `ios/Runner/Info.plist` 无 `NSLocationWhenInUseUsageDescription`；
- `AppConfig.weatherLocation` 是编译期 `--dart-define`，不是运行时状态。

## 三、可选方案对比

| 方案 | 精度 | 需要权限 | 国内可用性 | 隐私暴露 | 客户端改动 | 服务端改动 |
|---|---|---|---|---|---|---|
| **A. `geolocator` 系统定位**（推荐） | 城市级轻松、可到街区 | 是（COARSE 即可） | 好：Fused 不可用时自动回退 `LocationManager` | 坐标只发给自家服务端 | 中（插件 + 两条清单 + 一个 provider） | 零 |
| B. 高德 / 腾讯定位 SDK | 最好（IP+Wi-Fi+基站融合） | 是 + 隐私合规弹窗 | 最好（国内专用库） | 坐标发给第三方 SDK（本机处理可不开网上传） | 大（key、合规弹窗、包体） | 零 |
| C. 端侧查公网 IP（`ipwho.is` 等） | 城市级，常偏到省会 | 否 | 一般（境外服务慢/被墙，国内库要 key） | IP 暴露给第三方 | 小 | 零 |
| D. 服务端按 IP（现状） | 城市级，同上 | 否 | 线上可用，本地不可用 | IP 到自家服务端再到第三方 | 零 | 已实现 |
| E. 用户手选城市 | 完全准确 | 否 | 最好 | 无 | 小 | 零 |
| F. `network_info_plus` 读 Wi-Fi 反查 | 街区级理论可行 | Android 10+ 仍需定位权限 | 不可行（无公开 BSSID 库） | — | — | — |

补充说明：

- **A 的国内细节**：`geolocator` 在 Android 优先用 `FusedLocationProviderClient`，不可用时回退 `LocationManager`（官方文档明确）。国产 ROM 无 GMS，会走后者；`GPS_PROVIDER` 室内无信号，`NETWORK_PROVIDER` 由厂商定位服务提供，城市级通常够用。**但"国产 ROM 上回退后一定能定位"只有真机能验证，文档不能作为证据**——建议按本文第五节先做一次真机冒烟。
- **A 的权限细节**：Android 12+ 用户即使只给「大致位置」，精度也足够城市级天气；插件要求 `compileSdk 35`，本工程已在 36，`minSdk 24` 也满足。
- **B 的成本**：高德/腾讯定位 SDK 在国内确实更准，但需要 key（又是一份要保管的密钥）、需要首次启动的隐私授权弹窗、要改 `AGENTS.md` 里的权限申请口径，且与「本地优先、少依赖」的项目气质相冲。除非后面要做「按位置推荐日出日落/时区」这类强定位功能，否则不值得。
- **C 不可取的关键理由**：运营商大 NAT 下公网 IP 不等于所在地，实测常见「人在苏州、IP 落在南京」。天气卡片显示错误城市，比显示「暂不可用」更糟（违反「没有的东西就显示为没有」）。
- **E 应该保留**：作为兜底和用户纠正手段，成本最低，且不涉及权限。

## 四、推荐方案设计

### 4.1 分层取值顺序

```
① 用户手动选的城市（设置里持久化）              ← 最高优先，用户意图
② 设备定位坐标（本次运行时已授权且拿到 fix）     ← 主路径
③ 上次成功定位/城市的缓存                        ← 冷启动无权限也能显示
④ WEATHER_DEFAULT_LOCATION（服务端）             ← 运维兜底
⑤ 服务端按 IP（仅线上有效）                      ← 最后兜底
⑥ 都没有 → 「天气暂不可用」+「使用我的位置」入口  ← 诚实展示
```

`weatherProvider`（`lib/features/home/data/weather_service.dart:17-38`）现在是「`AppConfig.weatherLocation` 为空就不带参数」。改造后 ①②③ 合成一个 `String locationQuery`，仍然走同一个 `WeatherService`，**请求层的形状不变**，`test/weather_service_test.dart` 的既有断言基本不用动。

### 4.2 接口边界（可测试性）

按项目「领域逻辑不碰 I/O、插件走注入」的惯例：

```dart
// lib/features/home/domain/location_fix.dart
@immutable
class LocationFix {
  const LocationFix({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;

  /// 和风天气接受「经度,纬度」。两位小数约 1.1 km，城市级天气完全够用，
  /// 同时少往外吐一点位置精度。
  String get query =>
      '${longitude.toStringAsFixed(2)},${latitude.toStringAsFixed(2)}';
}

// lib/features/home/data/device_location.dart
abstract interface class DeviceLocation {
  /// 拿不到就返回 null，不抛异常、不返回假坐标。
  Future<LocationFix?> current();
}

class GeolocatorDeviceLocation implements DeviceLocation { /* 见 4.3 */ }
```

`deviceLocationProvider` 用 `Provider<DeviceLocation>` 暴露，Widget 测试里 override 成 fake，与现有 `sleepEntriesProvider` / `weatherHttpClientProvider` 的隔离方式一致。**绝不在测试里真调插件通道。**

### 4.3 权限与失败语义

```dart
Future<LocationFix?> current() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;   // 系统定位关闭
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();             // ← 只在用户主动触发时到达
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }
  final last = await Geolocator.getLastKnownPosition();             // 先要旧值，冷启动快
  if (last != null) return LocationFix(latitude: last.latitude, longitude: last.longitude);
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.low,           // 城市级足够，省电、成功率高
      timeLimit: Duration(seconds: 12),
    ),
  );
  return LocationFix(latitude: position.latitude, longitude: position.longitude);
}
```

要点：

- **只申请 `ACCESS_COARSE_LOCATION`**。城市级天气不需要精确位置，Android 12+ 会让用户选「大致位置」，申请 fine 只会多一次被拒的机会。
- `getCurrentPosition` 会抛 `TimeoutException` / `PermissionDeniedException` / `LocationServiceDisabledException`，**必须在外层 catch 后返回 null**，让 UI 落到「天气暂不可用」，不要吞掉后伪造城市。
- `deniedForever` 时给「去设置」入口（`Geolocator.openAppSettings()`），而不是反复弹窗。

### 4.4 权限申请时机（这条和规格冲突，必须先定）

`AGENTS.md` 写的是「**权限在用户启用对应功能时申请**」。天气卡片是首页自动加载的，如果一进首页就 `requestPermission()`，等于在用户没表达意图时弹系统框，**违反这条红线**。两种合规做法，二选一：

- **方案甲（推荐）**：默认不弹权限。天气卡片在「无位置」状态显示「位置未知 · 使用我的位置」按钮，用户点了才走 `requestPermission()`；授权后把结果写入缓存，后续自动使用。
- **方案乙**：在设置里加一个「使用当前位置显示天气」开关，打开时才申请权限。

两者都可以，但**不能是"启动即弹"**。

### 4.5 缓存（避免每次冷启动都要权限）

`AppSettings`（`lib/core/database/app_database.dart:187-214`）已经是键值表，加一列即可：

```dart
TextColumn get lastWeatherLocation => text().nullable()();   // "121.47,31.23" 或 "上海"
```

⚠️ 这会动表结构：`schemaVersion` 从 10 → 11，必须补 `onUpgrade` 分支和旧库测试。按 `AGENTS.md` 的迁移注意事项，先确认 `onUpgrade` 的版本下界，**不要用当前 Dart 表类去模拟旧表**。若想规避迁移，也可以把缓存塞进现有的 `insightProvider` 同款模式之外的单行 JSON —— 但加列更干净，建议照迁移规矩做。

### 4.6 服务端要不要改

**核心路径不用改。** 但有两处值得顺手补：

1. **坐标格式校验**：`location` 目前只校验长度 ≤ 100。建议在 DTO 里对 `^\d{1,3}(\.\d+)?,\d{1,3}(\.\d+)?$` 的形态做范围校验（纬度 ±90、经度 ±180），避免把畸形坐标打到上游换来一个 503。
2. **境外降级**：`lookupLocation()` 固定 `range: 'cn'`（`weather.service.ts:198-207`）。用户开 VPN 或在境外时坐标查询会 404 → 首页「天气暂不可用」。可选做法：`range:'cn'` 查空时去掉 `range` 再查一次，或直接换成 `WEATHER_DEFAULT_LOCATION`。这条和定位无关但同源，建议一并决策。

## 五、落地清单（按改动顺序）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `pubspec.yaml` | 加 `geolocator: ^14.1.2`（当前最新，要求 `compileSdk 35`，本工程 36 已满足） |
| 2 | `android/app/src/main/AndroidManifest.xml` | 加 `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>`。**插件自己的 manifest 只有前台定位 service，不带这两条权限**，必须应用自己声明 |
| 3 | `ios/Runner/Info.plist` | 加 `NSLocationWhenInUseUsageDescription`，文案要写清「只用于显示当地天气，位置不上传、不记录」 |
| 4 | `lib/features/home/domain/location_fix.dart` | 新增坐标值对象 + `query` 序列化 |
| 5 | `lib/features/home/data/device_location.dart` | 新增 `DeviceLocation` 接口与 `geolocator` 实现 + `deviceLocationProvider` |
| 6 | `lib/features/home/data/weather_service.dart` | `weatherProvider` 改为解析「手动城市 / 定位 / 缓存」得到 `locationQuery`；`WeatherService` 本身不动 |
| 7 | `lib/core/database/app_database.dart` | `AppSettings.lastWeatherLocation` + `schemaVersion` 11 + 迁移 |
| 8 | `lib/features/home/presentation/home_page.dart` | 无位置时给「使用我的位置」按钮；`deniedForever` 给「去设置」 |
| 9 | `test/` | `device_location` 的 fake + weatherProvider 的三种来源优先级测试；`app_config_test.dart` 现有断言不受影响 |
| 10 | `CHANGELOG.md` | 记一条功能变更 |

验证：

```bash
dart analyze
dart format lib/features/home lib/core/database
flutter test test/weather_service_test.dart test/app_config_test.dart
flutter test                 # 动了基础设施，跑全量
adb install ... && 真机冒烟：首次进入不弹框 → 点「使用我的位置」→ 授权 → 城市/温度出现
```

**注意**：Widget 测试要把 `deviceLocationProvider` override 成 fake；`geolocator` 在测试环境没有平台通道，真调必炸。

## 六、现在就解除阻塞（不改代码，三种办法）

### 1) USB 反向映射（最稳，不看 Wi-Fi/防火墙/代理脸色）

```bash
adb reverse tcp:8080 tcp:8080
flutter run -d <设备ID> \
  --dart-define=WEATHER_API_BASE_URL=http://127.0.0.1:8080/api \
  --dart-define=WEATHER_LOCATION=上海
```

`WEATHER_LOCATION` 是必须的：走 `127.0.0.1` 时服务端只会看到回环地址，按 IP 定位必然 400。

### 2) 同一 Wi-Fi + 电脑局域网 IP

```bash
ipconfig                     # 取 192.168.x.x
flutter run -d <设备ID> \
  --dart-define=WEATHER_API_BASE_URL=http://192.168.1.10:8080/api \
  --dart-define=WEATHER_LOCATION=上海
```

要放行 Windows 防火墙的 8080 入站；手机和电脑不同网段（访客 Wi-Fi、AP 隔离）会失败。

### 3) 想验证「按 IP 定位」本身（不改 app）

用 cloudflared / ngrok 把本机 8080 暴露成公网地址，再把 `WEATHER_API_BASE_URL` 指过去：

```bash
cloudflared tunnel --url http://localhost:8080
```

Cloudflare 隧道会带上 `cf-connecting-ip`，`weather.controller.ts` 直接读这个头，**不用改 `TRUST_PROXY`** 就能让 IP 定位跑通（`app.set('trust proxy', ...)` 只影响 `request.ip`，而 cf 分支不走它）。这条路能帮你确认「线上按 IP 定位」到底准不准。

> ⚠️ `--dart-define` 是编译期参数，改完必须**完整停掉再 `flutter run`**，热重载不会生效（`README.md:203` 已记）。

## 七、风险与合规

- **权限口径**：见 4.4。天气是"锦上添花"的信息，不该抢麦克风之外的第一个系统弹框。
- **数据最小化**：只发**两位小数**的坐标（≈1 km）给自家服务端，服务端再转发给和风；不发送睡眠记录、备注、音频。这与 `README.md:180-181` 现有表述一致，只需把「网络位置」扩写成「网络位置或设备位置（仅坐标）」。
- **商店申报**：一旦申请定位权限，Google Play 的「数据安全」表单要申报大致位置；App Store 隐私标签要勾 Coarse Location。**申报口径必须与实际行为一致**（只用于天气、不关联身份、不留存）。
- **国内合规**：隐私政策需列明「位置信息用于展示当地天气」，且申请发生在用户主动操作之后。若走方案乙（设置开关），描述会更干净。
- **不要伪造**：定位失败就是「天气暂不可用」，**不允许**回落到某个写死的"上海市"。这是 `AGENTS.md` 的硬约束。

## 八、待确认

1. 定位入口用**方案甲**（首页按钮）还是**方案乙**（设置开关）？影响 `home_page.dart` 的空状态设计。
2. 是否顺手做**境外/IP 定位失败降级**（4.6 第 2 条）？
3. 缓存用 **`AppSettings` 加列**（要迁移）还是先不做缓存（每次冷启动都要等一次定位）？
4. 以上确认后我可以直接按第五节实现。

## 九、落地结果（2026-10-26）

采用方案 A，按 4.4 的**方案甲**实现：默认不弹权限，卡片给「使用我的位置」。

| 文件 | 内容 |
|---|---|
| `pubspec.yaml` | `geolocator: ^14.1.2`（解析到的实际版本 14.1.2） |
| `android/app/src/main/AndroidManifest.xml` | 仅 `ACCESS_COARSE_LOCATION` |
| `ios/Runner/Info.plist` | `NSLocationWhenInUseUsageDescription` |
| `lib/features/home/domain/location_fix.dart` | 坐标值对象，`query` 输出「经度,纬度」两位小数 |
| `lib/features/home/data/device_location.dart` | `DeviceLocation` 接缝 + geolocator 实现 + 失败原因枚举 |
| `lib/features/home/data/weather_location.dart` | `WeatherLocationState` / `Notifier`（用户点击才 `requestPermission`） |
| `lib/features/home/data/weather_service.dart` | `weatherProvider` 先解析位置（显式坐标 → 静默已授权 → 空），再请求 |
| `lib/features/home/presentation/home_page.dart` | 天气失败且无位置时，按原因给「使用我的位置 / 重试 / 去设置」 |
| `test/weather_location_test.dart` | 权限时机、坐标序列化、四种失败分流、定位后重新请求 |
| `test/pages_widget_test.dart` | 卡片入口与永久拒绝后的文案 |

与第六节的差异：

- **没有做 DB 缓存**（4.5 那条）。OS 自己记得授权状态，`weatherProvider` 每次都会先做一次
  **不弹窗**的静默取值，所以授权过的设备不需要每天点一次；只有从未授权时才落到 `idle`。
  这样避开了 `schemaVersion` 迁移，代价是「首次定位要多等一次 fix」。
- **没有动服务端**（4.6 两条照旧待办）。`range: 'cn'` 在境外/VPN 下仍会 404。
- 静默取值给了 8 秒硬超时：定位是旁路，插件卡住时不能让天气跟着一起卡死。

验证情况：

- `dart analyze` 无问题；`flutter test` 全量（1048 条）。
- **真机未验证**：权限框文案与时机、`LocationManager` 回退后的实际定位速度、
  iOS 编译与 `Info.plist` 生效、以及授权后天气是否真的按所在城市显示。
- 测试环境里 geolocator 的平台通道不会回复，因此**任何渲染首页的 widget 测试都必须
  覆盖 `weatherProvider`**；这一点已写进 `pages_widget_test.dart` 的注释。

## 附：事实来源
- 代码：`lib/core/config/app_config.dart:55-79`、`lib/features/home/data/weather_service.dart:17-92`、`server/src/weather/weather.controller.ts:44-50`、`server/src/weather/weather.service.ts:177-251,424-446`、`server/src/weather/dto/weather-query.dto.ts:7-21`、`README.md:163-210`
- 和风天气 GeoAPI 城市搜索文档：`location` 支持「经度,纬度」十进制坐标（`GET /geo/v2/city/lookup`）
- `geolocator` 14.1.2 文档：Android 优先 `FusedLocationProviderClient`、不可用回退 `LocationManager`；`ACCESS_COARSE_LOCATION` / `ACCESS_FINE_LOCATION` 需应用自行在 manifest 声明，插件只自带 `FOREGROUND_SERVICE_LOCATION` 与前台定位 service；Android 12+ 用户可能只授予大致位置
- **未能实证**：本机网络环境下无法访问线上 Worker 与 `ipwho.is`（`curl` 返回 000），因此「线上按 IP 定位准确率」和「国产 ROM 回退 `LocationManager` 后能否定位」都只标注为待真机/联网验证，不作为结论。

## 七、真机实测修正（2026-10-26，小米 9）

上一节留的「真机未验证」已经被实测推翻了一部分，结论以本节为准。

### 设备与环境

`MI 9`（cepheus）/ Android 11（SDK 30）/ MIUI 12.5（V125）/ GMS 20.33.15 存在于系统分区。
`ACCESS_COARSE_LOCATION` 已授予（`granted=true`，appops `foreground`），系统定位 `location_mode=3`，
`gps` 与 `network` provider 均 `enabled=true`。

### 实测结果

| 取位方式 | 结果 |
| --- | --- |
| 融合定位 `low` / `best` | 超时 15s / 20s |
| `LocationManager` `low` / `medium`（`forceLocationManager`） | 超时 15s / 20s |
| `getPositionStream`（10 秒内首个事件） | 无事件 |
| `getLastKnownPosition(forceAndroidLocationManager: true)` | 立即返回 5 分钟前的 network 结果，精度 2000m |
| **直接问系统 `network` provider**（原生 `getCurrentLocation`） | **67ms**，`ageMs=4`，精度 2000m，坐标正确 |

MIUI 的 LMS 日志把原因写得很直白：

```
=MI LMS= request ... gps Request[ACCURACY_CITY gps interval=+10m] from com.abner.night_sleep
=MI LMS= request ... gps Request[ACCURACY_BLOCK gps interval=+10m] from com.abner.night_sleep
```

请求全部被派给 **gps** provider，且精度被标成 `ACCURACY_BLOCK`；室内 GPS 无信号，所以永远等不到回调。

### 根因

1. `geolocator` 的 Android 实现 `LocationManagerClient.determineProvider()` 顺序是
   `passive → fused(仅 API 31+) → GPS → NETWORK`。**只要 GPS provider「可用」就永远不选 network**，
   而「可用」不等于「有信号」。
2. 默认路径走 Google 融合定位（`FusedLocationClient`）。GMS 包在这类国行机器上存在，
   插件就不会回退 `LocationManager`，但 Google 的位置服务在境内不可用——于是也超时。

### 修复

Android 侧改由原生 `LocationManager` 直接请求 **network provider**
（`NetworkLocationHandler.kt`，API 30+ 用 `getCurrentLocation`，24–29 用 `requestSingleUpdate`）。
Dart 侧四档兜底共用一份时间预算（交互 12s / 静默 5s）：network → 15 分钟内缓存 → 实时定位 → 2 小时内缓存。

### 验证

- 真机前台：App 发出 `GET /api/weather?location=113.92%2C22.58`；LMS 记录
  `network Request[POWER_LOW network ...]` 后 43ms 完成。
- 单测：`test/device_location_test.dart` 五条（通道打桩，覆盖四档顺序与权限分支）。
- **仍有个前提**：`COARSE_LOCATION` 的 appops 是 `foreground`。**应用在后台或锁屏时系统会拒绝定位**
  （实测锁屏状态下的请求被拒，`rejectTime` 有记录）。首页在前台加载，不受影响；后台刷新天气若以后要做，
  必须另行处理。
- **仍未验证**：iOS 侧、权限框文案与时机、其他国产 ROM 的 network provider 是否同样可用。

### 附带发现（与本问题无关，但会挡联调）

`server/.env` 只有 `QWEATHER_API_HOST` / `PRIVATE_KEY` / `PROJECT_ID`，缺 `QWEATHER_KEY_ID` 与
`QWEATHER_DEVELOPER_ID`，`weather.service.ts` 的配置校验因此返回 503「天气服务尚未完成配置」。
定位修好之后如果仍然看不到天气，先补这两个变量。

