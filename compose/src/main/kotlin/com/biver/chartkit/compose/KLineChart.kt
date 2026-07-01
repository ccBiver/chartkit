package com.biver.chartkit.compose

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculateCentroidSize
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.biver.chartkit.indicator.Indicator
import com.biver.chartkit.indicator.IndicatorSeries
import com.biver.chartkit.indicator.LineStyle
import com.biver.chartkit.model.Candle
import com.biver.chartkit.model.TimeFrame
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** 渲染期共享给手势的几何信息（命中测试 / 滚动钳制）。 */
private class ChartGeometry {
    var candleWidth = 0f
    var chartWidth = 0f
    var rightFloat = 0f      // 贴右边缘的数据索引（可为小数）
    var firstIndex = 0
    var lastIndex = 0
    var minOffset = 0f       // 滚动下界（<0 表示允许拖离右边缘留白）
    var maxOffset = 0f
    var mainBottom = 0f      // 主图底部 y（用于命中测试限定区域）
    fun centerX(i: Int): Float = chartWidth - (rightFloat - i + 0.5f) * candleWidth
}

/**
 * com.biver.chartkit 的 Compose K 线图。
 *
 * @param mainIndicators 主图叠加指标（MA/EMA/BOLL…），多条线随主题循环取色
 * @param subIndicators  副图指标，每个独立成一个窗格（MACD/KDJ/RSI…），加副图=往 list 里加一个
 */
