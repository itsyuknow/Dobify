plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yuknow.ironly"
    compileSdk = flutter.compileSdkVersion.toInt()

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.yuknow.ironly"
        minSdk = flutter.minSdkVersion.toInt()
        targetSdk = flutter.targetSdkVersion.toInt()
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Updated desugaring library version
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.window:window:1.2.0")
    implementation("androidx.window:window-java:1.2.0")
}

flutter {
    source = "../.."
}