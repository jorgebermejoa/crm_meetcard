import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/configuracion.dart';

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

class ConfigService {
  static final ConfigService instance = ConfigService._();
  ConfigService._();

  ConfiguracionData? _cached;
  Future<ConfiguracionData>? _inflight;

  Future<ConfiguracionData> load() {
    if (_cached != null) return Future.value(_cached!);
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<ConfiguracionData> _fetch() async {
    try {
      final res = await http.get(Uri.parse('$_cfBase/obtenerConfiguracion'));
      _cached = ConfiguracionData.fromJson(jsonDecode(res.body));
    } catch (_) {
      _cached = ConfiguracionData.defaults();
    }
    return _cached!;
  }

  /// Llama esto después de guardar configuración para forzar recarga.
  void invalidate() => _cached = null;
}
