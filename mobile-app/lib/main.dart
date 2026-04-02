import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Custom Files
import 'registration.dart';
import 'edge_engine.dart';
import 'sms_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await EdgeEngine.init();
  } catch (e) {
    debugPrint("Edge Engine Fail: $e");
  }
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
          seedColor: const Color(0xFF006D32),
          primary: const Color(0xFF006D32),
        ),
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/main': (context) => const MainNavigationController(),
      },
    );
  }
}

// --- UPDATED LOGIN SCREEN (With Policy Assignment) ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLoggingIn = false;

  Future<void> _handleLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');

    if (phone == null) {
      Navigator.pushNamed(context, '/registration');
      return;
    }

    setState(() => isLoggingIn = true);

    try {
      // Backend Login: Validates user and assigns a demo policy if missing
      final response = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      );

      if (response.statusCode == 200) {
        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        if (mounted) Navigator.pushNamed(context, '/registration');
      }
    } catch (e) {
      // Offline fallback for demo stability
      if (mounted) Navigator.pushReplacementNamed(context, '/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInDown(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF006D32),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Iconsax.status_up,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Vritti",
              style: GoogleFonts.outfit(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF006D32),
              ),
            ),
            const SizedBox(height: 60),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: isLoggingIn ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: isLoggingIn
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Enter Dashboard",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- MAIN NAVIGATION CONTROLLER ---
class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});
  @override
  State<MainNavigationController> createState() =>
      _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  int _selectedIndex = 1;

  // Sync state with backend documentation
  String userName = "Rider";
  String userId = "";
  double currentBalance = 0.0;
  double moneyInvested = 0.0;
  double moneyCredited = 0.0;
  String incomeBracket = "Calculating...";

  // Security variables
  String gpsData = "Searching...";
  String detectedCity = "Fetching...";
  String registeredCity = "Delhi";
  bool isGpsSpoofed = false;
  bool isDeviceSecure = true;

  @override
  void initState() {
    super.initState();
    _initSession();
    _startLiveTracking();
    Timer.periodic(const Duration(minutes: 2), (t) => _syncHeartbeat());
  }

  Future<void> _initSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('user_name') ?? "Rider";
      userId = prefs.getString('user_phone') ?? "";
      registeredCity = prefs.getString('user_city') ?? "Delhi";
    });
    _fetchDashboard();
  }

  // --- API: DASHBOARD SYNC ---
  Future<void> _fetchDashboard() async {
    if (userId.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse(
          'https://vritti-ps1s.onrender.com/api/v1/user/dashboard/$userId',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentBalance = (data['currentBalance'] ?? 0).toDouble();
          moneyInvested = (data['moneyInvested'] ?? 0).toDouble();
          moneyCredited = (data['moneyCredited'] ?? 0).toDouble();
          incomeBracket = data['incomeBracket'] ?? "Tier 1";
        });
      }
    } catch (e) {
      debugPrint("Dashboard Sync Error");
    }
  }

  void _startLiveTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          gpsData =
              "${pos.latitude.toStringAsFixed(2)}, ${pos.longitude.toStringAsFixed(2)}";
          isGpsSpoofed = pos.isMocked;
        });
        _reverseGeocode(pos);
      }
    });
  }

  Future<void> _reverseGeocode(Position pos) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${pos.latitude}&longitude=${pos.longitude}&localityLanguage=en',
        ),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        setState(
          () => detectedCity = data['city'] ?? data['locality'] ?? "Chennai",
        );
      }
    } catch (e) {
      setState(() => detectedCity = "Chennai (Fallback)");
    }
  }

  Future<void> _syncHeartbeat() async {
    bool valid = await EdgeEngine.runInference();
    setState(() => isDeviceSecure = valid);
    try {
      await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/heartbeat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": userId,
          "status": valid ? "SECURE" : "FLAGGED",
        }),
      );
    } catch (e) {}
  }

  // --- API: AI DISRUPTION TRIGGER ---
  void triggerPayoutProcess() async {
    await _syncHeartbeat();

    // GUARD 1: DEVICE INTEGRITY (The Edge Engine check)
    if (isGpsSpoofed || !isDeviceSecure) {
      _showToast("🚨 FRAUD: Device or GPS mismatch detected.", Colors.red);
      return;
    }

    // GUARD 2: ZONAL CHECK (Fixed logic)
    if (detectedCity.toLowerCase().trim() !=
        registeredCity.toLowerCase().trim()) {
      _showToast(
        "📍 ZONAL ERROR: Actual Zone ($detectedCity) does not match Registered Zone ($registeredCity).",
        Colors.orange,
      );
      return;
    }

    try {
      // Step 1: AI Evaluation (Server side)
      final evalRes = await http.post(
        Uri.parse(
          'https://vritti-ps1s.onrender.com/api/v1/intelligence/evaluate',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"city": registeredCity}),
      );

      // Step 2: Demo Force Trigger (Credits the specific user)
      await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/demo/force-trigger'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": userId, "city": registeredCity}),
      );

      if (evalRes.statusCode == 200 || evalRes.statusCode == 201) {
        _showToast("✅ Disruption Verified. Wallet Credited.", Colors.green);
        _fetchDashboard(); // Update values
      }
    } catch (e) {
      _showToast("Backend Error", Colors.red);
    }
  }

  void _showToast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      InfoScreen(
        gps: gpsData,
        city: detectedCity,
        workCity: registeredCity,
        isSecure: isDeviceSecure,
        isSpoofed: isGpsSpoofed,
        onPayout: triggerPayoutProcess,
        onRefresh: _syncHeartbeat,
      ),
      HomeScreen(name: userName, invested: moneyInvested),
      ProfileScreen(
        name: userName,
        balance: currentBalance,
        payouts: moneyCredited,
        bracket: incomeBracket,
        phone: userId,
        city: registeredCity,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: screens[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(40),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 30),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _navItem(0, Iconsax.security_safe, "Security"),
        _navItem(1, Iconsax.home, "Home"),
        _navItem(2, Iconsax.user, "Profile"),
      ],
    ),
  );

  Widget _navItem(int i, IconData icon, String label) {
    bool active = _selectedIndex == i;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF006D32) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? Colors.white : Colors.grey[400],
              size: 24,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: active ? Colors.white : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- HOME SCREEN (Safety Investments) ---
