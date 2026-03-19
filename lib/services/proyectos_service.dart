import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/proyecto.dart';

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

class ProyectosService {
  static final ProyectosService instance = ProyectosService._();
  ProyectosService._();

  List<Proyecto>? _cached;
  // Evita llamadas HTTP duplicadas si dos widgets cargan simultáneamente
  Future<List<Proyecto>>? _inflight;

  /// Retorna caché si existe, si no hace fetch.
  /// Con [forceRefresh] invalida caché y obtiene datos frescos.
  Future<List<Proyecto>> load({bool forceRefresh = false}) {
    if (forceRefresh) invalidate();
    if (_cached != null) return Future.value(_cached!);
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<List<Proyecto>> _fetch() async {
    final res = await http.get(
      Uri.parse('$_cfBase/obtenerProyectos'),
    );
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode} al cargar proyectos');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    _cached = data
        .map((e) => Proyecto.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cached!;
  }

  /// Llama esto después de crear, editar o eliminar un proyecto.
  void invalidate() {
    _cached = null;
    _inflight = null;
  }
}
