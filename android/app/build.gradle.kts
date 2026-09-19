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

        // Baresip is built and validated for the 64-bit device and emulator
        // ABIs only. Avoid asking CMake for an unsupported 32-bit archive.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
            abiFilters.add("x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-DANDROID")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Baresip, Libre, and OpenSSL are pinned source submodules. The build script
// produces only ignored JNI artifacts, so source control never contains SIP
// credentials or host-specific native outputs.
val buildBaresipAndroid by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("bash", "android/scripts/build_baresip_android.sh")
    inputs.files(
        fileTree("${rootProject.projectDir.parent}/third_party/baresip"),
        fileTree("${rootProject.projectDir.parent}/third_party/re"),
        fileTree("${rootProject.projectDir.parent}/third_party/openssl"),
    )
    outputs.dir("src/main/jniLibs")
    outputs.dir("src/main/cpp/generated/include")
}

tasks.named("preBuild").configure { dependsOn(buildBaresipAndroid) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
