import 'dart:async';
import 'package:flutter/material.dart';

/// Lightweight top-of-screen toast for short alerts.
class TopSnack {
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;

    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: topPadding + 8,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: true,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ) ??
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Timer(duration, () {
      entry.remove();
    });
  }
}
