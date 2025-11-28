import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/Screens/Chat/FancySnackBarState.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/components/background.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/responsive.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  bool _showPass = false;
  bool _showConfirm = false;

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

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (!await _checkInternet()) {
      showCustomSnackBar(
        context,
        message: "No internet connection. Please check your network.",
        icon: Icons.wifi_off,
        gradientColors: [Colors.red, Colors.orange],
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _passCtrl.text))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Server is not responding");
            },
          );

      if (!mounted) return;

      showCustomSnackBar(
        context,
        message: "Password updated successfully",
        icon: Icons.check_circle_outline,
        gradientColors: [Colors.green, Colors.lightGreenAccent],
      );

      Navigator.pushReplacementNamed(context, '/login');
    } on TimeoutException {
      if (!mounted) return;

      showCustomSnackBar(
        context,
        message: "Server is not responding. Please try again later.",
        icon: Icons.timer_outlined,
        gradientColors: [Colors.red, Colors.orange],
      );
    } on SocketException {
      if (!mounted) return;

      showCustomSnackBar(
        context,
        message:
            "No internet connection. Please check your network and try again.",
        icon: Icons.wifi_off,
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
    } catch (e) {
      if (!mounted) return;

      showCustomSnackBar(
        context,
        message: "Unexpected error: $e",
        icon: Icons.error_outline,
        gradientColors: [Colors.red, Colors.orange],
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  // **************  FORM UI  **************
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Reset Password",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: defaultPadding * 2),

            // **************  PASSWORD FIELD  **************
            TextFormField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                hintText: "New password",
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPass ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() => _showPass = !_showPass);
                  },
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
            ),

            const SizedBox(height: defaultPadding),

            // **************  CONFIRM PASSWORD FIELD  **************
            TextFormField(
              controller: _confirmCtrl,
              obscureText: !_showConfirm,
              decoration: InputDecoration(
                hintText: "Confirm new password",
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showConfirm ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() => _showConfirm = !_showConfirm);
                  },
                ),
              ),
              validator: (v) =>
                  (v != _passCtrl.text) ? 'Passwords do not match' : null,
            ),

            const SizedBox(height: defaultPadding),

            // **************  SAVE BUTTON  **************
            ElevatedButton(
              onPressed: _loading ? null : _updatePassword,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Save Password"),
            ),
          ],
        ),
      ),
    );
  }
}
