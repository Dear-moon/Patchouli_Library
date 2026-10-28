# Rhino's optional JavaBean JSON converter uses java.desktop, absent on Android.
# BookSourceEngine explicitly installs the default toString conversion instead;
# scripts cannot load JavaToJSONConverters through the restricted class shutter.
# Map/Collection JSON conversion is intrinsic and does not use JavaBeans.
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor
# Hutool's optional bean-serialization annotation. The source host exposes
# byte/string crypto operations, not Hutool's bean serialization APIs.
-dontwarn java.beans.Transient

# Rhino's interpreter, built-ins and lazy constructors are connected through
# runtime class/method names (VMBridge, Interpreter, RegExp, typed arrays, E4X).
# Retain that runtime contract while allowing bytecode optimization. This does
# not retain the desktop shell/GUI, CommonJS loader or JVM bytecode compiler.
-keep,allowoptimization class org.htmlunit.corejs.javascript.* { *; }
-keep,allowoptimization class org.htmlunit.corejs.javascript.jdk18.** { *; }
-keep,allowoptimization class org.htmlunit.corejs.javascript.regexp.** { *; }
-keep,allowoptimization class org.htmlunit.corejs.javascript.typedarrays.** { *; }
-keep,allowoptimization class org.htmlunit.corejs.javascript.xmlimpl.** { *; }

# JCA provider registrations also contain implementation class-name strings.
# Without their mappings, Hutool sees a BC provider with no AES/RSA services.
-keep,allowoptimization class org.bouncycastle.jcajce.provider.** { *; }
-keep,allowoptimization class org.bouncycastle.jce.provider.** { *; }

# Source JavaScript calls these public API names through Rhino reflection.
# Preserve only the deliberately exposed parser/crypto APIs, not every dependency.
-keepnames class org.jsoup.**
-keepnames class org.seimicrawler.xpath.**
-keepnames class cn.hutool.crypto.**
-keepclassmembers class org.jsoup.** { public *; }
-keepclassmembers class org.seimicrawler.xpath.** { public *; }
-keepclassmembers class cn.hutool.crypto.** { public *; }
-keepclassmembers interface org.mewx.wenku8_flutter.legado.JsEncodeUtils { public *; }
