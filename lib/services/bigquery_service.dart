import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

class BigQueryService {
  static final BigQueryService instance = BigQueryService._();
  BigQueryService._();

  /// Ejecuta una consulta SQL en BigQuery a través del Cloud Function proxy.
  /// [sql] puede contener parámetros posicionales (@param o ?) según BigQuery.
  /// [params] lista de valores para los parámetros (opcional).
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();

    final resp = await http.post(
      Uri.parse('$_cfBase/queryBigQuery'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'query': sql, 'params': params}),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      final body = resp.body;
      throw Exception('BigQuery error ${resp.statusCode}: $body');
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// Cruza meses_publicado_ordendecompra (BigQuery) con proyectos (Firestore).
  /// Devuelve { totalBQ, totalEnApp, totalFueraDeApp, totalConOCFaltante,
  ///            enApp, fueraDeApp, ocFaltante }
  Future<Map<String, dynamic>> analizarMesesPublicadoOC() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();

    final resp = await http.get(
      Uri.parse('$_cfBase/analizarMesesPublicadoOC'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> obtenerCompetidoresLicitacion(String idLicitacion) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    final resp = await http.get(
      Uri.parse('$_cfBase/obtenerCompetidoresLicitacion?idLicitacion=${Uri.encodeComponent(idLicitacion)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> obtenerGanadorLicitacion(String idLicitacion) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    final resp = await http.get(
      Uri.parse('$_cfBase/obtenerGanadorLicitacion?idLicitacion=${Uri.encodeComponent(idLicitacion)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> obtenerHistorialGanador(String rutProveedor, {String? rutOrganismo}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    var url = '$_cfBase/obtenerHistorialGanador?rutProveedor=${Uri.encodeComponent(rutProveedor)}';
    if (rutOrganismo != null) url += '&rutOrganismo=${Uri.encodeComponent(rutOrganismo)}';
    final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> obtenerPrediccionOrganismo(String rutOrganismo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    final resp = await http.get(
      Uri.parse('$_cfBase/obtenerPrediccionOrganismo?rutOrganismo=${Uri.encodeComponent(rutOrganismo)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> obtenerFichaOrganismo(String rutOrganismo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    final resp = await http.get(
      Uri.parse('$_cfBase/obtenerFichaOrganismo?rutOrganismo=${Uri.encodeComponent(rutOrganismo)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> obtenerFichaProveedor(String rutProveedor) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    final resp = await http.get(
      Uri.parse('$_cfBase/obtenerFichaProveedor?rutProveedor=${Uri.encodeComponent(rutProveedor)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Retorna todas las filas de "Radar de Oportunidades" (caché 24h en Firestore).
  Future<List<Map<String, dynamic>>> obtenerRadarOportunidades() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();

    final resp = await http.get(
      Uri.parse('$_cfBase/obtenerRadarOportunidades'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['rows'] as List).cast<Map<String, dynamic>>();
  }

  /// Cruza clientes_nuevos_meetcard (BigQuery) con proyectos (Firestore).
  /// Devuelve { totalMeetcard, totalPresentes, totalAusentes, presentes, ausentes }
  Future<Map<String, dynamic>> analizarClientesMeetcard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();

    final resp = await http.get(
      Uri.parse('$_cfBase/analizarClientesMeetcard'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
