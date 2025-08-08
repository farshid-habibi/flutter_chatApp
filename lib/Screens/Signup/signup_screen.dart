import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/background.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/responsive.dart';

import 'components/sign_up_top_image.dart';
import 'components/signup_form.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, // اجازه می‌ده که ویجت‌ها با باز شدن کیبورد جا‌به‌جا بشن
      body: Background(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(), // بستن کیبورد با لمس فضای خالی
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                reverse: true, // اسکرول از پایین به بالا (برای نمایش دکمه هنگام باز بودن کیبورد)
                padding: EdgeInsets.only(
                  left: defaultPadding,
                  right: defaultPadding,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20, // بالا آوردن دکمه‌ها
                  top: 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: const Responsive(
                      mobile: MobileSignupScreen(),
                      desktop: Row(
                        children: [
                          Expanded(
                            child: SignUpScreenTopImage(),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 450,
                                  child: SignUpForm(),
                                ),
                                SizedBox(height: defaultPadding / 2),
                                // SocalSignUp()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class MobileSignupScreen extends StatelessWidget {
  const MobileSignupScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SignUpScreenTopImage(),
        SizedBox(height: defaultPadding),
        Row(
          children: [
            Spacer(),
            Expanded(
              flex: 8,
              child: SignUpForm(),
            ),
            Spacer(),
          ],
        ),
        // const SocalSignUp()
      ],
    );
  }
}
