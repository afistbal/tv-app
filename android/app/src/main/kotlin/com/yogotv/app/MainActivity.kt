package com.yogotv.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    var canPop = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yogotv.com/channel").setMethodCallHandler {
        call, result ->
            if(call.method == "moveToBack") {
                moveTaskToBack(false)
                result.success("")
            } else {
                result.notImplemented()
            }
        }
    }
}
