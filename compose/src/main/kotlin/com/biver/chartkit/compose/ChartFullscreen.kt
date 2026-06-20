package com.biver.chartkit.compose

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.annotation.DrawableRes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.biver.chartkit.indicator.Indicator
import com.biver.chartkit.model.Candle
import com.biver.chartkit.model.TimeFrame
import kotlinx.coroutines.flow.Flow

/**
 * 全屏 K 线配置：同进程内存交接（避免把大数组放进 Intent）。
 * 像配置 [KLineChart] 一样填这些字段，再调用 [Context.launchChartFullscreen] 即可横屏全屏展示。
 * 注意：当前为快照展示，不接 live tick（如需实时再扩展）。
 */
object ChartFullscreenConfig {
    var candles: List<Candle> = emptyList()
    var timeFrame: TimeFrame = TimeFrame.M15
    var theme: ChartTheme = ChartTheme.Dark
    var upDownColor: UpDownColor = UpDownColor.GreenUpRedDown
    var mode: ChartMode = ChartMode.Candle
    var mainIndicators: List<Indicator> = emptyList()
    var subIndicators: List<Indicator> = emptyList()
    var formatter: ChartFormatter = ChartFormatter.Default
    var tradeMarks: List<TradeMark> = emptyList()
    var showVolume: Boolean = true
    var blankScrollRatio: Float = 0.5f
    var crosshairMode: CrosshairMode = CrosshairMode.Free
    var labels: ChartLabels = ChartLabels()
    var crosshairDetail: ((Candle) -> List<CrosshairDetailRow>)? = null
    var onTradeMarkClick: (TradeMark) -> Unit = {}
    @DrawableRes var logoRes: Int = 0
    var logoPosition: LogoPosition = LogoPosition.Center
    var logoAlpha: Float = 0.10f
    /** 实时 tick：全屏期间增量喂入最新一根（同 [KLineChart] 的 tick）。 */
    var tick: Flow<Candle>? = null
    /** 全屏关闭回调（宿主用于恢复行情订阅等）。 */
    var onClose: () -> Unit = {}
}

/** 填好 [ChartFullscreenConfig] 后横屏全屏展示 K 线。 */
fun Context.launchChartFullscreen(configure: ChartFullscreenConfig.() -> Unit) {
    ChartFullscreenConfig.configure()
    startActivity(Intent(this, ChartFullscreenActivity::class.java))
}

/** 横屏全屏看 K 线（读取 [ChartFullscreenConfig]）；manifest 中固定 landscape。 */
class ChartFullscreenActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 沉浸式：隐藏状态栏 + 导航栏，上滑临时唤出
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        setContent {
            val cfg = ChartFullscreenConfig
            val state = rememberKLineChartState(cfg.timeFrame)
            LaunchedEffect(Unit) { state.setData(cfg.candles) }
            // 实时 tick 直喂全屏图
            LaunchedEffect(Unit) { cfg.tick?.collect { state.appendOrUpdate(it) } }
            // 关闭时通知宿主（恢复订阅等）
            DisposableEffect(Unit) { onDispose { cfg.onClose() } }
            Box(modifier = Modifier.fillMaxSize().background(cfg.theme.background)) {
                KLineChart(
                    state = state,
                    modifier = Modifier.fillMaxSize().padding(8.dp),
                    theme = cfg.theme,
                    upDownColor = cfg.upDownColor,
                    mode = cfg.mode,
                    mainIndicators = cfg.mainIndicators,
                    subIndicators = cfg.subIndicators,
                    formatter = cfg.formatter,
                    showVolume = cfg.showVolume,
                    tradeMarks = cfg.tradeMarks,
                    logo = if (cfg.logoRes != 0) painterResource(cfg.logoRes) else null,
                    logoPosition = cfg.logoPosition,
                    logoAlpha = cfg.logoAlpha,
                    blankScrollRatio = cfg.blankScrollRatio,
                    crosshairMode = cfg.crosshairMode,
                    labels = cfg.labels,
                    crosshairDetail = cfg.crosshairDetail,
                    onTradeMarkClick = cfg.onTradeMarkClick,
                )
                // 关闭按钮：圆形半透明底，浮在右上角（明确是按钮、不与右轴数字糊在一起）
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(10.dp)
                        .size(28.dp)
                        .background(cfg.theme.axisText.copy(alpha = 0.18f), CircleShape)
                        .clickable { finish() },
                    contentAlignment = Alignment.Center,
                ) {
                    CloseGlyph(color = cfg.theme.axisText, modifier = Modifier.size(13.dp))
                }
            }
        }
    }
}

/** 关闭按钮图标：叉号（自绘，无需图片资源）。 */
@Composable
private fun CloseGlyph(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val s = size.minDimension
        val w = (s * 0.10f).coerceAtLeast(2f)
        drawLine(color, Offset(0f, 0f), Offset(s, s), w)
        drawLine(color, Offset(s, 0f), Offset(0f, s), w)
    }
}
