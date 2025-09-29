package com.tinysync.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle

class MainActivity : FlutterActivity() {
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Add method channel for location plugin safety if needed
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tinysync/location_safety")
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.d("MainActivity", "MainActivity created")
    }
    
    override fun onDestroy() {
        android.util.Log.d("MainActivity", "MainActivity destroying...")
        try {
            super.onDestroy()
            android.util.Log.d("MainActivity", "MainActivity destroyed successfully")
        } catch (e: Exception) {
            // Catch and log any location plugin disposal errors
            android.util.Log.w("MainActivity", "Error during activity destruction: ${e.message}", e)
            // Continue with destruction despite errors
        }
    }
}