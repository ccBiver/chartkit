package com.biver.chartkit.demoapp

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "chartkit KMP demo",
        state = rememberWindowState(width = 440.dp, height = 880.dp),
    ) {
        App()
    }
}
