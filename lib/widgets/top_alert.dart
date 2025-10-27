import 'package:flutter/material.dart';
import '../core/utils.dart';

class TopAlert extends StatefulWidget {
  final int currentlyIn;
  final VoidCallback? onTap; // tap to open Log (ALL)
  const TopAlert({super.key, required this.currentlyIn, this.onTap});

  @override
  State<TopAlert> createState() => _TopAlertState();
}

class _TopAlertState extends State<TopAlert>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1, end: 0.25).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _text() {
    if (widget.currentlyIn == 0) return "All divers are OUT";
    if (widget.currentlyIn == 1) return "1 diver currently IN!";
    return "${widget.currentlyIn} Divers currently IN!";
  }

  Color _color() => widget.currentlyIn == 0 ? Colors.green : Colors.orange;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.currentlyIn == 0 ? "✅ " : "⚠️ ",
              style: TextStyle(fontSize: sf(context, 26)),
            ),
            Text(
              _text(),
              style: TextStyle(
                fontSize: sf(context, 22),
                fontWeight: FontWeight.bold,
                color: _color(),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      top: sf(context, 12),
      left: 0,
      right: 0,
      child: widget.onTap == null
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onTap,
              child: content,
            ),
    );
  }
}
