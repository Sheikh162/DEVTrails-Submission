import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

String _ts() => DateTime.now().toIso8601String();

class EdgeSnapshot {
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final double vibrationMagnitude;
  final double gyroMagnitude;
  final double speedKmph;
  final double maeScore;
  final bool isFraudFlag;
  final double lat;
  final double lng;
  final String locationName;
  final String hardwareGpsSummary;
  final String cellTowerId;
  final String cellTowerName;
  final String wifiBssid;
  final String wifiName;
  final String interpretation;
  final DateTime timestamp;

  const EdgeSnapshot({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.vibrationMagnitude,
    required this.gyroMagnitude,
    required this.speedKmph,
    required this.maeScore,
    required this.isFraudFlag,
    required this.lat,
    required this.lng,
    required this.locationName,
    required this.hardwareGpsSummary,
    required this.cellTowerId,
    required this.cellTowerName,
    required this.wifiBssid,
    required this.wifiName,
    required this.interpretation,
    required this.timestamp,
  });

  factory EdgeSnapshot.initial() {
    return EdgeSnapshot(
      ax: 0,
      ay: 0,
      az: 0,
      gx: 0,
      gy: 0,
      gz: 0,
      vibrationMagnitude: 0,
      gyroMagnitude: 0,
      speedKmph: 0,
      maeScore: 0.85,
      isFraudFlag: false,
      lat: 0,
      lng: 0,
      locationName: 'Awaiting GPS lock',
      hardwareGpsSummary: 'GPS initializing',
      cellTowerId: 'UNAVAILABLE_DEMO',
      cellTowerName: 'Cell tower API not wired in this build',
      wifiBssid: 'UNAVAILABLE_DEMO',
      wifiName: 'Wi-Fi scan plugin not wired in this build',
      interpretation: 'Buffers warming up',
      timestamp: DateTime.now(),
    );
  }
}

class EdgeEngine {
  static final ValueNotifier<EdgeSnapshot> liveSnapshot = ValueNotifier(
    EdgeSnapshot.initial(),
  );

  static StreamSubscription? _accelSub;
  static StreamSubscription? _gyroSub;
  static StreamSubscription<Position>? _gpsSub;

  static double _ax = 0;
  static double _ay = 0;
  static double _az = 0;
  static double _gx = 0;
  static double _gy = 0;
  static double _gz = 0;
  static double _speedKmph = 0;
  static double _lat = 0;
  static double _lng = 0;

  static final List<double> _vibrationBuffer = [];
  static final List<double> _speedBuffer = [];

  static Future<void> init() async {
    debugPrint('[${_ts()}] [EDGE] init() called. Starting accelerometer, gyro, GPS listeners');

    _accelSub?.cancel();
    _gyroSub?.cancel();
    _gpsSub?.cancel();

    _accelSub = userAccelerometerEvents.listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
      final vib = sqrt((e.x * e.x) + (e.y * e.y) + (e.z * e.z));
      _vibrationBuffer.add(vib);
      if (_vibrationBuffer.length > 120) _vibrationBuffer.removeAt(0);
      _publishSnapshot();
    });

    _gyroSub = gyroscopeEvents.listen((e) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
      _publishSnapshot();
    });

    final hasPermission = await _ensureLocationPermission();
    if (hasPermission) {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      ).listen((pos) {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _speedKmph = max(0, pos.speed * 3.6);
        _speedBuffer.add(_speedKmph);
        if (_speedBuffer.length > 120) _speedBuffer.removeAt(0);
        _publishSnapshot(isMocked: pos.isMocked);
      });
    } else {
      debugPrint('[${_ts()}] [EDGE] Location permission denied. GPS data unavailable.');
    }
  }

  static Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  static void _publishSnapshot({bool isMocked = false}) {
    final vib = sqrt((_ax * _ax) + (_ay * _ay) + (_az * _az));
    final gyroMag = sqrt((_gx * _gx) + (_gy * _gy) + (_gz * _gz));
    final correlation = _pearson(_speedBuffer, _vibrationBuffer).clamp(0.0, 1.0);
    final flagged = isMocked || (_speedKmph > 5 && (correlation < 0.35 || gyroMag < 0.02));

    final interpretation = flagged
        ? 'Potential mismatch detected (FRAUD_FLAG): speed/vibration/gyro pattern is inconsistent.'
        : 'Telemetry consistent (VERIFIED): speed and inertial signals are aligned.';

    liveSnapshot.value = EdgeSnapshot(
      ax: _ax,
      ay: _ay,
      az: _az,
      gx: _gx,
      gy: _gy,
      gz: _gz,
      vibrationMagnitude: vib,
      gyroMagnitude: gyroMag,
      speedKmph: _speedKmph,
      maeScore: correlation,
      isFraudFlag: flagged,
      lat: _lat,
      lng: _lng,
      locationName: _lat == 0 && _lng == 0
          ? 'Location pending'
          : 'Approx @ ${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}',
      hardwareGpsSummary: 'GPS speed=${_speedKmph.toStringAsFixed(2)}km/h, mocked=$isMocked',
      cellTowerId: 'UNAVAILABLE_DEMO',
      cellTowerName: 'Cell-tower scan not exposed by current Flutter plugin set',
      wifiBssid: 'UNAVAILABLE_DEMO',
      wifiName: 'Wi-Fi BSSID scan not exposed by current Flutter plugin set',
      interpretation: interpretation,
      timestamp: DateTime.now(),
    );
  }

  static double _pearson(List<double> x, List<double> y) {
    if (x.length < 10 || y.length < 10) return 0.85;
    final n = min(x.length, y.length);
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;

    for (var i = 0; i < n; i++) {
      final xv = x[x.length - n + i];
      final yv = y[y.length - n + i];
      sumX += xv;
      sumY += yv;
      sumXY += xv * yv;
      sumX2 += xv * xv;
      sumY2 += yv * yv;
    }

    final num = (n * sumXY) - (sumX * sumY);
    final den = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
    if (den == 0) return 0.0;
    return num / den;
  }

  static Future<EdgeSnapshot> collectSnapshot() async {
    return liveSnapshot.value;
  }

  static void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _gpsSub?.cancel();
  }
}
