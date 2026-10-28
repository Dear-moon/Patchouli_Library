/*
 * Adapted from Legado 3.0, GPL-3.0, by gedoor and Legado contributors.
 * Reference: LegadoTeam/legado 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Modified 2026-10-18: package/host adapters for the Wenku8 Flutter source engine.
 * Grammar and extraction algorithms are retained; see third_party/legado/README.md.
 */
package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import java.util.regex.Pattern

@Keep
object AnalyzeByRegex {

    fun getElement(res: String, regs: Array<String>, index: Int = 0): List<String>? {
        var vIndex = index
        val resM = Pattern.compile(regs[vIndex]).matcher(res)
        if (!resM.find()) {
            return null
        }
        // 判断索引的规则是最后一个规则
        return if (vIndex + 1 == regs.size) {
            // 新建容器
            val info = arrayListOf<String>()
            for (groupIndex in 0..resM.groupCount()) {
                info.add(resM.group(groupIndex)!!)
            }
            info
        } else {
            val result = StringBuilder()
            do {
                result.append(resM.group())
            } while (resM.find())
            getElement(result.toString(), regs, ++vIndex)
        }
    }

    fun getElements(res: String, regs: Array<String>, index: Int = 0): List<List<String>> {
        var vIndex = index
        val resM = Pattern.compile(regs[vIndex]).matcher(res)
        if (!resM.find()) {
            return arrayListOf()
        }
        // 判断索引的规则是最后一个规则
        if (vIndex + 1 == regs.size) {
            // 创建书息缓存数组
            val books = ArrayList<List<String>>()
            // 提取列表
            do {
                // 新建容器
                val info = arrayListOf<String>()
                for (groupIndex in 0..resM.groupCount()) {
                    info.add(resM.group(groupIndex) ?: "")
                }
                books.add(info)
            } while (resM.find())
            return books
        } else {
            val result = StringBuilder()
            do {
                result.append(resM.group())
            } while (resM.find())
            return getElements(result.toString(), regs, ++vIndex)
        }
    }
}
