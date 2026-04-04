import 'dart:async';
import 'dart:convert';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edge_engine.dart';
import 'registration.dart';

String _ts() => DateTime.now().toIso8601String();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D32)),
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

  void _log(String m) => debugPrint('[${_ts()}] [AUTH] $m');

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
        _toast('OTP request failed');
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
      'code': _codeController.text.trim(),
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
        await prefs.setString('user_name', (map['name'] ?? 'Rider').toString());
        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        _toast('Verify failed');
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.shield_tick, size: 80, color: Color(0xFF006D32)),
            const SizedBox(height: 16),
            Text('Vritti Login', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800)),
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
                child: Text(_busy ? 'Processing...' : (_otpSent ? 'Verify OTP' : 'Request OTP')),
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

class DemoDashboardScreen extends StatefulWidget {
  const DemoDashboardScreen({super.key});

  @override
  State<DemoDashboardScreen> createState() => _DemoDashboardScreenState();
}

class _DemoDashboardScreenState extends State<DemoDashboardScreen> {
  String userId = '';
  String userName = 'Rider';

  num premiumInvested = 0;
  num weeklyEarnings = 0;
  num walletBalance = 0;
  String currentStatus = 'UNKNOWN';
  List<dynamic> notifications = [];

  bool loadingWeek = false;
  bool loadingClaim = false;

  Timer? heartbeatTimer;
  final List<String> terminalLogs = [];

