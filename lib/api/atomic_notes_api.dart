import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/authentication/auth_services/cred.dart';
import 'package:atomic_notes/security/secure_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:atomic_notes/database/note.dart' show newId;

class ApiException implements Exception {
  final String code;
  final int statusCode;
  final int? retryAfterSeconds;
  ApiException(this.code, this.statusCode, {this.retryAfterSeconds});
  @override
  String toString() => code;
}

/// Historical totals for one Server operation, including on requestId replay.
/// These amounts do not indicate a new wallet debit for this HTTP attempt.
class PushReceipt {
  const PushReceipt({required this.charged, required this.refunded})
      : assert(charged >= 0), assert(refunded >= 0), assert(refunded <= charged);
  final int charged;
  final int refunded;
  int get netCharge => charged - refunded;
}

/// Note acknowledgements and optional billing metadata for the submitted batch.
/// A missing receipt means unknown cost, including with older Servers.
class PushReply {
  const PushReply({required this.requestId, required this.instant,
      required this.results, this.receipt});
  final String requestId;
  final bool instant;
  final List<Map<String, dynamic>> results;
  final PushReceipt? receipt;
}

/// The authenticated transport boundary. Every response belongs to the exact
/// session that sent it, including re-login to the same account.
class ApiClient {
  ApiClient._({http.Client? client, FlutterSecureStorage? storage,
      Uri? baseUrl, Duration requestTimeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage(aOptions: kSecureAndroidOptions),
        _baseUrl = baseUrl, _requestTimeout = requestTimeout;
  static final ApiClient instance = ApiClient._();

  @visibleForTesting
  factory ApiClient.forTest({required http.Client client, required Uri baseUrl,
      FlutterSecureStorage? storage, Duration requestTimeout = const Duration(seconds: 30)}) =>
      ApiClient._(client: client, baseUrl: baseUrl, storage: storage, requestTimeout: requestTimeout);

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final Uri? _baseUrl;
  final Duration _requestTimeout;
  static const _tokenKey = 'atomic_api_session_token';
  static const _userIdKey = 'atomic_api_user_id';
  static const _userEmailKey = 'atomic_api_user_email';
  final CredService _cred = CredService();
  String? _cachedToken;
  String? _cachedUserId;
  String? _cachedUserEmail;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  Future<void> _storageWrites = Future<void>.value();
  final StreamController<void> _sessionEndedController = StreamController<void>.broadcast();
  Stream<void> get onSessionEnded => _sessionEndedController.stream;

  late final GoogleSignIn _google = GoogleSignIn(
    forceCodeForRefreshToken: true,
    scopes: const ['email', 'https://www.googleapis.com/auth/drive.file'],
    serverClientId: _cred.GOOGLE_SERVER_CLIENT_ID,
  );

  Future<void> init() async {
    await _storageWrites;
    _cachedToken = await _storage.read(key: _tokenKey);
    _cachedUserId = await _storage.read(key: _userIdKey);
    _cachedUserEmail = await _storage.read(key: _userEmailKey);
    _sessionRevision++;
  }
  String? get currentUserId => _cachedUserId;
  String? get currentUserEmail => _cachedUserEmail;
  bool get isSignedIn => _cachedToken != null;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _baseUrl ?? Uri.parse(_cred.API_BASE_URL);
    return base.replace(path: '${base.path}$path',
      queryParameters: query?.isNotEmpty == true ? query : null);
  }

  Future<void> _queueStorage(Future<void> Function() action) {
    final write = _storageWrites.then((_) => action());
    _storageWrites = write.catchError((_) {});
    return write;
  }

  Future<void> _clearSession() {
    _cachedToken = null;
    _cachedUserId = null;
    _cachedUserEmail = null;
    _sessionRevision++;
    final clearing = _queueStorage(() async {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userIdKey);
      await _storage.delete(key: _userEmailKey);
    });
    _sessionEndedController.add(null);
    return clearing;
  }

