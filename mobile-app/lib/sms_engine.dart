import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  RegExp regExp = RegExp(r"(\d+(?:\.\d+)?)");
  var match = regExp.firstMatch(message.body ?? "");
  if (match != null) {
    double amount = double.tryParse(match.group(1)!) ?? 0.0;
    final prefs = await SharedPreferences.getInstance();
    double currentStored = prefs.getDouble('bg_payouts') ?? 0.0;
    await prefs.setDouble('bg_payouts', currentStored + amount);
  }
}

class SMSEngine {
  static final Telephony telephony = Telephony.instance;
  static Future<void> init(Function(double) onPayoutParsed) async {
    bool? granted = await telephony.requestSmsPermissions;
    if (granted == true) {
      telephony.listenIncomingSms(
        onNewMessage: (m) => _handle(m, onPayoutParsed),
        onBackgroundMessage: backgroundMessageHandler,
      );
    }
  }

  static void _handle(SmsMessage m, Function(double) o) {
    RegExp regExp = RegExp(r"(\d+(?:\.\d+)?)");
    var match = regExp.firstMatch(m.body ?? "");
    if (match != null) o(double.tryParse(match.group(1)!) ?? 0.0);
  }
}
