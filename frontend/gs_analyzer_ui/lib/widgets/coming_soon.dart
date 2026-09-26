import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class ComingSoon extends StatefulWidget {
  final Widget child;

  const ComingSoon({
    super.key,
    required this.child,
  });

  @override
  State<ComingSoon> createState() => _ComingSoonState();
}

class _ComingSoonState extends State<ComingSoon> {
  bool _isUnlocked = false;

  @override
  Widget build(BuildContext context) {
    final hud = context.HudTheme;
    if (_isUnlocked) {
      return widget.child;
    }

    return ClipRect(
      child: Stack(
        children: [
          const _DummyDashboardBackground(),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: Container(
                color: hud.textPaint.withValues(alpha: 0.1),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onDoubleTap: () {
                          if (kDebugMode) {
                            setState(() {
                              _isUnlocked = true;
                            });
                          }
                        },
                        child: Icon(
                          Icons.lock,
                          size: 45,
                          color: hud.textMain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'COMING SOON',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'THIS MODULE IS NOT AVAILABLE YET',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: hud.textMain.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DummyDashboardBackground extends StatelessWidget {
  const _DummyDashboardBackground();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}