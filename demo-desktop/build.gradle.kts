import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.compose")
}

// Compose Desktop demo for the multiplatform chartkit (:kmp). Run with `./gradlew :demo-desktop:run`.
dependencies {
    implementation(project(":kmp"))
    implementation(compose.desktop.currentOs)
    implementation(compose.material3)
}

compose.desktop {
    application {
        mainClass = "com.biver.chartkit.demodesktop.MainKt"
        nativeDistributions {
            targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb)
            packageName = "chartkit-desktop-demo"
            packageVersion = "1.0.0"
        }
    }
}
