import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _apiBaseUrl = 'http://localhost:10000';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final PageController _pageController = PageController();

  int _currentStep = 0;
  String name = '';
  String phone = '';
  String otp = '';
  String workCity = 'Chennai';
  bool isProcessing = false;
  bool consentAccepted = false;
  Map<String, dynamic>? _verifiedUser;

  static const List<String> _cities = [
    'Chennai',
    'Mumbai',
    'Delhi',
    'Bangalore',
    'Hyderabad',
    'Pune',
  ];

  Future<void> _requestOTP() async {
    if (name.trim().isEmpty || phone.trim().length < 10) return;

    setState(() => isProcessing = true);
    try {
      final res = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone.trim()}),
      );

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _nextPage();
      } else {
        _showSnack('Failed to request OTP');
      }
    } catch (_) {
      if (mounted) _showSnack('Unable to reach server');
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _verifyOTP() async {
    if (otp.trim().isEmpty) return;

    setState(() => isProcessing = true);
    try {
      final res = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone.trim(),
          'otp': otp.trim(),
          'name': name.trim(),
          'city': workCity,
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _verifiedUser = jsonDecode(res.body) as Map<String, dynamic>;
        _nextPage();
      } else {
        final body = jsonDecode(res.body);
        _showSnack(body['message']?.toString() ?? 'OTP verification failed');
      }
    } catch (_) {
      if (mounted) _showSnack('Unable to verify OTP');
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _finishOnboarding() async {
    if (!consentAccepted || _verifiedUser == null) return;

    final user = _verifiedUser!['user'] as Map<String, dynamic>?;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', user['id'].toString());
    await prefs.setString('user_name', user['name']?.toString() ?? name.trim());
    await prefs.setString('user_phone', phone.trim());
    await prefs.setString('user_city', workCity);

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/main');
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
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
                children: [_stepRegistration(), _stepOtp(), _stepConsent()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() => Row(
    children: List.generate(
      3,
      (i) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          height: 4,
          decoration: BoxDecoration(
            color: _currentStep >= i ? const Color(0xFF006D32) : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );

  Widget _stepRegistration() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sign Up', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Text('Name, phone and city are required to create your protection profile.'),
        const SizedBox(height: 28),
        _field('Full Name', Iconsax.user, (v) => name = v),
        const SizedBox(height: 16),
        _field('Phone Number', Iconsax.mobile, (v) => phone = v),
        const SizedBox(height: 16),
        _drop('City', workCity, _cities, (v) => setState(() => workCity = v ?? workCity)),
        const Spacer(),
        _btn(isProcessing ? 'Requesting OTP...' : 'Request OTP', _requestOTP),
      ],
    ),
  );

  Widget _stepOtp() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OTP Verification', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('Enter OTP sent to $phone'),
        const SizedBox(height: 28),
        _field('6-digit OTP', Iconsax.password_check, (v) => otp = v),
        const Spacer(),
        _btn(isProcessing ? 'Verifying...' : 'Verify OTP', _verifyOTP),
      ],
    ),
  );

  Widget _stepConsent() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Consent', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const Text(
            'I agree to location and sensor processing for fraud prevention and payout eligibility checks under Vritti policy terms.',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('I provide my consent'),
          value: consentAccepted,
          onChanged: (v) => setState(() => consentAccepted = v ?? false),
        ),
        const Spacer(),
        _btn('Continue to Dashboard', consentAccepted ? _finishOnboarding : () {}),
      ],
    ),
  );

  Widget _field(String hint, IconData icon, Function(String) onChanged) => TextField(
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _drop(String label, String value, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
      items: items.map((city) => DropdownMenuItem<String>(value: city, child: Text(city))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _btn(String title, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    height: 60,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF006D32),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(title),
    ),
  );
}