@Composable
fun KLineChart(
    state: KLineChartState,
    modifier: Modifier = Modifier,
    theme: ChartTheme = ChartTheme.Dark,
    upDownColor: UpDownColor = UpDownColor.GreenUpRedDown,
    mode: ChartMode = ChartMode.Candle,
    mainIndicators: List<Indicator> = emptyList(),
    subIndicators: List<Indicator> = emptyList(),
    formatter: ChartFormatter = ChartFormatter.Default,
    entranceAnimation: Boolean = true,
    resetAnimation: Boolean = entranceAnimation,
    showVolume: Boolean = true,
    tradeMarks: List<TradeMark> = emptyList(),
    logo: Painter? = null,
    logoPosition: LogoPosition = LogoPosition.Center,
    logoAlpha: Float = 0.10f,
    logoHeight: Dp = 32.dp,
    showSkeleton: Boolean = true,
    /** 允许向左滑出的空白区域占图宽比例（0=禁用并贴右；类 Binance ~0.5 可把最新根拖离右边缘留白）。 */
    blankScrollRatio: Float = 0f,
    crosshairMode: CrosshairMode = CrosshairMode.Free,
    crosshairDismiss: CrosshairDismiss = CrosshairDismiss.Persistent,
    /** 现价标签取值方式：默认 [LastPriceMode.Latest]（恒取最新价，超出可见区时贴边，业内标准）。 */
    lastPriceMode: LastPriceMode = LastPriceMode.Latest,
    labels: ChartLabels = ChartLabels(),
    /** 自定义详情浮窗内容：给定聚焦 K 线返回任意「标签+数据」行；为空则用内置 OHLC 行。 */
    crosshairDetail: ((Candle) -> List<CrosshairDetailRow>)? = null,
    onToggleFullscreen: (() -> Unit)? = null,
    onLoadMore: () -> Unit = {},
    onCrosshairChange: (Candle?) -> Unit = {},
    onTradeMarkClick: (TradeMark) -> Unit = {},
) {
    val density = LocalDensity.current
    val dims = theme.dims

    // 副图进出场：保留正在收缩的旧副图（收缩完再移除），每格独立权重 0→1 长出 / 1→0 收缩
    val subScope = rememberCoroutineScope()
    val displayedSubs = remember { mutableStateListOf<Indicator>() }
    val subWeights = remember { mutableStateMapOf<String, Animatable<Float, AnimationVector1D>>() }
    LaunchedEffect(subIndicators.map { it.id }) {
        subIndicators.forEach { ind ->
            if (displayedSubs.none { it.id == ind.id }) displayedSubs.add(ind)
            val a = subWeights.getOrPut(ind.id) { Animatable(0f) }
            subScope.launch { a.animateTo(1f, tween(300)) }
        }
        val keepIds = subIndicators.map { it.id }.toSet()
        displayedSubs.filter { it.id !in keepIds }.forEach { ind ->
            subWeights[ind.id]?.let { a ->
                subScope.launch {
                    a.animateTo(0f, tween(300))  // 收缩完再从显示列表移除
                    displayedSubs.removeAll { it.id == ind.id }
                    subWeights.remove(ind.id)
                }
            }
        }
    }

    // 指标在后台线程（Default）计算，主线程零阻塞；末根更新/追加只增量重算末值（合并 tick），其余全量
    val mainCache = remember { IndicatorCache() }
    val subCache = remember { IndicatorCache() }
    val mainSeries: List<IndicatorSeries> by produceState(
        initialValue = emptyList(), state.dataVersion, mainIndicators
    ) {
        val data = state.candles
        value = withContext(Dispatchers.Default) {
            incrementalCompute(mainIndicators, data, mainCache.data, mainCache.series)
                .also { mainCache.data = data; mainCache.series = it }
        }
    }
    val subSeries: List<IndicatorSeries> by produceState(
        initialValue = emptyList(), state.dataVersion, displayedSubs.toList()
    ) {
        val data = state.candles
        val inds = displayedSubs.toList()
        value = withContext(Dispatchers.Default) {
            incrementalCompute(inds, data, subCache.data, subCache.series)
                .also { subCache.data = data; subCache.series = it }
        }
    }

    val geo = remember { ChartGeometry() }

    // 入场/换周期动画：首屏 0→1 从左往右展开；切周期(setData→resetVersion)时先往左收(1→0)再从左往右(0→1)。
    // 首屏由 [entranceAnimation] 控制；后续全量更新(RESET，如切周期)由 [resetAnimation] 独立控制，
    // 关掉后切周期直接切换、不再重播退出/进入动画。
    val entrance = remember { Animatable(if (entranceAnimation) 0f else 1f) }
    val firstReveal = remember { booleanArrayOf(true) }
    LaunchedEffect(state.resetVersion) {
        val isFirst = firstReveal[0]
        firstReveal[0] = false
        if (state.candles.isEmpty()) return@LaunchedEffect
        val animate = if (isFirst) entranceAnimation else resetAnimation
        if (!animate) {
            entrance.snapTo(1f)                                              // 直接完整显示，不播动画
            return@LaunchedEffect
        }
        if (entrance.value >= 1f) {
            entrance.animateTo(0f, tween(340, easing = FastOutSlowInEasing))  // 往左收 + 淡出
        } else {
            entrance.snapTo(0f)
        }
        entrance.animateTo(1f, tween(620, easing = FastOutSlowInEasing))      // 从左往右 + 淡入
    }

    // 分页节流：同一数据版本只触发一次 onLoadMore
    var loadMoreVersion by remember { mutableStateOf(-1) }

    // 多平台文本绘制（复用同一 TextMeasurer，逐帧测量结果由 Compose 内部缓存）。
    // 默认缓存仅 8 条，而每帧要测量的标签（网格价/右轴/副图图例/时间轴…）远多于此，
    // 缓存击穿会导致每帧重新排版——在 iOS（Kotlin/Native debug）上尤其卡，故放大缓存。
    val textMeasurer = rememberTextMeasurer(cacheSize = 64)
    val axisText = remember(textMeasurer, dims.axisTextSize) { ChartText(textMeasurer, dims.axisTextSize) }
    val axisTextPx = with(density) { dims.axisTextSize.toPx() }
    // 买卖标记字形（固定 10sp，居中、白色）
    val markText = remember(textMeasurer) { ChartText(textMeasurer, 10.sp) }
    val markTextPx = with(density) { 10.sp.toPx() }

    val mainPath = remember { Path() }
    val fillPath = remember { Path() }

    // 时间→索引（按数据版本缓存）：把买卖标记的时间落到所属 K 线
    val candleTimes = remember(state.dataVersion) {
        LongArray(state.candles.size) { state.candles[it].time }
    }
    fun indexForTime(t: Long): Int {
        if (candleTimes.isEmpty()) return -1
        if (t <= candleTimes.first()) return 0
        if (t >= candleTimes.last()) return candleTimes.lastIndex
        var lo = 0; var hi = candleTimes.lastIndex
        while (lo <= hi) {
            val m = (lo + hi) / 2
            when {
                candleTimes[m] == t -> return m
                candleTimes[m] < t -> lo = m + 1
                else -> hi = m - 1
            }
        }
        return hi.coerceIn(0, candleTimes.lastIndex) // 落在 hi 这根区间内
    }

    fun indexAtX(x: Float): Int {
        val idx = (geo.rightFloat - (geo.chartWidth - x) / geo.candleWidth).roundToInt()
        // 上界放宽到右边缘槽位，允许把十字光标移入右侧留白（虚拟索引 > lastIndex）
        val upper = ceil(geo.rightFloat).toInt().coerceAtLeast(state.candles.lastIndex.coerceAtLeast(0))
        return idx.coerceIn(0, upper)
    }

    // 骨架屏微光相位（仅在无数据、且 showSkeleton 时读取，故有数据后不触发重绘）
    val skeletonTransition = rememberInfiniteTransition(label = "skeleton")
    val skeletonPhase by skeletonTransition.animateFloat(
        initialValue = -0.2f, targetValue = 1.2f,
        animationSpec = infiniteRepeatable(tween(1300, easing = LinearEasing), RepeatMode.Restart),
        label = "skeletonPhase",
    )

    BoxWithConstraints(modifier) {
        val totalH = maxHeight
        // 副图图例独占顶部一行（不与指标线/柱重叠）：副图总高 = 指标绘图高 + 该行高
        val subLegendPx = with(density) { dims.subLegendHeight.toPx() }
        Canvas(
            modifier = Modifier
            .fillMaxSize()
            // 切周期/首屏：整图随入场值淡入淡出（收起时淡出、展开时淡入）。
            // 无数据时入场值停在 0（动画要等数据到来才跑），故此处强制不透明，否则骨架屏会被一起淡没。
            .graphicsLayer { alpha = if (state.candles.isEmpty()) 1f else entrance.value.coerceIn(0f, 1f) }
            .pointerInput(Unit) {
                // 带方向锁的平移/缩放：双指或水平为主时由图表处理并消费；
                // 垂直为主时整段手势让行，父级（页面）可正常上下滚动。
                awaitEachGesture {
                    var zoom = 1f
                    var pan = Offset.Zero
                    var pastSlop = false
                    var horizontal = false
                    val slop = viewConfiguration.touchSlop

                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.any { it.isConsumed }) break
                        val pointers = event.changes.count { it.pressed }
                        val zoomChange = event.calculateZoom()
                        val panChange = event.calculatePan()

                        if (!pastSlop) {
                            zoom *= zoomChange
                            pan += panChange
                            val centroidSize = event.calculateCentroidSize(useCurrent = false)
                            val zoomMotion = abs(1 - zoom) * centroidSize
                            if (zoomMotion > slop || pan.getDistance() > slop || pointers > 1) {
                                pastSlop = true
                                // 多指=缩放，或水平位移占主导 → 图表手势；否则纵向 → 让给父级
                                horizontal = pointers > 1 || abs(pan.x) >= abs(pan.y)
                                if (!horizontal) {
                                    if (state.crosshairIndex >= 0) { state.clearCrosshair(); onCrosshairChange(null) }
                                    return@awaitEachGesture
                                }
                            }
                        }

                        if (pastSlop && horizontal) {
                            if (state.crosshairIndex >= 0) {
                                // 常驻十字光标：拖动/缩放即消失，本次手势不滚动
                                state.clearCrosshair(); onCrosshairChange(null)
                            } else {
                                val centroid = event.calculateCentroid(useCurrent = true)
                                val old = state.candleWidthPx
                                if (zoomChange != 1f && old > 0f) {
                                    val cw = (old * zoomChange).coerceIn(
                                        with(density) { dims.candleMinWidth.toPx() },
                                        with(density) { dims.candleMaxWidth.toPx() },
                                    )
                                    if (cw != old) {
                                        // 围绕捏合焦点缩放：保持焦点下那根的屏幕位置不动
                                        val k = geo.chartWidth - centroid.x
                                        val ratio = cw / old
                                        state.markUserScrolled()
                                        state.scrollOffsetPx = ((state.scrollOffsetPx + k) * ratio - k)
                                            .coerceIn(geo.minOffset, geo.maxOffset)
                                        state.candleWidthPx = cw
                                    }
                                }
                                if (panChange.x != 0f) {
                                    state.markUserScrolled()
                                    state.scrollOffsetPx = (state.scrollOffsetPx + panChange.x)
                                        .coerceIn(geo.minOffset, geo.maxOffset)
                                }
                            }
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            }
            .pointerInput(Unit) {
                detectDragGesturesAfterLongPress(
                    onDragStart = { pos ->
                        state.crosshairIndex = indexAtX(pos.x)
                        state.crosshairX = pos.x; state.crosshairY = pos.y
                        onCrosshairChange(state.candles.getOrNull(state.crosshairIndex))
                    },
                    onDrag = { change, _ ->
                        change.consume()
                        state.crosshairIndex = indexAtX(change.position.x)
                        state.crosshairX = change.position.x; state.crosshairY = change.position.y
                        onCrosshairChange(state.candles.getOrNull(state.crosshairIndex))
                    },
                    // 松手：OnRelease 立即消失；Persistent 保留（由点击/拖动再消失）
                    onDragEnd = { if (crosshairDismiss == CrosshairDismiss.OnRelease) { state.clearCrosshair(); onCrosshairChange(null) } },
                    onDragCancel = { if (crosshairDismiss == CrosshairDismiss.OnRelease) { state.clearCrosshair(); onCrosshairChange(null) } },
                )
            }
            .pointerInput(crosshairDismiss, tradeMarks, state.dataVersion) {
                detectTapGestures(onTap = { pos ->
                    if (state.crosshairIndex >= 0) {
                        // 常驻浮窗显示时：点击空白处消失
                        state.clearCrosshair(); onCrosshairChange(null)
                    } else if (crosshairDismiss == CrosshairDismiss.OnRelease && tradeMarks.isNotEmpty()) {
                        // 松手即消失模式：点击蜡烛上的买卖标记 → 跳转
                        val cw = geo.candleWidth
                        if (cw > 0f) {
                            var best: TradeMark? = null
                            var bestDx = cw
                            tradeMarks.forEach { m ->
                                val idx = indexForTime(m.time)
                                if (idx in geo.firstIndex..geo.lastIndex) {
                                    val dx = abs(pos.x - geo.centerX(idx))
                                    if (dx < bestDx) { bestDx = dx; best = m }
                                }
                            }
                            best?.let(onTradeMarkClick)
                        }
                    }
                })
            }
    ) {
        // 背景
        drawRect(theme.background)
        val candles = state.candles
        if (candles.isEmpty()) {
            if (showSkeleton) {
                // 用当前配置的蜡烛宽度（缩放后）算根数与实体宽，骨架与真实图同一密度
                val skCw = if (state.candleWidthPx > 0f) state.candleWidthPx
                else with(density) { dims.candleDefaultWidth.toPx() }
                drawSkeleton(
                    theme, theme.upColor(upDownColor), theme.downColor(upDownColor),
                    skeletonPhase, skCw, dims.candleGapRatio, showVolume, subIndicators.size,
                )
            }
            return@Canvas
        }

        val bottomAxis = with(density) { dims.bottomAxisHeight.toPx() }
        val paneGap = with(density) { dims.paneGap.toPx() }
        val chartH = size.height - bottomAxis

        // 候选蜡烛宽（首帧用默认）——与 chartW 无关，提前算好供自适应右轴复用
        val cw = if (state.candleWidthPx > 0f) state.candleWidthPx
        else with(density) { dims.candleDefaultWidth.toPx() }.also { state.candleWidthPx = it }
        val labelPad = 4f

        // 给定右轴留白 cW 时的可见 K 线区间
        fun visibleRange(cW: Float): Pair<Int, Int> {
            val maxOff = max(0f, candles.size * cw - cW)
            val minOff = if (blankScrollRatio > 0f) -cW * blankScrollRatio.coerceAtMost(0.9f) else 0f
            val off = state.scrollOffsetPx.coerceIn(minOff, maxOff)
            val rf = candles.lastIndex - off / cw
            val fi = floor(rf - cW / cw).toInt().coerceIn(0, candles.lastIndex)
            val li = ceil(rf).toInt().coerceIn(0, candles.lastIndex)
            return fi to li
        }
        // 主图价格区间（含主指标线，避免裁切），返回已含 6% 上下留白的 (min, max)
        fun priceRange(fi: Int, li: Int): Pair<Double, Double> {
            var lo = Double.MAX_VALUE; var hi = -Double.MAX_VALUE
            for (i in fi..li) { lo = min(lo, candles[i].low); hi = max(hi, candles[i].high) }
            mainSeries.forEach { s ->
                s.lines.forEach { line ->
                    for (i in fi..li) line.values.getOrNull(i)?.let { lo = min(lo, it); hi = max(hi, it) }
                }
            }
            if (lo == Double.MAX_VALUE) { lo = 0.0; hi = 1.0 }
            if (hi - lo < 1e-9) hi = lo + 1.0
            val p = (hi - lo) * 0.06
            return (lo - p) to (hi + p)
        }

        // —— 自适应右轴留白：先用最小留白粗算可见价格区间，量出最宽价格标签，
        //    据此把右轴撑到「最长价格 + 内边距」，蜡烛区从此不会被价格标签压住。
        //    dims.rightAxisWidth 退化为下限；精度随币种变化（后台返回）也能自适应。——
        val rightAxisMin = with(density) { dims.rightAxisWidth.toPx() }
        val (rf0, rl0) = visibleRange(size.width - rightAxisMin)
        val (pmin0, pmax0) = priceRange(rf0, rl0)
        val widestLabel = max(axisText.measure(formatter.price(pmax0)), axisText.measure(formatter.price(pmin0)))
        val rightAxis = max(rightAxisMin, widestLabel + labelPad * 2f)
        val chartW = size.width - rightAxis

        // 窗格高度分配：主图 + (成交量) + 各副图。副图按各自动画权重分配（增长出/减收缩，互不挤压）
        val volH = if (showVolume) chartH * dims.volumePaneFraction else 0f
        val subWeightVals = displayedSubs.map { subWeights[it.id]?.value ?: 0f }
        val subUnits = subWeightVals.sum()
        val perSubFull = chartH * dims.subPaneFraction
        // 副图过多时整体缩放，避免挤掉主图
        val subScale = if (subUnits > 0f && perSubFull * subUnits > chartH * 0.5f) (chartH * 0.5f) / (perSubFull * subUnits) else 1f
        // 每格高 = 指标绘图高(perSubFull*subScale) + 图例行高(subLegendPx)，整体按动画权重伸缩
        val subPaneH = subWeightVals.map { (perSubFull * subScale + subLegendPx) * it }
        val subTotalH = subPaneH.sum() + paneGap * subUnits
        val mainH = chartH - volH - subTotalH
        val mainTop = 0f
        val mainBottom = mainTop + mainH
        val volTop = mainBottom + (if (showVolume) paneGap else 0f)
        val volBottom = volTop + (volH - if (showVolume) paneGap else 0f)

        val maxOffset = max(0f, candles.size * cw - chartW)
        // 允许向左滑出空白：scrollOffset 可降到负值，把最新根拖离右边缘留白
        val minOffset = if (blankScrollRatio > 0f) -chartW * blankScrollRatio.coerceAtMost(0.9f) else 0f
        val offset = state.scrollOffsetPx.coerceIn(minOffset, maxOffset)
        val rightFloat = candles.lastIndex - offset / cw

        // 可见区间
        val firstIdx = floor(rightFloat - chartW / cw).toInt().coerceIn(0, candles.lastIndex)
        val lastIdx = ceil(rightFloat).toInt().coerceIn(0, candles.lastIndex)

        // 暴露给手势
        geo.candleWidth = cw; geo.chartWidth = chartW; geo.rightFloat = rightFloat
        geo.firstIndex = firstIdx; geo.lastIndex = lastIdx
        geo.minOffset = minOffset; geo.maxOffset = maxOffset
        geo.mainBottom = mainBottom

        // 触发分页（接近最早数据）
        if (firstIdx <= 3 && offset >= maxOffset - cw * 3 && loadMoreVersion != state.dataVersion) {
            loadMoreVersion = state.dataVersion
            onLoadMore()
        }

        fun centerX(i: Int): Float = chartW - (rightFloat - i + 0.5f) * cw
        // 读数聚焦索引：长按十字光标时取命中根，否则取最新一根
        val focusIdx = if (state.crosshairIndex in candles.indices) state.crosshairIndex else candles.lastIndex

        // —— 主图价格区间（含主指标线，避免裁切；与自适应右轴同一算法）——
        val (pMin, pMax) = priceRange(firstIdx, lastIdx)
        fun yOf(p: Double, top: Float, bottom: Float, lo: Double, hi: Double): Float =
            top + ((hi - p) / (hi - lo) * (bottom - top)).toFloat()
        fun mainY(p: Double) = yOf(p, mainTop, mainBottom, pMin, pMax)
        // 主图 y → 价格（自由十字光标右轴价格反推）
        fun mainPrice(y: Float): Double = pMax - (y - mainTop) / (mainBottom - mainTop) * (pMax - pMin)

        // —— 右轴标签：以 y 为竖直中心绘制，上下对称留白（修正旧版底部无 padding）——
        val labelHalfH = axisText.lineHeight / 2f + axisTextPx * 0.3f
        fun drawRightLabel(yCenter: Float, text: String, bg: Color, fg: Color) {
            val tw = axisText.measure(text)
            val cy = yCenter.coerceIn(labelHalfH, chartH - labelHalfH)
            // 贴右边缘、宽度随文本自适应：文本右对齐（右内边距 labelPad），左内边距相同 → 左右对称；
            // 价格长时整体向左生长，右边缘恒在画布内，保证完整不被裁。
            val textLeft = size.width - labelPad - tw
            drawRoundRect(bg, Offset(textLeft - labelPad, cy - labelHalfH), Size(size.width - (textLeft - labelPad), labelHalfH * 2f), CornerRadius(5f, 5f))
            axisText.drawVCenterLeft(this, text, textLeft, cy, fg)
        }
        // —— 底轴标签：以 x 为中心绘制（十字光标时间）——
        fun drawBottomLabel(xCenter: Float, text: String, bg: Color, fg: Color) {
            val tw = axisText.measure(text)
            val halfW = tw / 2f + 8f
            val cx = xCenter.coerceIn(halfW, chartW - halfW)
            drawRoundRect(bg, Offset(cx - halfW, chartH + 1f), Size(halfW * 2f, size.height - (chartH + 1f)), CornerRadius(5f, 5f))
            val cy = (chartH + size.height) / 2f
            axisText.drawVCenterLeft(this, text, cx - tw / 2f, cy, fg)
        }
        // —— 浮动时间标签：以 (x, y) 为中心绘制（用于主图底部的十字光标时间）——
        fun drawTimeTag(xCenter: Float, yCenter: Float, text: String, bg: Color, fg: Color) {
            val tw = axisText.measure(text)
            val halfW = tw / 2f + 8f
            val cx = xCenter.coerceIn(halfW, chartW - halfW)
            drawRoundRect(bg, Offset(cx - halfW, yCenter - labelHalfH), Size(halfW * 2f, labelHalfH * 2f), CornerRadius(5f, 5f))
            axisText.drawVCenterLeft(this, text, cx - tw / 2f, yCenter, fg)
        }

        // 入场：从最左过渡到最右——只绘制到 revLast（随 ease 0→1 推进），价格区间用全量保证刻度不跳
        val ease = entrance.value
        val revLast = if (ease >= 1f) lastIdx
        else floor(rightFloat + 0.5f - chartW * (1f - ease) / cw).toInt().coerceIn(firstIdx - 1, lastIdx)

        // —— 网格 + 右侧价格刻度 ——
        for (r in 0..theme.gridRows) {
            val y = mainTop + (mainBottom - mainTop) * r / theme.gridRows
            drawLine(theme.grid, Offset(0f, y), Offset(chartW, y), 1f)
            val p = pMax - (pMax - pMin) * r / theme.gridRows
            val ps = formatter.price(p)
            axisText.drawBaselineLeft(this, ps, size.width - labelPad - axisText.measure(ps), y + axisTextPx / 3f, theme.axisText)
        }

        val up = theme.upColor(upDownColor)
        val down = theme.downColor(upDownColor)

        if (mode == ChartMode.TimeLine) {
            // 分时：收盘价折线 + 渐变填充（按 revLast 从左往右展开）
            mainPath.reset(); fillPath.reset()
            var started = false
            var lastX = 0f
            for (i in firstIdx..revLast) {
                val x = centerX(i); val y = mainY(candles[i].close); lastX = x
                if (!started) { mainPath.moveTo(x, y); fillPath.moveTo(x, mainBottom); fillPath.lineTo(x, y); started = true }
                else { mainPath.lineTo(x, y); fillPath.lineTo(x, y) }
            }
            if (started) {
                fillPath.lineTo(lastX, mainBottom); fillPath.close()
                drawPath(fillPath, theme.timeLineFillTop)
                drawPath(mainPath, theme.timeLineStroke, style = Stroke(width = 2f))
            }
        } else {
            // 蜡烛（按 revLast 从左往右展开）
            val bodyW = cw * (1f - dims.candleGapRatio)
            for (i in firstIdx..revLast) {
                val c = candles[i]
                val x = centerX(i)
                val color = if (c.isBullish) up else down
                val top = min(mainY(c.open), mainY(c.close))
                val bot = max(mainY(c.open), mainY(c.close))
                drawLine(color, Offset(x, mainY(c.high)), Offset(x, mainY(c.low)), 1.2f)
                drawRect(color, Offset(x - bodyW / 2f, top), androidx.compose.ui.geometry.Size(bodyW, max(1f, bot - top)))
            }
            // 主指标线（SAR 等散点用 Points 风格画圆点）
            mainSeries.forEach { s ->
                s.lines.forEachIndexed { li, line ->
                    val col = theme.indicatorColors[li % theme.indicatorColors.size]
                    if (line.style == LineStyle.Points) {
                        drawSeriesPoints(line.values, firstIdx, revLast, ::centerX, { mainY(it) }, col, cw)
                    } else {
                        drawSeriesLine(line.values, firstIdx, revLast, ::centerX, { mainY(it) }, col, 1f, mainPath)
                    }
                }
            }
        }

        // —— 买卖标记 overlay：圆角徽章 + 指向蜡烛的小三角（B 绿在下方、S 红在上方），对齐 Figma ——
        // 可见 K 线柱 > 50 时隐藏标记（避免密集杂乱），≤ 50 自动恢复
        if (tradeMarks.isNotEmpty() && (lastIdx - firstIdx + 1) <= dims.tradeMarkMaxVisibleBars) {
            val bw = with(density) { 16.dp.toPx() }
            val bh = with(density) { 14.dp.toPx() }
            val corner = with(density) { 2.dp.toPx() }
            val ptrW = with(density) { 2.dp.toPx() }   // 三角半宽（全宽 4）
            val ptrH = with(density) { 3.dp.toPx() }
            val gap = with(density) { 2.dp.toPx() }
            val tri = Path()
            tradeMarks.forEach { m ->
                val idx = indexForTime(m.time)
                if (idx in firstIdx..revLast) {
                    val c = candles[idx]
                    val x = centerX(idx)
                    val color = if (m.isBuy) up else down
                    tri.reset()
                    val badgeTop: Float
                    if (m.isBuy) {
                        val tipY = mainY(c.low) + gap          // 三角尖贴近蜡烛
                        badgeTop = tipY + ptrH
                        tri.moveTo(x - ptrW, badgeTop); tri.lineTo(x + ptrW, badgeTop); tri.lineTo(x, tipY); tri.close()
                    } else {
                        val tipY = mainY(c.high) - gap
                        val badgeBottom = tipY - ptrH
                        badgeTop = badgeBottom - bh
                        tri.moveTo(x - ptrW, badgeBottom); tri.lineTo(x + ptrW, badgeBottom); tri.lineTo(x, tipY); tri.close()
                    }
                    drawRoundRect(
                        color,
                        Offset(x - bw / 2f, badgeTop),
                        androidx.compose.ui.geometry.Size(bw, bh),
                        androidx.compose.ui.geometry.CornerRadius(corner, corner),
                    )
                    drawPath(tri, color)
                    val glyph = if (m.isBuy) "B" else "S"
                    markText.drawBaselineLeft(this, glyph, x - markText.measure(glyph) / 2f, badgeTop + bh / 2f + markTextPx / 3f, Color.White)
                }
            }
        }

        // —— 现价线 / 标签 ——（取值方式由 lastPriceMode 决定）
        when (lastPriceMode) {
            LastPriceMode.RightmostVisible -> {
                // 跟随屏幕最右可见根：值与颜色都随之，必落在可见价格区间内
                val rc = candles[lastIdx].close
                val y = mainY(rc)
                val col = if (candles[lastIdx].isBullish) up else down
                drawLine(
                    col, Offset(0f, y), Offset(chartW, y), 1f,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f))
                )
                drawRightLabel(y, formatter.price(rc), col, Color.White)
            }
            LastPriceMode.Latest -> {
                // 业内标准：恒取最新价；落在可见区内则画线+标签，否则标签贴上/下边缘 + ↑/↓ 箭头
                val last = candles.last()
                val col = if (last.isBullish) up else down
                val rawY = mainY(last.close)
                if (rawY in mainTop..mainBottom) {
                    drawLine(
                        col, Offset(0f, rawY), Offset(chartW, rawY), 1f,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f))
                    )
                    drawRightLabel(rawY, formatter.price(last.close), col, Color.White)
                } else {
                    // 现价在可见区外：标签贴主图上/下沿（不画线、不加箭头）
                    val edgeY = if (rawY < mainTop) mainTop + labelHalfH else mainBottom - labelHalfH
                    drawRightLabel(edgeY, formatter.price(last.close), col, Color.White)
                }
            }
        }

        // —— 成交量窗格 ——
        if (showVolume && volBottom > volTop) {
            var vMax = 0.0
            for (i in firstIdx..lastIdx) vMax = max(vMax, candles[i].volume)
            if (vMax <= 0.0) vMax = 1.0
            val bodyW = cw * (1f - dims.candleGapRatio)
            for (i in firstIdx..revLast) {
                val c = candles[i]
                val h = (c.volume / vMax * (volBottom - volTop)).toFloat()
                val color = (if (c.isBullish) up else down).copy(alpha = theme.volumeUpAlpha)
                drawRect(color, Offset(centerX(i) - bodyW / 2f, volBottom - h), androidx.compose.ui.geometry.Size(bodyW, h))
            }
            // 右轴量纲刻度（顶=峰值，底=0），右对齐贴右轴
            val vMaxStr = abbrevNum(vMax)
            axisText.drawBaselineLeft(this, vMaxStr, size.width - labelPad - axisText.measure(vMaxStr), volTop + axisTextPx, theme.axisText)
            axisText.drawBaselineLeft(this, "0", size.width - labelPad - axisText.measure("0"), volBottom - 3f, theme.axisText)
        }

        // —— 副图窗格（每格按动画权重分配高度；收缩中的副图保留数据直到高度归零）——
        // 间隙随权重缩放并算进 subTotalH，保证所有副图始终落在 chartH 内、不侵入底部时间轴
        var paneTop = volBottom
        for (p in displayedSubs.indices) {
            val w = subWeightVals.getOrElse(p) { 0f }
            val paneH = subPaneH.getOrElse(p) { 0f }
            paneTop += paneGap * w
            val top = paneTop
            val bottom = top + paneH
            paneTop = bottom
            if (paneH < 1f) continue
            // 按 id 取对应序列（而非下标）：删除/重算瞬间避免「新窗格配到旧数据」的错位闪烁
            val s = subSeries.firstOrNull { it.id == displayedSubs[p].id } ?: continue
            // 区间（柱含 0 基线）
            var lo = Double.MAX_VALUE; var hi = -Double.MAX_VALUE
            var hasHist = false
            s.lines.forEach { line ->
                if (line.style == LineStyle.Histogram) hasHist = true
                for (i in firstIdx..lastIdx) line.values.getOrNull(i)?.let { lo = min(lo, it); hi = max(hi, it) }
            }
            if (lo == Double.MAX_VALUE) { lo = 0.0; hi = 1.0 }
            if (hasHist) { lo = min(lo, 0.0); hi = max(hi, 0.0) }
            if (hi - lo < 1e-9) hi = lo + 1.0
            // 内容按「稳定态完整高度 fullH」映射，再裁剪到当前可见高度：增/减时从头到脚显隐，而非压扁
            // 顶部留出 subLegendPx 作为图例独占行，指标绘图区从 contentTop 起算（数值不再与指标重叠）
            val fullH = perSubFull * subScale
            val contentTop = top + subLegendPx
            val visBottom = top + paneH
            fun subY(v: Double) = yOf(v, contentTop, contentTop + fullH, lo, hi)
            clipRect(0f, top, size.width, visBottom) {
                drawLine(theme.grid, Offset(0f, top), Offset(chartW, top), 1f)
                // 右轴刻度（顶=hi，底=lo），右对齐贴右轴（对齐指标绘图区，非图例行）
                val hiStr = formatter.price(hi)
                val loStr = formatter.price(lo)
                axisText.drawBaselineLeft(this, hiStr, size.width - labelPad - axisText.measure(hiStr), contentTop + axisTextPx, theme.axisText)
                axisText.drawBaselineLeft(this, loStr, size.width - labelPad - axisText.measure(loStr), contentTop + fullH - 3f, theme.axisText)
                val bodyW = cw * (1f - dims.candleGapRatio)
                s.lines.forEachIndexed { li, line ->
                    if (line.style == LineStyle.Histogram) {
                        val zeroY = subY(0.0)
                        for (i in firstIdx..revLast) {
                            val v = line.values.getOrNull(i) ?: continue
                            val y = subY(v)
                            val color = (if (v >= 0) up else down).copy(alpha = 0.8f)
                            drawRect(color, Offset(centerX(i) - bodyW / 2f, min(zeroY, y)), androidx.compose.ui.geometry.Size(bodyW, abs(y - zeroY)))
                        }
                    } else if (line.style == LineStyle.Points) {
                        val col = theme.indicatorColors[li % theme.indicatorColors.size]
                        drawSeriesPoints(line.values, firstIdx, revLast, ::centerX, { subY(it) }, col, cw)
                    } else {
                        val col = theme.indicatorColors[li % theme.indicatorColors.size]
                        drawSeriesLine(line.values, firstIdx, revLast, ::centerX, { subY(it) }, col, 1f, mainPath)
                    }
                }
                // 副图读数标签（聚焦根的各线当前值，按线着色）：绘制在顶部独占的图例行内，垂直居中，不与指标重叠
                val legendBaseline = top + subLegendPx / 2f + axisTextPx / 3f
                var lx = 6f
                s.lines.forEachIndexed { li, line ->
                    val col = theme.indicatorColors[li % theme.indicatorColors.size]
                    val vTxt = line.values.getOrNull(focusIdx)?.let { formatter.price(it) } ?: "--"
                    val txt = "${line.name} $vTxt"
                    axisText.drawBaselineLeft(this, txt, lx, legendBaseline, col)
                    lx += axisText.measure(txt) + 12f
                }
            }
        }

        // —— 底部时间轴作为独立层：先用背景盖住可能溢出到此区域的内容（副图收缩瞬间），再画时间 ——
        drawRect(theme.background, Offset(0f, chartH), androidx.compose.ui.geometry.Size(size.width, size.height - chartH))

        // —— 时间轴：按像素间距均匀放刻度，锚定到 step 整数倍（拖动时平滑、不挤在一起）——
        run {
            val labelW = axisText.measure(formatter.time(candles[lastIdx].time, state.timeFrame))
            // 间距取「标签宽 + 间隙」与「图宽/3」的较大者 → 一屏最多 3 个、且不重叠
            val minGap = max(labelW + 24f, chartW / 3f)
            val step = max(1, ceil(minGap / cw).toInt())
            val fadeMargin = 70f  // 距边缘多少像素内做淡入淡出
            var i = (firstIdx / step) * step
            if (i < firstIdx) i += step
            while (i <= lastIdx) {
                val label = formatter.time(candles[i].time, state.timeFrame)
                val w = axisText.measure(label)
                val tx = centerX(i) - w / 2f
                // 按距左右边缘的余量做透明度过渡：靠边→透明，进入→不透明（拖动时平滑淡入淡出）
                val room = min(tx, chartW - (tx + w))
                val a = (1f + room / fadeMargin).coerceIn(0f, 1f)
                if (a > 0.02f) {
                    axisText.drawBaselineLeft(this, label, tx, size.height - 4f, theme.axisText, alpha = a)
                }
                i += step
            }
        }

        // —— 十字光标（含右侧留白：虚拟索引 > lastIndex 时无 K 线，跟手指 + 外推时间）——
        val ci = state.crosshairIndex
        val rightSlot = ceil(rightFloat).toInt()
        if (ci in firstIdx..rightSlot) {
            val x = centerX(ci)
            val c = candles.getOrNull(ci)
            // 无 K 线（留白区）或自由模式：水平线跟手指；否则吸附收盘价
            val useFinger = (c == null || crosshairMode == CrosshairMode.Free) && state.crosshairY >= 0f
            val hy = when {
                useFinger -> state.crosshairY.coerceIn(0f, chartH)
                c != null -> mainY(c.close)
                else -> mainBottom
            }
            drawLine(theme.crosshair, Offset(x, 0f), Offset(x, chartH), 1f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
            drawLine(theme.crosshair, Offset(0f, hy), Offset(chartW, hy), 1f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
            // 右轴价格标签：跟手指→手指处价格（仅主图区内）；吸附→收盘价
            if (useFinger) {
                if (hy <= mainBottom) {
                    drawRightLabel(hy, formatter.price(mainPrice(hy.coerceIn(mainTop, mainBottom))), theme.crosshairLabelBg, theme.crosshairLabelText)
                }
            } else if (c != null) {
                drawRightLabel(hy, formatter.price(c.close), theme.crosshairLabelBg, theme.crosshairLabelText)
            }
            // 底轴时间标签：留白区按周期外推（lastTime + (ci-lastIndex)*周期毫秒）
            // 留白区无 K 线：按数据自身的每根间隔外推时间（不依赖 host 设 timeFrame）
            val barMs = if (candles.size >= 2)
                (candles.last().time - candles[candles.size - 2].time).coerceAtLeast(1L)
            else state.timeFrame.millis
            val t = c?.time ?: (candles.last().time + (ci - candles.lastIndex).toLong() * barMs)
            val timeStr = formatter.crosshairTime(t, state.timeFrame)
            drawBottomLabel(x, timeStr, theme.crosshairLabelBg, theme.crosshairLabelText)
            // 有副图时，主图底沿再放一个时间标签，避免还要跑到最底部时间轴去对照
            if (displayedSubs.isNotEmpty()) {
                drawTimeTag(x, mainBottom, timeStr, theme.crosshairLabelBg, theme.crosshairLabelText)
            }
        }
        }

        // —— 主图指标读数图例（滚动数字；仅数据/光标变化时重组，不闪烁）——
        if (state.candles.isNotEmpty() && mainSeries.isNotEmpty()) {
            val fi = state.crosshairIndex.let { if (it in state.candles.indices) it else state.candles.lastIndex }
            val crosshair = state.crosshairIndex in state.candles.indices
            // 每个主图指标占一行（如 MA 一行、EMA 一行），行内是该指标的各条线
            Column(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 8.dp, top = 3.dp, end = 8.dp),
                verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                mainSeries.forEach { s ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        s.lines.forEachIndexed { li, line ->
                            line.values.getOrNull(fi)?.let { v ->
                                LegendItem(
                                    name = line.name,
                                    value = v,
                                    color = theme.indicatorColors[li % theme.indicatorColors.size],
                                    fmt = formatter.price,
                                    animate = !crosshair,
                                    fontSize = dims.legendTextSize,
                                )
                            }
                        }
                    }
                }
            }
        }

        // —— 十字光标详情浮窗：内容可由 crosshairDetail 自定义，否则内置 OHLC；放手指对侧避免遮挡 ——
        if (state.crosshairIndex in state.candles.indices) {
            val c = state.candles[state.crosshairIndex]
            val ci = state.crosshairIndex
            val baseRows = crosshairDetail?.invoke(c)
                ?: defaultCrosshairRows(c, formatter, labels, theme, upDownColor, state.timeFrame)
            // 该根若有买卖记录，浮窗底部追加可点击的买/卖行（点击 → onTradeMarkClick 跳转）
            val markRows = tradeMarks.filter { indexForTime(it.time) == ci }.map { m ->
                val col = if (m.isBuy) theme.upColor(upDownColor) else theme.downColor(upDownColor)
                val priceStr = m.price?.let { formatter.price(it) } ?: ""
                val countStr = m.count?.let { " ($it)" } ?: ""   // 最近一笔单价(成交笔数)
                CrosshairDetailRow(
                    label = if (m.isBuy) labels.buy else labels.sell,
                    value = priceStr + countStr,
                    color = col,
                    labelColor = col,                 // 买/卖标签也用涨跌色
                    // 常驻模式下浮窗行可点击跳转（带箭头）；松手即消失模式则不可点（改点蜡烛标记）
                    onClick = if (crosshairDismiss == CrosshairDismiss.Persistent) ({ onTradeMarkClick(m) }) else null,
                )
            }
            val rows = baseRows + markRows
            val halfPx = with(density) { maxWidth.toPx() } / 2f
            val fingerOnLeft = state.crosshairX in 0f..halfPx
            CrosshairPanel(
                rows = rows,
                theme = theme,
                modifier = Modifier
                    .align(if (fingerOnLeft) Alignment.TopEnd else Alignment.TopStart)
                    .padding(top = 18.dp, start = 8.dp, end = 8.dp),
            )
        }

        // 主图底部 y（dp）：水印 / 全屏按钮共用。
        // 用与渲染层同一套公式（含副图动画权重 subWeights 与整体收缩 subScale），
        // 把水印稳稳钉在主图区中心——增删副图时随主图平滑移动，不再因「参数 vs 动画」不同步而跳动。
        val chartHDp = totalH - dims.bottomAxisHeight
        val volFrac = if (showVolume) dims.volumePaneFraction else 0f
        val logoSubUnits = displayedSubs.fold(0f) { acc, ind -> acc + (subWeights[ind.id]?.value ?: 0f) }
        val logoSubScale = if (logoSubUnits > 0f && dims.subPaneFraction * logoSubUnits > 0.5f)
            0.5f / (dims.subPaneFraction * logoSubUnits) else 1f
        // 与渲染层一致：每格高含图例行 subLegendHeight，故按权重计入
        val logoSubTotalDp = chartHDp * (dims.subPaneFraction * logoSubScale * logoSubUnits) +
            (dims.paneGap + dims.subLegendHeight) * logoSubUnits
        val mainBottomDp = chartHDp * (1f - volFrac) - logoSubTotalDp

        // —— Logo 水印：默认主图中心（类 Binance），位置 + 透明度可设 ——
        logo?.let { painter ->
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
                    .height(mainBottomDp),
                contentAlignment = logoPosition.toAlignment(),
            ) {
                Image(
                    painter = painter,
                    contentDescription = null,
                    alpha = logoAlpha.coerceIn(0f, 1f),
                    modifier = Modifier
                        .padding(12.dp)
                        .height(logoHeight)
                )
            }
        }

        // —— 主图左下角全屏按钮 ——
        if (onToggleFullscreen != null) {
            FullscreenGlyph(
                color = theme.axisText,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(x = 8.dp, y = mainBottomDp - 20.dp)
                    .size(14.dp)
                    .clickable { onToggleFullscreen() }
            )
        }
    }
}
