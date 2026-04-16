import 'dart:async';
import 'dart:convert';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

// ---------------------------------------------------------------------------
// INITIALIZE LOCAL NOTIFICATIONS GLOBALLY
// ---------------------------------------------------------------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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

  // Initialize Notifications for Android
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

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
          seedColor: const Color(0xFF005C34),
          primary: const Color(0xFF005C34),
          surface: const Color(0xFFF4F7F5),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF005C34),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
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

  // CHANGE THIS TO http://192.168.x.x:8000 FOR LOCAL TESTING
  static const String _baseUrl = 'https://vritti-ps1s.onrender.com';

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
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      if (res.statusCode == 200) {
        setState(() => _otpSent = true);
      } else {
        _toast('OTP request failed');
      }
    } catch (e) {
      _toast('Network error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _busy = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _phoneController.text.trim(),
          'otp': _codeController.text.trim(),
          'consentGiven': true,
        }),
      );
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
        _toast('Verify failed');
      }
    } catch (e) {
      _toast('Network error');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(
                Iconsax.shield_tick,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'Sign in to Vritti',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: const Icon(Iconsax.mobile),
                filled: true,
                fillColor: const Color(0xFFF4F7F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '6-Digit OTP',
                  prefixIcon: const Icon(Iconsax.password_check),
                  filled: true,
                  fillColor: const Color(0xFFF4F7F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _busy ? null : (_otpSent ? _verifyOtp : _requestOtp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _busy
                      ? 'Processing...'
                      : (_otpSent ? 'Verify Identity' : 'Continue'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Prominent Registration Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: OutlinedButton(
                onPressed: () => Navigator.pushNamed(context, '/registration'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Create new Rider Account',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DASHBOARD SCREEN
// ---------------------------------------------------------------------------

class DemoDashboardScreen extends StatefulWidget {
  const DemoDashboardScreen({super.key});
  @override
  State<DemoDashboardScreen> createState() => _DemoDashboardScreenState();
}

class _DemoDashboardScreenState extends State<DemoDashboardScreen> {
  static const Duration _heartbeatInterval = Duration(seconds: 10);

  // CHANGE THIS TO http://192.168.x.x:8000 FOR LOCAL TESTING
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
  String pricingCurrency = 'INR';
  List<dynamic> pricingTopRiskFactors = [];

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
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // FIRE NATIVE OS NOTIFICATION
  Future<void> _showPushNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'vritti_payouts',
          'Vritti Payouts',
          channelDescription: 'Notifications for instant disruption payouts',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          color: Color(0xFF005C34),
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );
    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(0, title, body, platformDetails);
  }

  Future<void> _requestNotificationPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await androidImplementation?.requestNotificationsPermission();
  }

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissions();
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

    if (userId.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    await _fetchDashboard();
    await _fetchPricingBundle();
    _startTelemetryLoop();
  }

  void _startTelemetryLoop() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _sendHeartbeat();
    });
  }

  Future<void> _fetchDashboard() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/v1/user/dashboard/$userId'),
      );
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

  Future<void> _fetchPricingBundle() async {
    if (userId.isEmpty) return;
    setState(() => pricingLoading = true);
    final encodedCity = Uri.encodeComponent(userCity);

    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/v1/pricing/quote/$userId?city=$encodedCity'),
      );
      if (res.statusCode == 200) {
        final quoteMap = jsonDecode(res.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          pricingBasePremium = quoteMap['basePremium'] ?? pricingBasePremium;
          pricingFinalPremium = quoteMap['finalPremium'] ?? pricingFinalPremium;
          pricingWRiskScore = quoteMap['wRiskScore'] ?? pricingWRiskScore;
          pricingRAlertMultiplier =
              quoteMap['rAlertMultiplier'] ?? pricingRAlertMultiplier;
          pricingTopRiskFactors =
              (quoteMap['engineResponse']?['top_risk_factors'] as List?) ?? [];
        });
      }
    } catch (e) {
      _log('PRICING', 'EXCEPTION => $e');
    } finally {
      if (mounted) setState(() => pricingLoading = false);
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
    };

    try {
      await http.post(
        Uri.parse('$_baseUrl/api/v1/telemetry/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('TELEMETRY', 'Heartbeat synced successfully.');
    } catch (e) {
      _log('TELEMETRY', 'Heartbeat sync failed: $e');
    }
  }

  Future<void> _simulateWeek() async {
    setState(() => loadingWeek = true);
    _log('SIMULATE', 'Initiating simulated week payload...');
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/demo/simulate-week'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      await _fetchDashboard();
      if (mounted) {
        if (res.statusCode == 200 || res.statusCode == 201) {
          _log('SIMULATE', 'Week simulation completed successfully.');
          _showToast('Week simulation completed!', Colors.green);
          await _showPushNotification(
            "Weekly Earnings Protected",
            "Your simulated week has been successfully processed.",
          );
        } else {
          _log('SIMULATE', 'Simulation failed with status ${res.statusCode}');
          _showToast('Simulation Failed', Colors.red);
        }
      }
    } catch (e) {
      _log('SIMULATE', 'Exception during simulate week: $e');
      if (mounted) _showToast('Simulate week failed', Colors.red);
    } finally {
      if (mounted) setState(() => loadingWeek = false);
    }
  }

  Future<void> _triggerClaim() async {
    setState(() => loadingClaim = true);
    final snapshot = await EdgeEngine.collectSnapshot();

    // ========================================================
    // DEMO OVERRIDE:
    // Guarantee 1000% Disruption by spoofing coordinates
    // to active warzones if user selected them during signup.
    // ========================================================
    double claimLat = snapshot.lat;
    double claimLng = snapshot.lng;

    if (userCity == 'Kyiv') {
      claimLat = 50.4501;
      claimLng = 30.5234;
    } else if (userCity == 'Beirut') {
      claimLat = 33.8938;
      claimLng = 35.5018;
    } else if (userCity == 'Gaza') {
      claimLat = 31.5017;
      claimLng = 34.4668;
    }

    final endpoint = godModeEnabled
        ? '$_baseUrl/api/demo/force-trigger'
        : '$_baseUrl/api/v1/claims/one-touch';

    _log('CLAIM', 'Triggering claim via $endpoint for city: $userCity');

    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'lat': claimLat, 'lng': claimLng}),
      );

      final data = jsonDecode(res.body);

      // Log steps for transparency terminal
      if (data['steps'] != null) {
        for (final step in data['steps']) {
          _log(
            'CLAIM_PROCESS',
            '${step['label']} -> ${step['status']}: ${step['detail']}',
          );
        }
      }

      if (res.statusCode == 200 &&
          (data['success'] == true || godModeEnabled)) {
        await _fetchDashboard();

        final amount = data['payoutAmount'] ?? 500;
        _log('CLAIM', 'Claim verified. Payout amount: ₹$amount');

        await _showPushNotification(
          "Disruption Verified!",
          "₹$amount has been successfully credited to your Gullak.",
        );

        if (mounted) {
          setState(() {
            godModeEnabled = false; // Turn off God Mode automatically
          });
          _showToast('Wage Relief Transferred', Colors.green);
        }
      } else {
        _log('CLAIM', 'Claim rejected: ${data['message']}');
        if (mounted) {
          _showToast(
            data['message'] ?? 'Claim Conditions Not Met',
            Colors.orange,
          );
        }
      }
    } catch (e) {
      _log('CLAIM', 'Exception during claim trigger: $e');
      if (mounted) _showToast('Claim Request Failed', Colors.red);
    } finally {
      if (mounted) setState(() => loadingClaim = false);
    }
  }

  Future<void> _toggleGodMode() async {
    if (godModeEnabled) {
      setState(() => godModeEnabled = false);
      return;
    }

    var password = '';
    final granted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Admin Access',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => password = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              backgroundColor: const Color(0xFF005C34),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(
              context,
              password.trim() == AppSecrets.godModePassword,
            ),
            child: const Text('Unlock Analytics'),
          ),
        ],
      ),
    );
    if (!mounted || granted == null) return;
    if (!granted) {
      _showToast('Invalid admin password', Colors.red);
      return;
    }
    setState(() => godModeEnabled = true);
    _showToast('Insurer Intelligence Dashboard Unlocked', Colors.green);
  }

  // ---------------------------------------------------------------------------
  // WORKER UI COMPONENTS
  // ---------------------------------------------------------------------------
  Widget _buildWorkerDashboard() {
    final bool isProtected = currentStatus != 'FRAUD_FLAG';
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final policyDates =
        "${startOfWeek.day}/${startOfWeek.month} - ${endOfWeek.day}/${endOfWeek.month}";
    final policyId =
        "POL-VR${userId.length > 4 ? userId.substring(0, 4).toUpperCase() : '9928'}";

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF005C34), Color(0xFF003820)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF005C34).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'EARNINGS PROTECTED',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Icon(
                    isProtected ? Iconsax.shield_tick : Iconsax.warning_2,
                    color: isProtected ? Colors.greenAccent : Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '₹${walletBalance.toStringAsFixed(2)}',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Divider(color: Colors.white24, height: 32),
              Row(
                children: [
                  _miniStat('Policy ID', policyId),
                  const Spacer(),
                  _miniStat('Coverage', policyDates),
                  const Spacer(),
                  _miniStat('Status', isProtected ? 'Active' : 'Paused'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 65,
          child: ElevatedButton.icon(
            onPressed: loadingClaim ? null : _triggerClaim,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE63946),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: loadingClaim
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Iconsax.flash_1, size: 24),
            label: Text(
              loadingClaim ? 'Processing...' : 'SOS: CLAIM WAGE RELIEF',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),

        Text(
          'Payouts & Claims',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 16),
        if (notifications.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Text(
                'No recent claims. Drive safely!',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          ...notifications.whereType<Map>().map(
            (e) => _notificationCard(Map<String, dynamic>.from(e)),
          ),

        const SizedBox(height: 24),
        Text(
          'Live Activity Log (Transparency)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 200, maxHeight: 300),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SingleChildScrollView(
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
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // ADMIN UI COMPONENTS (GOD MODE)
  // ---------------------------------------------------------------------------
  Widget _buildAdminDashboard() {
    double lossRatio = premiumInvested > 0
        ? (weeklyEarnings / premiumInvested) * 100
        : 0.0;
    double disruptionProb = (pricingWRiskScore * 100).clamp(0, 100).toDouble();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Icon(Iconsax.chart_2, color: Color(0xFF005C34)),
            const SizedBox(width: 8),
            Text(
              'Insurer Intelligence',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _adminMetric(
                'Global Loss Ratio',
                '${lossRatio.toStringAsFixed(1)}%',
                lossRatio > 60 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _adminMetric(
                'Predicted Claims',
                '${disruptionProb.toStringAsFixed(0)}% Prob',
                disruptionProb > 50 ? Colors.orange : Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Simulation Engine',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: loadingWeek ? null : _simulateWeek,
                icon: loadingWeek
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.calendar_1),
                label: const Text('Force Week'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: loadingClaim ? null : _triggerClaim,
                icon: loadingClaim
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Iconsax.danger),
                label: const Text(
                  'Simulate Disruption',
                  style: TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Backend Terminal',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 300, maxHeight: 500),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: terminalLogs
                  .map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
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
        ),
      ],
    );
  }

  Widget _adminMetric(String title, String value, Color statusColor) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
          ],
        ),
      );

  Widget _notificationCard(Map<String, dynamic> n) {
    final type = (n['type'] ?? 'INFO').toString();
    final c = type == 'SUCCESS' ? const Color(0xFF005C34) : Colors.blueGrey;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            type == 'SUCCESS' ? Iconsax.wallet_check : Iconsax.notification,
            color: c,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n['title']?.toString() ?? '-',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  n['message']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  n['timestamp']?.toString() ?? '-',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          godModeEnabled ? 'Vritti Admin' : 'Coverage Dashboard',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _toggleGodMode,
            icon: Icon(
              godModeEnabled ? Iconsax.unlock : Iconsax.lock,
              color: godModeEnabled ? Colors.greenAccent : Colors.white70,
            ),
          ),
          IconButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Iconsax.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FadeIn(
        child: godModeEnabled
            ? _buildAdminDashboard()
            : _buildWorkerDashboard(),
      ),
    );
  }
}
