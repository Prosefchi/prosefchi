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

    // Debug and profile share one set of greyed artwork. Neither needs telling
    // apart from the other — the label in each source set does that — and both
    // need telling apart from the release. One copy also means the greyscale
    // conversion recorded in dev/res/values/colors.xml is re-derived once if the
    // brand red ever moves, rather than once per build type with the two free to
    // drift. Only the names stay per-variant, in each source set's own strings.
    sourceSets {
        getByName("debug") { res.srcDir("src/dev/res") }
        getByName("profile") { res.srcDir("src/dev/res") }
    }

    buildTypes {
        // Android identifies an installed app by its application id, so a build
        // sharing one with the release replaces it — and since the two are
        // signed by different keys, the install is refused outright rather than
        // upgraded. Suffixing makes each a separate app, with its own reminders,
        // settings and stored calendar, so a working copy can sit beside the
        // released one instead of costing it its data.
        //
        // Only the application id moves. `namespace` stays put, which is what
        // resolves `.MainActivity` and the R class, so nothing in the manifest
        // or the Kotlin source has to know about this.
        //
        // It does carry the resource table's package name along with it, and
        // that is worth knowing rather than discovering: it is what
        // `getResources().getIdentifier(name, type, getPackageName())` searches,
        // which is how flutter_local_notifications resolves its default icon,
        // and a failure there fails `initialize` and takes the reminders screen
        // inert with it. Both sides move together, so the lookup still resolves.
        debug {
            applicationIdSuffix = ".debug"
        }

        // Same collision, same fix. `flutter run --profile` otherwise carries
        // the release id and installs over it exactly as debug used to.
        getByName("profile") {
            applicationIdSuffix = ".profile"
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
