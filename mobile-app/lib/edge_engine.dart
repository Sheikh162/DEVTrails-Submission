import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

String _ts() => DateTime.now().toIso8601String();

// ---------------------------------------------------------------------------
// DATA MODEL
// ---------------------------------------------------------------------------

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
  final String carrierName;
  final String mcc;
  final String mnc;
  final String wifiBssid;
  final String wifiName;
  final double? ambientTempC;
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
    required this.carrierName,
    required this.mcc,
    required this.mnc,
    required this.wifiBssid,
    required this.wifiName,
    required this.ambientTempC,
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
      cellTowerId: 'UNAVAILABLE',
      cellTowerName: 'Scanning...',
      carrierName: 'Scanning...',
      mcc: '---',
      mnc: '---',
      wifiBssid: 'UNAVAILABLE',
      wifiName: 'UNAVAILABLE',
      ambientTempC: null,
      interpretation: 'Buffers warming up',
      timestamp: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// ENGINE
// ---------------------------------------------------------------------------

class EdgeEngine {
  static final ValueNotifier<EdgeSnapshot> liveSnapshot = ValueNotifier(
    EdgeSnapshot.initial(),
  );

  static StreamSubscription? _accelSub;
  static StreamSubscription? _gyroSub;
  static StreamSubscription<Position>? _gpsSub;

  static double _ax = 0, _ay = 0, _az = 0;
  static double _gx = 0, _gy = 0, _gz = 0;
  static double _speedKmph = 0;
  static double _lat = 0, _lng = 0;

  static double _currentGyroEnergy = 0;
  static double _totalDistance = 0;
  static Position? _lastPosition;

  static final List<double> _vibrationBuffer = [];
  static final List<double> _speedBuffer = [];

  // MethodChannel — no 3rd-party plugin required.
  // Wire up in MainActivity.kt — see comment in _refreshDeviceInfo() below.
  static const _nativeChannel = MethodChannel('vritti/device_info');

  static String _carrierName = 'UNAVAILABLE';
  static String _mcc = '---';
  static String _mnc = '---';
  static String _cellTowerId = 'UNAVAILABLE';
  static double? _ambientTempC;

  static Timer? _deviceInfoTimer;

  // -------------------------------------------------------------------------
  // INIT
  // -------------------------------------------------------------------------

