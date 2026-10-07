package com.example.omniview

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/** Decodes HEIC/HEIF/AVIF with the platform decoder (offline, on-device) and returns PNG bytes. */
class MainActivity : FlutterActivity() {
    private val pool = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "omniview/image")
            .setMethodCallHandler { call, result ->
                if (call.method != "decodeToPng") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.arguments as ByteArray
                pool.execute {
                    try {
                        if (Build.VERSION.SDK_INT < 28) throw IllegalStateException("Requires Android 9 or newer")
                        val src = ImageDecoder.createSource(ByteBuffer.wrap(bytes))
                        val bmp = ImageDecoder.decodeBitmap(src) { dec, info, _ ->
                            dec.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                            val m = maxOf(info.size.width, info.size.height)
                            if (m > 4096) {
                                val k = 4096f / m
                                dec.setTargetSize(
                                    maxOf(1, (info.size.width * k).toInt()),
                                    maxOf(1, (info.size.height * k).toInt()))
                            }
                        }
                        val out = ByteArrayOutputStream()
                        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                        main.post { result.success(out.toByteArray()) }
                    } catch (e: Throwable) {
                        main.post { result.error("decode", e.message, null) }
                    }
                }
            }
    }
}
