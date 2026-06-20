plugins {
    id("org.jetbrains.kotlin.jvm")
    `maven-publish`
}

// Pure Kotlin/JVM core: model + indicator engine + built-ins. No Android deps; unit-tested.
group = "com.github.ccBiver.chartkit"
version = rootProject.extra["chartkitVersion"] as String

dependencies {
    testImplementation(kotlin("test-junit"))
}

tasks.test {
    useJUnit()
}

java {
    withSourcesJar()
}

publishing {
    publications {
        create<MavenPublication>("release") {
            from(components["java"])
            artifactId = "chartkit-core"
            pom {
                name.set("chartkit-core")
                description.set("Pure-Kotlin core of chartkit: Candle/TimeFrame model, indicator engine and built-ins (MA/EMA/BOLL/MACD/KDJ/RSI/WR/OBV/SAR/VOLMA).")
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
