import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads android/key.properties (never committed):
//   storeFile=/absolute/path/to/bodytmi-release.jks
//   keyAlias=bodytmi
//   storePassword=...   (or environment BODYTMI_STORE_PASSWORD)
//   keyPassword=...     (or environment BODYTMI_KEY_PASSWORD)
// Without that file, release builds fall back to the debug key so
// `flutter run --release` still works; `make release-apk` refuses that.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(name: String, environment: String): String =
    keyProperties.getProperty(name)
        ?: System.getenv(environment)
        ?: error("key.properties needs $name (or environment $environment).")

android {
    namespace = "org.bodytmi.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (reminders) needs desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "org.bodytmi.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect needs Android 8 (API 26).
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!keyProperties.isEmpty) {
            create("release") {
                storeFile = file(signingValue("storeFile", "BODYTMI_STORE_FILE"))
                storePassword = signingValue("storePassword", "BODYTMI_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "BODYTMI_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "BODYTMI_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
