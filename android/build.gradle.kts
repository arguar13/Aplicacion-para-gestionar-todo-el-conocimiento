allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// `receive_sharing_intent` 1.9.0 (la última publicada) declara
// `compileSdk 37` a secas en su build.gradle. Desde el ciclo de Android 17
// (API 37), Google ya no publica una plataforma "37" simple: solo existen
// "37.0", "37.1", etc., así que ese entero nunca resuelve a nada instalable.
// No hace falta seguirle el número: el plugin es un simple puente al botón
// de compartir del sistema y no usa ninguna API exclusiva de API 37, así
// que se lo fija a la 36 —la misma que usa el resto del proyecto, y de paso
// la que 8.13.0 (ver settings.gradle.kts) prueba oficialmente como
// máximo—, en vez de perseguir la que el propio paquete pidió de más.
subprojects {
    if (project.name == "receive_sharing_intent") {
        // El bloque de arriba ya fuerza a `:app` a evaluarse antes que el
        // resto, así que para cuando Gradle llega acá `:app` ya está
        // evaluado — pedirle `afterEvaluate` a un proyecto evaluado
        // revienta con `InvalidUserCodeException`. Este proyecto en
        // particular todavía no lo está, pero se guarda igual por las
        // dudas en vez de asumirlo.
        fun fixCompileSdk() {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
                ?.compileSdkVersion("android-36")
        }
        if (project.state.executed) fixCompileSdk() else project.afterEvaluate { fixCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
