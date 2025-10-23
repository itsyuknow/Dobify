plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.yuknow.ironly"
    compileSdk = flutter.compileSdkVersion.toInt()

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.yuknow.ironly"
        minSdk = flutter.minSdkVersion  // Updated to 23 to fix Firebase Auth minSdkVersion error
        targetSdk = flutter.targetSdkVersion.toInt()
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
        multiDexEnabled = true

        // ✅ FIXED KOTLIN SYNTAX
        resourceConfigurations.addAll(listOf("en", "hi"))
        vectorDrawables.useSupportLibrary = true
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            pickFirsts.addAll(listOf(
                "**/armeabi-v7a/libc++_shared.so",
                "**/x86_64/libc++_shared.so",
                "**/arm64-v8a/libc++_shared.so",
                "**/x86/libc++_shared.so"
            ))
        }
    }
}
//#YuKNOW
dependencies {
    // Core dependencies
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.window:window:1.2.0")
    implementation("androidx.window:window-java:1.2.0")

    // ✅ Updated Firebase dependencies
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")

    // ✅ Google Play Services for Auth (Updated versions)
    implementation("com.google.android.gms:play-services-auth:21.2.0")
    implementation("com.google.android.gms:play-services-base:18.5.0")

    // ✅ Multidex support
    implementation("androidx.multidex:multidex:2.0.1")

    // ✅ ADD THESE FOR SUPABASE AUTH
    implementation("androidx.browser:browser:1.8.0")
    implementation("androidx.activity:activity-ktx:1.9.2")
}

flutter {
    source = "../.."
}
