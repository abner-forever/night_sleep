package com.example.night_sleep

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private var compassHandler: CompassStreamHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // **这一行必须留着。** 本工程用的是 embedding v2（清单里 `flutterEmbedding=2`），
        // 插件注册就发生在 `super.configureFlutterEngine` 的实现里
        // （`GeneratedPluginRegistrant.registerGeneratedPlugins`）。
        // 覆写时漏掉它 → 通知、录音、安全存储**全体静默失效**，
        // 编译期与运行期都不会有任何提示，只有功能悄悄不工作。
        super.configureFlutterEngine(flutterEngine)

        // 本工程唯一一条手写通道。名字与 iOS 侧、Dart 侧三处必须一致。
        val handler = CompassStreamHandler(this)
        compassHandler = handler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL)
            .setStreamHandler(handler)
    }

    override fun onDestroy() {
        // 兜底反注册：引擎拆除时不一定送达 EventChannel 的 `cancel`。
        // `dispose()` 是幂等的，正常路径下这里是空操作。
        compassHandler?.dispose()
        compassHandler = null
        super.onDestroy()
    }

    private companion object {
        const val COMPASS_CHANNEL = "night_sleep/compass"
    }
}
