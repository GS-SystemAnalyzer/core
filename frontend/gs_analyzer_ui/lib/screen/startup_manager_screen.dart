import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/startup_program.dart';
import 'package:gs_analyzer_ui/providers/startup_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class StartupManagerScreen extends ConsumerWidget {
  const StartupManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(startupProvider);
    final hud = context.HudTheme;

    return Container(
      color: hud.base,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_outlined,
                color: hud.accentCyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text('STARTUP MANAGER', style: hud.header),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: hud.textDim,
                  size: 20,
                ),
                tooltip: 'Reload',
                onPressed: () => ref.read(startupProvider.notifier).load(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MANAGE PROGRAMS THAT LAUNCH AT LOGIN',
            style: hud.label,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: hud.hudPanelDecoration,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: state.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: hud.accentCyan),
                ),
                error: (e, _) => _ErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.read(startupProvider.notifier).load(),
                ),
                data: (programs) {
                  if (programs.isEmpty) {
                    return Center(
                      child: Text(
                        'NO STARTUP ENTRIES DETECTED',
                        style: hud.label,
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: programs.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: hud.textMain.withValues(alpha: 0.1), height: 1),
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
    final hud = context.HudTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Icon(
            program.isEnabled
                ? Icons.check_circle_outline
                : Icons.pause_circle_outline,
            color: program.isEnabled ? hud.accentGreen : hud.textDim,
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
                        style: hud.body.copyWith(
                          color: hud.textMain,
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
                  style: hud.label,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: program.isEnabled,
            activeThumbColor: hud.accentCyan,
            onChanged: (_) => _guard(context, () => notifier.toggle(program)),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: hud.accentRed,
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
    final hud = context.HudTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: hud.panel,
        title: Text('REMOVE STARTUP ENTRY', style: hud.header),
        content: Text(
          program.isSystemScope
              ? 'Remove "${program.name}" from startup?\n\nThis is a SYSTEM entry and requires administrator privileges.'
              : 'Remove "${program.name}" from startup?',
          style: hud.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: hud.label),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('REMOVE', style: hud.actionRed),
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
      _snack(context, e.message, context.HudTheme.accentAmber);
    } catch (e) {
      _snack(context, e.toString(), context.HudTheme.accentRed);
    }
  }

  void _snack(BuildContext context, String msg, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.HudTheme.panel,
        content: Text(
          msg,
          style: context.HudTheme.body.copyWith(color: color),
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
    final hud = context.HudTheme;
    final isSystem = scope.toLowerCase() == 'system';
    final color = isSystem ? hud.accentAmber : hud.textDim;
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
    final hud = context.HudTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: hud.accentRed,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text('STARTUP MODULE ERROR', style: hud.actionRed),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: hud.label,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: hud.accentCyan),
            ),
            child: Text('RETRY', style: hud.statCyan),
          ),
        ],
      ),
    );
  }
}
