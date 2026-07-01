// Top-level build file for the chartkit open-source library.
plugins {
    id("com.android.application") version "8.9.0" apply false
    id("com.android.library") version "8.9.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.10" apply false
    id("org.jetbrains.kotlin.jvm") version "2.1.10" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.10" apply false
    // KMP variant (new :kmp module → artifact chartkit-kmp). Existing Android modules unaffected.
    id("org.jetbrains.kotlin.multiplatform") version "2.1.10" apply false
    id("org.jetbrains.compose") version "1.7.3" apply false
}

// Single source of truth for the published library version (shared by :core, :compose and :kmp).
extra["chartkitVersion"] = "0.1.8"
