import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

String _edgeTs() => DateTime.now().toIso8601String();

class EdgeEngine {
  static List<double> _vibrationBuffer = [];
  static List<double> _speedBuffer = [];
  static double _totalDistance = 0.0;
  static Position? _lastPosition;

  static StreamSubscription? _accelSub;
  static StreamSubscription? _gyroSub;

  static double _currentGyroEnergy = 0.0;

  /// Initializes multiple sensor streams for data fusion
  static Future<void> init() async {
    debugPrint("[${_edgeTs()}] [EDGE_ENGINE] Initializing sensor streams...");
    // 1. Accelerometer Stream for Engine/Road Vibration (Physical Truth)
    _accelSub = userAccelerometerEvents.listen((event) {
      double magnitude = sqrt(
        pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
      );
      _vibrationBuffer.add(magnitude);
      // Maintain 2 minutes of historical data (at ~1Hz) for the correlation window
      if (_vibrationBuffer.length > 120) _vibrationBuffer.removeAt(0);
    });

    // 2. Gyroscope Stream for Rotational Verification (Detects Leaning/Turns)
    _gyroSub = gyroscopeEvents.listen((event) {
      // Combines 3-axis rotation into a single rotational energy metric
      _currentGyroEnergy = sqrt(
        pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
      );
    });
    debugPrint(
      "[${_edgeTs()}] [EDGE_ENGINE] Sensor streams active. Buffers => vibration:${_vibrationBuffer.length}, speed:${_speedBuffer.length}",
    );
  }

  /// Runs the statistical inference model to detect Fraud (e.g., GPS Spoofing)
  /// Called by main.dart every 30 seconds for heartbeat and batch sync
  static Future<Map<String, dynamic>> runInference() async {
    try {
      debugPrint("[${_edgeTs()}] [EDGE_ENGINE] Running inference cycle...");
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      // Track cumulative distance for the shift (Proof of Work)
      if (_lastPosition != null) {
        _totalDistance += Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      _lastPosition = pos;

      double currentSpeed = pos.speed * 3.6; // Convert m/s to km/h
      _speedBuffer.add(currentSpeed);
      if (_speedBuffer.length > 120) _speedBuffer.removeAt(0);

      // --- STATISTICAL CORE: PEARSON CORRELATION (r) ---
      // This proves that GPS speed changes are physically syncronized with device vibration.
      // A desktop phone with "spoofed" GPS will have a correlation near 0.
      double correlation = _calculatePearsonCorrelation(
        _speedBuffer,
        _vibrationBuffer,
      );

      // --- MULTIMODAL DECISION MATRIX ---
      bool isSecure = !pos.isMocked; // Hardware-level spoof check

      // If the vehicle is moving (> 5km/h), verify the physical dynamics
      if (currentSpeed > 5) {
        // High Speed + Zero Correlation = Fraud
        // High Speed + Zero Gyro (moving in a perfectly straight line forever) = Likely Emulation
        isSecure = correlation > 0.35 && _currentGyroEnergy > 0.02;
      }

      debugPrint(
        "[${_edgeTs()}] [EDGE_ENGINE] Inference Result => {"
        "correlation:${correlation.toStringAsFixed(3)}, "
        "gyroEnergy:${_currentGyroEnergy.toStringAsFixed(3)}, "
        "speedKmH:${currentSpeed.toStringAsFixed(2)}, "
        "distanceKm:${(_totalDistance / 1000).toStringAsFixed(3)}, "
        "isSecure:$isSecure, "
        "isMocked:${pos.isMocked}"
        "}",
      );

      final payload = {
        "isSecure": isSecure,
        "maeScore": correlation.clamp(
          0.0,
          1.0,
        ), // Maps the correlation to the backend's integrity metric
        "distance": _totalDistance / 1000, // Convert to KM
        "speed": currentSpeed,
      };
      debugPrint("[${_edgeTs()}] [EDGE_ENGINE] Payload => $payload");
      return payload;
    } catch (e) {
      debugPrint("[${_edgeTs()}] [EDGE_ENGINE] Inference failed => $e");
      return {
        "isSecure": false,
        "maeScore": 0.0,
        "distance": _totalDistance / 1000,
        "speed": 0.0,
      };
    }
  }

  /// Calculates the linear correlation between Speed and Vibration
  static double _calculatePearsonCorrelation(List<double> X, List<double> Y) {
    if (X.length < 15 || Y.length < 15)
      return 0.85; // Default to secure while buffers warm up

    int n = min(X.length, Y.length);
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;

    for (int i = 0; i < n; i++) {
      double xVal = X[X.length - n + i];
      double yVal = Y[Y.length - n + i];
      sumX += xVal;
      sumY += yVal;
      sumXY += xVal * yVal;
      sumX2 += xVal * xVal;
      sumY2 += yVal * yVal;
    }

    double numerator = (n * sumXY) - (sumX * sumY);
    double denominator = sqrt(
      (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY),
    );

    if (denominator == 0) return 0.0;
    return (numerator / denominator);
  }

  static void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
  }
}
