package org.mewx.wenku8_flutter

import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SourceFontCacheTest {
    @get:Rule val temp=TemporaryFolder()
    private fun run(state:SourceState=SourceState())=SourceRun(state=state,fetch={_,_,_,_->error("Unexpected nested request")})
    private fun response(headers:Map<String,List<String>>,status:Int=200)=SourceReply("https://fonts.example.test/font.woff2","",status,headers,data=if(status==304) byteArrayOf() else byteArrayOf(1,2,3,4))

    @Test fun freshFontSurvivesCacheInstanceAndNeverStoresTheUrlOrCredentials() {
        val folder=File(temp.root,"fonts");val run=run();var calls=0
        val fetch={_:Map<String,String> -> calls++;response(mapOf("Cache-Control" to listOf("public, max-age=3600")))}
        val first=SourceFontCache(folder).load("https://fonts.example.test/font.woff2?private=fixture","fixture-private-cookie",run,fetch)
        val second=SourceFontCache(folder).load("https://fonts.example.test/font.woff2?private=fixture","fixture-private-cookie",run,fetch)
        assertArrayEquals(first,second);assertEquals(1,calls);assertEquals(1,run.metrics.cacheHits.get())
        for(file in folder.listFiles()!!){assertFalse(file.readBytes().toString(Charsets.UTF_8).contains("fixture-private"));assertFalse(file.name.contains("private"))}
    }

    @Test fun staleFontUsesConditionalRevalidationAndNewFreshness() {
        val cache=SourceFontCache(File(temp.root,"fonts"));val run=run();var calls=0
        val fetch={headers:Map<String,String> ->
            calls++
            if(calls==1) response(mapOf("Cache-Control" to listOf("no-cache"),"ETag" to listOf("fixture-etag")))
            else {assertEquals("fixture-etag",headers["If-None-Match"]);response(mapOf("Cache-Control" to listOf("max-age=3600")),304)}
        }
        val first=cache.load("https://fonts.example.test/font.woff2","fixture-user",run,fetch)
        assertArrayEquals(first,cache.load("https://fonts.example.test/font.woff2","fixture-user",run,fetch))
        assertArrayEquals(first,cache.load("https://fonts.example.test/font.woff2","fixture-user",run,fetch))
        assertEquals(2,calls)
    }

    @Test fun noStoreResponsesAreNotPersisted() {
        val folder=File(temp.root,"fonts");val cache=SourceFontCache(folder);val run=run();var calls=0
        repeat(2){cache.load("https://fonts.example.test/font.woff2","fixture-user",run){calls++;response(mapOf("Cache-Control" to listOf("no-store")))}}
        assertEquals(2,calls);assertFalse(folder.exists())
    }

    @Test fun accountHeadersArePartOfTheCacheIdentity() {
        val folder=File(temp.root,"fonts");val cache=SourceFontCache(folder);var calls=0
        val fetch={_:Map<String,String> ->calls++;response(mapOf("Cache-Control" to listOf("max-age=3600")))}
        cache.load("https://fonts.example.test/font.woff2","fixture-user-a",run(),fetch)
        cache.load("https://fonts.example.test/font.woff2","fixture-user-b",run(),fetch)
        assertEquals(2,calls);assertEquals(2,folder.listFiles()!!.size)
    }

    @Test fun concurrentReadsDownloadOneCopy() {
        val cache=SourceFontCache(File(temp.root,"fonts"));val state=SourceState();val calls=AtomicInteger();val workers=Executors.newFixedThreadPool(2)
        try {
            val tasks=(1..2).map {workers.submit<ByteArray> {cache.load("https://fonts.example.test/font.woff2","fixture-user",run(state)){
                calls.incrementAndGet();Thread.sleep(40);response(mapOf("Cache-Control" to listOf("max-age=3600")))
            }}}
            assertArrayEquals(tasks[0].get(2,TimeUnit.SECONDS),tasks[1].get(2,TimeUnit.SECONDS));assertEquals(1,calls.get())
        } finally {workers.shutdownNow()}
    }
}
