import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/live_session_client.dart';

enum _SessionStatus { idle, connecting, active, stopping, error }

class LiveDemoScreen extends StatefulWidget {
  const LiveDemoScreen({super.key});

  @override
  State<LiveDemoScreen> createState() => _LiveDemoScreenState();
}

class _LiveDemoScreenState extends State<LiveDemoScreen>
    with WidgetsBindingObserver {
  final _hostController = TextEditingController(text: '192.168.1.10');
  final _portController = TextEditingController(text: '8443');
  final _certificateController = TextEditingController();
  final _client = LiveSessionClient();
  final List<String> _events = [];
  Future<void>? _stopOperation;

  _SessionStatus _status = _SessionStatus.idle;
  String _statusMessage = 'Sẵn sàng kết nối';
  bool _showCertificate = false;

  String? get _sessionId => _client.sessionId;
  bool get _hasSession => _sessionId != null;
  bool get _isBusy =>
      _status == _SessionStatus.connecting ||
      _status == _SessionStatus.stopping;
  bool get _isConnected =>
      _status == _SessionStatus.active && _client.isConnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _hasSession) {
      unawaited(_stopSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hostController.dispose();
    _portController.dispose();
    _certificateController.dispose();
    if (_hasSession) {
      unawaited(_stopSession(updateUi: false).whenComplete(_client.dispose));
    } else {
      unawaited(_client.dispose());
    }
    super.dispose();
  }

  void _setStatus(_SessionStatus status, String message) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _statusMessage = message;
    });
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(
        0,
        '${DateTime.now().toLocal().toString().substring(11, 19)}  $message',
      );
      if (_events.length > 40) _events.removeLast();
    });
  }

  Future<void> _startSession() async {
    if (_isBusy || _hasSession) return;
    _setStatus(_SessionStatus.connecting, 'Đang kiểm tra HTTPS...');
    setState(_events.clear);

    try {
      final port = int.tryParse(_portController.text.trim());
      if (port == null) {
        throw const FormatException('Port phải nằm trong khoảng 1–65535');
      }
      await _client.start(
        host: _hostController.text,
        port: port,
        certificatePem: _certificateController.text,
        onLog: _log,
        onMessage: _handleServerMessage,
        onDisconnected: _handleSocketClosed,
      );
      _setStatus(_SessionStatus.active, 'Phiên Live đang hoạt động');
    } catch (error) {
      _log('Không thể bắt đầu phiên: $error');
      _setStatus(_SessionStatus.error, 'Kết nối thất bại: $error');
    }
  }

  void _handleServerMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'session_ready':
        _log('WSS đã kết nối: session_ready');
        break;
      case 'media_received':
        _log('Server xác nhận đã nhận: ${message['stream']}');
        break;
      case 'pong':
        _log('Server trả pong');
        break;
      case 'error':
        _log('Server báo lỗi: ${message['message']}');
        break;
      default:
        _log('WSS nhận: $message');
    }
  }

  void _handleSocketClosed(Object? error) {
    if (_status == _SessionStatus.active) {
      _setStatus(
        _SessionStatus.error,
        error == null ? 'WSS đã đóng' : 'WSS bị ngắt: $error',
      );
    }
  }

  Future<void> _stopSession({bool updateUi = true}) {
    if (!_hasSession) return Future<void>.value();
    final currentOperation = _stopOperation;
    if (currentOperation != null) return currentOperation;
    if (_status == _SessionStatus.stopping) return Future<void>.value();

    final operation = _performStopSession(updateUi: updateUi);
    _stopOperation = operation;
    return operation.whenComplete(() => _stopOperation = null);
  }

  Future<void> _performStopSession({required bool updateUi}) async {
    if (!_hasSession) return;
    final sessionId = _sessionId;
    if (updateUi) {
      _setStatus(_SessionStatus.stopping, 'Đang kết thúc phiên qua HTTPS...');
    }

    try {
      final alreadyEnded = await _client.stop();
      _log(
        alreadyEnded
            ? 'Phiên $sessionId đã kết thúc trên server từ trước; đã xóa trạng thái cũ'
            : 'HTTPS kết thúc phiên: $sessionId',
      );
      if (updateUi) {
        _setStatus(
          _SessionStatus.idle,
          alreadyEnded ? 'Phiên đã kết thúc trước đó' : 'Phiên đã kết thúc',
        );
      }
    } catch (error) {
      _log('Không kết thúc được phiên trên server: $error');
      if (updateUi) {
        _setStatus(
          _SessionStatus.error,
          'Đã đóng WSS nhưng HTTPS kết thúc phiên lỗi: $error',
        );
      }
    }
  }

  void _sendTestEvent(String type) {
    try {
      _client.sendEvent(type);
      _log('Đã gửi sự kiện thử $type qua WSS');
    } catch (error) {
      _log('Gửi $type thất bại: $error');
    }
  }

  void _sendPing() {
    try {
      _client.sendPing();
      _log('Đã gửi ping qua WSS');
    } catch (error) {
      _log('Gửi ping thất bại: $error');
    }
  }

  Color get _statusColor => switch (_status) {
    _SessionStatus.active => const Color(0xFF16805D),
    _SessionStatus.connecting ||
    _SessionStatus.stopping => const Color(0xFFB76E00),
    _SessionStatus.error => const Color(0xFFB42318),
    _SessionStatus.idle => const Color(0xFF667085),
  };

  String get _statusLabel => switch (_status) {
    _SessionStatus.active => 'ĐANG LIVE',
    _SessionStatus.connecting => 'ĐANG KẾT NỐI',
    _SessionStatus.stopping => 'ĐANG TẮT',
    _SessionStatus.error => 'LỖI',
    _SessionStatus.idle => 'CHƯA KẾT NỐI',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Server Demo'),
        centerTitle: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(Icons.wifi_tethering_rounded, color: Color(0xFF087E8B)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            Text(
              'Kiểm tra kết nối thật',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Mobile gọi HTTPS để quản lý phiên và giữ một kết nối WSS để trao đổi dữ liệu.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF667085),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _buildStatusCard(theme),
            const SizedBox(height: 16),
            _buildServerCard(theme),
            const SizedBox(height: 16),
            _buildSessionCard(theme),
            const SizedBox(height: 16),
            _buildEventLog(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.sensors_rounded, color: _statusColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _statusColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_statusMessage, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(ThemeData theme) {
    return _SectionCard(
      title: 'Server',
      icon: Icons.dns_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  enabled: !_isBusy && !_hasSession,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'IP / hostname',
                    hintText: '192.168.1.10',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _portController,
                  enabled: !_isBusy && !_hasSession,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '8443',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _showCertificate = !_showCertificate),
            child: Row(
              children: [
                Icon(
                  _showCertificate ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF667085),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Chứng chỉ TLS dev (PEM) — tùy chọn nếu dùng CA tin cậy',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF475467),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showCertificate) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _certificateController,
              enabled: !_isBusy && !_hasSession,
              minLines: 4,
              maxLines: 7,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '-----BEGIN CERTIFICATE-----\n...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dán nội dung dev-cert.pem. App vẫn xác minh TLS và hostname; không nhập private key.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF667085),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionCard(ThemeData theme) {
    return _SectionCard(
      title: 'Phiên kết nối',
      icon: Icons.sync_alt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sessionId != null) ...[
            Text(
              'Session ID',
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _sessionId!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: const Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hasSession)
            FilledButton.icon(
              onPressed: _isBusy ? null : _startSession,
              icon: _status == _SessionStatus.connecting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Bắt đầu'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFF087E8B),
                foregroundColor: Colors.white,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _status == _SessionStatus.stopping
                  ? null
                  : _stopSession,
              icon: _status == _SessionStatus.stopping
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: const Text('Tắt phiên'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: const Color(0xFFB42318),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            'Khi đã kết nối, gửi sự kiện thử để xác nhận dữ liệu đi qua WSS và server phản hồi.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isConnected
                    ? () => _sendTestEvent('video_frame')
                    : null,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Thử video event'),
              ),
              OutlinedButton.icon(
                onPressed: _isConnected
                    ? () => _sendTestEvent('audio_chunk')
                    : null,
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('Thử audio event'),
              ),
              OutlinedButton.icon(
                onPressed: _isConnected ? _sendPing : null,
                icon: const Icon(Icons.network_ping_rounded, size: 18),
                label: const Text('Ping'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventLog(ThemeData theme) {
    return _SectionCard(
      title: 'Log kết nối',
      icon: Icons.receipt_long_outlined,
      trailing: TextButton(
        onPressed: _events.isEmpty ? null : () => setState(_events.clear),
        child: const Text('Xóa'),
      ),
      child: _events.isEmpty
          ? Text(
              'Chưa có sự kiện. Nhấn Bắt đầu để kiểm tra server.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF667085),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _events
                  .map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        event,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: const Color(0xFF344054),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF087E8B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
