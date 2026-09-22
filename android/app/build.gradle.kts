plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bigbrainzsolutions.omnidesk"
    // flutter_secure_storage and permission_handler currently require API 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bigbrainzsolutions.omnidesk"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // The app owns the native FCM entry point, so it needs the Firebase
    // Messaging API directly rather than relying on the Flutter plugin's
    // non-transitive implementation dependency.
    implementation("com.google.firebase:firebase-messaging:25.1.3")
    // Pusher's Java-WebSocket client depends on slf4j-api and reflectively
    // looks for a binding. Ship the matching no-op binding so release R8 has
    // the optional StaticLoggerBinder class without enabling extra logging.
    implementation("org.slf4j:slf4j-nop:1.7.25")
}

// The historical Baresip integration is intentionally not part of the active
// Android build. Its sources stay checked in until the dedicated cleanup pass
// after Android Telecom + WebRTC acceptance; normal builds must never compile,
// package, or invoke it.

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
