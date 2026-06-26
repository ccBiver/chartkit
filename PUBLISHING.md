# Publishing chartkit

chartkit publishes two artifacts (group `com.github.ccBiver.chartkit`, version from `chartkitVersion` in the root `build.gradle.kts`):

| Module | artifactId | Type |
|---|---|---|
| `:core` | `chartkit-core` | JVM jar (+ sources) |
| `:compose` | `chartkit-compose` | Android AAR (+ sources) |

`chartkit-compose` declares an `api` dependency on `chartkit-core`, so consumers only need the compose artifact. The `:demo` app is **not** published.

## Verify locally

```bash
./gradlew :core:publishToMavenLocal :compose:publishToMavenLocal
```

Then, in a project with `mavenLocal()` in its repositories:

```kotlin
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.5")
```

## Release via JitPack (default channel)

1. Push this repo to GitHub.
2. Tag a release: `git tag 0.1.5 && git push origin 0.1.5`.
3. Trigger a build on [jitpack.io](https://jitpack.io) for the tag (or just let the first consumer request it).

`jitpack.yml` already pins JDK 17 and runs `publishToMavenLocal` for the two library modules:

```yaml
jdk:
  - openjdk17
install:
  - ./gradlew :core:publishToMavenLocal :compose:publishToMavenLocal
```

Consumers add JitPack and depend on the compose module (JitPack serves it under the `com.github.<user>.<repo>` group, keeping the published artifactId):

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

// module build.gradle.kts
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.5")
```

> The library's Maven `group` is set to `com.github.ccBiver.chartkit` (matching JitPack's coordinate) and the git **tag must equal the version** (`0.1.5`, no `v` prefix). This keeps the compose → core transitive dependency (`com.github.ccBiver.chartkit:chartkit-core:0.1.5`) resolvable on JitPack, so consumers declare only the compose artifact.

## Compose Multiplatform (`chartkit-kmp`)

The `:kmp` module publishes the Compose Multiplatform variant (Android / iOS / Desktop). KMP produces
one root module plus a per-target artifact, all under the same version:

```
chartkit-kmp            # root: Gradle Module Metadata (variant routing)
chartkit-kmp-android
chartkit-kmp-desktop
chartkit-kmp-iosx64 / -iosarm64 / -iossimulatorarm64
```

Consumers depend only on the root coordinate from `commonMain`; Gradle resolves the right target via metadata:

```kotlin
implementation("com.github.ccBiver.chartkit:chartkit-kmp:0.1.5")
```

- Test locally with `./gradlew :kmp:publishToMavenLocal` (then `mavenLocal()` in a consumer). All six
  coordinates above must appear under `~/.m2/.../com/github/ccBiver/chartkit/`.
- The artifactId base is renamed from the module name (`kmp`) to `chartkit-kmp` in the `:kmp` build's
  `afterEvaluate` publishing block (the Android publication is created late by AGP, hence `afterEvaluate`).
- **JitPack caveat:** resolving KMP **Gradle Module Metadata** (needed for the iOS/Desktop variants) from
  JitPack can be flaky — JitPack primarily serves plain Maven. The Android variant resolves like any AAR;
  the iOS/Desktop klibs rely on metadata. If a consumer can't resolve a non-Android target via JitPack,
  publish to Maven Central (below) instead, which fully supports KMP metadata.

## Maven Central (optional, formal)

Requires a Sonatype account, a verified namespace, and GPG signing:

- Change `group` to a namespace you own (e.g. `io.github.<user>`).
- Add the `signing` plugin and a Central publishing repository (or the `vanniktech` / `gradle-nexus` publish plugin).
- Supply signing keys + credentials via environment variables / `~/.gradle/gradle.properties` — never commit them.

## POM metadata

`url` / `scm` / `developers` in both `build.gradle.kts` files are set to `ccBiver` / `github.com/ccBiver/chartkit`. If you later publish to Maven Central, change `group` to a namespace you own (and adjust the coordinates accordingly).

## Local Maven mirrors (e.g. China) — keep them OUT of the repo

`settings.gradle.kts` intentionally uses **official repositories only** (`google()`, `mavenCentral()`,
`gradlePluginPortal()`, `jitpack`). Do **not** add China mirrors (aliyun/tencent) here: they are
unreachable from JitPack's overseas builders and intermittently return 502, which breaks the build
(this is what broke 0.1.3).

For fast local builds, put mirrors in a **global** `~/.gradle/init.gradle.kts` instead — it applies to all
your projects and never ships with the repo, so CI/JitPack stay on official sources:

```kotlin
// ~/.gradle/init.gradle.kts
val aliyunPublic = "https://maven.aliyun.com/repository/public"
val aliyunGoogle = "https://maven.aliyun.com/repository/google"
val aliyunGradlePlugin = "https://maven.aliyun.com/repository/gradle-plugin"
beforeSettings {
    pluginManagement.repositories {
        maven { url = uri(aliyunGradlePlugin) }
        maven { url = uri(aliyunPublic) }
        maven { url = uri(aliyunGoogle) }
    }
    @Suppress("UnstableApiUsage")
    dependencyResolutionManagement.repositories {
        maven { url = uri(aliyunPublic) }
        maven { url = uri(aliyunGoogle) }
    }
}
```

`beforeSettings` injects the mirrors *before* each project's `settings.gradle.kts`, so locally they take
priority; on CI the file is absent and resolution uses the official repos.

## Cutting a version

1. Bump `extra["chartkitVersion"]` in the root `build.gradle.kts`.
2. Move `CHANGELOG.md` `[Unreleased]` entries under the new version + date.
3. Commit, tag (`X.Y.Z` — must equal the version, no `v` prefix), push.
