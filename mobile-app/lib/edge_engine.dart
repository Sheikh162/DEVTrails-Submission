import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class EdgeEngine {
  static double _emaEnergy = 0.0;
  static StreamSubscription? _accelSub;

  static Future<void> init() async {
    _accelSub = userAccelerometerEvents.listen((event) {
      double instantEnergy = sqrt(
        pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
      );
      // EMA Filter: requires consistent movement to pass
      _emaEnergy = (instantEnergy * 0.15) + (_emaEnergy * 0.85);
    });
  }

  static Future<bool> runInference() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      double speedKmh = pos.speed * 3.6;
      double vNorm = (speedKmh / 60.0).clamp(0.0, 1.0);
      double aNorm = (_emaEnergy / 12.0).clamp(0.0, 1.0);
      double inertialMAE = (vNorm - aNorm).abs();

      // STRICT THRESHOLD: 0.35
      bool isSecure = inertialMAE < 0.35 && !pos.isMocked;
      debugPrint(
        "EDGE AI: MAE ${inertialMAE.toStringAsFixed(2)} | Secure: $isSecure",
      );
      return isSecure;
    } catch (e) {
      return false; // Fail-safe: Block claims if sensors malfunction
    }
  }

  static void dispose() => _accelSub?.cancel();
}
