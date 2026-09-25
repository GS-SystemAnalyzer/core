import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class GoUpRowWidget extends ConsumerWidget {
  const GoUpRowWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        ref.read(directoryProvider.notifier).navigateUp();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: HudTheme.listItemDecoration,
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  const Icon(
                    Icons.keyboard_return_outlined,
                    color: HudTheme.accentCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '[..] GO UP A DIRECTORY',
                    style: HudTheme.bodyText.copyWith(
                      color: HudTheme.textMain,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(flex: 3, child: SizedBox()),
            const Expanded(flex: 2, child: SizedBox()),
            const Expanded(flex: 2, child: SizedBox()),
            const Expanded(flex: 1, child: SizedBox()),
          ],
        ),
      ),
    );
  }
}
