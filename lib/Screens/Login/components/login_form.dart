import 'package:flutter/material.dart';
import '../../../components/already_have_an_account_acheck.dart';
import '../../../constants.dart';
import '../../Signup/signup_screen.dart';
import 'login_screen_top_image.dart'; // اضافه کن برای تصویر بالا

class LoginForm extends StatelessWidget {
  const LoginForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(defaultPadding),
          child: Form(
            child: Column(
              mainAxisSize: MainAxisSize.min, // حتما اضافه شود
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LoginScreenTopImage(), // تصویر بالا
                const SizedBox(height: 40),
                TextFormField(
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  cursorColor: kPrimaryColor,
                  decoration: const InputDecoration(
                    hintText: "Your email",
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(defaultPadding),
                      child: Icon(Icons.person),
                    ),
                  ),
                ),
                const SizedBox(height: defaultPadding),
                TextFormField(
                  textInputAction: TextInputAction.done,
                  obscureText: true,
                  cursorColor: kPrimaryColor,
                  decoration: const InputDecoration(
                    hintText: "Your password",
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(defaultPadding),
                      child: Icon(Icons.lock),
                    ),
                  ),
                ),
                const SizedBox(height: defaultPadding),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text("LOGIN"),
                ),
                const SizedBox(height: defaultPadding),
                AlreadyHaveAnAccountCheck(
                  press: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) {
                          return const SignUpScreen();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
