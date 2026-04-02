import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. TOP LEVEL BACKGROUND HANDLER
// This runs in a separate isolate when the app is killed/backgrounded
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  debugPrint("🌙 BACKGROUND SMS RECEIVED: ${message.body}");

  // Logic to parse the amount (same as foreground)
  RegExp regExp = RegExp(r"(\d+(?:\.\d+)?)");
  var match = regExp.firstMatch(message.body ?? "");

  if (match != null) {
    double amount = double.tryParse(match.group(1)!) ?? 0.0;

    // Save to local storage so the UI can pick it up later
    final prefs = await SharedPreferences.getInstance();
    double currentStored = prefs.getDouble('bg_payouts') ?? 0.0;
    await prefs.setDouble('bg_payouts', currentStored + amount);
    debugPrint("✅ BACKGROUND STORED: ${currentStored + amount}");
  }
}

class SMSEngine {
  static final Telephony telephony = Telephony.instance;

  static Future<void> init(Function(double) onPayoutParsed) async {
    bool? permissionsGranted = await telephony.requestSmsPermissions;

    if (permissionsGranted == true) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          print("⚡ FOREGROUND SIGNAL");
          _handleMessage(message, onPayoutParsed);
        },
        // 2. ATTACH THE BACKGROUND HANDLER
        onBackgroundMessage: backgroundMessageHandler,
      );
      print("✅ Background & Foreground Listeners Active");
    }
  }

  static void _handleMessage(
    SmsMessage message,
    Function(double) onPayoutParsed,
  ) {
    RegExp regExp = RegExp(r"(\d+(?:\.\d+)?)");
    var match = regExp.firstMatch(message.body ?? "");
    if (match != null) {
      double amount = double.tryParse(match.group(1)!) ?? 0.0;
      onPayoutParsed(amount);
    }
  }
}
