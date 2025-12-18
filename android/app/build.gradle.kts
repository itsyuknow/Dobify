import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

/* 🔑 READ Flutter version from local.properties */
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(localPropertiesFile.inputStream())
}

val flutterVersionCode =
    localProperties.getProperty("flutter.versionCode")?.toInt() ?: 1
val flutterVersionName =
    localProperties.getProperty("flutter.versionName") ?: "1.0"

android {
    namespace = "com.yuknow.ironly"
    compileSdk = 36

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
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        // ✅ NOW Flutter controls the version
        versionCode = flutterVersionCode
        versionName = flutterVersionName

        multiDexEnabled = true
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
            pickFirsts.addAll(
                listOf(
                    "**/armeabi-v7a/libc++_shared.so",
                    "**/x86_64/libc++_shared.so",
                    "**/arm64-v8a/libc++_shared.so",
                    "**/x86/libc++_shared.so"
                )
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("androidx.window:window:1.2.0")
    implementation("androidx.window:window-java:1.2.0")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-ktx:1.11.0")
    implementation("androidx.browser:browser:1.9.0")

    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")

    implementation("com.google.android.gms:play-services-auth:21.2.0")
    implementation("com.google.android.gms:play-services-base:18.5.0")

    implementation("androidx.multidex:multidex:2.0.1")
}

flutter {
    source = "../.."
}
