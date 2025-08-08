import 'package:flutter/material.dart';
import 'package:flutter_application_1/DashboardScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/Screens/Welcome/welcome_screen.dart';
// 👈 Make sure this exists

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ctqagcifclyvlntfacnc.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0cWFnY2lmY2x5dmxudGZhY25jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM5NTk5NzcsImV4cCI6MjA2OTUzNTk3N30.HAsOI0qlt02OZqv3H2Y18cR8_M_5Vefzgp5kydYQGWM',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

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
            horizontal: defaultPadding,
            vertical: defaultPadding,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            borderSide: BorderSide.none,
          ),
        ),
      ),

      // 👇 Initial screen and route setup
      initialRoute: '/',
      routes: {
        '/': (context) => const WelcomeScreen(),
        '/dashboard': (context) => const DashboardScreen(), // 👈 Added dashboard route
      },
    );
  }
}
