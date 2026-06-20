// Top-level build file for the chartkit open-source library.
plugins {
    id("com.android.application") version "8.9.0" apply false
    id("com.android.library") version "8.9.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.10" apply false
    id("org.jetbrains.kotlin.jvm") version "2.1.10" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.10" apply false
}

// Single source of truth for the published library version (shared by :core and :compose).
extra["chartkitVersion"] = "0.1.1"
