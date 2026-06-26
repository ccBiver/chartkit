package com.biver.chartkit.demoapp

import androidx.compose.ui.window.ComposeUIViewController
import platform.UIKit.UIViewController

/** iOS 入口：被 iosApp 的 Swift 端通过 framework 调用，承载共享的 [App]。 */
fun MainViewController(): UIViewController = ComposeUIViewController { App() }
