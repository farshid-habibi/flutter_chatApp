import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/Screens/Auto/forgot_password_screen.dart'
    show ForgotPasswordScreen;
import 'package:flutter_application_1/Screens/Auto/reset_password_screen.dart';
import 'package:flutter_application_1/Screens/Chat/FancySnackBarState.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/components/already_have_an_account_acheck.dart';
import 'package:flutter_application_1/Screens/Signup/signup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    builder: (context) {
      final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

      return Positioned(
        bottom: keyboardHeight + 20,
        left: 20,
        right: 20,
        child: FancySnackBar(
          message: message,
          icon: icon,
          duration: duration,
          gradientColors:
              gradientColors ?? [Color(0xFF6A0DAD), Color(0xFF00BFFF)],
          onClose: () => overlayEntry.remove(),
        ),
      );
    },
  );

  overlay.insert(overlayEntry);
}

class LoginForm extends StatefulWidget {
  const LoginForm({Key? key}) : super(key: key);

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkPasswordRecovery();
  }

  void _checkPasswordRecovery() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          (route) => false,
        );
      }
    });
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

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    if (!await _checkInternet()) {
      _showError(
        'No internet connection. Please check your network.',
        icon: Icons.wifi_off, // آیکون وای‌فای قطع
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user != null) {
        if (response.user!.emailConfirmedAt == null) {
          _showError("Your email is not verified. Please check your inbox.");
          return;
        }

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        _showError('Incorrect email or password.');
      }
    } on SocketException {
      _showError('No internet connection. Please check your network.');
    } on AuthException catch (e) {
      if (e.message.contains("Email not confirmed")) {
        _showError("Please verify your email before login");
      } else {
        _showError("Incorrect email or password.");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message, {IconData icon = Icons.error_outline}) {
    showCustomSnackBar(
      context,
      message: message,
      icon: icon,
      gradientColors: [Colors.red, Colors.orange],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(defaultPadding),
          decoration: const BoxDecoration(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                cursorColor: kPrimaryColor,
                decoration: const InputDecoration(
                  hintText: "Email",
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(defaultPadding),
                    child: Icon(Icons.person),
                  ),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Please enter your email' : null,
              ),
              const SizedBox(height: defaultPadding),
              // Password field
              TextFormField(
                controller: _passwordController,
                textInputAction: TextInputAction.done,
                obscureText: _obscurePassword,
                cursorColor: kPrimaryColor,
                decoration: InputDecoration(
                  hintText: "Password",
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(defaultPadding),
                    child: Icon(Icons.lock),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: kPrimaryColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Please enter your password' : null,
              ),
              const SizedBox(height: defaultPadding),
              // Login button
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _signIn,
                      child: const Text("LOGIN"),
                    ),
              const SizedBox(height: defaultPadding / 2),
              // Forgot password link
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    );
                  },
                  child: const Text("Forgot password?"),
                ),
              ),
              const SizedBox(height: defaultPadding),
              // Sign up link
              AlreadyHaveAnAccountCheck(
                login: true,
                press: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SignUpScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
