import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.compose")
}

// Unified Compose Multiplatform demo for chartkit (:kmp): Android + iOS + Desktop, one shared App().
//   Android : ./gradlew :composeApp:installDebug   (or run from Android Studio)
//   Desktop : ./gradlew :composeApp:run
//   iOS     : open iosApp/iosApp.xcodeproj in Xcode and Run (builds the framework via Gradle)
kotlin {
    androidTarget {
        @OptIn(ExperimentalKotlinGradlePluginApi::class)
        compilerOptions { jvmTarget.set(JvmTarget.JVM_1_8) }
    }

    jvm("desktop")

    listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "ComposeApp"
            isStatic = true
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(project(":kmp"))
                implementation(compose.runtime)
                implementation(compose.foundation)
                implementation(compose.material3)
                implementation(compose.ui)
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("androidx.activity:activity-compose:1.9.3")
            }
        }
        val desktopMain by getting {
            dependencies {
                implementation(compose.desktop.currentOs)
            }
        }
    }
}

android {
    namespace = "com.biver.chartkit.demoapp"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.biver.chartkit.demoapp"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
}

compose.desktop {
    application {
        mainClass = "com.biver.chartkit.demoapp.MainKt"
        nativeDistributions {
            targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb)
            packageName = "chartkit-demo"
            packageVersion = "1.0.0"
        }
    }
}
