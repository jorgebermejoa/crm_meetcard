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
    );

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
    );

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
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
    );

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
