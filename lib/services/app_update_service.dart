import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Detects when a new version of the app has been deployed by polling
/// `flutter_service_worker.js`, which Flutter web regenerates on every build
/// with a new content hash. When the content changes, [hasUpdate] becomes true.
class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService instance = AppUpdateService._();
  AppUpdateService._();

  static const _pollInterval = Duration(minutes: 5);
  static const _workerUrl = '/flutter_service_worker.js';

  String? _initialHash;
  bool _hasUpdate = false;
  Timer? _timer;
  bool _dismissed = false;

  bool get hasUpdate => _hasUpdate && !_dismissed;

  /// Call once when the app starts (only active on web).
  void init() {
    if (!kIsWeb) return;
    _fetchHash().then((hash) {
      _initialHash = hash;
      _timer = Timer.periodic(_pollInterval, (_) => _check());
    });
  }

  Future<void> _check() async {
    if (_dismissed) return;
    final hash = await _fetchHash();
    if (hash != null && _initialHash != null && hash != _initialHash) {
      _hasUpdate = true;
      notifyListeners();
      _timer?.cancel(); // No need to keep polling once update is detected
    }
  }

  Future<String?> _fetchHash() async {
    try {
      // Cache-bust so we always get the latest from the server
      final uri = Uri.parse('$_workerUrl?_=${DateTime.now().millisecondsSinceEpoch}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.body;
    } catch (_) {}
    return null;
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
