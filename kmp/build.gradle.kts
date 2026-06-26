import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.compose")
    `maven-publish`
}

// Compose Multiplatform variant of chartkit (Android + iOS + Desktop), published as `chartkit-kmp`.
// Reuses the pure-Kotlin :core sources and the platform-agnostic Compose files via srcDir (single source
// of truth); only KLineChart + the fullscreen overlay are ported for multiplatform text rendering.
group = "com.github.ccBiver.chartkit"
version = rootProject.extra["chartkitVersion"] as String

kotlin {
    androidTarget {
        publishLibraryVariants("release")
        @OptIn(ExperimentalKotlinGradlePluginApi::class)
        compilerOptions { jvmTarget.set(JvmTarget.JVM_1_8) }
    }

    jvm("desktop")

    listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "ChartkitKmp"
            isStatic = true
        }
    }

    sourceSets {
        val commonMain by getting {
            // Single source of truth: share the pure-Kotlin core engine and the (now platform-agnostic,
            // TextMeasurer-based) Compose UI directly. Excluded files have a JVM-only implementation and
            // are re-provided here in a multiplatform form:
            //  - ChartRegistry.kt   : drops the JVM-only @Synchronized (init-time registry)
            //  - ChartFormatter.kt  : local-time formatting via kotlinx-datetime instead of java.util.Calendar
            //  - ChartFullscreen.kt : Android Activity launcher — Android-only, no KMP equivalent here
            kotlin.srcDir("../core/src/main/kotlin")
            kotlin.srcDir("../compose/src/main/kotlin")
            kotlin.exclude("**/ChartRegistry.kt", "**/ChartFormatter.kt", "**/ChartFullscreen.kt")

            dependencies {
                implementation(compose.runtime)
                implementation(compose.foundation)
                implementation(compose.ui)
                implementation(compose.animation)
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
                implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            }
        }
        val commonTest by getting {
            kotlin.srcDir("../core/src/test/kotlin")
            dependencies {
                implementation(kotlin("test"))
            }
        }
    }
}

android {
    namespace = "com.biver.chartkit.kmp"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

// JitPack/Maven coordinate: chartkit-kmp (+ per-platform suffixes resolved via Gradle metadata).
// afterEvaluate: AGP creates the `androidRelease` publication late, so rename here to catch it too.
// Anchor the replace at the start ("kmp" / "kmp-android" → "chartkit-kmp" / "chartkit-kmp-android")
// and skip already-renamed ones to stay idempotent.
afterEvaluate {
    publishing.publications.withType<MavenPublication>().configureEach {
        artifactId = artifactId.replaceFirst(Regex("^${project.name}"), "chartkit-kmp")
        pom {
            name.set("chartkit-kmp")
            description.set("Compose Multiplatform K-line (candlestick) chart for Android/iOS/Desktop: pure-Canvas rendering, indicators, crosshair, trade marks, skeleton and animations.")
            url.set("https://github.com/ccBiver/chartkit")
            licenses {
                license {
                    name.set("MIT License")
                    url.set("https://opensource.org/licenses/MIT")
                }
            }
            developers {
                developer {
                    id.set("ccBiver")
                    name.set("ccBiver")
                }
            }
            scm {
                url.set("https://github.com/ccBiver/chartkit")
                connection.set("scm:git:https://github.com/ccBiver/chartkit.git")
                developerConnection.set("scm:git:ssh://git@github.com/ccBiver/chartkit.git")
            }
        }
    }
}
