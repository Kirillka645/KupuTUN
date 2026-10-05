plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.kuputun.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "dev.kuputun.app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // NOTE: do not pin ndk.abiFilters here. libkuputun.aar ships
        // arm64-v8a/armeabi-v7a/x86_64 (scripts/build_go.sh), which already match
        // Flutter's default target platforms, and setting abiFilters explicitly
        // makes Gradle reject `flutter build apk --split-per-abi` with
        // "Conflicting configuration ... cannot be present when splits abi
        // filters are set".
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }


    signingConfigs {
        create("release") {
            val ks = System.getenv("KUPUTUN_KEYSTORE")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("KUPUTUN_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KUPUTUN_KEY_ALIAS")
                keyPassword = System.getenv("KUPUTUN_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("KUPUTUN_KEYSTORE") != null)
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Google Play: ship native symbols in the AAB (crash/ANR reports).
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }
        }
    }

    packaging {
        jniLibs { useLegacyPackaging = true }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

dependencies {
    // Built by scripts/build_go.sh android -> android/app/libs/kuputun.aar
    implementation(files("libs/kuputun.aar"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
