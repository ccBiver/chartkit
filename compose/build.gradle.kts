plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    `maven-publish`
}

// Compose rendering/interaction layer; depends on the pure-Kotlin :core.
group = "com.github.ccBiver.chartkit"
version = rootProject.extra["chartkitVersion"] as String

android {
    namespace = "com.biver.chartkit.compose"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
    }
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    api(project(":core"))

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2025.03.01"))
    implementation("androidx.compose.foundation:foundation:1.7.8")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.runtime:runtime")
    implementation("androidx.compose.animation:animation")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            artifactId = "chartkit-compose"
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("chartkit-compose")
                description.set("Jetpack Compose K-line (candlestick) chart: pure-Canvas rendering, indicators, crosshair, trade marks, skeleton and animations.")
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
}