  static Future<void> init() async {
    debugPrint('[${_ts()}] [EDGE_ENGINE] Initializing sensor streams...');

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
      _currentGyroEnergy = sqrt((e.x * e.x) + (e.y * e.y) + (e.z * e.z));
      _publishSnapshot();
    });

    final hasPermission = await _ensureLocationPermission();
    if (hasPermission) {
      _gpsSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
            ),
          ).listen((pos) {
            _lat = pos.latitude;
            _lng = pos.longitude;
            _speedKmph = max(0, pos.speed * 3.6);
            _speedBuffer.add(_speedKmph);
            if (_speedBuffer.length > 120) _speedBuffer.removeAt(0);
            _publishSnapshot(isMocked: pos.isMocked);
          });
    } else {
      debugPrint('[${_ts()}] [EDGE_ENGINE] Location permission denied.');
    }

    await _refreshDeviceInfo();
    _deviceInfoTimer?.cancel();
    _deviceInfoTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshDeviceInfo(),
    );

    debugPrint(
      '[${_ts()}] [EDGE_ENGINE] Init complete. carrier=$_carrierName mcc=$_mcc mnc=$_mnc',
    );
  }

  // -------------------------------------------------------------------------
  // NATIVE DEVICE INFO via MethodChannel
  //
  // Paste this into android/app/src/main/kotlin/<your/package>/MainActivity.kt:
  //
  // import android.content.Intent
  // import android.content.IntentFilter
  // import android.os.BatteryManager
  // import android.telephony.TelephonyManager
  // import io.flutter.embedding.android.FlutterActivity
  // import io.flutter.embedding.engine.FlutterEngine
  // import io.flutter.plugin.common.MethodChannel
  //
  // class MainActivity : FlutterActivity() {
  //   override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  //     super.configureFlutterEngine(flutterEngine)
  //     MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vritti/device_info")
  //       .setMethodCallHandler { call, result ->
  //         if (call.method == "getDeviceInfo") {
  //           val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
  //           val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
  //           val battery = registerReceiver(null, ifilter)
  //           val tempTenths = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
  //           result.success(mapOf(
  //             "carrierName"  to (tm.networkOperatorName ?: "UNAVAILABLE"),
  //             "mcc"          to (tm.networkOperator?.take(3) ?: "---"),
  //             "mnc"          to (tm.networkOperator?.drop(3) ?: "---"),
  //             "batteryTempC" to if (tempTenths >= 0) tempTenths / 10.0 else null
  //           ))
  //         } else result.notImplemented()
  //       }
  //   }
  // }
  // -------------------------------------------------------------------------

  static Future<void> _refreshDeviceInfo() async {
    try {
      final info = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getDeviceInfo',
      );
      if (info != null) {
        _carrierName = (info['carrierName'] as String?) ?? 'UNAVAILABLE';
        _mcc = (info['mcc'] as String?) ?? '---';
        _mnc = (info['mnc'] as String?) ?? '---';
        _cellTowerId = 'SIM_${_mcc}_$_mnc';
        final temp = info['batteryTempC'];
        _ambientTempC = temp != null ? (temp as num).toDouble() : null;
        debugPrint(
          '[${_ts()}] [EDGE_ENGINE] DeviceInfo => carrier=$_carrierName mcc=$_mcc mnc=$_mnc temp=$_ambientTempC',
        );
      }
    } on PlatformException catch (e) {
      // Channel not yet wired in MainActivity — non-fatal, app still works
      debugPrint(
        '[${_ts()}] [EDGE_ENGINE] DeviceInfo channel not available: ${e.message}',
      );
    } catch (e) {
      debugPrint('[${_ts()}] [EDGE_ENGINE] DeviceInfo exception: $e');
    }
    _publishSnapshot();
  }

  // -------------------------------------------------------------------------
  // LOCATION PERMISSION
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // INFERENCE
  // -------------------------------------------------------------------------

  static Future<Map<String, dynamic>> runInference() async {
    try {
      debugPrint('[${_ts()}] [EDGE_ENGINE] Running inference cycle...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      if (_lastPosition != null) {
        _totalDistance += Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      _lastPosition = pos;

      final currentSpeed = pos.speed * 3.6;
      _speedBuffer.add(currentSpeed);
      if (_speedBuffer.length > 120) _speedBuffer.removeAt(0);

      final correlation = _pearson(_speedBuffer, _vibrationBuffer);
      bool isSecure = !pos.isMocked;
      if (currentSpeed > 5) {
        isSecure = correlation > 0.35 && _currentGyroEnergy > 0.02;
      }

      debugPrint(
        '[${_ts()}] [EDGE_ENGINE] Inference => correlation:${correlation.toStringAsFixed(3)}, '
        'gyroEnergy:${_currentGyroEnergy.toStringAsFixed(3)}, speed:${currentSpeed.toStringAsFixed(2)}, '
        'distKm:${(_totalDistance / 1000).toStringAsFixed(3)}, isSecure:$isSecure, mocked:${pos.isMocked}',
      );

      return {
        'isSecure': isSecure,
        'maeScore': correlation.clamp(0.0, 1.0),
        'distance': _totalDistance / 1000,
        'speed': currentSpeed,
      };
    } catch (e) {
      debugPrint('[${_ts()}] [EDGE_ENGINE] Inference failed => $e');
      return {
        'isSecure': false,
        'maeScore': 0.0,
        'distance': _totalDistance / 1000,
        'speed': 0.0,
      };
    }
  }

  // -------------------------------------------------------------------------
  // SNAPSHOT PUBLISHER
  // -------------------------------------------------------------------------

  static void _publishSnapshot({bool isMocked = false}) {
    final vib = sqrt((_ax * _ax) + (_ay * _ay) + (_az * _az));
    final gyroMag = sqrt((_gx * _gx) + (_gy * _gy) + (_gz * _gz));
    final correlation = _pearson(
      _speedBuffer,
      _vibrationBuffer,
    ).clamp(0.0, 1.0);
    final flagged =
        isMocked || (_speedKmph > 5 && (correlation < 0.35 || gyroMag < 0.02));

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
      hardwareGpsSummary:
          'GPS speed=${_speedKmph.toStringAsFixed(2)}km/h, mocked=$isMocked',
      cellTowerId: _cellTowerId,
      cellTowerName: 'MCC:$_mcc MNC:$_mnc',
      carrierName: _carrierName,
      mcc: _mcc,
      mnc: _mnc,
      wifiBssid: 'UNAVAILABLE',
      wifiName: 'UNAVAILABLE',
      ambientTempC: _ambientTempC,
      interpretation: interpretation,
      timestamp: DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // PEARSON CORRELATION
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // PUBLIC API
  // -------------------------------------------------------------------------

  static Future<EdgeSnapshot> collectSnapshot() async => liveSnapshot.value;

  static void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _gpsSub?.cancel();
    _deviceInfoTimer?.cancel();
  }
}
