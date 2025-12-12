import 'dart:async';
import 'dart:io';

import 'package:Talkify/Screens/Chat/FancySnackBarState.dart';
import 'package:Talkify/components/background.dart';
import 'package:Talkify/constants.dart';
import 'package:Talkify/responsive.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  void showCustomSnackBar(
    BuildContext context, {
    required String message,
    IconData icon = Icons.info_outline,
    Duration duration = const Duration(seconds: 3),
    List<Color>? gradientColors,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FancySnackBar(
        message: message,
        icon: icon,
        duration: duration,
        gradientColors:
            gradientColors ?? [Color(0xFF6A0DAD), Color(0xFF00BFFF)],
        onClose: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    // 🔹 Check internet first
    if (!await _checkInternet()) {
      showCustomSnackBar(
        context,
        message: 'No internet connection. Please check your network.',
        icon: Icons.wifi_off,
        gradientColors: [Colors.red, Colors.orange],
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(
            _emailCtrl.text.trim(),
            redirectTo: 'myapp://reset-password',
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Request timed out");
            },
          );

      if (!mounted) return;

      _showResetEmailSuccess(context);
    } on TimeoutException {
      if (!mounted) return;
      showCustomSnackBar(
        context,
        message:
            'Connection timeout. Please check your internet and try again.',
        icon: Icons.timer_outlined,
        gradientColors: [Colors.red, Colors.orange],
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(
        context,
        message: e.message,
        icon: Icons.error_outline,
        gradientColors: [Colors.red, Colors.orange],
      );
    } catch (_) {
      if (!mounted) return;
      showCustomSnackBar(
        context,
        message: 'Unexpected error occurred. Please try again.',
        icon: Icons.error_outline,
        gradientColors: [Colors.red, Colors.orange],
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showResetEmailSuccess(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

        return Positioned(
          left: 16,
          right: 16,
          bottom: keyboardHeight + 30,
          child: GestureDetector(
            onTap: () {
              entry.remove(); // Hide message on click
              Navigator.of(context).pop();
            },
            child: Material(
              color: Colors.transparent,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color.fromARGB(255, 32, 115, 35), Colors.lightGreenAccent],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Password reset link has been sent to your email.",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Background(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(defaultPadding),
              child: Responsive(
                mobile: _buildForm(),
                desktop: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    Expanded(
                      child: Center(
                        child: SizedBox(width: 450, child: _buildForm()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(
          defaultPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Reset Password",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: defaultPadding * 2),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: "Enter your email",
                prefixIcon: Icon(Icons.email),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Email is required' : null,
            ),
            const SizedBox(height: defaultPadding),
            ElevatedButton(
              onPressed: _loading ? null : _sendResetEmail,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Send Reset Link"),
            ),
          ],
        ),
      ),
    );
  }
}
