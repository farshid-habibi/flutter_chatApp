import 'package:flutter/material.dart';
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

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passCtrl.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("رمز عبور تغییر کرد")),
      );
      Navigator.pushReplacementNamed(context, '/login');
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
            "تعیین رمز جدید",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: defaultPadding * 2),
          TextFormField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: "رمز جدید",
              prefixIcon: Icon(Icons.lock),
            ),
            validator: (v) =>
                (v == null || v.length < 6) ? 'حداقل ۶ کاراکتر' : null,
          ),
          const SizedBox(height: defaultPadding),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: "تکرار رمز جدید",
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) =>
                (v != _passCtrl.text) ? 'رمزها یکسان نیستند' : null,
          ),
          const SizedBox(height: defaultPadding),
          ElevatedButton(
            onPressed: _loading ? null : _updatePassword,
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("ذخیره رمز"),
          ),
        ],
      ),
    );
  }
}
