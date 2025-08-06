import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/background.dart';
import 'package:flutter_application_1/responsive.dart';

import 'components/login_form.dart';
import 'components/login_screen_top_image.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    Key? key,
    required String initialEmail,
    required String initialPassword,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Background(
      child: SingleChildScrollView(
        child: Responsive(
          mobile: const MobileLoginScreen(),
          desktop: Row(
            children: const [
              Expanded(
                child: LoginScreenTopImage(),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 450,
                    child: LoginForm(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileLoginScreen extends StatelessWidget {
  const MobileLoginScreen({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView( // اضافه‌شده برای جلوگیری از overflow
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const <Widget>[
          LoginScreenTopImage(),
          Row(
            children: [
              Spacer(),
              Expanded(
                flex: 8,
                child: LoginForm(),
              ),
              Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}
