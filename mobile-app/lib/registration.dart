import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _regTs() => DateTime.now().toIso8601String();

dynamic _regTryDecodeJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

const List<String> _kIndiaCities = [
  'Ahmedabad',
  'Bengaluru',
  'Bhopal',
  'Chennai',
  'Coimbatore',
  'Delhi',
  'Gurgaon',
  'Hyderabad',
  'Indore',
  'Jaipur',
  'Kochi',
  'Kolkata',
  'Lucknow',
  'Mumbai',
  'Nagpur',
  'Noida',
  'Patna',
  'Pune',
  'Surat',
  'Visakhapatnam',
  // --- GUARANTEED DISRUPTION ZONES FOR DEMO ---
  'Kyiv',
  'Beirut',
  'Gaza',
];

const List<String> _kPlatforms = [
  'Swiggy',
  'Zomato',
  'Uber',
  'Dunzo',
  'Blinkit',
  'Zepto',
];

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  String _city = 'Chennai';
  String _platform = 'Swiggy';
  bool _consentGiven = false;
  bool _otpRequested = false;
  bool _isBusy = false;

  // CHANGE THIS TO http://192.168.x.x:8000 FOR LOCAL TESTING
  static const _base = 'https://vritti-ps1s.onrender.com';

  void _log(String msg) => debugPrint('[$_regTs()] [REGISTRATION] $msg');

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      _toast('Enter valid phone number');
      return;
    }

    setState(() => _isBusy = true);
    final payload = {'phone': phone};
    _log('REQUEST => POST /api/v1/auth/request-otp payload=$payload');

    try {
      final res = await http.post(
        Uri.parse('$_base/api/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        setState(() => _otpRequested = true);
        _toast('OTP sent');
      } else {
        final decoded = _regTryDecodeJson(res.body);
        final msg =
            (decoded is Map ? decoded['error'] : null) ?? 'OTP request failed';
        _toast(msg.toString());
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error while requesting OTP');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyAndSignup() async {
    if (_nameController.text.trim().isEmpty) {
      _toast('Name required');
      return;
    }
    if (!_consentGiven) {
      _toast('Consent is mandatory');
      return;
    }

    final payload = {
      'phone': _phoneController.text.trim(),
      'otp': _codeController.text.trim(),
      'name': _nameController.text.trim(),
      'city': _city,
      'platform': _platform,
      'consentGiven': true,
    };

    setState(() => _isBusy = true);
    _log('REQUEST => POST /api/v1/auth/verify-otp payload=$payload');

    try {
      final res = await http.post(
        Uri.parse('$_base/api/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      _log('RESPONSE <= ${res.statusCode} body=${res.body}');

      if (res.statusCode == 200) {
        final map = jsonDecode(res.body);
        final userId = map['userId'] ?? map['user']?['id'] ?? '';
        final userName = map['name'] ?? map['user']?['name'] ?? 'Rider';

        if (userId.toString().isEmpty) {
          _toast('User ID missing in response');
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', userId.toString());
        await prefs.setString('user_name', userName.toString());
        await prefs.setString('user_city', _city);
        await prefs.setString('user_platform', _platform);

        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        final decoded = _regTryDecodeJson(res.body);
        final errMsg =
            (decoded is Map ? decoded['error'] : null) ??
            'OTP verification failed';
        _toast(errMsg.toString());
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error while verifying OTP');
    } finally {
      setState(() => _isBusy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Sign Up for Vritti',
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),

          // Name
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Iconsax.user),
            ),
          ),
          const SizedBox(height: 12),

          // Phone
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Iconsax.mobile),
            ),
          ),
          const SizedBox(height: 12),

          // City dropdown
          DropdownButtonFormField<String>(
            value: _city,
            decoration: const InputDecoration(
              labelText: 'City',
              prefixIcon: Icon(Iconsax.location),
            ),
            items: _kIndiaCities
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _city = v ?? _city),
          ),
          const SizedBox(height: 12),

          // Platform dropdown
          DropdownButtonFormField<String>(
            value: _platform,
            decoration: const InputDecoration(
              labelText: 'Delivery Platform',
              prefixIcon: Icon(Iconsax.briefcase),
            ),
            items: _kPlatforms
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _platform = v ?? _platform),
          ),
          const SizedBox(height: 12),

          // Consent
          CheckboxListTile(
            value: _consentGiven,
            title: const Text(
              'I consent to background telemetry for payout verification',
            ),
            onChanged: (v) => setState(() => _consentGiven = v ?? false),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Request OTP button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isBusy ? null : _requestOtp,
              icon: const Icon(Iconsax.sms),
              label: Text(_otpRequested ? 'Resend OTP' : 'Request OTP'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),

          // OTP entry + verify
          if (_otpRequested) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP Code',
                prefixIcon: Icon(Iconsax.password_check),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _verifyAndSignup,
                icon: _isBusy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.shield_tick),
                label: Text(
                  _isBusy ? 'Please wait...' : 'Verify OTP & Continue',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF006D32),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
