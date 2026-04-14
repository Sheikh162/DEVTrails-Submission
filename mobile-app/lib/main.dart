import 'dart:async';
import 'dart:convert';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edge_engine.dart';
import 'registration.dart';

String _ts() => DateTime.now().toIso8601String();

dynamic _tryDecodeJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String _prettyJson(dynamic data) {
  if (data == null) return 'null';
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

class AppSecrets {
  static String godModePassword = '123';

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('.env');
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final index = trimmed.indexOf('=');
        if (index == -1) continue;
        final key = trimmed.substring(0, index).trim();
        final value = trimmed.substring(index + 1).trim();
        if (key == 'GODMODE_PASSWORD' && value.isNotEmpty) {
          godModePassword = value;
        }
      }
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSecrets.load();
  await EdgeEngine.init();
  runApp(const VrittiApp());
}

class VrittiApp extends StatelessWidget {
  const VrittiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vritti',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00421A), // Darker Green Scheme
          primary: const Color(0xFF00421A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00421A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/registration': (_) => const RegistrationScreen(),
        '/main': (_) => const DemoDashboardScreen(),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// LOGIN SCREEN
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;

  void _log(String m) => debugPrint('[$_ts()] [AUTH] $m');

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      _toast('Enter valid phone number');
      return;
    }

