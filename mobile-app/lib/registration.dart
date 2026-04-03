import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

String _regTimestamp() => DateTime.now().toIso8601String();

dynamic _regTryDecodeJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String _regPrettyJson(dynamic data) {
  if (data == null) return 'null';
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Data State
  String name = "";
  String phone = "";
  String otp = "";
  String selectedPlatform = "Swiggy";
  String workCity = "Chennai";
  bool isProcessing = false;

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  // STEP 1: Request OTP
  Future<void> _requestOTP() async {
    if (phone.length < 10) {
      _showToast("Enter a valid phone number", Colors.orange);
      return;
    }

    setState(() => isProcessing = true);
    final url = 'https://vritti-ps1s.onrender.com/api/v1/auth/request-otp';
    final payload = {"phone": phone};
    debugPrint("[${_regTimestamp()}] [REG] Request => POST $url");
    debugPrint("[${_regTimestamp()}] [REG] Payload => ${_regPrettyJson(payload)}");

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      final decoded = _regTryDecodeJson(res.body);
      debugPrint(
        "[${_regTimestamp()}] [REG] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_regTimestamp()}] [REG] Response Body <= ${_regPrettyJson(decoded ?? res.body)}",
      );

      if (res.statusCode == 200) {
        _nextPage();
      } else {
        _showToast("Failed to send OTP", Colors.red);
      }
    } catch (e) {
      debugPrint("[${_regTimestamp()}] [REG] Exception during request OTP => $e");
      _showToast("Network Error", Colors.red);
    } finally {
      setState(() => isProcessing = false);
    }
  }

  // STEP 4: Final Verification & Consent
  Future<void> _completeRegistration() async {
    if (name.trim().isEmpty) {
      _showToast("Name is required for Sign Up", Colors.orange);
      return;
    }
    if (otp.trim().isEmpty) {
      _showToast("Please enter OTP", Colors.orange);
      return;
    }
    setState(() => isProcessing = true);
    final url = 'https://vritti-ps1s.onrender.com/api/v1/auth/verify-otp';
    final payload = {
      "phone": phone,
      "otp": otp,
      "name": name.trim(),
      "platform": selectedPlatform,
      "city": workCity,
      "consentGiven": true,
    };
    debugPrint("[${_regTimestamp()}] [REG] Request => POST $url");
    debugPrint("[${_regTimestamp()}] [REG] Payload => ${_regPrettyJson(payload)}");

    try {
      // Backend production requirement: Sign Up requires all fields + consentGiven: true
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      final data = _regTryDecodeJson(res.body);
      debugPrint(
        "[${_regTimestamp()}] [REG] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_regTimestamp()}] [REG] Response Body <= ${_regPrettyJson(data ?? res.body)}",
      );

      if (res.statusCode == 200) {
        final userData = data ?? jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('user_id', userData['user']['id']);
        await prefs.setString('user_name', userData['user']['name']);
        await prefs.setString('user_phone', phone);
        await prefs.setString('user_city', workCity);

        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        final err = (data is Map<String, dynamic>) ? data['error'] : null;
        _showToast(
          err?.toString() ?? "Invalid OTP or Registration Failed",
          Colors.red,
        );
      }
    } catch (e) {
      debugPrint(
        "[${_regTimestamp()}] [REG] Exception during complete registration => $e",
      );
      _showToast("Connection failed", Colors.red);
    } finally {
      setState(() => isProcessing = false);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildStepIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _stepIdentity(),
                  _stepOTP(),
                  _stepWorkDetails(),
                  _stepConsent(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Row(
      children: List.generate(
        4,
        (i) => Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: _currentStep >= i
                  ? const Color(0xFF006D32)
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _stepIdentity() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeInDown(
          child: Text(
            "Create your\nSafety Account",
            style: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 40),
        _field("Full Name", Iconsax.user, (v) => name = v),
        const SizedBox(height: 20),
        _field(
          "Mobile Number",
          Iconsax.mobile,
          (v) => phone = v,
          type: TextInputType.phone,
        ),
        const Spacer(),
        _btn(isProcessing ? "Processing..." : "Verify Identity", _requestOTP),
      ],
    ),
  );

  Widget _stepOTP() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Verify Phone",
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          "We've sent an OTP to $phone",
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 40),
        _field(
          "6-Digit Code",
          Iconsax.password_check,
          (v) => otp = v,
          type: TextInputType.number,
        ),
        const Spacer(),
        _btn("Confirm Code", _nextPage),
      ],
    ),
  );

  Widget _stepWorkDetails() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Work Profile",
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 40),
        _drop(
          "Primary Platform",
          selectedPlatform,
          ["Swiggy", "Zomato", "Uber Eats"],
          (v) => setState(() => selectedPlatform = v!),
        ),
        const SizedBox(height: 20),
        _drop("Base City", workCity, [
          "Chennai",
          "Mumbai",
          "Delhi",
          "Bangalore",
        ], (v) => setState(() => workCity = v!)),
        const Spacer(),
        _btn("Next: Legal Consent", _nextPage),
      ],
    ),
  );

  Widget _stepConsent() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Iconsax.shield_security, size: 80, color: Color(0xFF006D32)),
        const SizedBox(height: 24),
        Text(
          "Rider Consent",
          style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          "To provide proof of income and verify parametric claims, Vritti requires background access to your sensors and location while you are on a shift. This data is encrypted and used only for payout verification.",
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: Colors.grey),
        ),
        const Spacer(),
        _btn(
          isProcessing ? "Initialising Wallet..." : "I Agree & Finish",
          _completeRegistration,
        ),
      ],
    ),
  );

  Widget _field(
    String h,
    IconData i,
    Function(String) o, {
    TextInputType type = TextInputType.text,
  }) => TextField(
    onChanged: o,
    keyboardType: type,
    decoration: InputDecoration(
      prefixIcon: Icon(i),
      hintText: h,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _drop(String l, String v, List<String> items, Function(String?) o) =>
      DropdownButtonFormField<String>(
        value: v,
        decoration: InputDecoration(
          labelText: l,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: o,
      );

  Widget _btn(String t, VoidCallback p) => SizedBox(
    width: double.infinity,
    height: 60,
    child: ElevatedButton(
      onPressed: p,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF006D32),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}
