import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

extension HudThemeContext on BuildContext {
  HudThemeExtension get HudTheme => 
  Theme.of(this).extension<HudThemeExtension>()!;
}

extension HudTextThemeContext on BuildContext {
  TextTheme get HudTextTheme => Theme.of(this).textTheme;
}