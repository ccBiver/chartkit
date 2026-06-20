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
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.0")
```

## Release via JitPack (default channel)

1. Push this repo to GitHub.
2. Tag a release: `git tag 0.1.0 && git push origin 0.1.0`.
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
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.0")
```

> The library's Maven `group` is set to `com.github.ccBiver.chartkit` (matching JitPack's coordinate) and the git **tag must equal the version** (`0.1.0`, no `v` prefix). This keeps the compose → core transitive dependency (`com.github.ccBiver.chartkit:chartkit-core:0.1.0`) resolvable on JitPack, so consumers declare only the compose artifact.

## Maven Central (optional, formal)

Requires a Sonatype account, a verified namespace, and GPG signing:

- Change `group` to a namespace you own (e.g. `io.github.<user>`).
- Add the `signing` plugin and a Central publishing repository (or the `vanniktech` / `gradle-nexus` publish plugin).
- Supply signing keys + credentials via environment variables / `~/.gradle/gradle.properties` — never commit them.

## POM metadata

`url` / `scm` / `developers` in both `build.gradle.kts` files are set to `ccBiver` / `github.com/ccBiver/chartkit`. If you later publish to Maven Central, change `group` to a namespace you own (and adjust the coordinates accordingly).

## Cutting a version

1. Bump `extra["chartkitVersion"]` in the root `build.gradle.kts`.
2. Move `CHANGELOG.md` `[Unreleased]` entries under the new version + date.
3. Commit, tag (`X.Y.Z` — must equal the version, no `v` prefix), push.
