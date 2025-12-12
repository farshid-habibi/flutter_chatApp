import 'package:flutter/material.dart';

class FancySnackBar extends StatefulWidget {
  final String message;
  final IconData icon;
  final Duration duration;
  final List<Color> gradientColors;
  final VoidCallback onClose;

  const FancySnackBar({
    Key? key,
    required this.message,
    required this.icon,
    required this.duration,
    required this.gradientColors,
    required this.onClose,
  }) : super(key: key);

  @override
  State<FancySnackBar> createState() => FancySnackBarState();
}

class FancySnackBarState extends State<FancySnackBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.elasticOut)).animate(_controller);

    _fadeAnimation = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    Future.delayed(widget.duration, () async {
      await _controller.reverse();
      widget.onClose(); 
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 60,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontFamily: 'Vazir',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await _controller.reverse();
                      widget.onClose(); 
                    },
                    child: Icon(Icons.close, color: Colors.white70, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
