# Publishing chartkit

chartkit publishes three library artifacts (version from `chartkitVersion` in the root `build.gradle.kts`):

| Module | artifactId | Type | Channel |
|---|---|---|---|
| `:core` | `chartkit-core` | JVM jar (+ sources) | JitPack (`com.github.ccBiver.chartkit`) |
| `:compose` | `chartkit-compose` | Android AAR (+ sources) | JitPack (`com.github.ccBiver.chartkit`) |
| `:kmp` | `chartkit-kmp` | Compose Multiplatform (Android/iOS/Desktop) | **Maven Central** (`io.github.ccbiver`) |

`chartkit-compose` declares an `api` dependency on `chartkit-core`, so consumers only need the compose artifact. The `:demo` app is **not** published. The KMP variant `chartkit-kmp` is self-contained (it inlines the `:core` + `:compose` sources via `srcDir`) and ships on Maven Central because its iOS klibs cannot be built on JitPack — see [Compose Multiplatform (`chartkit-kmp`) → Maven Central](#compose-multiplatform-chartkit-kmp--maven-central).

## Verify locally

```bash
./gradlew :core:publishToMavenLocal :compose:publishToMavenLocal
```

Then, in a project with `mavenLocal()` in its repositories:

```kotlin
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.7")
```

## Release via JitPack (default channel)

1. Push this repo to GitHub.
2. Tag a release: `git tag 0.1.7 && git push origin 0.1.7`.
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
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.7")
```

> The library's Maven `group` is set to `com.github.ccBiver.chartkit` (matching JitPack's coordinate) and the git **tag must equal the version** (`0.1.7`, no `v` prefix). This keeps the compose → core transitive dependency (`com.github.ccBiver.chartkit:chartkit-core:0.1.7`) resolvable on JitPack, so consumers declare only the compose artifact.

## Compose Multiplatform (`chartkit-kmp`) → Maven Central

> **Why not JitPack?** JitPack's build machines are **Linux-only**, and Kotlin/Native **Apple targets
> (iosX64 / iosArm64 / iosSimulatorArm64) can only be compiled on macOS**. So JitPack *structurally
> cannot* produce the iOS klibs — the 404 / timeout / empty-metadata symptoms for `chartkit-kmp` on
> JitPack are not "flaky", they are a hard limitation. The Compose Multiplatform variant therefore
> ships via **Maven Central**, published from a Mac. (`:core` / `:compose` remain fine on JitPack —
> they are Android/JVM only.)

The `:kmp` module publishes via the **`com.vanniktech.maven.publish`** plugin under the namespace
`io.github.ccbiver`. KMP produces one root module plus a per-target artifact, all under the same version:

```
chartkit-kmp            # root: Gradle Module Metadata (variant routing)
chartkit-kmp-android
chartkit-kmp-desktop
chartkit-kmp-iosx64 / -iosarm64 / -iossimulatorarm64
```

### Consume

Consumers depend only on the root coordinate from `commonMain`; Gradle resolves the right target via
the published `.module` metadata. Add `mavenCentral()` (already standard) — no JitPack needed for KMP:

```kotlin
implementation("io.github.ccbiver:chartkit-kmp:0.1.7")
```

### Verify locally (no keys needed)

```bash
./gradlew :kmp:publishToMavenLocal
# All six coordinates land under ~/.m2/.../io/github/ccbiver/ ; confirm the iOS variants:
grep -ioE "iosX64|iosArm64|iosSimulatorArm64" \
  ~/.m2/repository/io/github/ccbiver/chartkit-kmp/0.1.7/chartkit-kmp-0.1.7.module | sort -u
```

A consumer on the **same machine** can use this immediately via `mavenLocal()`.

### Publish to Maven Central

One-time setup:

1. **Sonatype Central account** at <https://central.sonatype.com>; verify the `io.github.ccbiver`
   namespace (it issues a TXT/repo challenge tied to the `ccBiver` GitHub account). Generate a
   **user token** (username + password) under *Account → Generate User Token*.
2. **GPG key** for signing: `gpg --gen-key`, publish the public key to a keyserver
   (`gpg --keyserver keyserver.ubuntu.com --send-keys <KEYID>`), and export the **ASCII-armored secret
   key**: `gpg --armor --export-secret-keys <KEYID>`.

Supply credentials **out-of-band — never commit them** (use `~/.gradle/gradle.properties` or env vars):

```properties
# ~/.gradle/gradle.properties  (global, outside the repo)
mavenCentralUsername=<central-portal-token-username>
mavenCentralPassword=<central-portal-token-password>
signingInMemoryKey=-----BEGIN PGP PRIVATE KEY BLOCK-----\n...\n-----END...   # or via env
signingInMemoryKeyPassword=<gpg-key-passphrase>
```

Then publish + auto-release:

```bash
./gradlew :kmp:publishAndReleaseToMavenCentral --no-configuration-cache
```

- Signing is **conditional**: the build only signs when `signingInMemoryKey` is present, so the local
  `publishToMavenLocal` verification runs key-free while the real Central publish always signs (Central
  rejects unsigned uploads).
- The artifactId is set to `chartkit-kmp` via `mavenPublishing { coordinates(...) }`; vanniktech
  auto-configures all KMP publications (root metadata + every target) and the required sources/javadoc jars.

## POM metadata

`url` / `scm` / `developers` are set to `ccBiver` / `github.com/ccBiver/chartkit` across the modules. `:core` / `:compose` keep the JitPack group `com.github.ccBiver.chartkit`; `:kmp` uses the owned Maven Central namespace `io.github.ccbiver` (configured in `kmp/build.gradle.kts` via `mavenPublishing { coordinates(...) }`).

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
