import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart' as app_theme;
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

extension HudThemeContext on BuildContext {
  /// Resolves the active [HudThemeExtension] from the widget tree.
  HudThemeExtension get hudTheme =>
      Theme.of(this).extension<HudThemeExtension>() ??
      app_theme.HudTheme.darkTheme(
        HudColor.darkAccentCyan,
      ).extension<HudThemeExtension>()!;

  /// Deprecated alias so existing code using context.HudTheme doesn't break
  @Deprecated('Use context.hudTheme instead')
  HudThemeExtension get HudTheme => hudTheme;
}

extension HudTextThemeContext on BuildContext {
  /// Resolves the active [TextTheme] from the widget tree.
  TextTheme get hudTextTheme => Theme.of(this).textTheme;

  @Deprecated('Use context.hudTextTheme instead')
  TextTheme get HudTextTheme => hudTextTheme;
}
