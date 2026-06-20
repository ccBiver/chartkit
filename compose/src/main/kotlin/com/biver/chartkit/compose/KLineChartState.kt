package com.biver.chartkit.compose

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.biver.chartkit.model.Candle
import com.biver.chartkit.model.TimeFrame

/**
 * K 线数据更新类型——宿主用此常量驱动图，无需关心内部 setData/appendOrUpdate/prepend：
 *  - [RESET]  全量替换（首次加载、切周期）
 *  - [LATEST] 更新最新一根（实时 tick：同周期替换末根，跨周期追加）
 *  - [MORE]   加载更多更早数据（头部插入，保持当前可视位置不跳）
 */
enum class KLineUpdate { RESET, LATEST, MORE }

/**
 * 图表状态宿主（状态上提）。持有数据、可见视口、十字光标索引。
 * 业务方通过 [setData]/[appendOrUpdate]/[prepend] 驱动；KLineChart 读取并渲染。
 *
 * 视口用「每根像素宽 [candleWidthPx]」+「右端锚定的可见根数」表达：
 *  - [scrollOffsetPx] 为相对最新一根的横向偏移（>0 表示向历史方向拖动）。
 */
@Stable
class KLineChartState(
    timeFrame: TimeFrame = TimeFrame.M15,
) {
    var timeFrame: TimeFrame by mutableStateOf(timeFrame)
        private set

    /** 当前全部 K 线（不可变 list 引用；替换引用即触发重组）。 */
    var candles: List<Candle> by mutableStateOf(emptyList())
        private set

    /** 单根像素宽（含间隙），由缩放手势改变。0 表示用主题默认值首帧初始化。 */
    var candleWidthPx: Float by mutableStateOf(0f)

    /** 横向滚动偏移（像素，>=0；0=贴最新）。 */
    var scrollOffsetPx: Float by mutableStateOf(0f)

    /** 十字光标命中的数据索引；-1 表示无。 */
    var crosshairIndex: Int by mutableIntStateOf(-1)

    /** 十字光标手指像素位置（用于自由模式下的水平线 / 价格反推、详情浮窗定位）；-1 表示无。 */
    var crosshairX: Float by mutableStateOf(-1f)
    var crosshairY: Float by mutableStateOf(-1f)

    /** 清除十字光标（命中索引 + 手指位置）。 */
    fun clearCrosshair() {
        crosshairIndex = -1
        crosshairX = -1f
        crosshairY = -1f
    }

    /** 数据版本号：每次数据变化自增，用于指标缓存失效判断。 */
    var dataVersion: Int by mutableIntStateOf(0)
        private set

    /** 全量替换版本号：仅 [setData] 自增，用于触发「换周期重播入场动画」。 */
    var resetVersion: Int by mutableIntStateOf(0)
        private set

    /** 用户是否手动滚动过（决定新数据是否自动吸附最新）。 */
    private var userScrolled = false

    fun changeTimeFrame(tf: TimeFrame) {
        if (tf != timeFrame) {
            timeFrame = tf
            crosshairIndex = -1
        }
    }

    /** 全量替换数据（替代 initKDataList / resetDataList）。 */
    fun setData(data: List<Candle>) {
        candles = data
        dataVersion++
        resetVersion++
        // 全量替换（首屏 / 切周期）总是回到最新一屏
        scrollOffsetPx = 0f
        userScrolled = false
        crosshairIndex = -1
    }

    /**
     * 实时更新：若末根时间相同则替换末根，否则追加新根（替代 addSingleData）。
     */
    fun appendOrUpdate(candle: Candle) {
        val cur = candles
        candles = if (cur.isNotEmpty() && cur.last().time == candle.time) {
            cur.toMutableList().also { it[it.lastIndex] = candle }
        } else {
            cur + candle
        }
        dataVersion++
    }

    /** 头部插入更早的数据（替代 addPreDataList）。保持当前可视位置不“跳”。 */
    fun prepend(older: List<Candle>) {
        if (older.isEmpty()) return
        candles = older + candles
        dataVersion++
    }

    /**
     * 统一更新入口：按 [type] 决定全量替换 / 更新末根 / 头部加载更多。
     * [data] 始终传当前完整列表；MORE 时自动取「比现有多出来的头部增量」做 prepend。
     */
    fun applyUpdate(type: KLineUpdate, data: List<Candle>) {
        when (type) {
            KLineUpdate.RESET -> setData(data)
            KLineUpdate.LATEST -> data.lastOrNull()?.let { appendOrUpdate(it) }
            KLineUpdate.MORE -> {
                val delta = data.size - candles.size
                if (delta > 0) prepend(data.subList(0, delta)) else setData(data)
            }
        }
    }

    fun markUserScrolled() { userScrolled = true }
    fun resetUserScrolled() { userScrolled = false }
}

@Composable
fun rememberKLineChartState(timeFrame: TimeFrame = TimeFrame.M15): KLineChartState =
    remember { KLineChartState(timeFrame) }
