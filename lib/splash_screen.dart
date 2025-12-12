import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    print("SplashScreen loaded!");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateAfterDelay();
    });
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    print("Session: $session");

    if (session != null) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else {
      Navigator.of(context).pushReplacementNamed('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/chatApp.jpg'),
            fit: BoxFit.fitWidth,
          ),
        ),
       
      ),
    );
  }
}
