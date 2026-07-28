import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material never enters the repository. CI supplies it through
// the environment from organisation secrets; a local release build reads
// android/key.properties, which .gitignore already excludes along with *.jks.
//
// The environment is checked first so that a stray key.properties left in a
// workspace cannot quietly change what CI signs with. Passwords also survive
// the environment unaltered — java.util.Properties treats a backslash in a
// value as an escape, so a password containing one would arrive corrupted.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingSetting(variable: String, property: String): String? =
    System.getenv(variable) ?: keystoreProperties.getProperty(property)

val keystorePath = signingSetting("ANDROID_KEYSTORE_FILE", "storeFile")

android {
    namespace = "io.github.prosefchi.prosefchi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications calls java.time APIs, which do not exist
        // below API 26. Desugaring backports them; without it the build fails
        // outright at checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.prosefchi.prosefchi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // A fresh clone has no keystore, so declare the config only when there
        // is something to put in it and let the build type fall back below.
        if (keystorePath != null) {
            create("release") {
                // Resolves an absolute path — what CI passes — unchanged, and
                // a relative one against android/, where key.properties lives.
                storeFile = rootProject.file(keystorePath)
                storePassword = signingSetting("ANDROID_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingSetting("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = signingSetting("ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Android identifies an installed app by its application id, so a
            // debug build sharing one with the release replaces it — and the
            // two are signed by different keys, so the install is refused
            // outright rather than upgraded. Suffixing the debug id makes them
            // two apps: a working copy can sit beside the released one with its
            // own reminders, settings and stored calendar.
            //
            // Only the application id moves. `namespace` stays put, which is
            // what resolves `.MainActivity` and the R class, so nothing in the
            // manifest or the Kotlin source has to know about this.
            applicationIdSuffix = ".debug"
        }

        release {
            // Falling back to the debug key keeps `flutter run --release`
            // working for anyone without the keystore. The release workflow
            // refuses to build without it rather than relying on this, because
            // a debug-signed release APK installs perfectly well and only
            // reveals itself later, when the next release will not install
            // over it and every user has to uninstall first.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Version required by flutter_local_notifications; see its README.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
