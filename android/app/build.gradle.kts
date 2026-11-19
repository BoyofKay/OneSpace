plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// QA stays installable before Firebase registration. Once the Firebase
// Android config is supplied by CI, compile Google Services resources.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.onespace.onespace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The real application ID comes from the qa / prod flavor below.
        applicationId = "com.onespace.onespace"
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

    // Upload key for Google Play (production only). CI provides it from GitHub
    // secrets; it is never committed. Google re-signs with the Play app signing key.
    // Pin CI QA signing to the restored, verified preview keystore. Flutter's
    // implicit debug signing may otherwise generate a different certificate.
    val qaStableStore = System.getenv("ONESPACE_QA_KEYSTORE")
    val uploadStore = System.getenv("ONESPACE_UPLOAD_KEYSTORE")
    signingConfigs {
        if (qaStableStore != null) {
            // No fallback to a newly generated debug key when CI pins a key.
            create("qaStable") {
                storeFile = file(qaStableStore)
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
        if (uploadStore != null && file(uploadStore).exists()) {
            create("upload") {
                storeFile = file(uploadStore)
                storePassword = System.getenv("ONESPACE_UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("ONESPACE_UPLOAD_KEY_ALIAS")
                keyPassword = System.getenv("ONESPACE_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    // Two apps that install side by side:
    //   qa   -> onespace.qa        "OneSpace QA"  QA backend, test signing key (GitHub APKs)
    //   prod -> live.onespace.app  "OneSpace"     production backend, Play upload key (Google Play)
    // The Dart side picks the backend with --dart-define=ONESPACE_ENV=qa|production.
    flavorDimensions += "env"
    productFlavors {
        create("qa") {
            dimension = "env"
            applicationId = "onespace.qa"
            versionNameSuffix = "-qa"
            manifestPlaceholders["appLabel"] = "OneSpace QA"
            manifestPlaceholders["authScheme"] = "onespace-preview"
            // Stable test-only keystore restored by GitHub Actions (tools/dev-signing).
            signingConfig = if (qaStableStore != null)
                signingConfigs.getByName("qaStable")
                else signingConfigs.getByName("debug")
        }
        create("prod") {
            dimension = "env"
            applicationId = "live.onespace.app"
            manifestPlaceholders["appLabel"] = "OneSpace"
            manifestPlaceholders["authScheme"] = "onespace"
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }

    buildTypes {
        release {
            // Signing comes from the flavor above.
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
