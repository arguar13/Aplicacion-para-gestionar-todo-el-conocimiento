pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9.1.0 (recién publicado) rompía la compilación contra buena parte
    // del ecosistema de plugins de Flutter: `resValues` deshabilitado por
    // defecto, el Kotlin integrado que `file_picker` da por sentado y que
    // `audio_decoder` no tolera al mismo tiempo (ninguno de los dos tiene
    // todavía una versión publicada que arregle esto), y el propio AGP
    // recomendando no pasar de compileSdk 36. 8.13.0 es la última 8.x
    // estable — probada por el ecosistema entero — y no tiene Kotlin
    // integrado, así que ese choque puntual desaparece solo.
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
