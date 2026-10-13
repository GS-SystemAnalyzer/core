import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class GoUpRowWidget extends ConsumerWidget {
  const GoUpRowWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hud = context.hudTheme;
    return InkWell(
      onTap: () {
        ref.read(directoryProvider.notifier).navigateUp();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: hud.listItemDecoration,
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Icon(
                    Icons.keyboard_return_outlined,
                    color: hud.accentCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '[..] GO UP A DIRECTORY',
                      style: hud.body.copyWith(
                        color: hud.textMain,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
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
