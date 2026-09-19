import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class DirectoryTableHeader extends StatelessWidget {
  const DirectoryTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: HudTheme.bgPanel,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                SizedBox(width: 32), SizedBox(width: 20), SizedBox(width: 8),
                HudLabel('NAME'), // Kept left aligned to match the tree view
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: HudLabel('DATE MODIFIED', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: HudLabel('TYPE', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: HudLabel('SIZE', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 1,
            child: HudLabel('ACTION', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
