import 'package:flutter/material.dart';

class DynamicSnackBar {
  static show(
    BuildContext context, {
    required String message,
    required Color background,
    required IconData icon,
  }) {
    final overlay = Overlay.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    final overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 20,
          right: 20,
          bottom: (keyboardHeight > 0)
              ? keyboardHeight + 20 
              : 40, 
          child: _AnimatedToast(
            message: message,
            background: background,
            icon: icon,
          ),
        );
      },
    );

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 2)).then((_) {
      overlayEntry.remove();
    });
  }
}

class _AnimatedToast extends StatefulWidget {
  final String message;
  final Color background;
  final IconData icon;

  const _AnimatedToast({
    required this.message,
    required this.background,
    required this.icon,
  });

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: widget.background.withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
