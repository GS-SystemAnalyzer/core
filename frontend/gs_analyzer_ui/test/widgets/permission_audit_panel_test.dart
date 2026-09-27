import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/permission_audit_models.dart';
import 'package:gs_analyzer_ui/providers/permission_audit_provider.dart';
import 'package:gs_analyzer_ui/widgets/permission_audit_panel.dart';

Widget _wrap(dynamic overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: Scaffold(body: PermissionAuditPanel())),
  );
}

class FakePermissionAuditNotifier extends PermissionAuditNotifier {
  final AsyncValue<PermissionAuditResult?> _initialState;
  FakePermissionAuditNotifier(this._initialState);

  @override
  AsyncValue<PermissionAuditResult?> build() => _initialState;
}

void main() {
  testWidgets('shows offline view initially when data is null', (tester) async {
    await tester.pumpWidget(
      _wrap([
        permissionAuditProvider.overrideWith(() => PermissionAuditNotifier()),
      ]),
    );

    expect(find.text('SECURITY AUDIT OFFLINE'), findsOneWidget);
    expect(find.text('START SCAN'), findsOneWidget);
  });

  testWidgets('shows live progress with cancel button when loading', (
    tester,
  ) async {
    final Map<String, dynamic> progressData = {'scanned': 15000, 'issues': 2};

    await tester.pumpWidget(
      _wrap([
        auditProgressProvider.overrideWith((ref) => progressData),
        permissionAuditProvider.overrideWith(
          () => FakePermissionAuditNotifier(const AsyncValue.loading()),
        ),
      ]),
    );

    expect(find.text('AUDITING PERMISSIONS...'), findsOneWidget);
    expect(find.text('15000'), findsOneWidget); // scanned count
    expect(find.text('2'), findsOneWidget); // issues count
    expect(find.text('CANCEL SCAN'), findsOneWidget);
  });

  testWidgets('shows results when data is available', (tester) async {
    final result = PermissionAuditResult(
      root: 'C:\\',
      totalScanned: 42,
      auditedAt: DateTime.now(),
      issues: [
        PermissionIssue(
          path: 'C:\\test.exe',
          severity: 'high',
          type: 'executable_in_data_dir',
          description: 'A bad file',
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap([
        permissionAuditProvider.overrideWith(
          () => FakePermissionAuditNotifier(AsyncValue.data(result)),
        ),
      ]),
    );

    await tester.pumpAndSettle();

    expect(find.text('1 ISSUES FOUND — '), findsOneWidget);
    expect(find.text('1 HIGH, '), findsOneWidget);
    expect(find.textContaining('C:\\test.exe'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no issues', (tester) async {
    final result = PermissionAuditResult(
      root: 'C:\\',
      totalScanned: 42,
      auditedAt: DateTime.now(),
      issues: const [],
    );

    await tester.pumpWidget(
      _wrap([
        permissionAuditProvider.overrideWith(
          () => FakePermissionAuditNotifier(AsyncValue.data(result)),
        ),
      ]),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('NO ISSUES FOUND — PERMISSIONS LOOK CLEAN'),
      findsOneWidget,
    );
  });
}
