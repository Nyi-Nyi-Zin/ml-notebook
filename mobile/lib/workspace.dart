import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';
import 'local_engine.dart';

class Workspace extends ChangeNotifier {
  final ApiClient api;
  final SharedPreferencesAsync preferences;
  final FlutterSecureStorage secure;
  Workspace({
    ApiClient? api,
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secure,
  }) : api =
           api ??
           ApiClient(baseUrl: const String.fromEnvironment('API_BASE_URL')),
       preferences = preferences ?? SharedPreferencesAsync(),
       secure = secure ?? const FlutterSecureStorage();
  Catalog? catalog;
  Draft? draft;
  DraftRecord? current;
  Map<String, dynamic>? user, analysis;
  List<Map<String, dynamic>> teams = [];
  List<DraftRecord> sessions = [];
  final List<Draft> _undo = [];
  bool loading = true,
      busy = false,
      online = false,
      remoteAnalysis = false,
      dirty = false,
      archivedView = false;
  String? error, newTeamId;
  String focusSide = 'blue', language = 'en', priority = 'balanced';
  int focusIndex = 0, _analysisSerial = 0, _edits = 0, _documentEpoch = 0;
  int _cloudSerial = 0;
  Timer? _debounce;
  Future<void> _writes = Future.value();
  String get tokenKey =>
      'draftroom.session.${base64Url.encode(utf8.encode(api.baseUrl))}';
  bool get canEdit => current == null || current!.canEdit && !current!.archived;
  bool get canUndo => _undo.isNotEmpty;
  String t(String en, String mm) => language == 'mm' ? mm : en;

  Future<void> init() async {
    try {
      catalog = Catalog.fromJson(
        jsonDecode(await rootBundle.loadString('assets/catalog.json'))
            as Map<String, dynamic>,
      );
      final cachedCatalog = await preferences.getString('catalog_cache');
      if (cachedCatalog != null) {
        try {
          final candidate = Catalog.fromJson(
            jsonDecode(cachedCatalog) as Map<String, dynamic>,
          );
          if (candidate.heroes.isNotEmpty) catalog = candidate;
        } catch (_) {
          /* Fall back to the bundled baseline. */
        }
      }
      final url = await preferences.getString('api_url');
      if (url != null) api.baseUrl = url;
      language = await preferences.getString('language') ?? 'en';
      final cached = await preferences.getString('draft_cache');
      if (cached != null) {
        try {
          final d = Draft.fromJson(jsonDecode(cached) as Map<String, dynamic>);
          d.validate(catalog!);
          draft = d;
        } catch (_) {
          /* Ignore an obsolete or corrupt cache. */
        }
      }
      draft ??= Draft.sample(catalog!.id);
      loading = false;
      refreshAnalysis();
      notifyListeners();
      if (api.baseUrl.isNotEmpty) await connect();
    } catch (e) {
      loading = false;
      error = 'Could not initialize the workspace: $e';
      notifyListeners();
    }
  }

