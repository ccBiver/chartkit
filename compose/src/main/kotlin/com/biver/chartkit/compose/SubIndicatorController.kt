package com.biver.chartkit.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import com.biver.chartkit.indicator.Indicator

/**
 * 副图选择模式：
 * - [Single]   单选：点新指标替换旧的；点已选中的则关闭。
 * - [Multiple] 叠加：点一个往下加一个窗格（如先 MACD 再 KDJ → 两个副图依次往下排）。
 */
enum class SubIndicatorMode { Single, Multiple }

/**
 * 副图控制器：管理「选了哪些副图」与「单选/叠加」模式，结果直接喂给 [KLineChart] 的 subIndicators。
 *
 * ```
 * val sub = rememberSubIndicatorController(SubIndicatorMode.Multiple)
 * // 工具栏：
 * sub.toggle(Macd()); sub.toggle(Kdj())   // 两个副图往下加
 * KLineChart(..., subIndicators = sub.selected)
 * ```
 * 切换 [mode] 到 [SubIndicatorMode.Single] 时会自动只保留最后一个，行为立即生效。
 */
@Stable
class SubIndicatorController(mode: SubIndicatorMode = SubIndicatorMode.Single) {

    var mode: SubIndicatorMode by mutableStateOf(mode)
        private set

    /** 当前选中的副图（有序）。可直接作为 KLineChart 的 subIndicators 传入。 */
    val selected = mutableStateListOf<Indicator>()

    fun isSelected(id: String): Boolean = selected.any { it.id == id }

    /** 切换某指标的选中态，遵循当前 [mode]。 */
    fun toggle(indicator: Indicator) {
        val existing = selected.firstOrNull { it.id == indicator.id }
        when (mode) {
            SubIndicatorMode.Single -> {
                selected.clear()
                if (existing == null) selected.add(indicator) // 点已选中的同一项 = 关闭
            }
            SubIndicatorMode.Multiple -> {
                if (existing != null) selected.remove(existing) else selected.add(indicator)
            }
        }
    }

    /** 直接设定选中列表（如恢复用户偏好）。 */
    fun set(indicators: List<Indicator>) {
        selected.clear()
        if (mode == SubIndicatorMode.Single) {
            indicators.lastOrNull()?.let { selected.add(it) }
        } else {
            selected.addAll(indicators)
        }
    }

    fun clear() = selected.clear()

    /** 切换模式；切到单选时仅保留最后一个，避免残留多个窗格。 */
    fun changeMode(newMode: SubIndicatorMode) {
        if (newMode == mode) return
        mode = newMode
        if (newMode == SubIndicatorMode.Single && selected.size > 1) {
            val last = selected.last()
            selected.clear()
            selected.add(last)
        }
    }
}

@Composable
fun rememberSubIndicatorController(
    mode: SubIndicatorMode = SubIndicatorMode.Single,
): SubIndicatorController = remember { SubIndicatorController(mode) }