    setState(() => _busy = true);
    final payload = {'phone': phone};
    _log('REQUEST => POST /api/v1/auth/request-otp payload=$payload');
    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        setState(() => _otpSent = true);
      } else {
        final decoded = _tryDecodeJson(res.body);
        final msg =
            (decoded is Map ? decoded['error'] : null) ?? 'OTP request failed';
        _toast(msg.toString());
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _busy = true);
    final payload = {
      'phone': _phoneController.text.trim(),
      'otp': _codeController.text.trim(),
      'consentGiven': true,
    };
    _log('REQUEST => POST /api/v1/auth/verify-otp payload=$payload');

    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final userId = map['userId'] ?? map['user']?['id'] ?? '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', userId.toString());
        await prefs.setString(
          'user_name',
          (map['name'] ?? map['user']?['name'] ?? 'Rider').toString(),
        );
        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        final decoded = _tryDecodeJson(res.body);
        final msg =
            (decoded is Map ? decoded['error'] : null) ?? 'Verify failed';
        _toast(msg.toString());
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.shield_tick, size: 80, color: Color(0xFF00421A)),
            const SizedBox(height: 16),
            Text(
              'Vritti Login',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'OTP code'),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : (_otpSent ? _verifyOtp : _requestOtp),
                child: Text(
                  _busy
                      ? 'Processing...'
                      : (_otpSent ? 'Verify OTP' : 'Request OTP'),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/registration'),
              child: const Text('New user? Register'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DEMO DASHBOARD SCREEN
// ---------------------------------------------------------------------------

class DemoDashboardScreen extends StatefulWidget {
  const DemoDashboardScreen({super.key});

  @override
  State<DemoDashboardScreen> createState() => _DemoDashboardScreenState();
}

class _DemoDashboardScreenState extends State<DemoDashboardScreen> {
  static const Duration _heartbeatInterval = Duration(seconds: 10);
  static const String _baseUrl = 'https://vritti-ps1s.onrender.com';

  String userId = '';
  String userName = 'Rider';
  String userCity = 'Chennai';
  String userPlatform = 'Swiggy';

  num premiumInvested = 0;
  num weeklyEarnings = 0;
  num walletBalance = 0;
  String currentStatus = 'UNKNOWN';
  List<dynamic> notifications = [];

  bool pricingLoading = false;
  num pricingBasePremium = 0;
  num pricingFinalPremium = 0;
  num pricingWRiskScore = 0;
  num pricingRAlertMultiplier = 1;
  String pricingSource = 'unavailable';
  String pricingCurrency = 'INR';
  String pricingTimestamp = '-';
  String pricingConfidence = '-';
  String pricingZoneId = '-';
  String pricingAlertSource = '-';
  num pricingDiscountPct = 0;
  num pricingImdLevel = 0;
  num pricingMaxTemp = 0;
  bool pricingEngineReady = false;
  String pricingEngineStatus = 'unknown';
  String pricingModelTrainedAt = '-';
  int pricingTrainingRows = 0;
  num pricingDriftThreshold = 0;
  num pricingBaselineWRisk = 0;
  List<dynamic> pricingTopRiskFactors = [];
  Map<String, dynamic>? pricingEngineResponse;
  Map<String, dynamic>? pricingMlPayload;

  bool loadingWeek = false;
  bool loadingClaim = false;

  Timer? heartbeatTimer;
  final List<String> terminalLogs = [];
  bool godModeEnabled = false;

  void _log(String scope, String msg) {
    final line = '[$_ts()] [$scope] $msg';
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      terminalLogs.insert(0, line);
      if (terminalLogs.length > 150) terminalLogs.removeLast();
    });
  }

  void _showToast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id') ?? '';
    userName = prefs.getString('user_name') ?? 'Rider';
    userCity = prefs.getString('user_city') ?? 'Chennai';
    userPlatform = prefs.getString('user_platform') ?? 'Swiggy';
    _log(
      'BOOT',
      'userId=$userId userName=$userName city=$userCity platform=$userPlatform',
    );
    if (userId.isEmpty) {
      _log('BOOT', 'No session. Redirecting to login.');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    await _fetchDashboard();
    await _fetchPricingBundle(includeDiagnostics: godModeEnabled);
    _startTelemetryLoop();
  }

  void _startTelemetryLoop() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      await _sendHeartbeat();
    });
    _log(
      'TELEMETRY',
      'Started ${_heartbeatInterval.inSeconds}s heartbeat loop.',
    );
  }

  Future<void> _fetchDashboard() async {
    final url = '$_baseUrl/api/v1/user/dashboard/$userId';
    _log('DASHBOARD', 'REQUEST => GET $url');
    try {
      final res = await http.get(Uri.parse(url));
      _log('DASHBOARD', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode != 200) return;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        premiumInvested = map['premiumInvested'] ?? map['moneyInvested'] ?? 0;
        weeklyEarnings = map['weeklyEarnings'] ?? 0;
        walletBalance = map['walletBalance'] ?? map['currentBalance'] ?? 0;
        currentStatus = map['currentStatus']?.toString() ?? 'UNKNOWN';
        notifications = (map['notifications'] as List?) ?? [];
      });
    } catch (e) {
      _log('DASHBOARD', 'EXCEPTION => $e');
    }
  }

  Future<void> _fetchPricingBundle({required bool includeDiagnostics}) async {
    if (userId.isEmpty) return;
    setState(() => pricingLoading = true);
    final city = userCity.trim().isEmpty ? 'Chennai' : userCity.trim();
    final encodedCity = Uri.encodeComponent(city);

    try {
      final quoteUri = Uri.parse(
        '$_baseUrl/api/v1/pricing/quote/$userId?city=$encodedCity',
      );
      final healthUri = Uri.parse('$_baseUrl/api/v1/pricing/health');
      final alertUri = Uri.parse(
        '$_baseUrl/api/v1/pricing/r-alert/$encodedCity',
      );

      _log('PRICING_QUOTE', 'REQUEST => GET $quoteUri');
      _log('PRICING_HEALTH', 'REQUEST => GET $healthUri');
      _log('PRICING_ALERT', 'REQUEST => GET $alertUri');

      final responses = await Future.wait([
        http.get(quoteUri, headers: {'Accept': 'application/json'}),
        http.get(healthUri, headers: {'Accept': 'application/json'}),
        http.get(alertUri, headers: {'Accept': 'application/json'}),
      ]);

      final quoteRes = responses[0];
      final healthRes = responses[1];
      final alertRes = responses[2];

      _log(
        'PRICING_QUOTE',
        'RESPONSE <= ${quoteRes.statusCode} body=${quoteRes.body}',
      );
      _log(
        'PRICING_HEALTH',
        'RESPONSE <= ${healthRes.statusCode} body=${healthRes.body}',
      );
      _log(
        'PRICING_ALERT',
        'RESPONSE <= ${alertRes.statusCode} body=${alertRes.body}',
      );

      Map<String, dynamic>? quoteMap;
      Map<String, dynamic>? healthMap;
      Map<String, dynamic>? alertMap;
      Map<String, dynamic>? demoMap;

      if (quoteRes.statusCode == 200) {
        quoteMap = jsonDecode(quoteRes.body) as Map<String, dynamic>;
      }
      if (healthRes.statusCode == 200) {
        healthMap = jsonDecode(healthRes.body) as Map<String, dynamic>;
      }
      if (alertRes.statusCode == 200) {
        alertMap = jsonDecode(alertRes.body) as Map<String, dynamic>;
      }

      if (includeDiagnostics) {
        final demoEndpoint = '$_baseUrl/api/demo/pricing-quote';
        final payload = {'userId': userId, 'city': city};
        _log(
          'PRICING_DEMO',
          'REQUEST => POST $demoEndpoint payload=${jsonEncode(payload)}',
        );
        final demoRes = await http.post(
          Uri.parse(demoEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
        _log(
          'PRICING_DEMO',
          'RESPONSE <= ${demoRes.statusCode} body=${demoRes.body}',
        );
        if (demoRes.statusCode == 200) {
          demoMap = jsonDecode(demoRes.body) as Map<String, dynamic>;
        }
      }

      if (!mounted) return;
      final engine = (healthMap?['engine'] as Map?)?.cast<String, dynamic>();
      final engineResponse = (quoteMap?['engineResponse'] as Map?)
          ?.cast<String, dynamic>();
      final topRiskFactors =
          (engineResponse?['top_risk_factors'] as List?) ?? const [];
      final demoPayload = (demoMap?['mlPayload'] as Map?)
          ?.cast<String, dynamic>();

      setState(() {
        if (quoteMap != null) {
          userCity = (quoteMap['city'] ?? city).toString();
          pricingBasePremium = quoteMap['basePremium'] ?? pricingBasePremium;
          pricingFinalPremium = quoteMap['finalPremium'] ?? pricingFinalPremium;
          pricingWRiskScore = quoteMap['wRiskScore'] ?? pricingWRiskScore;
          pricingRAlertMultiplier =
              quoteMap['rAlertMultiplier'] ?? pricingRAlertMultiplier;
          pricingSource = (quoteMap['source'] ?? pricingSource).toString();
          pricingCurrency = (quoteMap['currency'] ?? pricingCurrency)
              .toString();
          pricingTimestamp = (quoteMap['timestamp'] ?? pricingTimestamp)
              .toString();
          pricingEngineResponse = engineResponse;
          pricingConfidence =
              (engineResponse?['confidence'] ?? pricingConfidence).toString();
          pricingTopRiskFactors = topRiskFactors;
        }
        if (alertMap != null) {
          pricingZoneId = (alertMap['zone_id'] ?? pricingZoneId).toString();
          pricingAlertSource = (alertMap['alert_source'] ?? pricingAlertSource)
              .toString();
          pricingDiscountPct = alertMap['discount_pct'] ?? pricingDiscountPct;
          pricingImdLevel = alertMap['imd_level'] ?? pricingImdLevel;
          pricingMaxTemp = alertMap['max_temp'] ?? pricingMaxTemp;
        }
        if (engine != null) {
          pricingEngineStatus = (engine['status'] ?? pricingEngineStatus)
              .toString();
          pricingEngineReady = engine['ready'] == true;
          pricingModelTrainedAt =
              (engine['model_trained_at'] ?? pricingModelTrainedAt).toString();
          pricingTrainingRows =
              (engine['n_training_rows'] ?? pricingTrainingRows) as int;
          pricingDriftThreshold =
              engine['drift_threshold'] ?? pricingDriftThreshold;
          pricingBaselineWRisk =
              engine['baseline_w_risk'] ?? pricingBaselineWRisk;
        }
        pricingMlPayload = demoPayload;
        pricingLoading = false;
      });
    } catch (e) {
      _log('PRICING', 'EXCEPTION => $e');
      if (!mounted) return;
      setState(() => pricingLoading = false);
    }
  }

  Future<void> _sendHeartbeat() async {
    if (userId.isEmpty) return;
    final snapshot = await EdgeEngine.collectSnapshot();

    final payload = {
      'userId': userId,
      'rider_id': userId,
      'delivery_platform': userPlatform,
      'home_zone_id': userCity,
      'status': snapshot.isFraudFlag ? 'FRAUD_FLAG' : 'VERIFIED',
      'lat': snapshot.lat,
      'lng': snapshot.lng,
      'speed': snapshot.speedKmph,
      'maeScore': snapshot.maeScore,
      'sensors': {
        'ax': snapshot.ax,
        'ay': snapshot.ay,
        'az': snapshot.az,
        'gx': snapshot.gx,
        'gy': snapshot.gy,
        'gz': snapshot.gz,
        'vibrationMagnitude': snapshot.vibrationMagnitude,
        'gyroMagnitude': snapshot.gyroMagnitude,
      },
      'location': {
        'lat': snapshot.lat,
        'lng': snapshot.lng,
        'locationName': snapshot.locationName,
        'speedKmph': snapshot.speedKmph,
      },
      'network': {
        'carrierName': snapshot.carrierName,
        'mcc': snapshot.mcc,
        'mnc': snapshot.mnc,
        'cellTowerId': snapshot.cellTowerId,
        'wifiBssid': snapshot.wifiBssid,
        'wifiName': snapshot.wifiName,
      },
      'pricingContext': {
        'home_zone_id': userCity,
        'delivery_platform': userPlatform,
        'max_temp_forecast': snapshot.ambientTempC,
        'rain_mm_7day_forecast': null,
        'wind_gust_kmh_forecast': null,
        'aqi_forecast_avg': null,
        'imd_alert_level_forecast': null,
        'bandh_probability_score': null,
        'festival_calendar_flag': null,
        'political_event_flag': null,
      },
    };

    final endpoint = '$_baseUrl/api/v1/telemetry/heartbeat';
    _log(
      'HEARTBEAT',
      'REQUEST => POST $endpoint payload=${jsonEncode(payload)}',
    );

    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('HEARTBEAT', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        final statusUrl = '$_baseUrl/api/v1/user/heartbeat/$userId';
        final statusRes = await http.get(Uri.parse(statusUrl));
        _log(
          'HEARTBEAT_STATUS',
          'RESPONSE <= ${statusRes.statusCode} body=${statusRes.body}',
        );
        await _fetchPricingBundle(includeDiagnostics: godModeEnabled);
      }
    } catch (e) {
      _log('HEARTBEAT', 'EXCEPTION => $e');
    }
  }

  Future<void> _simulateWeek() async {
    setState(() => loadingWeek = true);
    final payload = {'userId': userId};
    final endpoint = '$_baseUrl/api/demo/simulate-week';
    _log('SIMULATE_WEEK', 'REQUEST => POST $endpoint payload=$payload');

    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('SIMULATE_WEEK', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      await _fetchDashboard();
      await _fetchPricingBundle(includeDiagnostics: godModeEnabled);
      if (mounted) {
        _showToast(
          res.statusCode == 200
              ? 'Week simulation completed!'
              : 'Simulate returned ${res.statusCode}',
          res.statusCode == 200 ? Colors.green : Colors.orange,
        );
      }
    } catch (e) {
      _log('SIMULATE_WEEK', 'EXCEPTION => $e');
      if (mounted) _showToast('Simulate week failed', Colors.red);
    } finally {
      if (mounted) setState(() => loadingWeek = false);
    }
  }

  Future<void> _triggerClaim() async {
    setState(() => loadingClaim = true);
    final snapshot = await EdgeEngine.collectSnapshot();
    final payload = {
      'userId': userId,
      'lat': snapshot.lat,
      'lng': snapshot.lng,
    };
    final endpoint = '$_baseUrl/api/v1/claims/trigger';
    _log('CLAIM_TRIGGER', 'REQUEST => POST $endpoint payload=$payload');

    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('CLAIM_TRIGGER', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body);
        final logs = (map['logs'] as List?) ?? [];
        for (final item in logs) {
          _log(
            'CLAIM_STREAM',
            '${item['step']} :: ${item['status']} :: ${item['message']}',
          );
        }
      }
      await _fetchDashboard();
      await _fetchPricingBundle(includeDiagnostics: godModeEnabled);
    } catch (e) {
      _log('CLAIM_TRIGGER', 'EXCEPTION => $e');
    } finally {
      if (mounted) setState(() => loadingClaim = false);
    }
  }

  Future<void> _promptGodMode() async {
    var password = '';
    final granted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter God Mode Password'),
        content: TextField(
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onChanged: (value) => password = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              password.trim() == AppSecrets.godModePassword,
            ),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (!mounted || granted == null) return;
    if (!granted) {
      _showToast('Invalid god mode password', Colors.red);
      return;
    }
    setState(() => godModeEnabled = true);
    _showToast('God mode enabled', Colors.green);
    await _fetchPricingBundle(includeDiagnostics: true);
  }

  // ---------------------------------------------------------------------------
  // WIDGETS
  // ---------------------------------------------------------------------------

  Widget _metricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(Map<String, dynamic> n) {
    final type = (n['type'] ?? 'INFO').toString();
    final c = type == 'SUCCESS' ? Colors.green : Colors.blueGrey;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n['title']?.toString() ?? '-',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(n['message']?.toString() ?? '-'),
          const SizedBox(height: 4),
          Text(
            n['timestamp']?.toString() ?? '-',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    final riskColor = pricingWRiskScore >= 0.75
        ? Colors.red
        : pricingWRiskScore >= 0.5
        ? Colors.orange
        : Colors.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Dynamic Pricing Quote',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (pricingLoading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$pricingCurrency ${pricingFinalPremium.toStringAsFixed(0)}',
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Base: $pricingCurrency ${pricingBasePremium.toStringAsFixed(0)}  •  Source: $pricingSource  •  City: $userCity',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text('W-Risk ${pricingWRiskScore.toStringAsFixed(2)}'),
                backgroundColor: riskColor.withOpacity(0.12),
                labelStyle: TextStyle(color: riskColor),
              ),
              Chip(
                label: Text(
                  'R-Alert x${pricingRAlertMultiplier.toStringAsFixed(2)}',
                ),
                backgroundColor: Colors.blue.withOpacity(0.1),
              ),
              Chip(
                label: Text(
                  'Discount ${pricingDiscountPct.toStringAsFixed(0)}%',
                ),
                backgroundColor: Colors.green.withOpacity(0.1),
              ),
              Chip(
                label: Text(
                  pricingEngineReady ? 'Engine Ready' : 'Engine Pending',
                ),
                backgroundColor: pricingEngineReady
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Zone: $pricingZoneId  •  Alert source: $pricingAlertSource  •  Confidence: $pricingConfidence',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingDiagnostics() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.greenAccent,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PRICING GOD MODE DIAGNOSTICS'),
            const SizedBox(height: 8),
            Text('engineStatus: $pricingEngineStatus'),
            Text('engineReady: $pricingEngineReady'),
            Text('modelTrainedAt: $pricingModelTrainedAt'),
            Text('trainingRows: $pricingTrainingRows'),
            Text('driftThreshold: ${pricingDriftThreshold.toString()}'),
            Text('baselineWRisk: ${pricingBaselineWRisk.toString()}'),
            Text('rAlertMultiplier: ${pricingRAlertMultiplier.toString()}'),
            Text('imdLevel: ${pricingImdLevel.toString()}'),
            Text('maxTemp: ${pricingMaxTemp.toString()}'),
            Text('quoteTimestamp: $pricingTimestamp'),
            const Divider(color: Colors.white24, height: 24),
            const Text('Top Risk Factors'),
            const SizedBox(height: 6),
            if (pricingTopRiskFactors.isEmpty)
              const Text('No risk-factor breakdown returned.')
            else
              ...pricingTopRiskFactors.take(4).map((factor) {
                final map = Map<String, dynamic>.from(factor as Map);
                return Text('- ${map['factor']}: ${map['score']}');
              }),
            if (pricingMlPayload != null) ...[
              const Divider(color: Colors.white24, height: 24),
              const Text('ML Payload'),
              const SizedBox(height: 6),
              Text(_prettyJson(pricingMlPayload)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSensorTransparencyDiv() {
    return ValueListenableBuilder<EdgeSnapshot>(
      valueListenable: EdgeEngine.liveSnapshot,
      builder: (_, s, __) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(18),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LIVE TELEMETRY TRANSPARENCY DIV'),
                const SizedBox(height: 8),
                Text('timestamp: ${s.timestamp.toIso8601String()}'),
                Text('status: ${s.isFraudFlag ? 'FRAUD_FLAG' : 'VERIFIED'}'),
                Text(
                  'ax/ay/az: ${s.ax.toStringAsFixed(3)} / ${s.ay.toStringAsFixed(3)} / ${s.az.toStringAsFixed(3)}',
                ),
                Text(
                  'gx/gy/gz: ${s.gx.toStringAsFixed(3)} / ${s.gy.toStringAsFixed(3)} / ${s.gz.toStringAsFixed(3)}',
                ),
                Text(
                  'vibrationMagnitude: ${s.vibrationMagnitude.toStringAsFixed(4)}',
                ),
                Text('gyroMagnitude: ${s.gyroMagnitude.toStringAsFixed(4)}'),
                Text('maeScore: ${s.maeScore.toStringAsFixed(4)}'),
                Text('speed(km/h): ${s.speedKmph.toStringAsFixed(2)}'),
                Text(
                  'lat/lng: ${s.lat.toStringAsFixed(5)} / ${s.lng.toStringAsFixed(5)}',
                ),
                Text('locationName: ${s.locationName}'),
                Text('hardwareGps: ${s.hardwareGpsSummary}'),
                const Divider(color: Colors.white24, height: 16),
                const Text('NETWORK CONTEXT'),
                const SizedBox(height: 4),
                Text('carrier: ${s.carrierName}'),
                Text('mcc/mnc: ${s.mcc} / ${s.mnc}'),
                // NOTE: Cell Tower ID and WiFi Fields have been removed
                const Divider(color: Colors.white24, height: 16),
                Text(
                  'ambientTempC: ${s.ambientTempC?.toStringAsFixed(1) ?? 'unavailable'}',
                ),
                Text('interpretation: ${s.interpretation}'),
                const Divider(color: Colors.white24, height: 32),
                const Text(
                  'Active Zonal Protection Enabled',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Iconsax.shield_tick, size: 28),
            const SizedBox(width: 8),
            Text(
              'VRITTI',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 22,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                userName,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: godModeEnabled ? null : _promptGodMode,
            icon: Icon(
              godModeEnabled ? Iconsax.eye : Iconsax.lock,
              color: godModeEnabled ? Colors.greenAccent : Colors.white70,
            ),
          ),
          IconButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Iconsax.logout, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FadeIn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    'Premium Invested',
                    '₹$premiumInvested',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricCard(
                    'Weekly Earnings',
                    '₹$weeklyEarnings',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricCard(
                    'Wallet',
                    '₹$walletBalance',
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _metricCard(
              'Current Fraud Status',
              currentStatus,
              currentStatus == 'FRAUD_FLAG' ? Colors.red : Colors.green,
            ),
            const SizedBox(height: 16),
            _buildPricingCard(),
            const SizedBox(height: 16),
            if (godModeEnabled) ...[
              _buildSensorTransparencyDiv(),
              const SizedBox(height: 16),
              _buildPricingDiagnostics(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: loadingWeek ? null : _simulateWeek,
                      icon: loadingWeek
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Iconsax.flash_1),
                      label: Text(
                        loadingWeek ? 'Simulating...' : 'Simulate Week',
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: loadingClaim ? null : _triggerClaim,
                      icon: loadingClaim
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Iconsax.warning_2),
                      label: Text(
                        loadingClaim ? 'Triggering...' : 'Disruption Trigger',
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Notifications',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (notifications.isEmpty)
              const Text('No notifications yet.')
            else
              ...notifications.whereType<Map>().map(
                (e) => _notificationCard(Map<String, dynamic>.from(e)),
              ),
            if (godModeEnabled) ...[
              const SizedBox(height: 16),
              Text(
                'Terminal Log Stream',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(minHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: terminalLogs
                      .map(
                        (l) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            l,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
