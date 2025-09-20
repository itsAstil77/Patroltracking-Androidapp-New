package com.example.patroltracking

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Bundle

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Don't handle NFC here to prevent double processing
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Just pass the intent to Flutter without any additional processing
    }
}

