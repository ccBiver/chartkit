import com.vanniktech.maven.publish.SonatypeHost
import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.compose")
    // KMP-aware publishing to Maven Central (com.vanniktech.maven.publish). This is the reliable
    // distribution path for the Compose Multiplatform variant: it publishes EVERY target (the root
    // Gradle Module Metadata + android AAR + desktop jar + iosX64/iosArm64/iosSimulatorArm64 klibs),
    // signs all artifacts, and uploads to the Sonatype Central Portal. JitPack (Linux-only builders)
    // structurally cannot produce Apple klibs, so it is NOT used for :kmp.
    id("com.vanniktech.maven.publish") version "0.30.0"
}

// Compose Multiplatform variant of chartkit (Android + iOS + Desktop), published as `chartkit-kmp`.
// Reuses the pure-Kotlin :core sources and the platform-agnostic Compose files via srcDir (single source
// of truth); only KLineChart + the fullscreen overlay are ported for multiplatform text rendering.
//
// Maven Central namespace: io.github.ccbiver (verifiable via the ccBiver GitHub account). The legacy
// JitPack coordinate (com.github.ccBiver.chartkit) cannot serve iOS klibs, so :kmp moves to Central.
group = "io.github.ccbiver"
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
                // NOTE: chartkit no longer depends on kotlinx-datetime. The default time formatter
                // uses platform calendars via expect/actual (PlatformTime.kt). This avoids a runtime
                // crash when a consumer pulls kotlinx-datetime 0.7+ (which removed kotlinx.datetime.Instant),
                // since Gradle would otherwise force chartkit's resolved version up and break it.
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

// Maven Central publishing via com.vanniktech.maven.publish. The plugin auto-configures all KMP
// publications (root module metadata + every target), so the consumer coordinate is simply:
//   io.github.ccbiver:chartkit-kmp:<version>
// and Gradle resolves the right iOS/Android/Desktop variant from the published .module metadata.
//
// Credentials & signing are supplied OUT-OF-BAND (never committed) via Gradle properties / env vars:
//   ORG_GRADLE_PROJECT_mavenCentralUsername / ...Password  → Central Portal token (user/pass)
//   ORG_GRADLE_PROJECT_signingInMemoryKey / ...KeyPassword → ASCII-armored GPG secret key
// Publish with:  ./gradlew :kmp:publishAndReleaseToMavenCentral --no-configuration-cache
mavenPublishing {
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL, automaticRelease = true)
    // Sign only when a GPG key is actually available (set via ORG_GRADLE_PROJECT_signingInMemoryKey
    // or -PsigningInMemoryKey). Maven Central requires signatures, so the real publish always signs;
    // local `publishToMavenLocal` runs key-free for quick verification.
    if (project.findProperty("signingInMemoryKey") != null) {
        signAllPublications()
    }
    coordinates(group.toString(), "chartkit-kmp", version.toString())
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
