import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

http.Response _ok(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

void main() {
  group('ApiService.undoNuke', () {
    test(
      'targeted undo uses /undo/{operationId} as a ROUTE segment (no query)',
      () async {
        late Uri captured;
        final client = MockClient((req) async {
          captured = req.url;
          return _ok({
            'deletedFiles': 1,
            'recoverable': true,
            'operationId': 'op-123',
          });
        });

        await ApiService(client).undoNuke('op-123');

        // Backend route is POST undo/{operationId?}: it binds {operationId} from the
        // PATH. A ?query string is ignored, so the wrong (most-recent) op is undone.
        expect(captured.path, endsWith('/api/nuke/undo/op-123'));
        expect(
          captured.query,
          isEmpty,
          reason: 'operationId must be a path segment, not a query parameter',
        );
      },
    );

    test('untargeted undo posts to /undo with no id', () async {
      late Uri captured;
      late String method;
      final client = MockClient((req) async {
        captured = req.url;
        method = req.method;
        return _ok({
          'deletedFiles': 1,
          'recoverable': true,
          'operationId': 'op-1',
        });
      });

      await ApiService(client).undoNuke();

      expect(method, 'POST');
      expect(captured.path, endsWith('/api/nuke/undo'));
      expect(captured.query, isEmpty);
    });

    test('throws on non-200', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      expect(() => ApiService(client).undoNuke('op-1'), throwsException);
    });
  });

  group('ApiService.executeNuke', () {
    test(
      'DELETEs /execute with paths, planToken and useRecycleBin in body',
      () async {
        late http.Request req;
        final client = MockClient((r) async {
          req = r;
          return _ok({
            'deletedFiles': 1,
            'recycleBinUsed': true,
            'operationId': 'op-1',
          });
        });

        await ApiService(
          client,
        ).executeNuke(['C:\\temp\\x'], 'tok', useRecycleBin: true);

        expect(req.method, 'DELETE');
        expect(req.url.path, endsWith('/api/nuke/execute'));
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['paths'], ['C:\\temp\\x']);
        expect(body['planToken'], 'tok');
        expect(body['useRecycleBin'], isTrue);
      },
    );
  });

  group('ApiService.clearUndoStack', () {
    test('DELETEs /undo', () async {
      late http.Request req;
      final client = MockClient((r) async {
        req = r;
        return http.Response('', 200);
      });
      await ApiService(client).clearUndoStack();
      expect(req.method, 'DELETE');
      expect(req.url.path, endsWith('/api/nuke/undo'));
    });
  });

  group('ApiService.getUndoHistory', () {
    test('GETs /undo/history and parses the list', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'operationId': 'op-1',
                'usedRecycleBin': true,
                'deletedFiles': 2,
                'originalPaths': [],
                'deletedPaths': [],
                'executedAt': '2026-06-24T10:00:00Z',
              },
            ],
          }),
          200,
        ),
      );

      final hist = await ApiService(client).getUndoHistory();
      expect(hist, hasLength(1));
      expect(hist.first.deletedFiles, 2);
      expect(hist.first.usedRecycleBin, isTrue);
    });
  });

  group('ApiService.killRamProcesses', () {
    test('returns true when processes are terminated successfully', () async {
      late http.Request req;
      final client = MockClient((r) async {
        req = r;
        return http.Response(
          jsonEncode({'message': '1 PIDs Terminated'}),
          200,
        );
      });

      final result = await ApiService(client).killRamProcesses([1234]);
      expect(result, isTrue);
      expect(req.method, 'POST');
      expect(req.url.path, endsWith('/api/Telemetry/ram/kill'));
      expect(jsonDecode(req.body), [1234]);
    });

    test('throws Access Denied when 200 OK returns 0 PIDs Terminated', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'message': '0 PIDs Terminated'}),
            200,
          ));

      expect(
        () => ApiService(client).killRamProcesses([4]),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('Access Denied: Run as Administrator'))),
      );
    });

    test('throws Access Denied on 403 Forbidden', () async {
      final client = MockClient((_) async => http.Response('Forbidden', 403));

      expect(
        () => ApiService(client).killRamProcesses([4]),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('Access Denied: Run as Administrator'))),
      );
    });

    test('throws with status code details on 500 error', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'error': 'Internal server failure'}),
            500,
          ));

      expect(
        () => ApiService(client).killRamProcesses([1234]),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('Internal server failure'))),
      );
    });
  });
}