  Future<void> connect() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final json = await api.request(
        'GET',
        '/v1/catalog?patch_id=${Uri.encodeComponent(draft!.patchId)}',
        auth: false,
      );
      catalog = Catalog.fromJson(Map<String, dynamic>.from(json as Map));
      await preferences.setString('catalog_cache', jsonEncode(catalog!.json));
      online = true;
      try {
        api.token = await secure.read(key: tokenKey);
      } catch (_) {
        api.token = null;
      }
      if (api.token != null) {
        try {
          user = Map<String, dynamic>.from(
            await api.request('GET', '/v1/auth/me') as Map,
          );
          await refreshCloud();
        } on ApiException catch (e) {
          if (e.status == 401) {
            api.token = null;
            user = null;
            await secure.delete(key: tokenKey);
          } else {
            rethrow;
          }
        }
      }
      refreshAnalysis();
    } catch (e) {
      online = false;
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setUrl(String value) async {
    final url = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (url.isNotEmpty &&
        (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment)) {
      throw const FormatException(
        'Enter an HTTP(S) API origin without credentials, query or fragment.',
      );
    }
    _documentEpoch++;
    api.baseUrl = url;
    api.token = null;
    user = null;
    current = null;
    teams = [];
    sessions = [];
    newTeamId = null;
    online = false;
    await preferences.setString('api_url', url);
    notifyListeners();
    if (url.isNotEmpty) {
      await connect();
    } else {
      refreshAnalysis();
    }
  }

  Future<void> authenticate(
    String email,
    String password, {
    String? name,
  }) async {
    final result = Map<String, dynamic>.from(
      await api.request(
            'POST',
            name == null ? '/v1/auth/login' : '/v1/auth/register',
            body: {'email': email, 'password': password, 'display_name': ?name},
            auth: false,
          )
          as Map,
    );
    api.token = result['token'] as String;
    user = Map<String, dynamic>.from(result['user'] as Map);
    online = true;
    try {
      await secure.write(key: tokenKey, value: api.token);
    } catch (_) {
      error =
          'Signed in for this session. Secure storage is unavailable on this origin; use HTTPS for persistent sign-in.';
    }
    await refreshCloud();
    notifyListeners();
  }

  Future<void> logout() async {
    _documentEpoch++;
    try {
      if (api.token != null) await api.request('POST', '/v1/auth/logout');
    } finally {
      try {
        await secure.delete(key: tokenKey);
      } catch (_) {}
      api.token = null;
      user = null;
      teams = [];
      sessions = [];
      newTeamId = null;
      current = null;
      draft = Draft.sample(catalog!.id);
      _undo.clear();
      dirty = false;
      _edits++;
      await _writes;
      await preferences.remove('draft_cache');
      refreshAnalysis();
      notifyListeners();
    }
  }

  void _cache() {
    final body = jsonEncode(draft!.toJson());
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => preferences.setString('draft_cache', body))
        .catchError((Object _) {
          error =
              'Local cache could not be saved. Save to the server or copy the JSON.';
          notifyListeners();
        });
  }

  void _checkpoint() {
    _undo.add(draft!.copy());
    if (_undo.length > 30) _undo.removeAt(0);
  }

  void changed({bool analyze = true}) {
    dirty = true;
    _edits++;
    _cache();
    if (analyze) refreshAnalysis();
    notifyListeners();
  }

  void selectFocus(String side, int index) {
    focusSide = side;
    focusIndex = index;
    refreshAnalysis();
    notifyListeners();
  }

  void assignHero(String side, int index, bool ban, String id) {
    if (!canEdit) {
      throw const FormatException(
        'This team draft is read-only. Save a personal copy to edit.',
      );
    }
    final next = draft!.copy();
    final arr = ban ? next.side(side).bans : next.side(side).picks;
    if (arr[index] == id) return;
    arr[index] = id;
    next.validate(catalog!);
    _checkpoint();
    draft = next;
    if (!ban) {
      focusSide = side;
      focusIndex = index;
    }
    changed();
  }

  void removeHero(String side, int index, bool ban) {
    if (!canEdit) return;
    _checkpoint();
    (ban ? draft!.side(side).bans : draft!.side(side).picks)[index] = null;
    changed();
  }

  void undo() {
    if (_undo.isEmpty || !canEdit) return;
    final prior = _undo.removeLast();
    prior.title = draft!.title;
    prior.notes = draft!.notes;
    draft = prior;
    changed();
  }

  void newDraft({bool example = false}) {
    _documentEpoch++;
    draft = example ? Draft.sample(catalog!.id) : Draft.empty(catalog!.id);
    current = null;
    newTeamId = null;
    _undo.clear();
    focusSide = 'blue';
    focusIndex = 0;
    changed();
  }

  void swap() {
    if (!canEdit) return;
    _checkpoint();
    final blue = draft!.blue;
    draft!.blue = draft!.red;
    draft!.red = blue;
    focusSide = focusSide == 'blue' ? 'red' : 'blue';
    changed();
  }

  void setPriority(String value) {
    priority = value;
    refreshAnalysis();
    notifyListeners();
  }

  Future<void> toggleLanguage() async {
    language = language == 'en' ? 'mm' : 'en';
    await preferences.setString('language', language);
    refreshAnalysis();
    notifyListeners();
  }

  Future<void> useLatestCatalog() async {
    final result = await api.request('GET', '/v1/catalog', auth: false);
    final next = Catalog.fromJson(Map<String, dynamic>.from(result as Map));
    catalog = next;
    await preferences.setString('catalog_cache', jsonEncode(next.json));
    online = true;
    newDraft();
  }

  void refreshAnalysis() {
    if (catalog == null || draft == null) return;
    final serial = ++_analysisSerial;
    remoteAnalysis = false;
    try {
      analysis = localAnalysis(
        draft!,
        catalog!,
        focusSide,
        focusIndex,
        priority,
        language,
      );
    } catch (e) {
      error = '$e';
      analysis = null;
    }
    _debounce?.cancel();
    if (online) {
      final body = {
        'draft': draft!.toJson(),
        'side': focusSide,
        'role_index': focusIndex,
        'priority': priority,
        'language': language,
      };
      _debounce = Timer(const Duration(milliseconds: 250), () async {
        try {
          final result = await api.request(
            'POST',
            '/v1/analyze',
            body: body,
            auth: false,
          );
          if (serial == _analysisSerial) {
            analysis = Map<String, dynamic>.from(result as Map);
            remoteAnalysis = true;
            notifyListeners();
          }
        } catch (_) {
          if (serial == _analysisSerial) {
            remoteAnalysis = false;
            notifyListeners();
          }
        }
      });
    }
  }

  Future<void> refreshCloud() async {
    if (user == null) return;
    final serial = ++_cloudSerial;
    final accountId = user!['id'];
    final baseUrl = api.baseUrl;
    final token = api.token;
    final archived = archivedView;
    bool isCurrent() =>
        serial == _cloudSerial &&
        user?['id'] == accountId &&
        api.baseUrl == baseUrl &&
        api.token == token &&
        archivedView == archived;
    final ts = await api.request('GET', '/v1/teams');
    if (!isCurrent()) return;
    final result = await api.request('GET', '/v1/drafts?archived=$archived');
    if (!isCurrent()) return;
    teams = (ts as List)
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();
    sessions = (result as List)
        .map((r) => DraftRecord.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    notifyListeners();
  }

  Future<void> save({bool asCopy = false}) async {
    if (user == null) {
      throw const ApiException(401, 'Sign in to save drafts to PostgreSQL.');
    }
    draft!.validate(catalog!);
    if (!asCopy && current != null && !current!.canEdit) {
      throw const FormatException(
        'Read-only draft. Save a personal copy instead.',
      );
    }
    final epoch = _documentEpoch;
    final creating = asCopy || current == null;
    final atEdit = _edits;
    final teamId = creating ? newTeamId : current!.teamId;
    final result = await api.request(
      creating ? 'POST' : 'PUT',
      creating ? '/v1/drafts' : '/v1/drafts/${current!.id}',
      body: {
        'draft': draft!.toJson(),
        'team_id': teamId,
        if (!creating) 'expected_revision': current!.revision,
      },
    );
    if (epoch == _documentEpoch) {
      current = DraftRecord.fromJson(Map<String, dynamic>.from(result as Map));
      dirty = atEdit != _edits;
    }
    await refreshCloud();
    notifyListeners();
  }

  Future<void> open(DraftRecord record) async {
    final epoch = ++_documentEpoch;
    final edits = _edits;
    final baseUrl = api.baseUrl;
    bool isCurrent() =>
        epoch == _documentEpoch && edits == _edits && api.baseUrl == baseUrl;
    final result = DraftRecord.fromJson(
      Map<String, dynamic>.from(
        await api.request('GET', '/v1/drafts/${record.id}') as Map,
      ),
    );
    if (!isCurrent()) return;
    var nextCatalog = catalog!;
    if (result.draft.patchId != nextCatalog.id) {
      nextCatalog = Catalog.fromJson(
        Map<String, dynamic>.from(
          await api.request(
                'GET',
                '/v1/catalog?patch_id=${Uri.encodeComponent(result.draft.patchId)}',
                auth: false,
              )
              as Map,
        ),
      );
      if (!isCurrent()) return;
    }
    result.draft.validate(nextCatalog);
    catalog = nextCatalog;
    current = result;
    draft = result.draft.copy();
    newTeamId = result.canEdit ? result.teamId : null;
    dirty = false;
    _undo.clear();
    _edits++;
    _cache();
    refreshAnalysis();
    notifyListeners();
    await preferences.setString('catalog_cache', jsonEncode(nextCatalog.json));
  }

  Future<void> archive(DraftRecord record) async {
    await api.request(
      'PUT',
      '/v1/drafts/${record.id}/archive',
      body: {
        'archived': !record.archived,
        'expected_revision': record.revision,
      },
    );
    if (current?.id == record.id) {
      current = null;
      dirty = true;
    }
    await refreshCloud();
    notifyListeners();
  }

  Future<void> createTeam(String name) async {
    await api.request('POST', '/v1/teams', body: {'name': name});
    await refreshCloud();
  }

  Future<void> joinTeam(String code) async {
    await api.request('POST', '/v1/teams/join', body: {'code': code.trim()});
    await refreshCloud();
  }

  Future<String> invite(String teamId, String role) async {
    final r = await api.request(
      'POST',
      '/v1/teams/$teamId/invites',
      body: {'role': role},
    );
    return (r as Map)['code'] as String;
  }

  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'format': 'draftroom-native-v1', 'draft': draft!.toJson()});
  void importJson(String value) {
    if (value.length > 131072) {
      throw const FormatException('Draft JSON is too large.');
    }
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['format'] != 'draftroom-native-v1') {
      throw const FormatException('Choose a native DraftRoom draft export.');
    }
    final next = Draft.fromJson(
      Map<String, dynamic>.from(json['draft'] as Map),
    );
    next.validate(catalog!);
    _documentEpoch++;
    draft = next;
    current = null;
    newTeamId = null;
    _undo.clear();
    changed();
  }

  String brief() {
    final a = analysis;
    if (a == null) return 'Choose a draft first.';
    final e = a['emblem'] as Map?;
    return '# ${draft!.title}\n\nPatch: ${catalog!.patch['label']}\nRules: ${a['rules_version']}\n\n${['blue', 'red'].map((side) => '${draft!.side(side).name}: ${draft!.side(side).picks.asMap().entries.map((entry) => '${roles[entry.key]} — ${catalog!.hero(entry.value)?.name ?? 'TBD'}').join(' | ')}').join('\n')}\n\n${e == null ? 'No focused hero.' : '## ${a['focus']['name']}\n${e['base']} → ${(e['talents'] as List).join(' → ')}\nSpell: ${e['spell']}\n\n${e['reason']}\n\nTrade-off: ${e['tradeoff']}\n\nAlternative: ${e['alternative']}'}\n\n## Matchup priorities\n${(a['threats'] as List).map((p) => '- ${p['title']}: ${p['body']}').join('\n')}\n\n## Game plan\n${(a['plan'] as List).map((p) => '### ${p['title']}\n${p['body']}').join('\n\n')}\n\n## Notes\n${draft!.notes}\n\nCoaching heuristics, not live patch verification. Check talent effects in the game client.';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    api.close();
    super.dispose();
  }
}
