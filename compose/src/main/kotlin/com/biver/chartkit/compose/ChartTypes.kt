package com.biver.chartkit.compose

import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color

/**
 * 买卖标记（覆盖物）。[time] 对齐到所属 K 线的开盘时间（或落在该根区间内即可）。
 * 买入标记画在 K 线下方、卖出画在上方，可在详情浮窗里点击跳转。
 */
data class TradeMark(
    val time: Long,
    val isBuy: Boolean,
    val price: Double? = null,
    val count: Int? = null,   // 该 K 线该方向的成交笔数
)

/** Logo 水印位置（默认主图中心，类 Binance 水印）。 */
enum class LogoPosition { Center, TopStart, TopEnd, BottomStart, BottomEnd }

/** 十字光标 Y 轴行为：[SnapToClose] 吸附到收盘价；[Free] 跟随手指自由移动（右轴显示手指处价格）。 */
enum class CrosshairMode { SnapToClose, Free }

/** 现价线/标签的取值方式。 */
enum class LastPriceMode {
    /**
     * 业内标准（TradingView/Binance/OKX）：恒取**最新成交价**（数据最后一根的收盘价），与滚动位置无关。
     * 当最新一根滑出屏幕、且现价落在可见价格区间之外时，标签贴到图表上/下边缘（不消失、不跳动）。
     */
    Latest,

    /** 跟随**当前屏幕最右边那根可见 K 线**的收盘价：值与颜色都随之，横向滚动时上下移动。 */
    RightmostVisible,
}

/**
 * 十字光标/详情浮窗的消失方式：
 *  - [OnRelease] 松手即消失（长按期间显示）。此时浮窗内买卖行不可点击/无箭头，改为点击蜡烛上的标记跳转。
 *  - [Persistent] 松手不消失，点击空白或拖动/缩放图表才消失。此时浮窗买卖行可点击跳转（带箭头）。
 */
enum class CrosshairDismiss { OnRelease, Persistent }

/** 十字光标详情浮窗的字段标签（可本地化覆盖；默认英文缩写，开源友好）。 */
data class ChartLabels(
    val time: String = "Time",
    val open: String = "O",
    val high: String = "H",
    val low: String = "L",
    val close: String = "C",
    val change: String = "Chg",
    val changePct: String = "Chg%",
    val amplitude: String = "Amp",
    val volume: String = "Vol",
    val turnover: String = "Turnover",
    val buy: String = "Buy",
    val sell: String = "Sell",
)

/** 详情浮窗的一行：标签 + 数据，[color] 为空则用默认文字色（涨跌等可指定颜色）。[onClick] 非空则该行可点击（如买卖记录跳转）。 */
data class CrosshairDetailRow(
    val label: String,
    val value: String,
    val color: Color? = null,
    val labelColor: Color? = null,
    val onClick: (() -> Unit)? = null,
)

internal fun LogoPosition.toAlignment(): Alignment = when (this) {
    LogoPosition.Center -> Alignment.Center
    LogoPosition.TopStart -> Alignment.TopStart
    LogoPosition.TopEnd -> Alignment.TopEnd
    LogoPosition.BottomStart -> Alignment.BottomStart
    LogoPosition.BottomEnd -> Alignment.BottomEnd
}
