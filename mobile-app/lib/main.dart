import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edge_engine.dart';
import 'registration.dart';

const String _apiBaseUrl = 'http://localhost:10000';

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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D32)),
      ),
      initialRoute: '/registration',
      routes: {
        '/registration': (_) => const RegistrationScreen(),
        '/main': (_) => const MainNavigationController(),
      },
    );
  }
}

class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});

  @override
  State<MainNavigationController> createState() => _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  int _selectedIndex = 0;

  String userId = '';
  String userName = 'Driver';
  String city = 'Chennai';
  String gps = 'Locating...';

  double gullakBalance = 0;
  double totalPayout = 0;
  bool policyActive = false;

  bool isFraudFlagged = false;
  SensorSnapshot sensor = EdgeEngine.lastSnapshot;

  StreamSubscription<Position>? _locationSub;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id') ?? '';
    userName = prefs.getString('user_name') ?? 'Driver';
    city = prefs.getString('user_city') ?? 'Chennai';

    await _refreshDashboard();
    _startLocationSync();
    await _runAndSendHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _runAndSendHeartbeat(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _refreshDashboard() async {
    if (userId.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$_apiBaseUrl/api/v1/user/dashboard/$userId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          gullakBalance = (data['currentBalance'] ?? data['walletBalance'] ?? 0).toDouble();
          totalPayout = (data['moneyCredited'] ?? data['totalPayout'] ?? 0).toDouble();
          policyActive = (data['policyActive'] ?? true) as bool;
        });
      }

      final policyRes = await http.get(Uri.parse('$_apiBaseUrl/api/v1/premium/policies/$userId'));
      if (policyRes.statusCode == 200) {
        final raw = jsonDecode(policyRes.body);
        final first = raw is List && raw.isNotEmpty ? raw.first as Map<String, dynamic> : null;
        if (first != null && mounted) {
          setState(() {
            final status = (first['status'] ?? '').toString().toUpperCase();
            policyActive = status == 'ACTIVE' || status == 'VERIFIED' || status == 'IN_FORCE';
          });
        }
      }
    } catch (_) {
      // Keep stale UI values if server is unavailable.
    }
  }

  void _startLocationSync() {
    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen((pos) async {
      final coords = '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';
      if (mounted) setState(() => gps = coords);
      if (userId.isEmpty) return;

      try {
        await http.post(
          Uri.parse('$_apiBaseUrl/api/v1/user/location'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': userId,
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'city': city,
          }),
        );
      } catch (_) {}
    });
  }

  Future<void> _runAndSendHeartbeat() async {
    if (userId.isEmpty) return;

    final snapshot = await EdgeEngine.runInference();
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'status': snapshot.heartbeatStatus}),
      );

      final statusRes = await http.get(Uri.parse('$_apiBaseUrl/api/v1/user/heartbeat/$userId'));
      if (statusRes.statusCode == 200) {
        final body = jsonDecode(statusRes.body) as Map<String, dynamic>;
        final status = (body['status'] ?? snapshot.heartbeatStatus).toString().toUpperCase();
        isFraudFlagged = status.contains('FLAG');
      } else {
        isFraudFlagged = snapshot.isFlagged;
      }
    } catch (_) {
      isFraudFlagged = snapshot.isFlagged;
    }

    if (mounted) {
      setState(() {
        sensor = snapshot;
      });
    }
  }

  Future<void> _claimPayout() async {
    if (userId.isEmpty) return;

    final logs = <String>[];

    Future<void> addLog(String line) async {
      logs.add(line);
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ClaimLogDialog(logs: List<String>.from(logs)),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    await addLog('Policy check ✓');
    final policyRes = await http.get(Uri.parse('$_apiBaseUrl/api/v1/premium/policies/$userId'));
    if (policyRes.statusCode >= 400) {
      _snack('Policy not active');
      return;
    }

    await addLog('News Scraper ✓');
    await http.get(Uri.parse('$_apiBaseUrl/api/v1/intelligence/status/$city'));

    await addLog('Weather ✓');
    await http.get(Uri.parse('$_apiBaseUrl/api/v1/intelligence/history/$city'));

    await addLog('Edge Engine ✓');
    await _runAndSendHeartbeat();

    final claimRes = await http.post(
      Uri.parse('$_apiBaseUrl/api/v1/claims/one-touch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'city': city}),
    );

    if (!mounted) return;

    if (claimRes.statusCode == 200 || claimRes.statusCode == 201) {
      final body = jsonDecode(claimRes.body) as Map<String, dynamic>;
      final amount = (body['amount'] ?? body['payoutAmount'] ?? 500).toDouble();
      setState(() => gullakBalance += amount);
      _snack('₹${amount.toStringAsFixed(0)} added to Gullak!');
      await _refreshDashboard();
    } else {
      String message = 'Claim rejected';
      try {
        final body = jsonDecode(claimRes.body) as Map<String, dynamic>;
        message = body['message']?.toString() ?? message;
      } catch (_) {}
      _snack(message);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        name: userName,
        city: city,
        gps: gps,
        walletBalance: gullakBalance,
        policyActive: policyActive,
        isFraudFlagged: isFraudFlagged,
        sensor: sensor,
        onClaimTap: _claimPayout,
        onManualHeartbeat: _runAndSendHeartbeat,
      ),
      ProfileScreen(
        name: userName,
        city: city,
        walletBalance: gullakBalance,
        totalPayout: totalPayout,
        policyActive: policyActive,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: SafeArea(child: screens[_selectedIndex]),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Iconsax.home, 'Dashboard'),
            _navItem(1, Iconsax.user, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF006D32) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey[700]),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.name,
    required this.city,
    required this.gps,
    required this.walletBalance,
    required this.policyActive,
    required this.isFraudFlagged,
    required this.sensor,
    required this.onClaimTap,
    required this.onManualHeartbeat,
  });

  final String name;
  final String city;
  final String gps;
  final double walletBalance;
  final bool policyActive;
  final bool isFraudFlagged;
  final SensorSnapshot sensor;
  final VoidCallback onClaimTap;
  final VoidCallback onManualHeartbeat;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Namaste, $name', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800)),
          Text('City: $city', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 18),
          _walletCard(),
          const SizedBox(height: 16),
          _policyCard(),
          const SizedBox(height: 16),
          _sensorCard(),
          const SizedBox(height: 16),
          _fraudCard(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onClaimTap,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006D32), foregroundColor: Colors.white),
              child: const Text('Claim Payout'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(onPressed: onManualHeartbeat, child: const Text('Refresh Fraud Indicator')),
          ),
        ],
      ),
    );
  }

  Widget _walletCard() => _card(
    'Gullak Balance',
    '₹${walletBalance.toStringAsFixed(2)}',
    Iconsax.wallet,
    const Color(0xFF006D32),
  );

  Widget _policyCard() => _card(
    'Policy Status',
    policyActive ? 'ACTIVE' : 'INACTIVE',
    Iconsax.shield_tick,
    policyActive ? Colors.green : Colors.orange,
  );

  Widget _sensorCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Edge Engine Sensor Readings', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('GPS: $gps'),
        Text('Speed: ${sensor.speedKmh.toStringAsFixed(1)} km/h'),
        Text('Accel Energy: ${sensor.accelEnergy.toStringAsFixed(2)}'),
        Text('MAE mismatch: ${sensor.mae.toStringAsFixed(2)}'),
      ],
    ),
  );

  Widget _fraudCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isFraudFlagged ? Colors.red.shade50 : Colors.green.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: isFraudFlagged ? Colors.red : Colors.green),
    ),
    child: Row(
      children: [
        Icon(Iconsax.security_safe, color: isFraudFlagged ? Colors.red : Colors.green),
        const SizedBox(width: 10),
        Text(
          isFraudFlagged ? 'FRAUD INDICATOR: RED' : 'FRAUD INDICATOR: GREEN',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isFraudFlagged ? Colors.red : Colors.green,
          ),
        ),
      ],
    ),
  );

  Widget _card(String label, String value, IconData icon, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      ],
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.name,
    required this.city,
    required this.walletBalance,
    required this.totalPayout,
    required this.policyActive,
  });

  final String name;
  final String city;
  final double walletBalance;
  final double totalPayout;
  final bool policyActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 38,
            backgroundColor: Color(0xFF006D32),
            child: Icon(Iconsax.user, size: 32, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(name, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(city, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          _line('Gullak Balance', '₹${walletBalance.toStringAsFixed(2)}'),
          _line('Total Payout Received', '₹${totalPayout.toStringAsFixed(2)}'),
          _line('Policy', policyActive ? 'Active' : 'Inactive'),
        ],
      ),
    );
  }

  Widget _line(String k, String v) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))],
    ),
  );
}

class _ClaimLogDialog extends StatelessWidget {
  const _ClaimLogDialog({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Claim pipeline'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: logs.map((line) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line))).toList(),
        ),
      ),
    );
  }
}