class HomeScreen extends StatelessWidget {
  final String name;
  final double invested;
  const HomeScreen({super.key, required this.name, required this.invested});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Namaste, $name",
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            _card("TOTAL SAFETY INVESTMENTS", invested, Iconsax.verify),
            const SizedBox(height: 32),
            const Text(
              "Active Protections",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _tile(
              "Zonal Rain Shield",
              "Parametric • Active",
              Iconsax.cloud_notif,
            ),
            _tile(
              "Strike Protection",
              "Platform • Active",
              Iconsax.security_user,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, double value, IconData icon) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF006D32),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "₹${value.toStringAsFixed(2)}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Divider(color: Colors.white24, height: 32),
        const Row(
          children: [
            Icon(Iconsax.shield_tick, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(
              "Rider SIP Active • Secured by Vritti",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _tile(String t, String s, IconData i) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: const Color(0xFFF0F4F1),
      child: Icon(i, color: const Color(0xFF006D32), size: 20),
    ),
    title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: Text(s),
    trailing: const Icon(Iconsax.arrow_right_3, size: 16, color: Colors.grey),
  );
}

// --- PROFILE SCREEN (Payouts & Gullak) ---
class ProfileScreen extends StatelessWidget {
  final String name, phone, city, bracket;
  final double balance, payouts;
  const ProfileScreen({
    super.key,
    required this.name,
    required this.phone,
    required this.city,
    required this.bracket,
    required this.balance,
    required this.payouts,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF006D32),
              child: Text(
                name[0],
                style: const TextStyle(
                  fontSize: 32,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            _miniDashboard(),
            const SizedBox(height: 24),
            _info(Iconsax.status_up, "Verified Income Tier", bracket),
            _info(Iconsax.mobile, "Phone Number", phone),
            _info(Iconsax.location, "Work City", city),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              child: const Text("Log Out", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniDashboard() => Row(
    children: [
      _box(
        "Gullak (Balance)",
        "₹${balance.toStringAsFixed(0)}",
        Iconsax.wallet,
      ),
      const SizedBox(width: 12),
      _box(
        "Total Payouts",
        "₹${payouts.toStringAsFixed(0)}",
        Iconsax.receive_square,
      ),
    ],
  );

  Widget _box(String l, String v, IconData i) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, color: const Color(0xFF006D32), size: 20),
          const SizedBox(height: 8),
          Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    ),
  );

  Widget _info(IconData i, String t, String s) => ListTile(
    leading: Icon(i, color: const Color(0xFF006D32)),
    title: Text(t, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    subtitle: Text(
      s,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Colors.black,
      ),
    ),
  );
}

// --- SECURITY HUB (Hardware Validation) ---
class InfoScreen extends StatelessWidget {
  final String gps, city, workCity;
  final bool isSpoofed, isSecure;
  final VoidCallback onPayout, onRefresh;
  const InfoScreen({
    super.key,
    required this.gps,
    required this.city,
    required this.workCity,
    required this.isSpoofed,
    required this.isSecure,
    required this.onPayout,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Security Hub",
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF006D32),
              ),
            ),
            const SizedBox(height: 24),
            _statusCard(),
            const Spacer(),
            ElevatedButton(
              onPressed: onRefresh,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text("Re-scan Physical Integrity"),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onPayout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text("Force AI Evaluation (Demo)"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      children: [
        _row(
          Iconsax.gps,
          "HARDWARE GPS",
          isSpoofed ? "SPOOFED" : "LOCKED",
          isSpoofed ? Colors.red : Colors.green,
        ),
        const Divider(height: 40),
        _row(
          Iconsax.cpu,
          "EDGE AI ENGINE",
          isSecure ? "SECURE" : "FLAGGED",
          isSecure ? Colors.green : Colors.red,
        ),
        const Divider(height: 40),
        _row(
          Iconsax.location,
          "RESOLVED ZONE",
          city,
          city == workCity ? Colors.blue : Colors.orange,
        ),
      ],
    ),
  );

  Widget _row(IconData i, String l, String v, Color c) => Row(
    children: [
      Icon(i, color: c),
      const SizedBox(width: 16),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    ],
  );
}
