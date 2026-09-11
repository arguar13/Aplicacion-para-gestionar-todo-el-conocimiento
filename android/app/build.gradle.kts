plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.sinapsis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identidad base de la app. Cada flavor le agrega su sufijo abajo,
        // salvo prod, que usa este tal cual.
        applicationId = "app.sinapsis"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Los tres flavors espejan los entry points de Dart (main_dev.dart,
    // main_staging.dart, main_prod.dart) y el enum `AppFlavor`. Hasta ahora
    // los flavors solo existían del lado de Dart, así que los tres builds
    // compartían applicationId: Android los veía como la MISMA app y cada
    // `flutter run` desinstalaba al anterior. Imposible tener dev y prod en
    // el mismo teléfono, que es justamente para lo que sirven los flavors.
    //
    // Uso:
    //   flutter run   --flavor dev     -t lib/main_dev.dart
    //   flutter build appbundle --flavor prod -t lib/main_prod.dart
    flavorDimensions += "environment"

    productFlavors {
        create("dev") {
            dimension = "environment"
            // app.sinapsis.dev — un applicationId distinto es, para
            // Android, una app distinta: ícono propio, datos propios,
            // desinstalación independiente.
            applicationIdSuffix = ".dev"
            // Queda a la vista en Ajustes > Apps y en cualquier reporte de
            // error: "0.1.0-dev" no se confunde con un build de producción.
            versionNameSuffix = "-dev"
            // `resValue` genera @string/app_name en tiempo de build, que es
            // lo que lee android:label en el manifest. Así el nombre bajo
            // el ícono delata el entorno de un vistazo.
            resValue("string", "app_name", "Sinapsis Dev")
        }

        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Sinapsis Staging")
        }

        create("prod") {
            dimension = "environment"
            // Sin sufijo, a propósito: este es el applicationId de
            // publicación y no puede cambiar nunca — Google Play lo usa
            // como identidad permanente de la app.
            resValue("string", "app_name", "Sinapsis")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
