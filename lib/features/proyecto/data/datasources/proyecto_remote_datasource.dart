import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/proyecto_model.dart';

abstract class ProyectoRemoteDataSource {
  Future<ProyectoModel> getProyecto(String id);
  /// Busca por contract ID (idLicitacion / idCotizacion / CM id).
  /// Retorna null si no se encuentra ningún documento con ese contract ID.
  Future<ProyectoModel?> getProyectoByContractId(String contractId);
  Future<List<ProyectoModel>> getProyectos();
  Future<void> updateProyecto(String id, Map<String, dynamic> data);

  Future<Map<String, dynamic>> getExternalApiData(String id, {String? idLicitacion, String? urlConvenioMarco, bool forceRefresh = false});
  Future<Map<String, dynamic>> getOrdenCompra(String id, {String? proyectoId, bool forceRefresh = false});
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
  Future<ProyectoModel?> getProyectoByContractId(String contractId) async {
    // Busca en los tres campos posibles que se usan como contract ID en la URL
    for (final field in ['idLicitacion', 'idCotizacion']) {
      final snap = await _firestore
          .collection('proyectos')
          .where(field, isEqualTo: contractId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        data['id'] = snap.docs.first.id;
        return ProyectoModel.fromJson(data);
      }
    }
    // Busca por CM id extraído de urlConvenioMarco
    final cmSnap = await _firestore
        .collection('proyectos')
        .where('urlConvenioMarco', isGreaterThanOrEqualTo: '')
        .get();
    for (final doc in cmSnap.docs) {
      final d = doc.data();
      final url = d['urlConvenioMarco']?.toString() ?? '';
      final match = RegExp(r'/id/([^/\?#]+)').firstMatch(url);
      if (match?.group(1) == contractId) {
        d['id'] = doc.id;
        return ProyectoModel.fromJson(d);
      }
    }
    return null;
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

    Map<String, dynamic>? staleCache;

    // 1. Try Firebase cache first
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
            if (edad.inHours < 24) {
              return c['data']; // Fresh cache → return immediately
            }
            staleCache = c['data'] as Map<String, dynamic>?; // Keep stale as fallback
          }
        }
      } catch (e) {
        debugPrint('Cache fetch (OCDS) failed, falling through to API: $e');
      }
    }

    // 2. Query API
    String url;
    if (isConvenioMarco) {
      url = '$_baseUrl/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(urlConvenioMarco)}';
    } else if (idLicitacion != null && idLicitacion.isNotEmpty) {
      final useAward = idLicitacion.contains('CM') || idLicitacion.contains('TD') || idLicitacion.contains('SE');
      url = '$_baseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(idLicitacion)}${useAward ? '&type=award' : ''}';
    } else {
      if (staleCache != null) return staleCache;
      throw Exception('Falta ID de licitación o URL de Convenio Marco para consultar la API');
    }

    try {
      final headers = await _getAuthHeaders();
      final resp = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        try {
          await _saveToCache(id, tipo, data);
        } catch (e) {
          debugPrint('Error persisting OCDS cache: $e');
        }
        return data;
      }
      // API returned non-200: use stale cache if available
      debugPrint('API OCDS returned ${resp.statusCode}, using stale cache: ${staleCache != null}');
      if (staleCache != null) return staleCache;
      throw Exception('Error al consultar API Mercado Público: ${resp.statusCode}');
    } catch (e) {
      if (staleCache != null) {
        debugPrint('API OCDS error ($e), returning stale cache');
        return staleCache;
      }
      rethrow;
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
  Future<Map<String, dynamic>> getOrdenCompra(String id, {String? proyectoId, bool forceRefresh = false}) async {
    final cacheKey = 'oc_$id';
    Map<String, dynamic>? staleCache;

    // 1. Try Firebase cache first
    if (!forceRefresh && proyectoId != null) {
      try {
        final headers = await _getAuthHeaders();
        final cResp = await _client.get(
          Uri.parse('$_baseUrl/obtenerCacheExterno?proyectoId=$proyectoId&tipo=$cacheKey'),
          headers: headers,
        );
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            final fetchedAtStr = c['fetchedAt']?.toString();
            final fetchedAt = fetchedAtStr != null ? DateTime.tryParse(fetchedAtStr) : null;
            final edad = fetchedAt != null ? DateTime.now().difference(fetchedAt) : const Duration(days: 999);
            if (edad.inHours < 24) {
              return c['data']; // Fresh cache → return immediately
            }
            staleCache = c['data'] as Map<String, dynamic>?; // Keep stale as fallback
          }
        }
      } catch (e) {
        debugPrint('Cache fetch (OC $id) failed, falling through to API: $e');
      }
    }

    // 2. Query API: buscarOrdenCompra
    try {
      final headers = await _getAuthHeaders();
      final url = '$_baseUrl/buscarOrdenCompra?id=${Uri.encodeComponent(id)}';
      final resp = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (proyectoId != null) {
          try {
            await _saveToCache(proyectoId, cacheKey, data);
          } catch (e) {
            debugPrint('Error persisting OC cache: $e');
          }
        }
        return data;
      }
      // API returned non-200: use stale cache if available
      debugPrint('API OC $id returned ${resp.statusCode}, using stale cache: ${staleCache != null}');
      if (staleCache != null) return staleCache;
      throw Exception('Error al consultar Orden de Compra: ${resp.statusCode}');
    } catch (e) {
      debugPrint('Error fetching orden de compra $id: $e');
      if (staleCache != null) {
        debugPrint('API OC error ($e), returning stale cache');
        return staleCache;
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getForoData(String idLicitacion, {bool forceRefresh = false}) async {
    final doc = await _firestore.collection('licitaciones_foro').doc(idLicitacion).get();
    if (doc.exists && !forceRefresh) {
      final cached = (doc.data()!['enquiries'] as List).cast<Map<String, dynamic>>();
      // Validar que el caché usa el formato normalizado (description/answer).
      // Si tiene el formato antiguo de MP (Pregunta/Respuesta), forzar refetch.
      final isNormalized = cached.isEmpty || cached.first.containsKey('description');
      if (isNormalized) return cached;
    }
    
    // Trigger fetch — CF guarda en Firestore Y devuelve las enquiries directamente
    final headers = await _getAuthHeaders();
    final cfResp = await _client.get(
      Uri.parse('$_baseUrl/fetchForoLicitacion?id=$idLicitacion'),
      headers: headers,
    ).timeout(const Duration(seconds: 30));
    if (cfResp.statusCode == 200) {
      final body = json.decode(cfResp.body);
      final enquiries = (body['enquiries'] as List?)?.cast<Map<String, dynamic>>();
      if (enquiries != null && enquiries.isNotEmpty) return enquiries;
    }
    // Fallback: leer desde Firestore (por si la CF ya había guardado antes)
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
    ).timeout(const Duration(seconds: 60));
    if (resp.statusCode == 200) {
      return json.decode(resp.body)['resumen'] ?? '';
    }
    throw Exception('generarResumenForo falló: ${resp.statusCode}');
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
    final cacheDoc = _firestore.collection('cache_bq').doc('analisis_$proyectoId');
    Map<String, dynamic>? staleCache;

    // 1. Try Firebase cache first
    try {
      final snap = await cacheDoc.get();
      if (snap.exists) {
        final d = snap.data()!;
        final fetchedAt = (d['fetchedAt'] as Timestamp?)?.toDate();
        final age = fetchedAt != null ? DateTime.now().difference(fetchedAt) : null;
        if (age != null && age.inHours < 24) {
          return Map<String, dynamic>.from(d['data'] as Map); // Fresh → return
        }
        staleCache = Map<String, dynamic>.from(d['data'] as Map); // Stale → keep as fallback
      }
    } catch (e) {
      debugPrint('Cache read (analisisBq) failed: $e');
    }

    // 2. Call Cloud Function
    try {
      final headers = await _getAuthHeaders();
      final resp = await _client.get(
        Uri.parse('$_baseUrl/getAnalisisBq?proyectoId=$proyectoId'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        // Save to Firebase cache
        try {
          await cacheDoc.set({'data': data, 'fetchedAt': FieldValue.serverTimestamp()});
        } catch (e) {
          debugPrint('Error persisting analisisBq cache: $e');
        }
        return data;
      }
      // API returned non-200: use stale cache if available
      debugPrint('getAnalisisBq returned ${resp.statusCode}, using stale cache: ${staleCache != null}');
      if (staleCache != null) return staleCache;
      throw Exception('getAnalisisBq falló: ${resp.statusCode}');
    } catch (e) {
      if (staleCache != null) {
        debugPrint('getAnalisisBq error ($e), returning stale cache');
        return staleCache;
      }
      rethrow;
    }
  }
}
