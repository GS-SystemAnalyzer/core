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

    test('copyWith preserves every field when called with no arguments', () {
      final ext = HudTheme.darkTheme(Colors.cyan).extension<HudThemeExtension>()!;
      final copied = ext.copyWith();

      expect(copied.accentColor, ext.accentColor);
      expect(copied.base, ext.base);
      expect(copied.panel, ext.panel);
      expect(copied.border, ext.border);
      expect(copied.accentCyan, ext.accentCyan);
      expect(copied.accentGreen, ext.accentGreen);
      expect(copied.accentRed, ext.accentRed);
      expect(copied.accentAmber, ext.accentAmber);
      expect(copied.accentPurple, ext.accentPurple);
      expect(copied.accentBlue, ext.accentBlue);
      expect(copied.textMain, ext.textMain);
      expect(copied.textMuted, ext.textMuted);
      expect(copied.textDim, ext.textDim);
      expect(copied.textPaint, ext.textPaint);
      expect(copied.header, ext.header);
      expect(copied.labelStyle, ext.labelStyle);
      expect(copied.valueStyle, ext.valueStyle);
      expect(copied.statGreen, ext.statGreen);
      expect(copied.actionRed, ext.actionRed);
      expect(copied.body, ext.body);
      expect(copied.hudPanelDecoration, ext.hudPanelDecoration);
      expect(copied.listItemDecoration, ext.listItemDecoration);
    });

    test('backward-compat getters: label delegates to labelStyle, statCyan to valueStyle', () {
      final ext = HudTheme.darkTheme(Colors.cyan).extension<HudThemeExtension>()!;

      expect(ext.label, ext.labelStyle);
      expect(ext.statCyan, ext.valueStyle);
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
      expect(darkExt.fileTypeColor('system'), darkExt.accentBlue);
      expect(darkExt.fileTypeColor('SYSTEM'), darkExt.accentBlue);
      expect(darkExt.fileTypeColor('System'), darkExt.accentBlue);
      expect(darkExt.fileTypeColor('other'), darkExt.textMain.withValues(alpha: 0.7));
      expect(darkExt.fileTypeColor('unknown'), darkExt.textMain.withValues(alpha: 0.7));
      expect(darkExt.fileTypeColor(''), darkExt.textMain.withValues(alpha: 0.7));

      final lightExt = HudTheme.lightTheme(Colors.blue).extension<HudThemeExtension>()!;
      expect(lightExt.fileTypeColor('media'), lightExt.accentCyan);
      expect(lightExt.fileTypeColor('documents'), lightExt.accentGreen);
      expect(lightExt.fileTypeColor('executables'), lightExt.accentRed);
      expect(lightExt.fileTypeColor('archives'), lightExt.accentAmber);
      expect(lightExt.fileTypeColor('code'), lightExt.accentPurple);
      expect(lightExt.fileTypeColor('system'), lightExt.accentBlue);
      expect(lightExt.fileTypeColor('unknown'), lightExt.textMain.withValues(alpha: 0.7));
    });

    test('fileTypeColor returns accentBlue for system and derives default from textMain', () {
      final baseExt = HudTheme.darkTheme(Colors.cyan).extension<HudThemeExtension>()!;
      const customTextMain = Color(0xFF123456);
      final customExt = baseExt.copyWith(textMain: customTextMain);

      // 'system' now maps to accentBlue, independent of textMain
      expect(customExt.fileTypeColor('system'), customExt.accentBlue);
      expect(customExt.fileTypeColor('SYSTEM'), customExt.accentBlue);
      // default / unrecognised categories still derive from textMain
      expect(customExt.fileTypeColor('default'), customTextMain.withValues(alpha: 0.7));
      expect(customExt.fileTypeColor('anything_else'), customTextMain.withValues(alpha: 0.7));
    });
  });

  group('HudThemeContext extension methods', () {
    testWidgets('context.hudTheme retrieves mounted HudThemeExtension', (tester) async {
      late HudThemeExtension retrievedTheme;
      late TextTheme retrievedTextTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(Colors.amber),
          home: Builder(
            builder: (context) {
              retrievedTheme = context.hudTheme;
              retrievedTextTheme = context.hudTextTheme;
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

    testWidgets('context.hudTheme falls back gracefully when extension is unmounted', (tester) async {
      late HudThemeExtension fallbackTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              fallbackTheme = context.hudTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(fallbackTheme, isNotNull);
      expect(fallbackTheme.base, HudColor.darkBgBase);
      expect(fallbackTheme.accentCyan, HudColor.darkAccentCyan);
    });

    // ignore: deprecated_member_use_from_same_package
    testWidgets('deprecated context.HudTheme alias still works', (tester) async {
      late HudThemeExtension retrievedTheme;
      late TextTheme retrievedTextTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(Colors.amber),
          home: Builder(
            builder: (context) {
              // ignore: deprecated_member_use
              retrievedTheme = context.HudTheme;
              // ignore: deprecated_member_use
              retrievedTextTheme = context.HudTextTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(retrievedTheme, isNotNull);
      expect(retrievedTheme.accentColor, Colors.amber);
      expect(retrievedTextTheme, isNotNull);
    });

    testWidgets('hudTheme and deprecated HudTheme return the same instance', (tester) async {
      late HudThemeExtension newAccessor;
      late HudThemeExtension deprecatedAccessor;
      late TextTheme newTextAccessor;
      late TextTheme deprecatedTextAccessor;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(Colors.purple),
          home: Builder(
            builder: (context) {
              newAccessor = context.hudTheme;
              // ignore: deprecated_member_use
              deprecatedAccessor = context.HudTheme;
              newTextAccessor = context.hudTextTheme;
              // ignore: deprecated_member_use
              deprecatedTextAccessor = context.HudTextTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(identical(newAccessor, deprecatedAccessor), isTrue);
      expect(identical(newTextAccessor, deprecatedTextAccessor), isTrue);
    });
  });
}
