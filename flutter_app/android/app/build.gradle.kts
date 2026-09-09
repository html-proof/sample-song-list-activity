plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.musichub.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "com.musichub.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

val firebaseCoreRuntimeJar = project(":firebase_core").layout.buildDirectory.file(
    "intermediates/runtime_library_classes_jar/release/bundleLibRuntimeToJarRelease/classes.jar",
)

dependencies {
    // firebase_core 4.14's Kotlin classes are present in its runtime JAR but
    // omitted from its compile JAR with this legacy AGP Kotlin configuration.
    // Expose the same runtime artifact for compilation only; normal plugin
    // packaging still contributes it exactly once to the APK.
    compileOnly(files(firebaseCoreRuntimeJar))
}

tasks.matching { it.name == "compileReleaseJavaWithJavac" }.configureEach {
    dependsOn(":firebase_core:bundleLibRuntimeToJarRelease")
}

flutter {
    source = "../.."
}
