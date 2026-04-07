import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/proyecto.dart';

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

class ProyectosService {
  static final ProyectosService instance = ProyectosService._();
  ProyectosService._();

  static const _ttl = Duration(minutes: 5);

  List<Proyecto>? _cached;
  DateTime? _loadedAt;
  // Evita llamadas HTTP duplicadas si dos widgets cargan simultáneamente
  Future<List<Proyecto>>? _inflight;

  /// Retorna caché si no ha expirado (TTL 5 min), si no hace fetch.
  /// Con [forceRefresh] invalida caché y obtiene datos frescos.
  Future<List<Proyecto>> load({bool forceRefresh = false}) {
    if (forceRefresh) invalidate();
    final now = DateTime.now();
    final cacheValid =
        _cached != null && _loadedAt != null && now.difference(_loadedAt!) < _ttl;
    if (cacheValid) return Future.value(_cached!);
    // Agregamos un catchError para imprimir el error en la consola de Flutter/Dart.
    // Esto nos ayuda a ver si el error es capturado por Dart o si es un problema a nivel de navegador (como CORS)
    // que no llega a ser un error de Dart.
    return _inflight ??= _fetch().catchError((e, s) {
      debugPrint('Error capturado en ProyectosService: $e');
      throw e; // Re-lanzamos el error para que el FutureBuilder lo maneje.
    }).whenComplete(() => _inflight = null);
  }

  Future<List<Proyecto>> _fetch() async {
    final res = await http.get(
      Uri.parse('$_cfBase/obtenerProyectos'),
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode} al cargar proyectos');
    }
    debugPrint('ProyectosService: JSON recibido: ${res.body.substring(0, 500)}...'); // Muestra los primeros 500 caracteres
    final data = jsonDecode(res.body) as List<dynamic>;
    final List<Proyecto> proyectos = [];
    for (final item in data) {
      try {
        proyectos.add(Proyecto.fromJson(item as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Error al parsear un proyecto: $e. Datos del proyecto: $item');
        // Opcional: se omite el proyecto con error para no bloquear la app.
      }
    }
    _cached = proyectos;
    _loadedAt = DateTime.now();
    return _cached!;
  }

  /// Llama esto después de crear, editar o eliminar un proyecto.
  void invalidate() {
    _cached = null;
    _loadedAt = null;
    _inflight = null;
  }
}
