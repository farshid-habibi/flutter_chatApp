import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/Screens/Chat/FancySnackBarState.dart';
import 'package:flutter_application_1/Screens/Login/login_screen.dart';
import 'package:flutter_application_1/components/already_have_an_account_acheck.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../constants.dart';

class SignUpForm extends StatefulWidget {
  const SignUpForm({Key? key}) : super(key: key);

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _email = '';
  String _password = '';
  bool _isLoading = false;
  bool _obscurePassword = true;

  void showSuccessPopup(BuildContext context) {
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
              entry.remove(); // Hide Message
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
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
                    colors: [Colors.green, Colors.teal],
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
                        "Sign up successful! Please check your email.",
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_username.length < 6) {
      showCustomSnackBar(
        context,
        message: "Username must be at least 6 characters.",
        icon: Icons.error_outline,
        gradientColors: [Colors.red, Colors.orange],
      );
      return;
    }

    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));

      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw const SocketException("No Internet");
      }
    } catch (_) {
      showCustomSnackBar(
        context,
        message: 'No internet connection. Please check your network.',
        icon: Icons.wifi_off,
        gradientColors: [Colors.red, Colors.orange],
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _email,
        password: _password,
        data: {'username': _username},
      );

      // Success
      if (response.user != null || response.session != null) {
        showSuccessPopup(context);
      } else {
        showCustomSnackBar(
          context,
          message: 'Sign up failed. Incorrect email or password.',
          icon: Icons.error_outline,
          gradientColors: [Colors.red, Colors.orange],
        );
      }
    } on AuthException {
      showCustomSnackBar(
        context,
        message: 'Sign up failed. Incorrect email or password.',
        icon: Icons.error_outline,
        gradientColors: [Colors.red, Colors.orange],
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void showCustomSnackBar(
    BuildContext context, {
    required String message,
    required IconData icon,
    required List<Color> gradientColors,
  }) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: keyboardHeight + 20, // 🔥 Push above Keyboard
          left: 16,
          right: 16,
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradientColors),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          children: [
            TextFormField(
              textInputAction: TextInputAction.next,
              cursorColor: kPrimaryColor,
              decoration: const InputDecoration(
                hintText: "Your username",
                prefixIcon: Padding(
                  padding: EdgeInsets.all(defaultPadding),
                  child: Icon(Icons.person_outline),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a username';
                }
                return null;
              },
              onSaved: (value) => _username = value ?? '',
            ),
            const SizedBox(height: defaultPadding),

            TextFormField(
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              cursorColor: kPrimaryColor,
              decoration: const InputDecoration(
                hintText: "Your email",
                prefixIcon: Padding(
                  padding: EdgeInsets.all(defaultPadding),
                  child: Icon(Icons.email),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty || !value.contains('@')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
              onSaved: (value) => _email = value ?? '',
            ),
            const SizedBox(height: defaultPadding),

            TextFormField(
              textInputAction: TextInputAction.done,
              obscureText: _obscurePassword,
              cursorColor: kPrimaryColor,
              decoration: InputDecoration(
                hintText: "Your password",
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(defaultPadding),
                  child: Icon(Icons.lock),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: kPrimaryColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'Password must be at least 6 characters long';
                }
                return null;
              },
              onSaved: (value) => _password = value ?? '',
            ),
            const SizedBox(height: defaultPadding / 2),

            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submit,
                    child: Text("Sign Up".toUpperCase()),
                  ),
            const SizedBox(height: defaultPadding),
            AlreadyHaveAnAccountCheck(
              login: false,
              press: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
