import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

/// Visual state of a minimized operation, driving the ring's centre glyph.
enum OpVisualState { active, complete, failed }

/// A minimized long-running-operation indicator. It rests as a small circular
/// progress ring (determinate arc that fills as the percent rises, integer in
/// the centre) and expands to a full pill on mouse hover; a tap on either opens
/// the full dialog. Mounted above the Navigator (no `Overlay` ancestor), so it
/// uses no `Tooltip` and stays clipped. Dragging is handled by the parent layer.
class MinimizedOpPill extends StatefulWidget {
  final String label;
  final Color accent;

  /// 0.0–1.0, or null when progress is indeterminate (no spinner — see ring).
  final double? progress;

  /// Current target / path, middle-ellipsised at fixed width.
  final String target;

  /// Whether the expanded pill shows icon + percentage only (no label row).
  final bool compact;

  final OpVisualState state;

  final VoidCallback onRestore;

  /// Null = no abort affordance (export has no abort).
  final VoidCallback? onAbort;

  const MinimizedOpPill({
    super.key,
    required this.label,
    required this.accent,
    this.progress,
    required this.target,
    required this.onRestore,
    this.onAbort,
    this.compact = false,
    this.state = OpVisualState.active,
  });

  @override
  State<MinimizedOpPill> createState() => _MinimizedOpPillState();
}

class _MinimizedOpPillState extends State<MinimizedOpPill> {
  bool _expanded = false;
  Timer? _collapseTimer;

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _handleEnter() {
    _collapseTimer?.cancel();
    if (!_expanded) setState(() => _expanded = true);
  }

  void _handleExit() {
    _collapseTimer?.cancel();
    // 250ms grace so moving within the widget doesn't flicker a collapse.
    _collapseTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && _expanded) setState(() => _expanded = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _handleEnter(),
      onExit: (_) => _handleExit(),
      // Cursor is set by the parent layer (grab / grabbing); defer to it.
      child: GestureDetector(
        onTap: widget.onRestore,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomLeft,
          child: _expanded ? _buildPill(context) : _buildRing(context),
        ),
      ),
    );
  }

  // ---- Collapsed ring -------------------------------------------------------

  Widget _buildRing(BuildContext context) {
    final hud = context.hudTheme;
    final accent = widget.accent;

    double? arcValue;
    Widget centre;
    switch (widget.state) {
      case OpVisualState.complete:
        arcValue = 1.0;
        centre = Icon(Icons.check, size: 18, color: accent);
        break;
      case OpVisualState.failed:
        arcValue = 1.0;
        centre = Icon(Icons.priority_high, size: 18, color: accent);
        break;
      case OpVisualState.active:
        arcValue = widget.progress; // null => indeterminate (handled below)
        centre = widget.progress != null
            ? Text(
                '${(widget.progress! * 100).round()}',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              )
            : Text(
                '⋯', // ⋯ — static, no spinner
                style: TextStyle(fontSize: 16, color: accent),
              );
        break;
    }

    return Container(
      key: const Key('op_ring'),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hud.panel,
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: arcValue != null
                // Determinate arc over a static full track — fills as % rises.
                ? CircularProgressIndicator(
                    value: arcValue,
                    strokeWidth: 3,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.15),
                  )
                // Indeterminate: a STATIC faint ring (never value:null — spins).
                : DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3),
                        width: 3,
                      ),
                    ),
                  ),
          ),
          centre,
        ],
      ),
    );
  }

  // ---- Expanded pill --------------------------------------------------------

  Widget _buildPill(BuildContext context) {
    final hud = context.hudTheme;
    final accent = widget.accent;
    final pct = widget.progress != null
        ? (widget.progress! * 100).toStringAsFixed(0)
        : '…';

    return Container(
      width: 220,
      height: widget.compact ? 36 : 56,
      decoration: hud.hudPanelDecoration.copyWith(
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      // Clip so content can never overflow the fixed-height pill.
      child: ClipRect(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: accent,
                      value: widget.progress,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!widget.compact)
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: accent,
                          letterSpacing: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PillIconButton(
                    icon: Icons.open_in_full_rounded,
                    color: hud.textMuted,
                    tooltip: 'Restore',
                    onTap: widget.onRestore,
                  ),
                  if (widget.onAbort != null)
                    _PillIconButton(
                      icon: Icons.close_rounded,
                      color: hud.accentRed,
                      tooltip: 'Abort',
                      onTap: widget.onAbort!,
                    ),
                ],
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 4),
                _MiddleEllipsisText(
                  text: widget.target,
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 9,
                    color: hud.textDim,
                  ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: widget.progress,
                    color: accent,
                    backgroundColor: hud.textDim.withValues(alpha: 0.15),
                    minHeight: 3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PillIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _PillIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // No Tooltip: the pill is mounted above the Navigator (MaterialApp.builder)
    // and has no Overlay ancestor, which Tooltip requires. Semantics keeps the
    // accessible label without that dependency.
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        label: tooltip,
        button: true,
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }
}

/// Renders [text] with middle ellipsis at a fixed width.
class _MiddleEllipsisText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _MiddleEllipsisText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    // Cheap middle-ellipsis: keep first ~10 and last ~11 chars.
    const maxChars = 24;
    final display = text.length > maxChars
        ? '${text.substring(0, 10)}…${text.substring(text.length - 11)}'
        : text;
    return SizedBox(
      width: 196,
      child: Text(display, style: style, maxLines: 1, overflow: TextOverflow.clip),
    );
  }
}
