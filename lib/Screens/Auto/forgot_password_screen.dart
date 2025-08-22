import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/components/background.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/responsive.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailCtrl.text.trim(),
        redirectTo: 'myapp://reset-password',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لینک بازیابی به ایمیل ارسال شد')),
      );
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
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
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const Text(
            "بازیابی رمز عبور",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: defaultPadding * 2),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: "ایمیل خود را وارد کنید",
              prefixIcon: Icon(Icons.email),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'ایمیل الزامی است' : null,
          ),
          const SizedBox(height: defaultPadding),
          ElevatedButton(
            onPressed: _loading ? null : _sendResetEmail,
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("ارسال لینک"),
          ),
        ],
      ),
    );
  }
}
