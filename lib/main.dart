import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/Screens/Chat/chat_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/Screens/Auto/reset_password_screen.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/Screens/Welcome/welcome_screen.dart';
import 'package:flutter_application_1/DashboardScreen.dart';
import 'package:flutter_application_1/splash_screen.dart';
import 'package:flutter_application_1/Screens/Login/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ctqagcifclyvlntfacnc.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0cWFnY2lmY2x5dmxudGZhY25jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5NTk5NzcsImV4cCI6MjA2OTUzNTk3N30.HAsOI0qlt02OZqv3H2Y18cR8_M_5Vefzgp5kydYQGWM',
   authOptions: const FlutterAuthClientOptions(
    autoRefreshToken: true
  ),
  
  );

  // Listener برای تغییرات session و token refresh
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    final session = data.session;
    print('📡 Auth event: $event');
    if (session != null) {
      print('📌 New access token: ${session.accessToken}');
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<AuthState> _authSub;
  String _initialRoute = '/welcome';

  @override
  void initState() {
    super.initState();

    // بررسی session فعلی
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && session.user != null) {
      _initialRoute = '/dashboard';
    }

    // Listener برای رویدادهای خاص auth
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Auth',
      theme: ThemeData(
        primaryColor: kPrimaryColor,
        scaffoldBackgroundColor: Colors.white,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            foregroundColor: Colors.white,
            backgroundColor: kPrimaryColor,
            shape: const StadiumBorder(),
            maximumSize: const Size(double.infinity, 56),
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: kPrimaryLightColor,
          prefixIconColor: kPrimaryColor,
          contentPadding: EdgeInsets.symmetric(
            vertical: defaultPadding,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      initialRoute: _initialRoute,
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/welcome': (context) => const WelcomeScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/login': (context) => const LoginScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
      },
    );
  }
}
