import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorSnapshot {
  final double speedKmh;
  final double accelEnergy;
  final double mae;
  final bool isFlagged;

  const SensorSnapshot({
    required this.speedKmh,
    required this.accelEnergy,
    required this.mae,
    required this.isFlagged,
  });

  String get heartbeatStatus => isFlagged ? 'FLAGGED' : 'NORMAL';
}

class EdgeEngine {
  static double _emaEnergy = 0.0;
  static StreamSubscription? _accelSub;

  static const double _maeThreshold = 0.35;

  static SensorSnapshot lastSnapshot = const SensorSnapshot(
    speedKmh: 0,
    accelEnergy: 0,
    mae: 0,
    isFlagged: false,
  );

  static Future<void> init() async {
    _accelSub = userAccelerometerEvents.listen((event) {
      final instantEnergy =
          sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));
      _emaEnergy = (instantEnergy * 0.15) + (_emaEnergy * 0.85);
    });
  }

  static Future<SensorSnapshot> runInference() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      final speedKmh = pos.speed * 3.6;
      final vNorm = (speedKmh / 60.0).clamp(0.0, 1.0);
      final aNorm = (_emaEnergy / 12.0).clamp(0.0, 1.0);
      final mae = (vNorm - aNorm).abs();
      final isFlagged = mae >= _maeThreshold || pos.isMocked;

      lastSnapshot = SensorSnapshot(
        speedKmh: speedKmh,
        accelEnergy: _emaEnergy,
        mae: mae,
        isFlagged: isFlagged,
      );
      return lastSnapshot;
    } catch (_) {
      lastSnapshot = SensorSnapshot(
        speedKmh: 0,
        accelEnergy: _emaEnergy,
        mae: 1,
        isFlagged: true,
      );
      return lastSnapshot;
    }
  }

  static void dispose() => _accelSub?.cancel();
}
