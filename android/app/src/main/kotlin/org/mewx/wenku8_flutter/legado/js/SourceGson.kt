/* Adapted from Legado utils/GsonExtensions.kt, GPL-3.0.
 * Reference 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Changes: package and visibility; retain INITIAL_GSON adapters, omit Android
 * rule-entity adapters (our rule maps preserve the original JSON fields). */
package org.mewx.wenku8_flutter.legado.js

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.ToNumberPolicy
import com.google.gson.internal.LinkedTreeMap
import com.google.gson.reflect.TypeToken
import java.lang.reflect.Type
import kotlin.math.ceil

internal object SourceGson {
    val gson: Gson by lazy {
        GsonBuilder()
            .registerTypeAdapter(object : TypeToken<Map<String?, Any?>?>() {}.type, MapDeserializerDoubleAsIntFix())
            .registerTypeAdapter(Int::class.java, IntJsonDeserializer())
            .registerTypeAdapter(String::class.java, StringJsonDeserializer())
            .setObjectToNumberStrategy(ToNumberPolicy.LONG_OR_DOUBLE)
            .disableHtmlEscaping()
            .setPrettyPrinting()
            .create()
    }
}

private class StringJsonDeserializer : JsonDeserializer<String?> {
    override fun deserialize(json: JsonElement, typeOfT: Type, context: JsonDeserializationContext?): String? = when {
        json.isJsonPrimitive -> json.asString
        json.isJsonNull -> null
        else -> json.toString()
    }
}

private class IntJsonDeserializer : JsonDeserializer<Int?> {
    override fun deserialize(json: JsonElement, typeOfT: Type?, context: JsonDeserializationContext?): Int? = when {
        json.isJsonPrimitive -> {
            val primitive = json.asJsonPrimitive
            if (primitive.isNumber) primitive.asNumber.toInt() else null
        }
        else -> null
    }
}

private class MapDeserializerDoubleAsIntFix : JsonDeserializer<Map<String, Any?>?> {
    override fun deserialize(json: JsonElement, type: Type, context: JsonDeserializationContext): Map<String, Any?>? {
        @Suppress("UNCHECKED_CAST")
        return read(json) as? Map<String, Any?>
    }
    private fun read(json: JsonElement): Any? = when {
        json.isJsonArray -> json.asJsonArray.mapTo(ArrayList()) { read(it) }
        json.isJsonObject -> LinkedTreeMap<String, Any?>().apply {
            for ((key, value) in json.asJsonObject.entrySet()) put(key, read(value))
        }
        json.isJsonPrimitive -> {
            val primitive = json.asJsonPrimitive
            when {
                primitive.isBoolean -> primitive.asBoolean
                primitive.isString -> primitive.asString
                primitive.isNumber -> {
                    val num = primitive.asNumber
                    if (ceil(num.toDouble()) == num.toLong().toDouble()) num.toLong() else num.toDouble()
                }
                else -> null
            }
        }
        else -> null
    }
}
