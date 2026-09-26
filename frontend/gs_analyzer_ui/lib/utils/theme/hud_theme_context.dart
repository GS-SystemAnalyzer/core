import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart' as app_theme;

extension HudThemeContext on BuildContext {
  HudThemeExtension get HudTheme => 
      Theme.of(this).extension<HudThemeExtension>() ??
      app_theme.HudTheme.darkTheme(HudColor.darkAccentCyan).extension<HudThemeExtension>()!;
}

extension HudTextThemeContext on BuildContext {
  TextTheme get HudTextTheme => Theme.of(this).textTheme;
}