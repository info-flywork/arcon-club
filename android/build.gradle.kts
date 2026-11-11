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
// Eski compileSdk ile gelen eklentiler (agora_rtc_engine: 31) yeni androidx ile derlenemiyor
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 36
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

// camera_android_camerax + CameraX 1.5.3: derlemede CallbackToFutureAdapter (concurrent-futures) aranıyor
subprojects {
    if (name == "camera_android_camerax") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add("compileOnly", "androidx.concurrent:concurrent-futures:1.2.0")
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
