import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class CustomProgressIndicator extends StatelessWidget {
  final String label;
  final String tag;
  final double value;
  final double height;
  final Animation<Color?>? color;

  const CustomProgressIndicator({
    super.key,
    required this.label,
    required this.tag,
    required this.value,
    required this.height,
    this.color
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(     
              label.toUpperCase()
            ),
            Text(
              tag.toUpperCase(),
              style: HudTheme.statGreen,
            ),
          ],
        ),
        const SizedBox(height: 9,),
        LinearProgressIndicator(
          value: value,
          borderRadius: BorderRadius.circular(10),
          minHeight: height,
          valueColor: color,
          backgroundColor: Colors.grey[800],
        )
      ],
    );      
  }
}