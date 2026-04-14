// import 'package:another_telephony/telephony.dart';
// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// /// TOP LEVEL BACKGROUND HANDLER
// /// This runs in a separate isolate when the app is killed or in the background.
// /// It acts as a 'Flight Recorder' for financial SMS data.
// @pragma('vm:entry-point')
// void backgroundMessageHandler(SmsMessage message) async {
//   debugPrint("🌙 VRITTI BACKGROUND: Processing Incoming SMS Proof...");

//   // Logic to parse the currency amount (e.g., 'Credited ₹500.00')
//   RegExp regExp = RegExp(r"(?:INR|₹|Rs\.?)\s?(\d+(?:\.\d{1,2})?)");
//   var match = regExp.firstMatch(message.body ?? "");

//   if (match != null) {
//     try {
//       double amount = double.tryParse(match.group(1)!) ?? 0.0;

//       // Persist to local 'Proof of Income' buffer
//       final prefs = await SharedPreferences.getInstance();
//       double currentStored = prefs.getDouble('local_income_proof') ?? 0.0;
//       await prefs.setDouble('local_income_proof', currentStored + amount);

//       debugPrint("✅ VRITTI BACKGROUND: Proof Recorded: ₹$amount");
//     } catch (e) {
//       debugPrint("❌ VRITTI BACKGROUND: Parse Error: $e");
//     }
//   }
// }

// class SMSEngine {
//   static final Telephony telephony = Telephony.instance;

//   /// Initializes foreground and background listeners with explicit permissions.
//   static Future<void> init(Function(double) onPayoutParsed) async {
//     bool? permissionsGranted = await telephony.requestSmsPermissions;

//     if (permissionsGranted == true) {
//       telephony.listenIncomingSms(
//         onNewMessage: (SmsMessage message) {
//           debugPrint("⚡ VRITTI FOREGROUND: SMS Proof Detected");
//           _handleMessage(message, onPayoutParsed);
//         },
//         onBackgroundMessage: backgroundMessageHandler,
//       );
//       debugPrint("✅ VRITTI SMS ENGINE: Real-time Proof Listeners Active");
//     } else {
//       debugPrint(
//         "⚠️ VRITTI SMS ENGINE: SMS Permissions Denied. Real-time proof disabled.",
//       );
//     }
//   }

//   /// Internal handler for foreground messages to update UI immediately
//   static void _handleMessage(
//     SmsMessage message,
//     Function(double) onPayoutParsed,
//   ) {
//     // Production Regex: Captures amounts following currency symbols or labels
//     RegExp regExp = RegExp(r"(?:INR|₹|Rs\.?)\s?(\d+(?:\.\d{1,2})?)");
//     var match = regExp.firstMatch(message.body ?? "");

//     if (match != null) {
//       double amount = double.tryParse(match.group(1)!) ?? 0.0;
//       if (amount > 0) {
//         onPayoutParsed(amount);
//       }
//     }
//   }

//   /// Utility to retrieve locally buffered income proof for backend syncing
//   static Future<double> getLocalProofBuffer() async {
//     final prefs = await SharedPreferences.getInstance();
//     return prefs.getDouble('local_income_proof') ?? 0.0;
//   }

//   /// Utility to clear buffer after successful backend sync
//   static Future<void> clearLocalProofBuffer() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove('local_income_proof');
//   }
// }
