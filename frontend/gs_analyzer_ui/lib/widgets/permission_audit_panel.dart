import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/permission_audit_models.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/permission_audit_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class PermissionAuditPanel extends ConsumerWidget {
  const PermissionAuditPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditState = ref.watch(permissionAuditProvider);
    final currentDrive = ref.watch(currentDriveProvider);
    final hud = context.hudTheme;

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: auditState.when(
        data: (result) {
          if (result == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 48,
                    color: hud.textDim,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SECURITY AUDIT OFFLINE',
                    style: hud.header.copyWith(
                      color: hud.textDim,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan for world-writable paths and orphaned executables.',
                    style: hud.label,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: hud.accentCyan),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      if (currentDrive != null) {
                        ref
                            .read(permissionAuditProvider.notifier)
                            .runAudit(currentDrive.name);
                      }
                    },
                    icon: Icon(
                      Icons.play_arrow,
                      color: hud.accentCyan,
                    ),
                    label: Text(
                      'START SCAN',
                      style: hud.body.copyWith(
                        color: hud.accentCyan,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return _buildResultList(context, result);
        },
        loading: () {
          final progress = ref.watch(auditProgressProvider);
          final scanned = progress?['scanned'] ?? 0;
          final issues = progress?['issues'] ?? 0;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('AUDITING PERMISSIONS...', style: hud.header),
                const SizedBox(height: 24),
                SizedBox(
                  width: 250,
                  child: LinearProgressIndicator(
                    color: hud.accentCyan,
                    backgroundColor: hud.textMain.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('SCANNED: ', style: hud.label),
                    Text('$scanned', style: hud.statCyan),
                    const SizedBox(width: 16),
                    Text('ISSUES: ', style: hud.label),
                    Text(
                      '$issues',
                      style: hud.statCyan.copyWith(
                        color: issues > 0
                            ? hud.accentAmber
                            : hud.statCyan.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: hud.accentRed),
                  ),
                  onPressed: () {
                    ref.read(permissionAuditProvider.notifier).cancelAudit();
                  },
                  icon: Icon(Icons.close, color: hud.accentRed),
                  label: Text('CANCEL SCAN', style: hud.actionRed),
                ),
              ],
            ),
          );
        },
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: hud.accentRed,
              ),
              const SizedBox(height: 16),
              Text('AUDIT FAILED', style: hud.actionRed),
              const SizedBox(height: 8),
              Text(
                err.toString(),
                style: hud.body.copyWith(color: hud.accentRed),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: hud.accentCyan),
                ),
                onPressed: () {
                  ref.read(permissionAuditProvider.notifier).reset();
                },
                icon: Icon(Icons.refresh, color: hud.accentCyan),
                label: Text(
                  'RESET',
                  style: hud.body.copyWith(color: hud.accentCyan),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultList(BuildContext context, PermissionAuditResult result) {
    final hud = context.hudTheme;
    if (result.issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: hud.accentGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'NO ISSUES FOUND — PERMISSIONS LOOK CLEAN',
              style: hud.header.copyWith(color: hud.accentGreen),
            ),
          ],
        ),
      );
    }

    int high = result.issues.where((i) => i.severity == 'high').length;
    int medium = result.issues.where((i) => i.severity == 'medium').length;
    int low = result.issues.where((i) => i.severity == 'low').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: hud.textMain.withValues(alpha: 0.1),
          child: Row(
            children: [
              Text(
                '${result.issues.length} ISSUES FOUND — ',
                style: hud.body.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '$high HIGH, ',
                style: hud.body.copyWith(
                  color: hud.accentRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$medium MEDIUM, ',
                style: hud.body.copyWith(
                  color: hud.accentAmber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$low LOW',
                style: hud.body.copyWith(
                  color: hud.accentGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: result.issues.length,
            separatorBuilder: (context, index) =>
                Divider(color: hud.textMain.withValues(alpha: 0.1), height: 1),
            itemBuilder: (context, index) {
              final issue = result.issues[index];
              final Color badgeColor = _getSeverityColor(issue.severity, context);

              return ListTile(
                onTap: () => _showIssueDetailSheet(context, issue),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  issue.type.toUpperCase(),
                  style: hud.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
                subtitle: Text(
                  issue.path,
                  style: hud.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: hud.textDim,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getSeverityColor(String severity, BuildContext context) {
    switch (severity.toLowerCase()) {
      case 'high':
        return context.hudTheme.accentRed;
      case 'medium':
        return context.hudTheme.accentAmber;
      case 'low':
      default:
        return context.hudTheme.accentGreen;
    }
  }

  void _showIssueDetailSheet(BuildContext context, PermissionIssue issue) {
    final hud = context.hudTheme;
    final badgeColor = _getSeverityColor(issue.severity, context);

    showModalBottomSheet(
      context: context,
      backgroundColor: hud.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${issue.severity.toUpperCase()} SEVERITY',
                    style: hud.header.copyWith(color: badgeColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('TYPE', style: hud.label),
              const SizedBox(height: 4),
              Text(issue.type.toUpperCase(), style: hud.body),

              const SizedBox(height: 16),
              Text('DESCRIPTION', style: hud.label),
              const SizedBox(height: 4),
              Text(issue.description, style: hud.body),

              const SizedBox(height: 16),
              Text('PATH', style: hud.label),
              const SizedBox(height: 4),
              Text(issue.path, style: hud.body),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: hud.accentCyan),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: issue.path));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Path copied to clipboard',
                          style: hud.body.copyWith(
                            color: hud.base,
                          ),
                        ),
                        backgroundColor: hud.accentCyan,
                      ),
                    );
                  },
                  icon: Icon(Icons.copy, color: hud.accentCyan),
                  label: Text(
                    'COPY PATH',
                    style: hud.body.copyWith(
                      color: hud.accentCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
