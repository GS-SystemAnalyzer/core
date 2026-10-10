import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_text_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

void main() {
  group('HudTheme Theme Generation', () {
    test('lightTheme generates valid ThemeData with light brightness and extension', () {
      const accent = Colors.purple;
      final theme = HudTheme.lightTheme(accent);

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, HudColor.lightBgBase);
      expect(theme.colorScheme.primary, accent);
      expect(theme.colorScheme.surface, HudColor.lightBgPanel);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.textTheme.bodyMedium?.fontFamily, HudTextTheme.fontCore);

      final ext = theme.extension<HudThemeExtension>();
      expect(ext, isNotNull);
      expect(ext!.accentColor, accent);
      expect(ext.base, HudColor.lightBgBase);
      expect(ext.panel, HudColor.lightBgPanel);
      expect(ext.border, HudColor.lightPrimaryBorder);
    });

    test('darkTheme generates valid ThemeData with dark brightness and extension', () {
      const accent = Colors.tealAccent;
      final theme = HudTheme.darkTheme(accent);

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, HudColor.darkBgBase);
      expect(theme.colorScheme.primary, accent);
      expect(theme.colorScheme.surface, HudColor.darkBgPanel);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.textTheme.bodyMedium?.fontFamily, HudTextTheme.fontCore);

      final ext = theme.extension<HudThemeExtension>();
      expect(ext, isNotNull);
      expect(ext!.accentColor, accent);
      expect(ext.base, HudColor.darkBgBase);
      expect(ext.panel, HudColor.darkBgPanel);
      expect(ext.border, HudColor.darkPrimaryBorder);
    });

    test('resolveThemeMode correctly maps theme identifiers', () {
      expect(HudTheme.resolveThemeMode('cyber_light'), ThemeMode.light);
      expect(HudTheme.resolveThemeMode('light'), ThemeMode.light);
      expect(HudTheme.resolveThemeMode('LIGHT'), ThemeMode.light);

      expect(HudTheme.resolveThemeMode('cyber_dark'), ThemeMode.dark);
      expect(HudTheme.resolveThemeMode('dark'), ThemeMode.dark);
      expect(HudTheme.resolveThemeMode('DARK'), ThemeMode.dark);

      expect(HudTheme.resolveThemeMode('system'), ThemeMode.system);
      expect(HudTheme.resolveThemeMode('SYSTEM'), ThemeMode.system);
      expect(HudTheme.resolveThemeMode(null), ThemeMode.system);
      expect(HudTheme.resolveThemeMode('unknown'), ThemeMode.system);
    });
  });

  group('HudThemeExtension', () {
    test('copyWith copies all properties or preserves existing', () {
      final ext = HudTheme.darkTheme(Colors.cyan).extension<HudThemeExtension>()!;

      final copied = ext.copyWith(
        accentColor: Colors.red,
        base: Colors.black,
      );

      expect(copied.accentColor, Colors.red);
      expect(copied.base, Colors.black);
      expect(copied.panel, ext.panel);
      expect(copied.border, ext.border);
      expect(copied.header, ext.header);
      expect(copied.statGreen, ext.statGreen);
    });

    test('lerp smoothly interpolates between two extensions', () {
      final ext1 = HudTheme.darkTheme(Colors.blue).extension<HudThemeExtension>()!;
      final ext2 = HudTheme.lightTheme(Colors.green).extension<HudThemeExtension>()!;

      final lerpedHalf = ext1.lerp(ext2, 0.5);
      expect(lerpedHalf, isNotNull);
      expect(lerpedHalf.accentColor, Color.lerp(ext1.accentColor, ext2.accentColor, 0.5));
      expect(lerpedHalf.base, Color.lerp(ext1.base, ext2.base, 0.5));
      expect(lerpedHalf.panel, Color.lerp(ext1.panel, ext2.panel, 0.5));

      final lerpedZero = ext1.lerp(ext2, 0.0);
      expect(lerpedZero.accentColor.toARGB32(), ext1.accentColor.toARGB32());

      final lerpedOne = ext1.lerp(ext2, 1.0);
      expect(lerpedOne.accentColor.toARGB32(), ext2.accentColor.toARGB32());

      expect(ext1.lerp(null, 0.5), equals(ext1));
    });

    test('fileTypeColor maps category names to theme accent colors case-insensitively', () {
      final darkExt = HudTheme.darkTheme(Colors.cyan).extension<HudThemeExtension>()!;
      expect(darkExt.fileTypeColor('media'), darkExt.accentCyan);
      expect(darkExt.fileTypeColor('MEDIA'), darkExt.accentCyan);
      expect(darkExt.fileTypeColor('documents'), darkExt.accentGreen);
      expect(darkExt.fileTypeColor('Documents'), darkExt.accentGreen);
      expect(darkExt.fileTypeColor('executables'), darkExt.accentRed);
      expect(darkExt.fileTypeColor('EXECUTABLES'), darkExt.accentRed);
      expect(darkExt.fileTypeColor('archives'), darkExt.accentAmber);
      expect(darkExt.fileTypeColor('ARCHIVES'), darkExt.accentAmber);
      expect(darkExt.fileTypeColor('code'), darkExt.accentPurple);
      expect(darkExt.fileTypeColor('Code'), darkExt.accentPurple);
      expect(darkExt.fileTypeColor('system'), darkExt.textDim);
      expect(darkExt.fileTypeColor('SYSTEM'), darkExt.textDim);
      expect(darkExt.fileTypeColor('other'), darkExt.textDim.withValues(alpha: 0.2));
      expect(darkExt.fileTypeColor('unknown'), darkExt.textDim.withValues(alpha: 0.2));

      final lightExt = HudTheme.lightTheme(Colors.blue).extension<HudThemeExtension>()!;
      expect(lightExt.fileTypeColor('media'), lightExt.accentCyan);
      expect(lightExt.fileTypeColor('documents'), lightExt.accentGreen);
      expect(lightExt.fileTypeColor('executables'), lightExt.accentRed);
      expect(lightExt.fileTypeColor('archives'), lightExt.accentAmber);
      expect(lightExt.fileTypeColor('code'), lightExt.accentPurple);
      expect(lightExt.fileTypeColor('system'), lightExt.textDim);
      expect(lightExt.fileTypeColor('unknown'), lightExt.textDim.withValues(alpha: 0.2));
    });
  });

  group('HudThemeContext extension methods', () {
    testWidgets('context.HudTheme retrieves mounted HudThemeExtension', (tester) async {
      late HudThemeExtension retrievedTheme;
      late TextTheme retrievedTextTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(Colors.amber),
          home: Builder(
            builder: (context) {
              retrievedTheme = context.HudTheme;
              retrievedTextTheme = context.HudTextTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(retrievedTheme, isNotNull);
      expect(retrievedTheme.accentColor, Colors.amber);
      expect(retrievedTheme.base, HudColor.darkBgBase);
      expect(retrievedTextTheme, isNotNull);
    });

    testWidgets('context.HudTheme falls back gracefully when extension is unmounted', (tester) async {
      late HudThemeExtension fallbackTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              fallbackTheme = context.HudTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(fallbackTheme, isNotNull);
      expect(fallbackTheme.base, HudColor.darkBgBase);
      expect(fallbackTheme.accentCyan, HudColor.darkAccentCyan);
    });
  });
}
