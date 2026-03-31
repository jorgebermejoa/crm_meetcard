import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/proyecto_model.dart';

abstract class ProyectoRemoteDataSource {
  Future<ProyectoModel> getProyecto(String id);
  Future<List<ProyectoModel>> getProyectos();
  Future<void> updateProyecto(String id, Map<String, dynamic> data);
  
  Future<Map<String, dynamic>> getExternalApiData(String id, {String? idLicitacion, String? urlConvenioMarco, bool forceRefresh = false});
  Future<List<Map<String, dynamic>>> getForoData(String idLicitacion, {bool forceRefresh = false});
  Future<String> generateForoSummary(String idLicitacion, List<Map<String, dynamic>> enquiries);
  
  Future<List<Map<String, dynamic>>> getCompetidores(String idLicitacion);
  Future<List<Map<String, dynamic>>> getGanador(String idLicitacion);
  Future<Map<String, dynamic>> getAnalisisBq(String proyectoId);
}

class ProyectoRemoteDataSourceImpl implements ProyectoRemoteDataSource {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final http.Client _client = http.Client();
  
  static const _baseUrl = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

  Future<Map<String, String>> _getAuthHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken() ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  @override
  Future<ProyectoModel> getProyecto(String id) async {
    final doc = await _firestore.collection('proyectos').doc(id).get();
    if (!doc.exists) throw Exception('Proyecto no encontrado');
    final data = doc.data()!;
    data['id'] = doc.id;
    return ProyectoModel.fromJson(data);
  }

  @override
  Future<List<ProyectoModel>> getProyectos() async {
    final query = await _firestore.collection('proyectos').get();
    return query.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return ProyectoModel.fromJson(data);
    }).toList();
  }

  @override
  Future<void> updateProyecto(String id, Map<String, dynamic> data) async {
    await _firestore.collection('proyectos').doc(id).update(data);
  }

  @override
  Future<Map<String, dynamic>> getExternalApiData(String id, {String? idLicitacion, String? urlConvenioMarco, bool forceRefresh = false}) async {
    final bool isConvenioMarco = urlConvenioMarco != null && urlConvenioMarco.isNotEmpty;
    final String tipo = isConvenioMarco ? 'convenio_marco' : 'ocds';

    // 1. Try cache if not forcing
    if (!forceRefresh) {
      try {
        final headers = await _getAuthHeaders();
        final cResp = await _client.get(
          Uri.parse('$_baseUrl/obtenerCacheExterno?proyectoId=$id&tipo=$tipo'),
          headers: headers,
        );
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            final fetchedAtStr = c['fetchedAt']?.toString();
            final fetchedAt = fetchedAtStr != null ? DateTime.tryParse(fetchedAtStr) : null;
            final edad = fetchedAt != null ? DateTime.now().difference(fetchedAt) : const Duration(days: 999);
            // Cache valid for 24 hours
            if (edad.inHours < 24) return c['data'];
          }
        }
      } catch (_) {}
    }

    // 2. Query API
    String url;
    if (isConvenioMarco) {
      url = '$_baseUrl/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(urlConvenioMarco)}';
    } else if (idLicitacion != null && idLicitacion.isNotEmpty) {
      final useAward = idLicitacion.contains('CM') || idLicitacion.contains('TD') || idLicitacion.contains('SE');
      url = '$_baseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(idLicitacion)}${useAward ? '&type=award' : ''}';
    } else {
      throw Exception('Falta ID de licitación o URL de Convenio Marco para consultar la API');
    }

    final headers = await _getAuthHeaders();
    final resp = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      // Save to cache (await to ensure persistence)
      try {
        await _saveToCache(id, tipo, data);
      } catch (e) {
        debugPrint('Error persisting OCDS cache: $e');
      }
      return data;
    } else {
      throw Exception('Error al consultar API Mercado Público: ${resp.statusCode}');
    }
  }

  Future<void> _saveToCache(String id, String tipo, Map<String, dynamic> data) async {
    try {
      final headers = await _getAuthHeaders();
      final resp = await _client.post(
        Uri.parse('$_baseUrl/guardarCacheExterno'),
        headers: headers,
        body: json.encode({
          'proyectoId': id,
          'tipo': tipo,
          'data': data,
        }),
      );
      if (resp.statusCode != 200) {
        debugPrint('Cloud Function guardarCacheExterno returned ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      debugPrint('Exception in _saveToCache: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getForoData(String idLicitacion, {bool forceRefresh = false}) async {
    final doc = await _firestore.collection('licitaciones_foro').doc(idLicitacion).get();
    if (doc.exists && !forceRefresh) {
      return (doc.data()!['enquiries'] as List).cast<Map<String, dynamic>>();
    }
    
    // Trigger fetch
    final headers = await _getAuthHeaders();
    await _client.get(
      Uri.parse('$_baseUrl/fetchForoLicitacion?id=$idLicitacion'),
      headers: headers,
    );
    // Wait for Firestore update (ideal would be a recursive retry or listening to the stream)
    await Future.delayed(const Duration(seconds: 3));
    final docRetry = await _firestore.collection('licitaciones_foro').doc(idLicitacion).get();
    if (docRetry.exists) {
      return (docRetry.data()!['enquiries'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  @override
  Future<String> generateForoSummary(String idLicitacion, List<Map<String, dynamic>> enquiries) async {
    final headers = await _getAuthHeaders();
    final resp = await _client.post(
      Uri.parse('$_baseUrl/generarResumenForo'),
      headers: headers,
      body: json.encode({
        'idLicitacion': idLicitacion,
        'enquiries': enquiries,
      }),
    );
    if (resp.statusCode == 200) {
      return json.decode(resp.body)['resumen'] ?? '';
    }
    return '';
  }

  @override
  Future<List<Map<String, dynamic>>> getCompetidores(String idLicitacion) async {
    // Mirroring BigQueryService logic via cloud function/proxy
    return []; // Implementation detail
  }

  @override
  Future<List<Map<String, dynamic>>> getGanador(String idLicitacion) async {
    return []; // Implementation detail
  }
  @override
  Future<Map<String, dynamic>> getAnalisisBq(String proyectoId) async {
    final headers = await _getAuthHeaders();
    final resp = await _client.get(
      Uri.parse('$_baseUrl/getAnalisisBq?proyectoId=$proyectoId'),
      headers: headers,
    );
    if (resp.statusCode == 200) {
      return json.decode(resp.body);
    }
    return {};
  }
}
