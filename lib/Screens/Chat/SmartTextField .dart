import 'package:flutter/material.dart';

class SmartTextField extends StatefulWidget {
  final TextEditingController controller;
  const SmartTextField({super.key, required this.controller});

  @override
  State<SmartTextField> createState() => _SmartTextFieldState();
}

class _SmartTextFieldState extends State<SmartTextField> {
  TextDirection _textDirection = TextDirection.ltr;

  void _updateTextDirection(String text) {
    if (text.isEmpty) return;
    final firstChar = text.characters.first;
    final isArabicOrPersian = RegExp(r'[\u0600-\u06FF]').hasMatch(firstChar);
    setState(() {
      _textDirection =
          isArabicOrPersian ? TextDirection.rtl : TextDirection.ltr;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      textAlign: _textDirection == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.left,
      textDirection: _textDirection,
      onChanged: _updateTextDirection,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: "Write something...",
        hintStyle: TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
