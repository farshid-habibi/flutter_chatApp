import 'package:Talkify/components/background.dart';
import 'package:Talkify/constants.dart';
import 'package:Talkify/responsive.dart';
import 'package:flutter/material.dart';


import 'components/sign_up_top_image.dart';
import 'components/signup_form.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, 
      body: Background(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                reverse: true, 
                padding: EdgeInsets.only(
                  left: defaultPadding,
                  right: defaultPadding,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
