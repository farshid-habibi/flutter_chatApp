import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants.dart';

class AlreadyHaveAnAccountCheck extends StatelessWidget {
  final bool login;
  final Function? press;
  const AlreadyHaveAnAccountCheck({
    Key? key,
    this.login = true,
    required this.press,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,  // محدود کردن عرض Row
      children: <Widget>[
        Flexible(
          child: Text(
            login ? "Don’t have an Account ? " : "Already have an Account ? ",
            style: const TextStyle(color: kPrimaryColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: press as void Function()?,
          child: Text(
            login ? "Sign Up" : "Sign In",
            style: const TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        )
      ],
    );
  }
}
