import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class HudAccentToggle<T> extends StatelessWidget {
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool showSelectedIcon;
  final VisualDensity visualDensity;
  final bool compact;

  const HudAccentToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.showSelectedIcon = true,
    this.visualDensity = VisualDensity.standard,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hud = context.hudTheme;
    final button = SegmentedButton<T>(
      segments: compact ? [for (final segment in segments)
        ButtonSegment<T>(value: segment.value,
          label: segment.label == null ? null : FittedBox(fit: BoxFit.scaleDown,
            child: DefaultTextStyle.merge(maxLines: 1, softWrap: false, child: segment.label!)),
          icon: segment.icon, tooltip: segment.tooltip, enabled: segment.enabled),
      ] : segments,
      expandedInsets: compact ? EdgeInsets.zero : null,
      selected: {selected},
      showSelectedIcon: showSelectedIcon,
      onSelectionChanged: (selection) => onChanged(selection.single),
      style: ButtonStyle(
        visualDensity: compact ? const VisualDensity(vertical: -3) : visualDensity,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
        alignment: compact ? Alignment.center : null,
        // Density subtracts 12px from each vertical inset; retain 4px padding.
        padding: compact ? const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 16)) : null,
        iconSize: compact ? const WidgetStatePropertyAll(14) : null,
        textStyle: WidgetStatePropertyAll(compact ? hud.body.copyWith(fontSize: 11) : hud.body),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? hud.onAccent : hud.textMain),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? hud.accentColor : hud.panel),
        overlayColor: WidgetStatePropertyAll(hud.panel.withValues(alpha: 0)),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
          color: states.contains(WidgetState.focused) && states.contains(WidgetState.selected)
              ? hud.onAccent : hud.accentColor,
          width: states.contains(WidgetState.focused) ? 2 : 1,
        )),
      ),
    );
    return compact ? SizedBox(width: segments.length * 82.0, height: 28, child: button) : button;
  }
}