  void _log(String scope, String msg) {
    final line = '[${_ts()}] [$scope] $msg';
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      terminalLogs.insert(0, line);
      if (terminalLogs.length > 150) terminalLogs.removeLast();
    });
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
    _log('BOOT', 'Loaded session userId=$userId userName=$userName');
    if (userId.isEmpty) {
      _log('BOOT', 'No user session found. Redirecting to login.');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    await _fetchDashboard();
    _startTelemetryLoop();
  }

  void _startTelemetryLoop() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _sendHeartbeat();
    });
    _log('TELEMETRY', 'Started 1-second heartbeat loop for demo mode.');
  }

  Future<void> _fetchDashboard() async {
    final url = 'https://vritti-ps1s.onrender.com/api/v1/user/dashboard/$userId';
    _log('DASHBOARD', 'REQUEST => GET $url');
    try {
      final res = await http.get(Uri.parse(url));
      _log('DASHBOARD', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode != 200) return;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
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

  Future<void> _sendHeartbeat() async {
    if (userId.isEmpty) return;

    final snapshot = await EdgeEngine.collectSnapshot();
    final payload = {
      'userId': userId,
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
      },
      'location': {'lat': snapshot.lat, 'lng': snapshot.lng},
    };

    const endpoint = 'https://vritti-ps1s.onrender.com/api/v1/telemetry/heartbeat';
    _log('HEARTBEAT', 'REQUEST => POST $endpoint payload=${jsonEncode(payload)}');

    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('HEARTBEAT', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        final statusUrl = 'https://vritti-ps1s.onrender.com/api/v1/user/heartbeat/$userId';
        final statusRes = await http.get(Uri.parse(statusUrl));
        _log('HEARTBEAT_STATUS', 'RESPONSE <= ${statusRes.statusCode} body=${statusRes.body}');
      }
    } catch (e) {
      _log('HEARTBEAT', 'EXCEPTION => $e');
    }
  }

  Future<void> _simulateWeek() async {
    setState(() => loadingWeek = true);
    final payload = {'userId': userId};
    const endpoint = 'https://vritti-ps1s.onrender.com/api/demo/simulate-week';
    _log('SIMULATE_WEEK', 'REQUEST => POST $endpoint payload=$payload');

    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('SIMULATE_WEEK', 'RESPONSE <= ${res.statusCode} body=${res.body}');
      await _fetchDashboard();
      if (mounted && res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Week simulation completed!')),
        );
      }
    } catch (e) {
      _log('SIMULATE_WEEK', 'EXCEPTION => $e');
    } finally {
      setState(() => loadingWeek = false);
    }
  }

  Future<void> _triggerClaim() async {
    setState(() => loadingClaim = true);
    final snapshot = await EdgeEngine.collectSnapshot();
    final payload = {'userId': userId, 'lat': snapshot.lat, 'lng': snapshot.lng};
    const endpoint = 'https://vritti-ps1s.onrender.com/api/v1/claims/trigger';
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
    } catch (e) {
      _log('CLAIM_TRIGGER', 'EXCEPTION => $e');
    } finally {
      setState(() => loadingClaim = false);
    }
  }

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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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
          Text(n['title']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(n['message']?.toString() ?? '-'),
          const SizedBox(height: 4),
          Text(n['timestamp']?.toString() ?? '-', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
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
            style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LIVE TELEMETRY TRANSPARENCY DIV'),
                const SizedBox(height: 8),
                Text('timestamp: ${s.timestamp.toIso8601String()}'),
                Text('status: ${s.isFraudFlag ? 'FRAUD_FLAG' : 'VERIFIED'}'),
                Text('ax/ay/az: ${s.ax.toStringAsFixed(3)} / ${s.ay.toStringAsFixed(3)} / ${s.az.toStringAsFixed(3)}'),
                Text('gx/gy/gz: ${s.gx.toStringAsFixed(3)} / ${s.gy.toStringAsFixed(3)} / ${s.gz.toStringAsFixed(3)}'),
                Text('vibrationMagnitude: ${s.vibrationMagnitude.toStringAsFixed(4)}'),
                Text('gyroMagnitude: ${s.gyroMagnitude.toStringAsFixed(4)}'),
                Text('maeScore: ${s.maeScore.toStringAsFixed(4)}'),
                Text('speed(km/h): ${s.speedKmph.toStringAsFixed(2)}'),
                Text('lat/lng: ${s.lat.toStringAsFixed(5)} / ${s.lng.toStringAsFixed(5)}'),
                Text('locationName: ${s.locationName}'),
                Text('hardwareGps: ${s.hardwareGpsSummary}'),
                Text('cellTowerId: ${s.cellTowerId}'),
                Text('cellTowerName: ${s.cellTowerName}'),
                Text('wifiBssid: ${s.wifiBssid}'),
                Text('wifiName: ${s.wifiName}'),
                const SizedBox(height: 6),
                Text('interpretation: ${s.interpretation}'),
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
        title: Text('Vritti Demo Console — $userName'),
        actions: [
          IconButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Iconsax.logout),
          ),
        ],
      ),
      body: FadeIn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: _metricCard('Premium Invested', '₹$premiumInvested', Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _metricCard('Weekly Earnings', '₹$weeklyEarnings', Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _metricCard('Wallet', '₹$walletBalance', Colors.orange)),
              ],
            ),
            const SizedBox(height: 8),
            _metricCard('Current Fraud Status', currentStatus, currentStatus == 'FRAUD_FLAG' ? Colors.red : Colors.green),
            const SizedBox(height: 14),
            _buildSensorTransparencyDiv(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loadingWeek ? null : _simulateWeek,
                    icon: loadingWeek
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Iconsax.flash_1),
                    label: Text(loadingWeek ? 'Simulating...' : 'Simulate Week'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loadingClaim ? null : _triggerClaim,
                    icon: loadingClaim
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Iconsax.warning_2),
                    label: Text(loadingClaim ? 'Triggering...' : 'Disruption Trigger'),
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
            Text('Notifications', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (notifications.isEmpty)
              const Text('No notifications yet.')
            else
              ...notifications
                  .whereType<Map>()
                  .map((e) => _notificationCard(Map<String, dynamic>.from(e))),
            const SizedBox(height: 16),
            Text('Terminal Log Stream', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700)),
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
        ),
      ),
    );
  }
}
