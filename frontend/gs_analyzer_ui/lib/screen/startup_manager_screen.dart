import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/startup_program.dart';
import 'package:gs_analyzer_ui/providers/startup_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class StartupManagerScreen extends ConsumerWidget {
  const StartupManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(startupProvider);

    return Container(
      color: HudTheme.bgBase,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.rocket_launch_outlined,
                color: HudTheme.accentCyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text('STARTUP MANAGER', style: HudTheme.headerCyan),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: HudTheme.textDim,
                  size: 20,
                ),
                tooltip: 'Reload',
                onPressed: () => ref.read(startupProvider.notifier).load(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'MANAGE PROGRAMS THAT LAUNCH AT LOGIN',
            style: HudTheme.labelMuted,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: HudTheme.hudPanelDecoration,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: state.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: HudTheme.accentCyan),
                ),
                error: (e, _) => _ErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.read(startupProvider.notifier).load(),
                ),
                data: (programs) {
                  if (programs.isEmpty) {
                    return const Center(
                      child: Text(
                        'NO STARTUP ENTRIES DETECTED',
                        style: HudTheme.labelMuted,
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: programs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, i) =>
                        _StartupRow(program: programs[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupRow extends ConsumerWidget {
  const _StartupRow({required this.program});

  final StartupProgram program;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(startupProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Icon(
            program.isEnabled
                ? Icons.check_circle_outline
                : Icons.pause_circle_outline,
            color: program.isEnabled ? HudTheme.accentGreen : HudTheme.textDim,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        program.name.isEmpty ? '(unnamed)' : program.name,
                        overflow: TextOverflow.ellipsis,
                        style: HudTheme.bodyText.copyWith(
                          color: HudTheme.textMain,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ScopeTag(scope: program.scope),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  program.arguments == null || program.arguments!.isEmpty
                      ? program.executablePath
                      : '${program.executablePath} ${program.arguments}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.labelMuted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: program.isEnabled,
            activeColor: HudTheme.accentCyan,
            onChanged: (_) => _guard(context, () => notifier.toggle(program)),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: HudTheme.accentRed,
              size: 20,
            ),
            tooltip: program.isSystemScope
                ? 'Remove (requires admin)'
                : 'Remove',
            onPressed: () => _confirmDelete(context, notifier),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    StartupNotifier notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgPanel,
        title: const Text('REMOVE STARTUP ENTRY', style: HudTheme.headerCyan),
        content: Text(
          program.isSystemScope
              ? 'Remove "${program.name}" from startup?\n\nThis is a SYSTEM entry and requires administrator privileges.'
              : 'Remove "${program.name}" from startup?',
          style: HudTheme.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: HudTheme.labelMuted),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REMOVE', style: HudTheme.actionRed),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _guard(context, () => notifier.remove(program));
    }
  }

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on StartupAdminRequiredException catch (e) {
      _snack(context, e.message, HudTheme.accentAmber);
    } catch (e) {
      _snack(context, e.toString(), HudTheme.accentRed);
    }
  }

  void _snack(BuildContext context, String msg, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: HudTheme.bgPanel,
        content: Text(
          msg,
          style: HudTheme.bodyText.copyWith(color: color),
        ),
      ),
    );
  }
}

class _ScopeTag extends StatelessWidget {
  const _ScopeTag({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final isSystem = scope.toLowerCase() == 'system';
    final color = isSystem ? HudTheme.accentAmber : HudTheme.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        scope.toUpperCase(),
        style: TextStyle(
          fontFamily: HudTheme.fontCore,
          color: color,
          fontSize: 9,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            color: HudTheme.accentRed,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text('STARTUP MODULE ERROR', style: HudTheme.actionRed),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: HudTheme.labelMuted,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: HudTheme.accentCyan),
            ),
            child: const Text('RETRY', style: HudTheme.statCyan),
          ),
        ],
      ),
    );
  }
}
