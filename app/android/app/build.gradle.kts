import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: copy android/key.properties.example to android/key.properties and fill it in.
// The file and the keystore must never be committed (see .gitignore).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.doculoom.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.doculoom.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob app ID. Defaults to Google's public test ID; pass -PadmobAppId=ca-app-pub-... for release.
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAppId") as String?) ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Signed with your upload key when key.properties exists; otherwise the debug key, which
            // Google Play rejects, so create the key first (see README).
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

// Size: lucide_icons_flutter bundles six variable-weight icon fonts (~3 MB) that the app never
// uses (it only uses the static `Lucide` family). Drop them and their FontManifest entries from
// the release assets.
val unusedFontFamily = Regex("""packages/lucide_icons_flutter/Lucide[1-6]00""")
tasks.configureEach {
    if (name == "copyFlutterAssetsRelease") {
        doLast {
            outputs.files.files.filter { it.isDirectory }.forEach { out ->
                val manifest = File(out, "flutter_assets/FontManifest.json")
                    .takeIf { it.exists() } ?: File(out, "FontManifest.json").takeIf { it.exists() }
                    ?: return@forEach
                val fonts = groovy.json.JsonSlurper().parse(manifest) as List<*>
                val kept = fonts.filter { f ->
                    !unusedFontFamily.matches((f as Map<*, *>)["family"] as String)
                }
                (fonts - kept.toSet()).forEach { f ->
                    ((f as Map<*, *>)["fonts"] as List<*>).forEach { e ->
                        File(manifest.parentFile, (e as Map<*, *>)["asset"] as String).delete()
                    }
                }
                manifest.writeText(groovy.json.JsonOutput.toJson(kept))
            }
        }
    }
}

dependencies {
    // Hindi and other Devanagari scripts for on-device text recognition (Latin ships with the plugin).
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")
    testImplementation("junit:junit:4.13.2")
}
