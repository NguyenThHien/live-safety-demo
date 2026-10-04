import 'dart:async';
import 'dart:convert';
import 'dart:io';

class _ApiException extends HttpException {
  _ApiException(this.statusCode, String message, {super.uri}) : super(message);

  final int statusCode;
}

class LiveSessionClient {
  HttpClient? _httpClient;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  String? _sessionId;

  String? get sessionId => _sessionId;
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> start({
    required String host,
    required int port,
    String? certificatePem,
    required void Function(String message) onLog,
    required void Function(Map<String, dynamic> message) onMessage,
    required void Function(Object? error) onDisconnected,
  }) async {
    if (_sessionId != null || _socket != null) {
      throw StateError('A live session is already active');
    }

    try {
      final baseUri = _baseUri(host, port);
      final client = _createHttpClient(certificatePem);
      _httpClient = client;

      final health = await _request(
        client,
        'GET',
        baseUri.replace(path: '/health'),
      );
      if (health['ready'] != true) {
        throw const HttpException('Server báo chưa sẵn sàng');
      }
      onLog('HTTPS /health: server sẵn sàng');

      final created = await _request(
        client,
        'POST',
        baseUri.replace(path: '/sessions'),
      );
      final sessionId = created['session_id'];
      final websocketPath = created['websocket_path'];
      if (sessionId is! String || websocketPath is! String) {
        throw const FormatException(
          'Server không trả session_id/websocket_path',
        );
      }
      _sessionId = sessionId;
      onLog('HTTPS tạo phiên: $sessionId');

      final websocketUri = baseUri.replace(
        scheme: 'wss',
        path: websocketPath,
        query: null,
        fragment: null,
      );
      final socket = await WebSocket.connect(
        websocketUri.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 10));
      _socket = socket;

      final ready = Completer<void>();
      _socketSubscription = socket.listen(
        (dynamic data) {
          _handleMessage(data, sessionId, ready, onLog, onMessage);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!ready.isCompleted) ready.completeError(error, stackTrace);
          onLog('WSS lỗi: $error');
          onDisconnected(error);
        },
        onDone: () {
          if (!ready.isCompleted) {
            ready.completeError(
              const WebSocketException('Socket đóng trước khi sẵn sàng'),
            );
          }
          onLog('WSS đã đóng');
          onDisconnected(null);
        },
      );
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      await _cleanupAfterStartFailure(onLog);
      rethrow;
    }
  }

  void _handleMessage(
    dynamic data,
    String sessionId,
    Completer<void> ready,
    void Function(String message) onLog,
    void Function(Map<String, dynamic> message) onMessage,
  ) {
    final text = data is String ? data : utf8.decode(data as List<int>);
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      onLog('WSS nhận dữ liệu không phải JSON');
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      onLog('WSS nhận JSON không đúng định dạng');
      return;
    }

    if (decoded['type'] == 'session_ready' &&
        decoded['session_id'] == sessionId) {
      if (!ready.isCompleted) ready.complete();
    }
    onMessage(decoded);
  }

  Future<void> _cleanupAfterStartFailure(
    void Function(String message) onLog,
  ) async {
    final sessionId = _sessionId;
    if (sessionId != null && _httpClient != null) {
      try {
        await _request(
          _httpClient!,
          'DELETE',
          _baseUriFromClientConfiguration().replace(
            path: '/sessions/$sessionId',
          ),
        );
        onLog('Đã dọn phiên tạo dở');
        _sessionId = null;
      } catch (error) {
        if (error is _ApiException && error.statusCode == HttpStatus.notFound) {
          onLog('Phiên đã kết thúc trên server; xóa trạng thái phiên cũ');
          _sessionId = null;
        } else {
          onLog('Không dọn được phiên trên server: $error');
        }
      }
    }
    await _closeSocket();
    if (_sessionId == null) {
      _httpClient?.close(force: true);
      _httpClient = null;
      _activeBaseUri = null;
    }
  }

  Future<bool> stop() async {
    final sessionId = _sessionId;
    Object? requestError;
    var wasAlreadyEnded = false;
    if (sessionId != null) {
      try {
        final client = _httpClient;
        if (client == null) throw StateError('HTTPS client đã bị đóng');
        final baseUri = _baseUriFromClientConfiguration();
        await _request(
          client,
          'DELETE',
          baseUri.replace(path: '/sessions/$sessionId'),
        );
        _sessionId = null;
      } catch (error) {
        if (error is _ApiException && error.statusCode == HttpStatus.notFound) {
          _sessionId = null;
          wasAlreadyEnded = true;
        } else {
          requestError = error;
        }
      }
    }

    await _closeSocket();
    if (requestError != null) {
      Error.throwWithStackTrace(requestError, StackTrace.current);
    }
    _sessionId = null;
    _activeBaseUri = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    return wasAlreadyEnded;
  }

  Future<void> dispose() async {
    await _closeSocket();
    _httpClient?.close(force: true);
    _httpClient = null;
    _sessionId = null;
    _activeBaseUri = null;
  }

  Uri? _activeBaseUri;

  Uri _baseUriFromClientConfiguration() {
    final uri = _activeBaseUri;
    if (uri == null) throw StateError('Server URI chưa được cấu hình');
    return uri;
  }

  Future<void> _closeSocket() async {
    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) await subscription.cancel();

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'Client closed');
      } on WebSocketException {
        // The peer already closed the connection.
      }
    }
  }

  void sendEvent(String type) {
    final socket = _socket;
    if (!isConnected || socket == null) {
      throw StateError('WSS is not connected');
    }
    socket.add(
      jsonEncode({
        'type': type,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': base64Encode(utf8.encode('mobile-connection-test')),
      }),
    );
  }

  void sendPing() {
    final socket = _socket;
    if (!isConnected || socket == null) {
      throw StateError('WSS is not connected');
    }
    socket.add(jsonEncode({'type': 'ping'}));
  }

  Future<Map<String, dynamic>> _request(
    HttpClient client,
    String method,
    Uri uri,
  ) async {
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (method == 'POST') {
      request.headers.contentType = ContentType.json;
      request.write('{}');
    }

    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _ApiException(
        response.statusCode,
        'HTTP ${response.statusCode}${body.isEmpty ? '' : ': $body'}',
        uri: uri,
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Server trả JSON không đúng định dạng');
    }
    return decoded;
  }

  HttpClient _createHttpClient(String? certificatePem) {
    final pem = certificatePem?.trim() ?? '';
    if (pem.isEmpty) return HttpClient();
    if (!pem.contains('-----BEGIN CERTIFICATE-----') ||
        !pem.contains('-----END CERTIFICATE-----')) {
      throw const FormatException('Chứng chỉ cần ở định dạng PEM');
    }

    final securityContext = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(utf8.encode(pem));
    return HttpClient(context: securityContext);
  }

  Uri _baseUri(String host, int port) {
    final normalizedHost = host.trim();
    if (normalizedHost.isEmpty ||
        normalizedHost.contains('/') ||
        normalizedHost.contains('://')) {
      throw const FormatException(
        'Nhập hostname hoặc IP của server, không kèm https://',
      );
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Port phải nằm trong khoảng 1–65535');
    }

    final uri = Uri(scheme: 'https', host: normalizedHost, port: port);
    _activeBaseUri = uri;
    return uri;
  }
}
