import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties().apply {
    if (signingPropertiesFile.exists()) {
        signingPropertiesFile.inputStream().use { load(it) }
    }
}
val releaseSigningReady = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !signingProperties.getProperty(it).isNullOrBlank() }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) }
        && !releaseSigningReady) {
        throw GradleException("Release signing is required. Configure android/key.properties; see docs/android-signing.md")
    }
}

android {
    namespace = "com.example.night_sleep"
    // 36 / 24 是 Flutter 3.47.5 的模板默认值（FlutterExtension.kt 里的
    // compileSdkVersion = 36、minSdkVersion = 24）。**已经逐个核过本工程全部带 Android
    // 实现的插件的下界**（读的是它们自己的 android/build.gradle，不是文档）：
    //   compileSdk 最高的 = 36，来自 flutter_local_notifications 22.3.1 与 record_android 2.2.0；
    //   minSdk  最高的 = 24，来自上面两个 + audio_session、flutter_secure_storage、
    //                     url_launcher_android 共五个。
    // 与模板默认值恰好相等，因此不写死数字。将来再加插件（或 Flutter 调低默认值）时要重核。
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // **flutter_local_notifications 10+ 的硬要求**，而且它的 README 明说
        // 「即使你不使用排定通知也必须开」（插件内部用了 `java.time` 等新 API）。
        // 不开的话编译期就炸，报错还长得像「Java 版本不对」。
        // 开关与下面的 coreLibraryDesugaring 依赖**必须成对**，缺一个同样编译不过。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // 占位配置，与 iOS / macOS 的 `com.example.nightSleep` **不同名**：
        // 那是 Flutter 两条模板各自的默认（iOS 把 night_sleep 转成 camelCase，
        // Android 保留 snake_case）。两者是两个独立的商店身份，不要求一致；
        // 待项目方给出真实 ID 后一并替换（总规格 §10 第 1 条）。
        applicationId = "com.example.night_sleep"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeType = signingProperties.getProperty("storeType", "PKCS12")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 与上面 `isCoreLibraryDesugaringEnabled = true` 成对，版本号照
    // flutter_local_notifications 22.3.1 的 README（它自己也用这个版本）。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
