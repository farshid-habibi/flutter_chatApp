import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class AuthPage extends StatefulWidget {
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  bool isLogin = true;

  void _submit(AuthProvider auth) async {
    if (isLogin) {

      await auth.signIn(
        emailController.text.trim(),
        passwordController.text.trim(),
      );
    } else {
     
  
      final error = await auth.signUp(
        emailController.text.trim(),
        passwordController.text.trim(),
        name: nameController.text.trim(),
      );

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ثبت‌نام موفقیت‌آمیز بود ✅")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "ورود" : "ثبت‌نام")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (!isLogin)
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "نام"),
              ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "ایمیل"),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "رمز عبور"),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            auth.isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () => _submit(auth),
                    child: Text(isLogin ? "ورود" : "ثبت‌نام"),
                  ),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(
                isLogin ? "اکانت نداری؟ ثبت‌نام کن" : "اکانت داری؟ وارد شو",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
