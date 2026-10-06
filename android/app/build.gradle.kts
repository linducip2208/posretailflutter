import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.posretail.pos_retail"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.posretail.pos_retail"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing dari android/key.properties (TIDAK dicommit, lihat
    // android/key.properties.example). Tanpa file itu, fallback ke debug key
    // agar `flutter run --release` tetap jalan di mesin dev.
    val keyPropsFile = rootProject.file("key.properties")
    val hasReleaseKey = keyPropsFile.exists()
    if (hasReleaseKey) {
        val keyProps = Properties().apply {
            load(FileInputStream(keyPropsFile))
        }
        signingConfigs {
            create("release") {
                keyAlias = keyProps["keyAlias"].toString()
                keyPassword = keyProps["keyPassword"].toString()
                storeFile = file(keyProps["storeFile"].toString())
                storePassword = keyProps["storePassword"].toString()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