  Future<void> _saveSession(String token, String userId, String email) {
    _cachedToken = token;
    _cachedUserId = userId;
    _cachedUserEmail = email;
    _sessionRevision++;
    return _queueStorage(() async {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userIdKey, value: userId);
      await _storage.write(key: _userEmailKey, value: email);
    });
  }

  Future<dynamic> _request(String method, String path, {Object? body,
      Map<String, String>? query, bool authenticated = true,
      Duration? timeout, bool acceptSyncFailure = false}) async {
    final revision = _sessionRevision;
    final token = authenticated ? _cachedToken : null;
    final request = http.Request(method, _uri(path, query));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await _client.send(request).then(http.Response.fromStream)
        .timeout(timeout ?? _requestTimeout);
    // Reject both success and failure from old sessions before interpreting
    // anything. Account ID alone cannot detect A -> sign-out -> A.
    if (revision != _sessionRevision) throw ApiException('session_changed', 409);
    dynamic decoded;
    try { decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body); }
    on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw ApiException('invalid_response', response.statusCode);
      }
      decoded = <String, dynamic>{};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    final code = decoded is Map && decoded['error'] is String
        ? decoded['error'] as String : 'http_${response.statusCode}';
    if (response.statusCode == 401 && code != 'missing_token' && token != null) {
      unawaited(_clearSession().catchError((_) {}));
    }
    if (acceptSyncFailure && response.statusCode == 502 && code == 'note_sync_failed') return decoded;
    final wait = decoded is Map ? decoded['retry_after_seconds'] : null;
    throw ApiException(code, response.statusCode, retryAfterSeconds: wait is num ? wait.toInt() : null);
  }

  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw ApiException('cancelled', 0);
    final code = account.serverAuthCode;
    if (code == null) throw ApiException('no_server_auth_code', 0);
    final data = await _request('POST', '/auth/google/mobile',
      authenticated: false, body: {'serverAuthCode': code}) as Map;
    final user = data['user'] as Map;
    await _saveSession(data['token'] as String, user['id'] as String, user['email'] as String);
  }

  Future<void> signOut() async {
    final revision = _sessionRevision;
    try {
      await _request('POST', '/auth/logout', timeout: const Duration(seconds: 10));
    } catch (_) { /* Always complete local logout even when revocation is unavailable. */ }
    if (revision != _sessionRevision) return;
    try { await _google.signOut().timeout(const Duration(seconds: 5)); } catch (_) {}
    if (revision != _sessionRevision) return;
    await _clearSession();
  }

  Future<PushReply> pushNotes(List<Map<String, dynamic>> rows,
      {required String requestId, bool instant = false}) async {
    final data = await _request('POST', '/notes/push',
      body: {'rows': rows, 'requestId': requestId, 'mode': instant ? 'instant' : 'standard'},
      timeout: const Duration(seconds: 90), acceptSyncFailure: true) as Map;
    final charged = data['charged'];
    final refunded = data['refunded'];
    // Old Servers omit receipts. Malformed optional billing metadata must not
    // discard valid note acknowledgements or imply that an operation was free.
    final receipt = charged is int && refunded is int &&
        charged >= 0 && refunded >= 0 && refunded <= charged
        ? PushReceipt(charged: charged, refunded: refunded) : null;
    return PushReply(
      requestId: requestId, instant: instant,
      results: List<Map<String, dynamic>>.from(data['results'] as List),
      receipt: receipt,
    );
  }
  Future<Map<String, dynamic>> pullNotes({int? after, bool encOnly = false}) async =>
    Map<String, dynamic>.from(await _request('GET', '/notes/pull', query: {
      if (encOnly) 'encOnly': 'true', if (after != null) 'after': after.toString(),
    }, timeout: const Duration(seconds: 90)) as Map);
  Future<int> remoteNoteCount() async => (await _request('GET', '/notes/count'))['count'] as int;
  Future<void> wipeRemoteNotes() async { await _request('DELETE', '/notes', timeout: const Duration(seconds: 90)); }
  Future<Map<String, dynamic>?> getVault() async {
    try { return await _request('GET', '/vault') as Map<String, dynamic>; }
    on ApiException catch (e) { if (e.statusCode == 404) return null; rethrow; }
  }
  Future<void> createVault({required String verifier, required int kdfMemory,
      required int kdfIterations, required int kdfParallelism}) async {
    await _request('POST', '/vault', body: {'verifier': verifier, 'kdfMemory': kdfMemory,
      'kdfIterations': kdfIterations, 'kdfParallelism': kdfParallelism});
  }
  int _coinReplayRevision = -1;
  bool _coinReplaySupported = false;
  Future<Map<String, dynamic>> energyState() async {
    final state = await _request('GET', '/energy') as Map<String, dynamic>;
    _coinReplayRevision = sessionRevision;
    _coinReplaySupported = state['coin_request_replay'] == true;
    return state;
  }
  Future<int?> pendingCoinConversion() async {
    final user = currentUserId, revision = sessionRevision;
    if (user == null) return null;
    final saved = await _storage.read(key: 'atomic_coin_conversion_$user');
    if (revision != sessionRevision) throw ApiException('session_changed', 409);
    return saved == null ? null : (jsonDecode(saved) as Map)['coins'] as int;
  }

  bool _converting = false;

  /// Save before sending. An ambiguous response survives process restart and account switching.
  Future<void> energyConvert(int coins) async {
    if (_converting) throw ApiException('coin_conversion_busy', 409);
    final user = currentUserId;
    final revision = sessionRevision;
    if (user == null) throw ApiException('missing_token', 401);
    _converting = true;
    final key = 'atomic_coin_conversion_$user';
    try {
      if (_coinReplayRevision != revision || !_coinReplaySupported) await energyState();
      if (revision != sessionRevision) throw ApiException('session_changed', 409);
      if (!_coinReplaySupported) throw ApiException('coin_replay_unavailable', 409);
      final saved = await _storage.read(key: key);
      final pending = saved == null ? <String, dynamic>{
        'coins': coins, 'request_id': newId(),
      } : Map<String, dynamic>.from(jsonDecode(saved) as Map);
      if (pending['coins'] != coins) {
        throw ApiException('coin_conversion_pending_${pending['coins']}', 409);
      }
      await _queueStorage(() => _storage.write(key: key, value: jsonEncode(pending)));
      if (revision != sessionRevision) throw ApiException('session_changed', 409);
      try {
        await _request('POST', '/energy/convert', body: pending);
      } on ApiException catch (e) {
        // Only explicit no-write refusals clear the request. Timeouts/5xx/401/unknown outcomes retain it.
        if (['insufficient_coins', 'energy_cap_exceeded', 'invalid_amount'].contains(e.code)) {
          await _queueStorage(() => _storage.delete(key: key));
        }
        rethrow;
      }
      await _queueStorage(() => _storage.delete(key: key));
    } finally {
      _converting = false;
    }
  }
  Future<Map<String, dynamic>> coinBatches({String? cursor}) async =>
    await _request('GET', '/energy/coins', query: cursor == null ? null : {'cursor': cursor}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> upgradeNoteLimit(int fromLimit) async =>
    await _request('POST', '/energy/note-limit', body: {'from_limit': fromLimit}) as Map<String, dynamic>;
  Future<List<Map<String, dynamic>>> notificationsFeed({String? appVersion}) async {
    final data = await _request('GET', '/notifications',
      query: appVersion == null ? null : {'app_version': appVersion}) as Map;
    return (data['rows'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
  Future<void> markNotificationRead(String id) async { await _request('POST', '/notifications/${Uri.encodeComponent(id)}/read'); }
  Future<void> markAllNotificationsRead({String? appVersion}) async {
    await _request('POST', '/notifications/read-all', query: appVersion == null ? null : {'app_version': appVersion});
  }
  Future<void> dismissNotification(String id) async { await _request('POST', '/notifications/${Uri.encodeComponent(id)}/dismiss'); }
  Future<String> getUsername() async => (await _request('GET', '/atomicuser'))['username'] as String;
  Future<void> setUsername(String username) async { await _request('PATCH', '/atomicuser', body: {'username': username}); }
}
