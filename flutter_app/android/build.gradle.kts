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

    // Firebase Auth 24.2 exposes a Checker Framework annotation in one of its
    // inferred Kotlin types, but does not publish checker-qual transitively.
    // Keep the annotation compile-only; it is not required in the APK runtime.
    if (name == "firebase_auth") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add(
                "compileOnly",
                "org.checkerframework:checker-qual:3.43.0",
            )
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
