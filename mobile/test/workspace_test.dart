import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:draftroom/api.dart';
import 'package:draftroom/models.dart';
import 'package:draftroom/workspace.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  Workspace create(Completer<http.Response> response) {
    final api = ApiClient(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/v1/drafts') {
          return response.future;
        }
        return http.Response('[]', 200);
      }),
    );
    final w = Workspace(api: api);
    w.catalog = Catalog.fromJson(
      jsonDecode(File('assets/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    w.draft = Draft.sample(w.catalog!.id);
    w.loading = false;
    w.user = {
      'id': 'owner',
      'email': 'test@example.test',
      'display_name': 'Coach',
    };
    return w;
  }

  http.Response saved(Draft d) => http.Response(
    jsonEncode({
      'id': 'draft-1',
      'owner_id': 'owner',
      'team_id': null,
      'draft': d.toJson(),
      'revision': 1,
      'updated_at': '2026-11-07T00:00:00Z',
      'can_edit': true,
      'archived': false,
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test(
    'a delayed cloud save cannot attach itself to a new working draft',
    () async {
      final response = Completer<http.Response>();
      final w = create(response);
      final original = w.draft!.copy();
      final pending = w.save();
      w.newDraft();
      response.complete(saved(original));
      await pending;
      expect(w.current, isNull);
      expect(w.draft!.blue.picks.every((id) => id == null), isTrue);
      w.dispose();
    },
  );
  test(
    'edits made while saving remain dirty and are not replaced by the response',
    () async {
      final response = Completer<http.Response>();
      final w = create(response);
      final original = w.draft!.copy();
      final pending = w.save();
      w.draft!.notes = 'Changed while request was in flight';
      w.changed(analyze: false);
      response.complete(saved(original));
      await pending;
      expect(w.current!.revision, 1);
      expect(w.dirty, isTrue);
      expect(w.draft!.notes, 'Changed while request was in flight');
      w.dispose();
    },
  );
  for (final editInsteadOfNew in [false, true]) {
    test(
      'delayed open preserves ${editInsteadOfNew ? "new edits" : "a new draft"}',
      () async {
        final response = Completer<http.Response>();
        final w = create(Completer<http.Response>());
        final original = w.draft!.copy();
        final record = DraftRecord.fromJson(
          jsonDecode(saved(original).body) as Map<String, dynamic>,
        );
        final custom = Workspace(
          api: ApiClient(
            baseUrl: 'https://api.example.test',
            client: MockClient((_) => response.future),
          ),
        );
        custom.catalog = w.catalog;
        custom.draft = original.copy();
        custom.loading = false;
        final pending = custom.open(record);
        if (editInsteadOfNew) {
          custom.draft!.notes = 'Keep the notes I am typing';
          custom.changed(analyze: false);
        } else {
          custom.newDraft();
        }
        response.complete(saved(original));
        await pending;
        expect(custom.current, isNull);
        expect(custom.dirty, isTrue);
        if (editInsteadOfNew) {
          expect(custom.draft!.notes, 'Keep the notes I am typing');
        } else {
          expect(custom.draft!.blue.picks.every((id) => id == null), isTrue);
        }
        custom.dispose();
        w.dispose();
      },
    );
  }

  test('cloud refresh cannot restore teams after an account changes', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final w = Workspace(
      api: ApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient((_) {
          requests++;
          return response.future;
        }),
      ),
    );
    w.user = {'id': 'old-account'};
    w.api.token = 'old-session';
    final pending = w.refreshCloud();
    w.user = {'id': 'new-account'};
    w.api.token = 'new-session';
    response.complete(
      http.Response(
        '[{"id":"private-old-team","name":"Private","role":"owner"}]',
        200,
      ),
    );
    await pending;
    expect(w.teams, isEmpty);
    expect(w.sessions, isEmpty);
    expect(requests, 1);
    w.dispose();
  });

  test('an older refresh cannot replace a newer cloud result', () async {
    final old = Completer<http.Response>();
    var teamRequests = 0;
    final w = Workspace(
      api: ApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/v1/teams') {
            if (++teamRequests == 1) return old.future;
            return http.Response(
              '[{"id":"latest","name":"Latest team","role":"owner"}]',
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      ),
    );
    w.user = {'id': 'owner'};
    final pending = w.refreshCloud();
    await Future<void>.delayed(Duration.zero);
    await w.refreshCloud();
    old.complete(
      http.Response('[{"id":"old","name":"Old team","role":"owner"}]', 200),
    );
    await pending;
    expect(w.teams.single['id'], 'latest');
    w.dispose();
  });
}
