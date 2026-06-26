pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://jitpack.io") }
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

// 注意：不要在此处写国内镜像（aliyun/tencent 等）。这些镜像对海外 CI / JitPack 不可达（曾导致 502 → 构建失败）。
// 本地（国内）加速请用全局 ~/.gradle/init.gradle.kts 配置镜像，对所有项目生效且不污染仓库。详见 PUBLISHING.md。

rootProject.name = "chartkit"
include(":core")
include(":compose")
include(":demo")
include(":kmp")
include(":composeApp")
