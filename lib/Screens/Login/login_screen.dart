import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/background.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/responsive.dart';

import 'components/login_form.dart';
import 'components/login_screen_top_image.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

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
                    child: Responsive(
                      mobile: const MobileLoginScreen(),
                      desktop: Row(
                        children: [
                          const Expanded(
                            child: LoginScreenTopImage(),
                          ),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: 450,
                                child: const LoginForm(),
                              ),
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

class MobileLoginScreen extends StatelessWidget {
  const MobileLoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const <Widget>[
        LoginScreenTopImage(),
        SizedBox(height: defaultPadding),
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
    );
  }
}
