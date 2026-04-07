import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../models/configuracion.dart';
import '../../../../models/proyecto.dart';
import '../../../../services/bigquery_service.dart';
import '../../../../services/config_service.dart';
import '../../../../services/proyectos_service.dart';
import '../proyectos_constants.dart';

class ProyectosRemoteDatasource {
  final ProyectosService _proyectosService;
  final ConfigService _configService;
  final BigQueryService _bigQueryService;
  final FirebaseFirestore _firestore;

  ProyectosRemoteDatasource({
    ProyectosService? proyectosService,
    ConfigService? configService,
    BigQueryService? bigQueryService,
    FirebaseFirestore? firestore,
  })  : _proyectosService = proyectosService ?? ProyectosService.instance,
        _configService = configService ?? ConfigService.instance,
        _bigQueryService = bigQueryService ?? BigQueryService.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<Proyecto>> loadProyectos({bool forceRefresh = false}) async {
    return _proyectosService.load(forceRefresh: forceRefresh);
  }

  Future<ConfiguracionData> loadConfig() async {
    return _configService.load();
  }

  Future<List<Map<String, dynamic>>> loadRadarOportunidades({bool forceRefresh = false}) async {
    // Fast path: leer desde Firestore caché directamente (evita llamar a la CF)
    if (!forceRefresh) {
      final snap = await _firestore
          .collection('cache_bq')
          .doc('radar_oportunidades')
          .get();
      if (snap.exists) {
        final d = snap.data()!;
        final fetchedAt = (d['fetchedAt'] as Timestamp?)?.toDate();
        final age = fetchedAt != null
            ? DateTime.now().difference(fetchedAt)
            : null;
        if (age != null && age.inHours < 24) {
          return (d['rows'] as List? ?? []).cast<Map<String, dynamic>>();
        }
      }
    }
    // Caché inexistente o stale: llamar CF (que también actualiza Firestore)
    return _bigQueryService.obtenerRadarOportunidades();
  }

  Future<void> sincronizarPostulacionDesdeOcds(List<Proyecto> proyectos) async {
    final pendientes = proyectos
        .where(
          (p) =>
              p.idLicitacion != null &&
              p.idLicitacion!.isNotEmpty &&
              (p.fechaPublicacion == null ||
               p.fechaConsultasInicio == null ||
               p.fechaAdjudicacion == null),
        )
        .toList();

    if (pendientes.isEmpty) return;

    final token = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
    final authHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    for (final p in pendientes) {
      int attempt = 0;
      const maxAttempts = 3;
      while (attempt < maxAttempts) {
        try {
          final resp = await http
              .get(
                Uri.parse(
                  '$kCloudFunctionsBaseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(p.idLicitacion!)}',
                ),
                headers: authHeaders,
              )
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode != 200) break;

          final data = json.decode(resp.body) as Map<String, dynamic>;
          final releases =
              (data['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          if (releases.isEmpty) break;
          final tender = releases.last['tender'] as Map<String, dynamic>? ?? {};

          final tp = tender['tenderPeriod'] as Map<String, dynamic>?;
          final eq = tender['enquiryPeriod'] as Map<String, dynamic>?;
          final ap = tender['awardPeriod'] as Map<String, dynamic>?;

          final updates = <String, dynamic>{'id': p.id};
          if (p.fechaPublicacion == null && tp?['startDate'] != null) {
            updates['fechaPublicacion'] = tp!['startDate'];
          }
          if (p.fechaCierre == null && tp?['endDate'] != null) {
            updates['fechaCierre'] = tp!['endDate'];
          }
          if (p.fechaConsultasInicio == null && eq?['startDate'] != null) {
            updates['fechaConsultasInicio'] = eq!['startDate'];
          }
          if (p.fechaConsultas == null && eq?['endDate'] != null) {
            updates['fechaConsultas'] = eq!['endDate'];
          }
          if (p.fechaAdjudicacion == null && ap?['startDate'] != null) {
            updates['fechaAdjudicacion'] = ap!['startDate'];
          }
          if (p.fechaAdjudicacionFin == null && ap?['endDate'] != null) {
            updates['fechaAdjudicacionFin'] = ap!['endDate'];
          }

          if (updates.length <= 1) break;

          updates['origenFechas'] = 'ocds';
          await http.post(
            Uri.parse('$kCloudFunctionsBaseUrl/actualizarProyecto'),
            headers: authHeaders,
            body: json.encode(updates),
          );
          break; // éxito — salir del loop de reintentos
        } catch (e) {
          attempt++;
          if (attempt >= maxAttempts) {
            debugPrint('OCDS sync failed for ${p.idLicitacion} after $maxAttempts attempts: $e');
          } else {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }
    }
  }

  Future<void> updateProyectoEstadoManual(String projectId, String? estadoManual) async {
    await _firestore
        .collection('proyectos')
        .doc(projectId)
        .update({'estadoManual': estadoManual});
  }
}