import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

class ResumenService {
  static final ResumenService instance = ResumenService._();
  ResumenService._();

  static const _ttl = Duration(minutes: 5);

  Map<String, dynamic>? _cached;
  DateTime? _loadedAt;
  Future<Map<String, dynamic>>? _inflight;

  /// Retorna caché si no ha expirado (TTL 5 min), si no hace fetch.
  /// Con [forceRefresh] invalida caché y obtiene datos frescos.
  Future<Map<String, dynamic>> load({bool forceRefresh = false}) {
    if (forceRefresh) invalidate();
    final now = DateTime.now();
    final cacheValid = _cached != null &&
        _loadedAt != null &&
        now.difference(_loadedAt!) < _ttl;
    if (cacheValid) return Future.value(_cached!);
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<Map<String, dynamic>> _fetch() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken() ?? '';
    final res = await http.get(
      Uri.parse('$_cfBase/obtenerResumen'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode} al cargar resumen');
    }
    _cached = jsonDecode(res.body) as Map<String, dynamic>;
    _loadedAt = DateTime.now();
    return _cached!;
  }

  /// Llama esto después de calcular estadísticas.
  void invalidate() {
    _cached = null;
    _loadedAt = null;
    _inflight = null;
  }
}
