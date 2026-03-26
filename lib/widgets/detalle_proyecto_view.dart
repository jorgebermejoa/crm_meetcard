import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../app_shell.dart';
import '../models/configuracion.dart';
import '../models/proyecto.dart';
import '../services/bigquery_service.dart';
import '../services/config_service.dart';
import '../services/proyectos_service.dart';
import '../services/upload_service.dart';
import 'app_breadcrumbs.dart';
import 'campo_editable.dart';

class DetalleProyectoView extends StatefulWidget {
  final Proyecto proyecto;
  final VoidCallback? onBack;
  final VoidCallback? onOpenMenu;
  final String? initialTabName;

  const DetalleProyectoView({
    super.key,
    required this.proyecto,
    this.onBack,
    this.onOpenMenu,
    this.initialTabName,
  });

  @override
  State<DetalleProyectoView> createState() => _DetalleProyectoViewState();
}

class _DetalleProyectoViewState extends State<DetalleProyectoView>
    with TickerProviderStateMixin {
  static const _baseUrl =
      'https://us-central1-licitaciones-prod.cloudfunctions.net';
  static const _primaryColor = Color(0xFF5B21B6);
  static const _bgColor = Color(0xFFF2F2F7);

  late Proyecto _proyecto;
  late TabController _tabController;

  // ─── Cadena contractual ───────────────────────────────────────────────────
  List<Proyecto>? _cadena;              // lista ordenada de la cadena completa
  List<Proyecto>? _sugerencias;         // candidatos a encadenar

  Map<String, dynamic>? _ocdsData;
  Map<String, dynamic>? _mpApiData;
  bool _cargandoOcds = false;
  String? _errorOcds;
  String? _ocdsLastFetch;

  Map<String, dynamic>? _convenioData;
  bool _cargandoConvenio = false;
  String? _errorConvenio;
  String? _convenioLastFetch;

  List<Map<String, dynamic>?> _ocDataList = [];
  bool _cargandoOc = false;
  String? _errorOc;
  final Map<String, String?> _ocLastFetchMap = {};

  List<Map<String, dynamic>> _historial = [];

  // ─── Foro ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _foroEnquiries = [];
  bool _cargandoForo = false;
  bool _foroCargado = false;
  DateTime? _foroFechaCache;
  final TextEditingController _foroSearch = TextEditingController();
  String _foroQuery = '';
  String? _foroResumen;
  bool _cargandoResumen = false;

  // ─── Análisis BQ ──────────────────────────────────────────────────────────
  bool _analisisCargando = false;
  String? _analisisError;
  List<Map<String, dynamic>> _competidores = [];
  List<Map<String, dynamic>> _ganadorOcs = [];
  List<Map<String, dynamic>> _historialGanador = [];
  List<Map<String, dynamic>> _permanenciaGanador = [];
  List<Map<String, dynamic>> _predicciones = [];
  String? _rutGanador;
  String? _nombreGanador;
  String? _rutOrganismo;

  List<String> _modalidades = ['Licitación Pública', 'Convenio Marco', 'Trato Directo', 'Otro'];
  List<String> _productosOpciones = [];
  List<String> _tiposDocumento = ['Contrato', 'Orden de Compra', 'Acta de Evaluación', 'Otro'];
  List<EstadoItem> _estados = [
    EstadoItem(nombre: 'Vigente', color: '10B981'),
    EstadoItem(nombre: 'X Vencer', color: 'F59E0B'),
    EstadoItem(nombre: 'Finalizado', color: '64748B'),
    EstadoItem(nombre: 'Sin fecha', color: 'EF4444'),
  ];

  // ─── TAB HELPERS ──────────────────────────────────────────────────────────

  List<Tab> get _tabs {
    return [
      const Tab(text: 'Proyecto'),
      if (_proyecto.idLicitacion?.isNotEmpty == true ||
          _proyecto.modalidadCompra == 'Licitación Pública')
        const Tab(text: 'Detalle'),
      if (_proyecto.urlConvenioMarco?.isNotEmpty == true)
        const Tab(text: 'Detalle'),
      if (_proyecto.idsOrdenesCompra.isNotEmpty)
        const Tab(text: 'Orden de Compra'),
      if (_proyecto.idLicitacion?.isNotEmpty == true)
        const Tab(text: 'Análisis'),
      if (_proyecto.idLicitacion?.isNotEmpty == true)
        const Tab(text: 'Foro'),
      const Tab(text: 'Certificados'),
      const Tab(text: 'Reclamos'),
    ];
  }

  int get _tabCount => _tabs.length;

  void _rebuildTabController() {
    final prevIndex = _tabController.index;
    _tabController.dispose();
    _tabController = TabController(length: _tabCount, vsync: this);
    final safeIndex = prevIndex.clamp(0, _tabCount - 1);
    if (safeIndex > 0) _tabController.index = safeIndex;
    setState(() {});
  }

  int _indexOfTabNamed(String name) {
    final lower = name.toLowerCase();
    final tabs = _tabs;
    for (int i = 0; i < tabs.length; i++) {
      final tabText = (tabs[i].text ?? '').toLowerCase();
      if (tabText == lower || tabText.startsWith(lower)) return i;
    }
    return -1;
  }

  @override
  void initState() {
    super.initState();
    _proyecto = widget.proyecto;
    _tabController = TabController(length: _tabCount, vsync: this);
    if (widget.initialTabName != null) {
      final idx = _indexOfTabNamed(widget.initialTabName!);
      if (idx >= 0) _tabController.index = idx;
    }
    if (_proyecto.idLicitacion?.isNotEmpty == true) _cargarOcds();
    if (_proyecto.urlConvenioMarco?.isNotEmpty == true) _cargarConvenio();
    if (_proyecto.idsOrdenesCompra.isNotEmpty) _cargarOc();
    if (_proyecto.idLicitacion?.isNotEmpty == true) _cargarForo();
    _cargarCadena();
    _foroSearch.addListener(() => setState(() => _foroQuery = _foroSearch.text.toLowerCase()));
    ConfigService.instance.load().then((cfg) {
      if (!mounted) return;
      setState(() {
        if (cfg.modalidades.isNotEmpty) _modalidades = cfg.modalidades;
        if (cfg.estados.isNotEmpty) _estados = cfg.estados;
        if (cfg.productos.isNotEmpty) {
          _productosOpciones = cfg.productos.map((p) => p.abreviatura).toList();
        }
        if (cfg.tiposDocumento.isNotEmpty) _tiposDocumento = cfg.tiposDocumento;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _foroSearch.dispose();
    super.dispose();
  }

  // ─── DATA ─────────────────────────────────────────────────────────────────

  Future<void> _cargarOcds({bool forceRefresh = false}) async {
    setState(() { _cargandoOcds = true; _errorOcds = null; });
    final idLic = _proyecto.idLicitacion!;
    // 1. Try cache (máx 3 días)
    if (!forceRefresh) {
      try {
        final cResp = await http.get(Uri.parse(
            '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=ocds'))
            .timeout(const Duration(seconds: 10));
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            final fetchedAt = c['fetchedAt'] != null
                ? DateTime.tryParse(c['fetchedAt'].toString())
                : null;
            final edad = fetchedAt != null
                ? DateTime.now().difference(fetchedAt)
                : const Duration(days: 999);
            if (edad.inHours < 24) {
              if (mounted) {
                setState(() {
                  _ocdsData = c['data'];
                  _ocdsLastFetch = c['fetchedAt']?.toString();
                  _cargandoOcds = false;
                });
                _sincronizarFechasDesdeOcds();
              }
              // Si releases vacío en caché, intentar mp_api como complemento
              final releases = (c['data']['releases'] as List?) ?? [];
              if (releases.isEmpty) await _tryLoadMpApiCache();
              return;
            }
          }
        }
      } catch (_) {}
    }
    // 2. Query API
    try {
      final useAward = _proyecto.modalidadCompra == 'Convenio Marco' ||
          _proyecto.modalidadCompra == 'Trato Directo';
      final resp = await http
          .get(Uri.parse('$_baseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(idLic)}${useAward ? '&type=award' : ''}'))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (mounted) {
          setState(() { _ocdsData = data; _ocdsLastFetch = null; _cargandoOcds = false; });
          _sincronizarFechasDesdeOcds();
        }
        // 3. Save to cache (fire and forget)
        http.post(Uri.parse('$_baseUrl/guardarCacheExterno'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'proyectoId': _proyecto.id, 'tipo': 'ocds', 'data': data}));
        // Re-load fetchedAt after save
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            final cResp = await http.get(Uri.parse(
                '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=ocds'))
                .timeout(const Duration(seconds: 5));
            if (cResp.statusCode == 200) {
              final c = json.decode(cResp.body);
              if (c != null && mounted) setState(() => _ocdsLastFetch = c['fetchedAt']?.toString());
            }
          } catch (_) {}
        });
        // Si releases vacío, intentar mp_api como complemento
        final releases = (data['releases'] as List?) ?? [];
        if (releases.isEmpty) await _tryLoadMpApiCache();
      } else {
        // OCDS no disponible → intentar caché mp_api
        await _tryLoadMpApiCache();
        if (_mpApiData == null && mounted) {
          setState(() { _errorOcds = 'Error ${resp.statusCode}'; _cargandoOcds = false; });
        }
      }
    } catch (e) {
      await _tryLoadMpApiCache();
      if (_mpApiData == null && mounted) {
        setState(() { _errorOcds = e.toString(); _cargandoOcds = false; });
      }
    }
  }

  /// Intenta cargar el caché mp_api cuando OCDS no está disponible.
  Future<void> _tryLoadMpApiCache() async {
    try {
      final resp = await http
          .get(Uri.parse(
              '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=mp_api'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final c = json.decode(resp.body);
        if (c != null && c['data'] != null && mounted) {
          setState(() {
            _mpApiData = c['data'] as Map<String, dynamic>;
            _cargandoOcds = false;
          });
        }
      }
    } catch (_) {}
  }

  // ─── Foro (Firestore caché + OCDS API) ───────────────────────────────────

  /// Determina si la licitación ya está adjudicada/cerrada (no necesita refresco frecuente).
  bool get _licitacionCerrada {
    final tender = _ocdsData?['tender'];
    if (tender is Map) {
      final status = tender['status']?.toString().toLowerCase() ?? '';
      if (status == 'complete' || status == 'cancelled' || status == 'unsuccessful') return true;
      final details = (tender['statusDetails'] ?? '').toString().toLowerCase();
      if (details.contains('adjudicada') || details.contains('desierta') || details.contains('revocada')) return true;
    }
    return _proyecto.estado == EstadoProyecto.finalizado;
  }

  Future<void> _cargarForo({bool forceRefresh = false}) async {
    final id = _proyecto.idLicitacion?.trim() ?? '';
    if (id.isEmpty) return;
    setState(() => _cargandoForo = true);
    try {
      final db = FirebaseFirestore.instance;
      // Guardamos en proyectos/{proyectoId}/foro/{licitacionId}
      // (el usuario tiene permisos de escritura sobre sus propios proyectos)
      final cacheRef = db
          .collection('proyectos')
          .doc(_proyecto.id)
          .collection('foro')
          .doc(id);

      // 1. Leer caché de Firestore
      if (!forceRefresh) {
        final snap = await cacheRef.get();
        if (snap.exists) {
          final cached = snap.data()?['enquiries'];
          final ts = snap.data()?['fetchedAt'];
          final fechaCache = ts is Timestamp ? ts.toDate() : null;
          final antiguedad = fechaCache != null ? DateTime.now().difference(fechaCache) : null;
          // Usar caché si: cerrada (cualquier antigüedad) o < 7 días
          final cacheValido = fechaCache != null &&
              (antiguedad! < const Duration(days: 7) || _licitacionCerrada);
          if (cacheValido && cached is List && cached.isNotEmpty) {
            if (mounted) {
              setState(() {
                _foroEnquiries = cached.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
                _foroFechaCache = fechaCache;
                _foroCargado = true;
              });
            }
            return;
          }
        }
      }

      // 2. Fetch via CF proxy (avoids CORS on web)
      final uri = Uri.parse('$_baseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(id)}&type=tender');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final releases = (data['releases'] as List?) ?? [];
      final seen = <String>{};
      final all = <Map<String, dynamic>>[];
      for (final release in releases) {
        if (release is! Map) continue;
        final tender = release['tender'];
        if (tender is! Map) continue;
        final eqs = tender['enquiries'];
        if (eqs is! List) continue;
        for (final e in eqs) {
          if (e is! Map) continue;
          final eid = e['id']?.toString() ?? '';
          if (seen.add(eid)) all.add(Map<String, dynamic>.from(e));
        }
      }

      // 3. Actualizar UI primero (independiente de si el write a Firestore falla)
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _foroEnquiries = all;
          _foroFechaCache = now;
          _foroCargado = true;
        });
      }

      // 4. Persistir caché en Firestore (best-effort)
      try {
        await cacheRef.set({
          'enquiries': all,
          'fetchedAt': FieldValue.serverTimestamp(),
          'licitacionId': id,
        });
      } catch (_) { /* permisos o red: ignorar, ya se muestra en UI */ }

    } catch (e) {
      if (mounted) setState(() => _foroCargado = true);
    } finally {
      if (mounted) setState(() => _cargandoForo = false);
    }
  }

  Future<void> _generarResumenForo() async {
    final id = _proyecto.idLicitacion?.trim() ?? '';
    if (id.isEmpty || _foroEnquiries.isEmpty) return;
    setState(() => _cargandoResumen = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final uri = Uri.parse('$_baseUrl/resumirForo'
          '?proyectoId=${Uri.encodeComponent(_proyecto.id)}'
          '&licitacionId=${Uri.encodeComponent(id)}');
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (mounted) setState(() => _foroResumen = data['resumen']?.toString());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoResumen = false);
    }
  }

  void _mostrarResumenForo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForoResumenSheet(
        nombreProyecto: _proyecto.productos,
        resumenInicial: _foroResumen,
        onGenerar: () async {
          setState(() => _foroResumen = null);
          await _generarResumenForo();
          return _foroResumen;
        },
      ),
    );
  }

  List<Proyecto>? _sucesores; // sucesores directos del proyecto actual

  Future<void> _cargarCadena() async {
    try {
      final todos = await ProyectosService.instance.load();
      final cadena = _resolverCadena(todos, _proyecto.id);
      final sucesores = _sucesoresDirectos(todos);
      final sugerencias = _calcularSugerencias(todos, cadena);
      if (!mounted) return;
      setState(() {
        if (cadena.length > 1 || sucesores.isNotEmpty) _cadena = cadena;
        _sucesores = sucesores;
        if (sugerencias.isNotEmpty) _sugerencias = sugerencias;
      });
    } catch (_) {}
  }

  /// Normaliza nombre de institución: elimina la unidad de compra (parte después de "|").
  String _normInst(String raw) => raw.split('|').first.trim().toUpperCase();

  /// Extrae el código numérico de organismo desde idLicitacion ("2348-23-LP21" → "2348"),
  /// OCDS identifier ("CL-MP-2348" → "2348"), o desde OC.CodigoLicitacion (para CM).
  String? _codigoOrganismo() {
    // 1. Desde idLicitacion directo
    final fromLicit = _proyecto.idLicitacion?.split('-').first.trim();
    if (fromLicit != null && fromLicit.isNotEmpty && int.tryParse(fromLicit) != null) {
      return fromLicit;
    }
    // 2. Desde OC.CodigoLicitacion — clave para Convenio Marco que hereda licitación original
    for (final oc in _ocDataList) {
      if (oc == null) continue;
      final codLicit = oc['CodigoLicitacion']?.toString().trim() ?? '';
      final code = codLicit.split('-').first.trim();
      if (code.isNotEmpty && int.tryParse(code) != null) return code;
    }
    // 3. Desde OCDS buyer identifier
    if (_ocdsData != null) {
      final releases = (_ocdsData!['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (releases.isNotEmpty) {
        final parties = (releases.last['parties'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final buyer = parties.firstWhere(
          (p) => (p['roles'] as List?)?.contains('buyer') == true,
          orElse: () => <String, dynamic>{},
        );
        final rawId = (buyer['identifier'] as Map?)?['id']?.toString() ?? '';
        final parts = rawId.split('-');
        if (parts.length >= 3) return parts.last;
      }
    }
    return null;
  }

  /// Encuentra proyectos del mismo organismo no incluidos en la cadena actual.
  /// Detecta cross-modal: un CM y una LP del mismo organismo se reconocen
  /// por código de organismo (vía CodigoLicitacion en OC), RUT, o nombre normalizado.
  List<Proyecto> _calcularSugerencias(List<Proyecto> todos, List<Proyecto> cadenaActual) {
    final idCadena = cadenaActual.map((p) => p.id).toSet();
    final codigoOrg = _codigoOrganismo();
    final instNorm = _normInst(_proyecto.institucion).toLowerCase();
    // Excluir los ya encadenados desde este proyecto
    final yaEncadenados = _proyecto.proyectoContinuacionIds.toSet();

    return todos.where((p) {
      if (idCadena.contains(p.id)) return false;
      if (yaEncadenados.contains(p.id)) return false;
      if (p.id == _proyecto.id) return false;
      // Match por código de organismo
      if (codigoOrg != null) {
        final pCode = p.idLicitacion?.split('-').first.trim();
        if (pCode == codigoOrg) return true;
      }
      final pNorm = _normInst(p.institucion).toLowerCase();
      return pNorm == instNorm;
    }).toList()
      ..sort((a, b) {
        final aLibre = a.proyectoContinuacionIds.isEmpty ? 0 : 1;
        final bLibre = b.proyectoContinuacionIds.isEmpty ? 0 : 1;
        if (aLibre != bLibre) return aLibre.compareTo(bLibre);
        final aFecha = a.fechaInicio ?? a.fechaCreacion ?? DateTime(2000);
        final bFecha = b.fechaInicio ?? b.fechaCreacion ?? DateTime(2000);
        return bFecha.compareTo(aFecha);
      });
  }

  /// Resuelve la cadena de ancestros hasta el proyecto actual (más antiguo primero),
  /// sin incluir los sucesores (estos se muestran por separado en el timeline).
  List<Proyecto> _resolverCadena(List<Proyecto> todos, String idActual) {
    final porId = {for (final p in todos) p.id: p};
    // Buscar raíz: remontando por predecesores
    String? raizId = idActual;
    final visitados = <String>{};
    while (true) {
      if (visitados.contains(raizId)) break;
      visitados.add(raizId!);
      final predecesor = todos.where((p) => p.proyectoContinuacionIds.contains(raizId)).firstOrNull;
      if (predecesor == null) break;
      raizId = predecesor.id;
    }
    // Construir cadena lineal desde raíz hasta idActual (primer sucesor en cada paso)
    final cadena = <Proyecto>[];
    String? cursor = raizId;
    final vistos = <String>{};
    while (cursor != null && !vistos.contains(cursor)) {
      vistos.add(cursor);
      final nodo = porId[cursor];
      if (nodo == null) break;
      cadena.add(nodo);
      if (cursor == idActual) break;
      // Seguir por el primer sucesor que lleva al proyecto actual
      cursor = nodo.proyectoContinuacionIds
          .firstWhere((sid) => _estaEnCamino(porId, sid, idActual), orElse: () => nodo.proyectoContinuacionId ?? '');
      if (cursor.isEmpty) break;
    }
    return cadena;
  }

  /// Devuelve true si desde [desde] se puede llegar a [hasta] siguiendo sucesores.
  bool _estaEnCamino(Map<String, Proyecto> porId, String desde, String hasta) {
    final vistos = <String>{};
    String? cursor = desde;
    while (cursor != null && !vistos.contains(cursor)) {
      if (cursor == hasta) return true;
      vistos.add(cursor);
      cursor = porId[cursor]?.proyectoContinuacionId;
    }
    return false;
  }

  /// Obtiene los sucesores directos del proyecto actual ya cargados.
  List<Proyecto> _sucesoresDirectos(List<Proyecto> todos) {
    final porId = {for (final p in todos) p.id: p};
    return _proyecto.proyectoContinuacionIds
        .map((id) => porId[id])
        .whereType<Proyecto>()
        .toList();
  }

  Future<void> _cargarOc({bool forceRefresh = false}) async {
    final ids = _proyecto.idsOrdenesCompra.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    setState(() { _cargandoOc = true; _errorOc = null; _ocDataList = []; });
    // Sequential to avoid rate-limiting from the Mercado Público API
    final results = <Map<String, dynamic>?>[];
    for (final id in ids) {
      results.add(await _cargarUnaOc(id, forceRefresh: forceRefresh));
      if (mounted) setState(() => _ocDataList = List.from(results));
    }
    if (mounted) setState(() => _cargandoOc = false);
    // Siempre convertir UF→CLP para el render, luego guardar total si no existe
    if (results.any((oc) => oc != null)) {
      _resolverConversionUFyCLP(results);
    }
    // Re-calcular sugerencias: las OCs pueden revelar CodigoLicitacion en proyectos CM
    if (_sugerencias == null) _cargarCadena();
  }

  /// Convierte UF→CLP en cada OC que lo requiera (siempre) y guarda montoTotalOC si aún no existe.
  /// Detecta la moneda de una OC revisando todos los campos posibles de la API de MP.
  String _detectarMoneda(Map<String, dynamic> oc, {String? ocId}) {
    String? normalizar(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final u = v.trim().toUpperCase();
      if (u == 'CLF' || u == 'UF' || u.contains('FOMENTO')) return 'UF';
      if (u == 'USD' || u == 'DÓLAR' || u == 'DOLAR') return 'USD';
      if (u == 'PESO' || u == 'CLP' || u == 'PESO CHILENO') return 'CLP';
      if (v.trim() == '2') return 'UF'; // código numérico en algunos endpoints
      return null;
    }
    // Revisar campos del header (TipoMoneda es el campo real de la API de MP)
    for (final key in ['_moneda', 'TipoMoneda', 'TipoMonedaOC', 'Moneda']) {
      final r = normalizar(oc[key]?.toString());
      if (r != null) return r;
    }
    // Fallback: revisar moneda del primer ítem
    final items = (oc['Items']?['Listado'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isNotEmpty) {
      final r = normalizar(items[0]['Moneda']?.toString());
      if (r != null) return r;
    }
    return 'CLP';
  }

  Future<void> _resolverConversionUFyCLP(List<Map<String, dynamic>?> ocs) async {
    // Si alguna OC no tiene moneda detectada y el proyecto tiene licitación, obtener moneda desde OCDS
    final ocsSinMoneda = ocs.whereType<Map<String, dynamic>>()
        .where((oc) => _detectarMoneda(oc) == 'CLP' && (oc['_moneda'] == null || oc['_moneda'].toString().isEmpty))
        .toList();
    if (ocsSinMoneda.isNotEmpty && (_proyecto.idLicitacion?.isNotEmpty ?? false)) {
      try {
        final uri = Uri.parse('$_baseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(_proyecto.idLicitacion!)}&type=award');
        final resp = await http.get(uri).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final releases = data['releases'] as List?;
          if (releases != null && releases.isNotEmpty) {
            final awards = releases[0]['awards'] as List?;
            final awardValue = (awards != null && awards.isNotEmpty)
                ? (awards[0] as Map<String, dynamic>)['value'] as Map<String, dynamic>?
                : null;
            final currency = awardValue?['currency']?.toString() ?? '';
            if (currency.isNotEmpty && currency != 'CLP') {
              for (final oc in ocsSinMoneda) {
                oc['_moneda'] = currency;
              }
            }
          }
        }
      } catch (_) {}
    }
    double total = 0;
    for (final oc in ocs) {
      if (oc == null) continue;
      final raw = (oc['Total'] as num?)?.toDouble() ?? 0;
      if (raw == 0) continue;
      final ocId = oc['Codigo']?.toString() ?? '';
      final moneda = _detectarMoneda(oc, ocId: ocId.isNotEmpty ? ocId : null);
      if (moneda == 'UF') {
        final fechaStr = oc['Fechas']?['FechaCreacion']?.toString();
        final fecha = (fechaStr != null ? DateTime.tryParse(fechaStr) : null) ?? DateTime.now();
        final uf = await _getUFValue(fecha);
        final clp = raw * (uf > 0 ? uf : 1);
        oc['_ufValueDia'] = uf;
        oc['_totalCLP'] = clp;
        total += clp;
      } else {
        total += raw;
      }
    }
    // Refrescar UI con valores UF convertidos
    if (mounted) setState(() => _ocDataList = List.from(ocs));
    // Guardar montoTotalOC solo si aún no estaba registrado
    if (total == 0 || _proyecto.montoTotalOC != null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/actualizarProyecto'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': _proyecto.id,
          'montoTotalOC': total,
          '_campoEditado': 'montoTotalOC',
          '_valorAnterior': '',
          '_valorNuevo': total.toStringAsFixed(0),
        }),
      );
      ProyectosService.instance.invalidate();
      if (mounted) setState(() => _proyecto = _proyecto.copyWithMontoTotalOC(total));
    } catch (_) {}
  }

  Future<double> _getUFValue(DateTime fecha) async {
    try {
      final d = '${fecha.day.toString().padLeft(2, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.year}';
      final resp = await http
          .get(Uri.parse('https://mindicador.cl/api/uf/$d'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final serie = data['serie'] as List?;
        if (serie != null && serie.isNotEmpty) {
          return (serie[0]['valor'] as num).toDouble();
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<Map<String, dynamic>?> _cargarUnaOc(String id, {bool forceRefresh = false}) async {
    final cacheKey = 'oc_$id';
    // 1. Try cache (máx 3 días)
    if (!forceRefresh) {
      try {
        final cResp = await http.get(Uri.parse(
            '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=${Uri.encodeComponent(cacheKey)}'))
            .timeout(const Duration(seconds: 10));
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            final fetchedAt = c['fetchedAt'] != null
                ? DateTime.tryParse(c['fetchedAt'].toString())
                : null;
            final edad = fetchedAt != null
                ? DateTime.now().difference(fetchedAt)
                : const Duration(days: 999);
            if (edad.inHours < 24) {
              if (mounted) setState(() => _ocLastFetchMap[id] = c['fetchedAt']?.toString());
              return c['data'] as Map<String, dynamic>;
            }
          }
        }
      } catch (_) {}
    }
    // 2. Query API
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/buscarOrdenCompra?id=${Uri.encodeComponent(id)}'))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (mounted) setState(() => _ocLastFetchMap[id] = null);
        // 3. Save to cache (fire and forget)
        http.post(Uri.parse('$_baseUrl/guardarCacheExterno'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'proyectoId': _proyecto.id, 'tipo': cacheKey, 'data': data}));
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            final cResp = await http.get(Uri.parse(
                '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=${Uri.encodeComponent(cacheKey)}'))
                .timeout(const Duration(seconds: 5));
            if (cResp.statusCode == 200) {
              final c = json.decode(cResp.body);
              if (c != null && mounted) setState(() => _ocLastFetchMap[id] = c['fetchedAt']?.toString());
            }
          } catch (_) {}
        });
        return data;
      }
      return null;
    } catch (_) { return null; }
  }

  Future<void> _cargarConvenio({bool forceRefresh = false}) async {
    setState(() { _cargandoConvenio = true; _errorConvenio = null; });
    final url = _proyecto.urlConvenioMarco!;
    // 1. Try cache (máx 3 días)
    if (!forceRefresh) {
      try {
        final cResp = await http.get(Uri.parse(
            '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=convenio'))
            .timeout(const Duration(seconds: 10));
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            final fetchedAt = c['fetchedAt'] != null
                ? DateTime.tryParse(c['fetchedAt'].toString())
                : null;
            final edad = fetchedAt != null
                ? DateTime.now().difference(fetchedAt)
                : const Duration(days: 999);
            if (edad.inHours < 24) {
              if (mounted) {
                setState(() {
                  _convenioData = c['data'];
                  _convenioLastFetch = c['fetchedAt']?.toString();
                  _cargandoConvenio = false;
                });
                _sincronizarFechasDesdeConvenio();
              }
              return;
            }
          }
        }
      } catch (_) {}
    }
    // 2. Query Cloud Function
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(url)}'))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() { _convenioData = data; _convenioLastFetch = null; _cargandoConvenio = false; });
          _sincronizarFechasDesdeConvenio();
        }
        // 3. Save to cache (fire and forget)
        http.post(Uri.parse('$_baseUrl/guardarCacheExterno'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'proyectoId': _proyecto.id, 'tipo': 'convenio', 'data': data}));
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            final cResp = await http.get(Uri.parse(
                '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=convenio'))
                .timeout(const Duration(seconds: 5));
            if (cResp.statusCode == 200) {
              final c = json.decode(cResp.body);
              if (c != null && mounted) setState(() => _convenioLastFetch = c['fetchedAt']?.toString());
            }
          } catch (_) {}
        });
      } else {
        if (mounted) setState(() { _errorConvenio = 'Error ${resp.statusCode}'; _cargandoConvenio = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorConvenio = e.toString(); _cargandoConvenio = false; });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHistorial() async {
    try {
      final resp = await http.get(
          Uri.parse('$_baseUrl/obtenerHistorialProyecto?id=${_proyecto.id}'));
      if (resp.statusCode == 200) {
        final List data = json.decode(resp.body);
        final result = data.cast<Map<String, dynamic>>();
        _historial = result;
        return result;
      }
    } catch (_) {}
    return _historial;
  }

  Future<void> _editarCampo({
    required String nombreCampo,
    required String valorAnterior,
    required String valorNuevo,
    required Map<String, dynamic> data,
  }) async {
    final body = <String, dynamic>{
      'id': _proyecto.id,
      ...data,
      '_campoEditado': nombreCampo,
      '_valorAnterior': valorAnterior,
      '_valorNuevo': valorNuevo,
    };
    final resp = await http.post(
      Uri.parse('$_baseUrl/actualizarProyecto'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (resp.statusCode == 200) {
      final listResp =
          await http.get(Uri.parse('$_baseUrl/obtenerProyectos'));
      if (listResp.statusCode == 200) {
        final List all = json.decode(listResp.body);
        final updated = all
            .cast<Map<String, dynamic>>()
            .firstWhere((m) => m['id'] == _proyecto.id,
                orElse: () => <String, dynamic>{});
        if (updated.isNotEmpty && mounted) {
          setState(() => _proyecto = Proyecto.fromJson(updated));
          _rebuildTabController();
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Error: ${json.decode(resp.body)['error'] ?? resp.body}'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  Future<void> _recargarUnaOc(String id) async {
    final idx = _proyecto.idsOrdenesCompra.indexOf(id);
    if (idx < 0) return;
    setState(() => _cargandoOc = true);
    final data = await _cargarUnaOc(id, forceRefresh: true);
    if (mounted) {
      setState(() {
        if (idx < _ocDataList.length) _ocDataList[idx] = data;
        _cargandoOc = false;
      });
    }
  }

  String _fileNameFromUrl(String url) {
    try {
      final decoded = Uri.decodeFull(url);
      final name = decoded.split('/').last.split('?').first;
      return name.isNotEmpty ? name : url;
    } catch (_) {
      return url;
    }
  }

  String _extractCmId(String url) {
    final match = RegExp(r'/id/([^/\?#]+)').firstMatch(url);
    return match?.group(1) ?? url;
  }

  void _abrirFicha() {
    if (_proyecto.modalidadCompra == 'Convenio Marco' &&
        _proyecto.urlConvenioMarco?.isNotEmpty == true) {
      web.window.open(_proyecto.urlConvenioMarco!, '_blank');
      return;
    }
    final id = _proyecto.idLicitacion;
    if (id == null) return;
    web.window.open(
      'http://www.mercadopublico.cl/Procurement/Modules/RFB/DetailsAcquisition.aspx?idlicitacion=$id',
      '_blank',
    );
  }

  Widget _fichaButton() {
    return InkWell(
      onTap: _abrirFicha,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ver Ficha',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor)),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 11, color: _primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _exportBadge() {
    return InkWell(
      onTap: () => _showExportMenu(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF64748B).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.file_download_outlined, size: 14, color: Color(0xFF64748B)),
      ),
    );
  }

  Future<void> _abrirDialogoEncadenar() async {
    List<Proyecto> todos;
    try {
      todos = await ProyectosService.instance.load();
    } catch (_) {
      todos = [];
    }
    // Exclude self
    final candidatos = todos.where((p) => p.id != _proyecto.id).toList();

    if (!mounted) return;

    final seleccionado = await showDialog<Proyecto>(
      context: context,
      builder: (ctx) => _EncadenarDialog(
        candidatos: candidatos,
        actual: _proyecto,
      ),
    );

    if (seleccionado == null) return;
    await _encadenarCon(seleccionado);
  }

  Widget _encadenarButton() {
    final linked = _proyecto.proyectoContinuacionId?.isNotEmpty == true;
    return InkWell(
      onTap: _abrirDialogoEncadenar,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: linked
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : const Color(0xFF64748B).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              linked ? Icons.link : Icons.link_outlined,
              size: 13,
              color: linked ? const Color(0xFF10B981) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Text(
              linked ? 'Encadenado' : 'Encadenar',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: linked ? const Color(0xFF10B981) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshBar(String? lastFetch, VoidCallback onRefresh, {bool loading = false}) {
    String label = 'Datos externos';
    if (lastFetch != null) {
      try {
        final dt = DateTime.parse(lastFetch).toLocal();
        final d = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
        final t = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
        label = 'Caché: $d $t';
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(lastFetch != null ? Icons.cloud_done_outlined : Icons.cloud_outlined,
            size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Expanded(child: Text(label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400))),
        InkWell(
          onTap: loading ? null : onRefresh,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              loading
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: _primaryColor.withValues(alpha: 0.7)))
                  : Icon(Icons.refresh, size: 14, color: _primaryColor.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                loading ? 'Actualizando...' : 'Actualizar',
                style: GoogleFonts.inter(fontSize: 12, color: _primaryColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  void _mostrarOpcionesEstado() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) {
        String? selected = _proyecto.estadoManual;
        return StatefulBuilder(
          builder: (ctx, setS) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            elevation: 0,
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESTADO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3)),
                    const SizedBox(height: 4),
                    Text('Cambiar estado', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(10)),
                      clipBehavior: Clip.antiAlias,
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                       child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _estados.asMap().entries.map((e) {
                          final item = e.value;
                          final isSelected = selected == item.nombre;
                          final isLast = e.key == _estados.length - 1;
                          return Column(children: [
                            InkWell(
                              onTap: () => setS(() => selected = item.nombre),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(children: [
                                  Container(width: 10, height: 10,
                                    decoration: BoxDecoration(color: item.colorValue, shape: BoxShape.circle)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(item.nombre.replaceFirst(RegExp(r'^\d+-'), ''), style: GoogleFonts.inter(fontSize: 14, color: isSelected ? item.fgColor : const Color(0xFF1E293B), fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400))),
                                  if (isSelected) Icon(Icons.check, size: 16, color: item.fgColor),
                                ]),
                              ),
                            ),
                            if (!isLast) Divider(height: 1, color: Colors.grey.shade200),
                          ]);
                        }).toList(),
                      ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: TextButton.styleFrom(backgroundColor: const Color(0xFFF2F2F7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
                          child: Text('Cancelar', style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            if (selected != null) {
                              _editarCampo(nombreCampo: 'Estado', valorAnterior: _proyecto.estadoManual ?? '', valorNuevo: selected!, data: {'estadoManual': selected});
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0),
                          child: Text('Guardar', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarHistorial() {
    final future = _historial.isNotEmpty ? Future.value(_historial) : _fetchHistorial();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, ctrl) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Historial', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                    Text('Cambios realizados al proyecto', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400)),
                  ]),
                ),
                IconButton(icon: Icon(Icons.close, size: 20, color: Colors.grey.shade400), onPressed: () => Navigator.of(context).pop(), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.history, size: 40, color: Colors.grey.shade200),
                      const SizedBox(height: 8),
                      Text('Sin cambios aún', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
                    ]));
                  }
                  return ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (_, i) => _buildHistorialItem(items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (c > 0 && c % 3 == 0) buf.write('.');
      buf.write(s[i]);
      c++;
    }
    return buf.toString().split('').reversed.join('');
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _fmtDateStr(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _cleanName(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return raw.split('|').first.trim();
  }

  int _diasRestantes() {
    if (_proyecto.fechaTermino == null) return 0;
    return _proyecto.fechaTermino!.difference(DateTime.now()).inDays;
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 700;
      final hPad = isMobile ? 20.0 : 32.0;

      return Scaffold(
        backgroundColor: _bgColor,
        body: Column(
          children: [
            _buildAppBar(hPad, isMobile),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: hPad, vertical: isMobile ? 16 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(isMobile),
                          if (_cadena != null && (_cadena!.length > 1 || (_sucesores?.isNotEmpty ?? false))) ...[
                            const SizedBox(height: 20),
                            _buildCadenaTimeline(_cadena!, _sucesores ?? []),
                          ],
                          const SizedBox(height: 24),
                          _buildTabs(isMobile),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildAppBar(double hPad, bool isMobile) {
    final institucion = _cleanName(_proyecto.institucion).split('|').first.trim();
    return buildBreadcrumbAppBar(
      context: context,
      hPad: hPad,
      onOpenMenu: openAppDrawer,
      crumbs: [
        BreadcrumbItem('Proyectos', onTap: () => context.pop()),
        BreadcrumbItem(institucion),
      ],
    );
  }

  // ─── EXPORT ───────────────────────────────────────────────────────────────

  void _showExportMenu(BuildContext context) {
    final hasReclamos = _proyecto.reclamos.isNotEmpty;
    final hasOcds = _ocdsData != null;
    final hasConvenio = _convenioData != null;
    final hasOc = _ocDataList.any((d) => d != null);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Exportar proyecto',
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(
            _cleanName(_proyecto.institucion).split('|').first.trim(),
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          _exportOpt(Icons.folder_outlined, 'Datos del proyecto (CSV)',
              'Información general, fechas y valores', () {
            Navigator.pop(context);
            _exportProyectoCSV();
          }),
          if (hasReclamos) ...[
            const SizedBox(height: 8),
            _exportOpt(Icons.gavel_outlined, 'Reclamos (CSV)',
                '${_proyecto.reclamos.length} reclamo${_proyecto.reclamos.length != 1 ? 's' : ''}', () {
              Navigator.pop(context);
              _exportReclamosCSV();
            }),
          ],
          if (hasOcds || hasConvenio) ...[
            const SizedBox(height: 8),
            _exportOpt(Icons.code_outlined, 'Detalle licitación (JSON)',
                'Datos OCDS del Mercado Público', () {
              Navigator.pop(context);
              _exportDetalleJSON();
            }),
          ],
          if (hasOc) ...[
            const SizedBox(height: 8),
            _exportOpt(Icons.shopping_cart_outlined, 'Órdenes de compra (CSV)',
                '${_proyecto.idsOrdenesCompra.length} orden${_proyecto.idsOrdenesCompra.length != 1 ? 'es' : ''}', () {
              Navigator.pop(context);
              _exportOcCSV();
            }),
          ],
          const SizedBox(height: 8),
          _exportOpt(Icons.print_outlined, 'Imprimir / PDF',
              'Genera una página HTML lista para imprimir o guardar como PDF', () {
            Navigator.pop(context);
            _exportDetalleProyectoPDF();
          }),
        ]),
      ),
    );
  }

  Widget _exportOpt(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: const Color(0xFFF8FAFC),
      leading: Icon(icon, color: _primaryColor, size: 22),
      title: Text(title,
          style: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B))),
      subtitle: Text(subtitle,
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
      onTap: onTap,
    );
  }

  void _downloadFile(String content, String filename, String mime) {
    final bytes = utf8.encode('\uFEFF$content');
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename;
    web.document.body!.appendChild(anchor);
    anchor.click();
    web.document.body!.removeChild(anchor);
    web.URL.revokeObjectURL(url);
  }

  void _exportProyectoCSV() {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    String fmtDate(DateTime? d) => d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final buf = StringBuffer();
    buf.writeln('Campo,Valor');
    buf.writeln('Institución,${esc(_cleanName(_proyecto.institucion))}');
    buf.writeln('Modalidad,${esc(_proyecto.modalidadCompra)}');
    buf.writeln('Productos,${esc(_proyecto.productos)}');
    buf.writeln('Estado,${esc(_proyecto.estado)}');
    buf.writeln('ID Licitación,${esc(_proyecto.idLicitacion ?? '')}');
    buf.writeln('Valor Mensual,${_proyecto.valorMensual?.toStringAsFixed(0) ?? ''}');
    buf.writeln('Fecha Inicio,${fmtDate(_proyecto.fechaInicio)}');
    buf.writeln('Fecha Término,${fmtDate(_proyecto.fechaTermino)}');
    buf.writeln('Fecha Inicio Ruta,${fmtDate(_proyecto.fechaInicioRuta)}');
    buf.writeln('Fecha Término Ruta,${fmtDate(_proyecto.fechaTerminoRuta)}');
    buf.writeln('Reclamos Pendientes,${_proyecto.reclamos.where((r) => r.estado == 'Pendiente').length}');
    buf.writeln('Total Reclamos,${_proyecto.reclamos.length}');

    final ts = DateTime.now().millisecondsSinceEpoch;
    _downloadFile(buf.toString(), 'proyecto_$ts.csv', 'text/csv;charset=utf-8;');
  }

  void _exportReclamosCSV() {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    String fmtDate(DateTime? d) => d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final buf = StringBuffer();
    buf.writeln('N°,Descripción,Estado,Fecha Ingreso,Fecha Respuesta,Descripción Respuesta');
    for (int i = 0; i < _proyecto.reclamos.length; i++) {
      final r = _proyecto.reclamos[i];
      buf.writeln([
        i + 1,
        esc(r.descripcion),
        esc(r.estado),
        fmtDate(r.fechaReclamo),
        fmtDate(r.fechaRespuesta),
        esc(r.descripcionRespuesta ?? ''),
      ].join(','));
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    _downloadFile(buf.toString(), 'reclamos_$ts.csv', 'text/csv;charset=utf-8;');
  }

  void _exportDetalleJSON() {
    final data = _ocdsData ?? _convenioData ?? {};
    final content = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(content);
    final blob = web.Blob([bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/json'));
    final url = web.URL.createObjectURL(blob);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = 'detalle_$ts.json';
    web.document.body!.appendChild(anchor);
    anchor.click();
    web.document.body!.removeChild(anchor);
    web.URL.revokeObjectURL(url);
  }

  void _exportOcCSV() {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';

    final buf = StringBuffer();
    buf.writeln('OC ID,Proveedor,RUT Proveedor,N° Item,Descripción,Cantidad,Unidad,Precio Unit.,Total');
    for (int oi = 0; oi < _ocDataList.length; oi++) {
      final oc = _ocDataList[oi];
      if (oc == null) continue;
      final ocId = _proyecto.idsOrdenesCompra.length > oi ? _proyecto.idsOrdenesCompra[oi] : '';
      final proveedor = oc['Proveedor'] as Map<String, dynamic>? ?? {};
      final nombreProv = proveedor['Nombre']?.toString() ?? '';
      final rutProv = proveedor['Rut']?.toString() ?? '';
      final items = (oc['Items']?['Listado'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (items.isEmpty) {
        buf.writeln([esc(ocId), esc(nombreProv), esc(rutProv), '', '', '', '', '', ''].join(','));
      } else {
        for (final item in items) {
          buf.writeln([
            esc(ocId),
            esc(nombreProv),
            esc(rutProv),
            item['Correlativo']?.toString() ?? '',
            esc(item['Nombre']?.toString() ?? ''),
            item['Cantidad']?.toString() ?? '',
            esc(item['UnidadMedida']?.toString() ?? ''),
            item['PrecioUnitario']?.toString() ?? '',
            item['Total']?.toString() ?? '',
          ].join(','));
        }
      }
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    _downloadFile(buf.toString(), 'ordenes_compra_$ts.csv', 'text/csv;charset=utf-8;');
  }

  void _exportDetalleProyectoPDF() {
    final p = _proyecto;
    String fmtDate(DateTime? d) => d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    String fmtVal(double? v) {
      if (v == null) return '—';
      final s = v.toInt().toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return '\$ ${buf.toString()}';
    }
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    final institucion = _cleanName(p.institucion);
    final estado = p.estado;

    // ── Estado color ──
    final estadoColor = {
          EstadoProyecto.vigente: '#16a34a',
          EstadoProyecto.xVencer: '#d97706',

          EstadoProyecto.finalizado: '#6b7280',
          EstadoProyecto.sinFecha: '#6b7280',
        }[estado] ??
        '#6b7280';

    // ── Fechas rows ──
    final fechaRows = StringBuffer();
    void addFecha(String label, DateTime? d) {
      if (d == null) return;
      fechaRows.write('<tr><td class="fl">$label</td><td>${esc(fmtDate(d))}</td></tr>');
    }
    addFecha('Inicio contrato', p.fechaInicio);
    addFecha('Término contrato', p.fechaTermino);
    addFecha('Inicio ruta', p.fechaInicioRuta);
    addFecha('Término ruta', p.fechaTerminoRuta);
    addFecha('Publicación licitación', p.fechaPublicacion);
    addFecha('Cierre recepción', p.fechaCierre);
    addFecha('Adjudicación', p.fechaAdjudicacion);

    // ── Reclamos section ──
    final reclamosHtml = StringBuffer();
    if (p.reclamos.isNotEmpty) {
      reclamosHtml.write('''
<h2>Reclamos (${p.reclamos.length})</h2>
<table>
  <thead><tr><th>#</th><th>Descripción</th><th>Estado</th><th>Ingreso</th><th>Respuesta</th><th>Documentos</th></tr></thead>
  <tbody>
''');
      for (int i = 0; i < p.reclamos.length; i++) {
        final r = p.reclamos[i];
        final allDocs = [...r.documentos, ...r.documentosRespuesta];
        final docsHtml = allDocs.isEmpty
            ? '—'
            : allDocs.map((d) => '<a href="${esc(d.url)}">${esc(d.nombre ?? d.tipo)}</a>').join('<br>');
        reclamosHtml.write('''
    <tr>
      <td>${i + 1}</td>
      <td>${esc(r.descripcion)}</td>
      <td><span style="color:${r.estado == 'Pendiente' ? '#d97706' : '#16a34a'}">${esc(r.estado)}</span></td>
      <td>${esc(fmtDate(r.fechaReclamo))}</td>
      <td>${esc(fmtDate(r.fechaRespuesta))}</td>
      <td>$docsHtml</td>
    </tr>
''');
        if (r.descripcionRespuesta != null && r.descripcionRespuesta!.isNotEmpty) {
          reclamosHtml.write('''
    <tr><td></td><td colspan="5" style="color:#374151;font-style:italic">Respuesta: ${esc(r.descripcionRespuesta!)}</td></tr>
''');
        }
      }
      reclamosHtml.write('  </tbody></table>');
    }

    // ── Certificados section ──
    final certHtml = StringBuffer();
    if (p.certificados.isNotEmpty) {
      certHtml.write('''
<h2>Certificados de experiencia (${p.certificados.length})</h2>
<table>
  <thead><tr><th>#</th><th>Descripción</th><th>Fecha emisión</th><th>Enlace</th></tr></thead>
  <tbody>
''');
      for (int i = 0; i < p.certificados.length; i++) {
        final c = p.certificados[i];
        final enlace = c.url != null ? '<a href="${esc(c.url!)}">${esc(c.url!)}</a>' : '—';
        certHtml.write('''
    <tr>
      <td>${i + 1}</td>
      <td>${esc(c.descripcion)}</td>
      <td>${esc(fmtDate(c.fechaEmision))}</td>
      <td>$enlace</td>
    </tr>
''');
      }
      certHtml.write('  </tbody></table>');
    }

    // ── Documentos section ──
    final docsHtml = StringBuffer();
    if (p.documentos.isNotEmpty) {
      docsHtml.write('''
<h2>Documentos del proyecto (${p.documentos.length})</h2>
<table>
  <thead><tr><th>#</th><th>Tipo</th><th>Nombre</th><th>Enlace</th></tr></thead>
  <tbody>
''');
      for (int i = 0; i < p.documentos.length; i++) {
        final d = p.documentos[i];
        docsHtml.write('''
    <tr>
      <td>${i + 1}</td>
      <td>${esc(d.tipo)}</td>
      <td>${esc(d.nombre ?? '—')}</td>
      <td><a href="${esc(d.url)}">${esc(d.url)}</a></td>
    </tr>
''');
      }
      docsHtml.write('  </tbody></table>');
    }

    // ── OC IDs ──
    final ocHtml = p.idsOrdenesCompra.isEmpty
        ? ''
        : '<p><strong>Órdenes de compra:</strong> ${p.idsOrdenesCompra.map(esc).join(', ')}</p>';

    // ── Notas ──
    final notasHtml = (p.notas != null && p.notas!.isNotEmpty)
        ? '<h2>Notas</h2><p>${esc(p.notas!).replaceAll('\n', '<br>')}</p>'
        : '';

    // ── Detalle OCDS (licitación) ──
    final ocdsHtml = StringBuffer();
    if (_ocdsData != null) {
      final releases = _ocdsData!['releases'] as List?;
      final last = releases?.isNotEmpty == true
          ? releases!.last as Map<String, dynamic>
          : <String, dynamic>{};
      final tender = last['tender'] as Map<String, dynamic>? ?? {};
      final parties = (last['parties'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final buyer = parties.firstWhere(
          (pp) => (pp['roles'] as List?)?.contains('buyer') == true,
          orElse: () => <String, dynamic>{});

      // Tender header
      final tenderTitle = tender['title']?.toString() ?? '';
      final tenderDesc = tender['description']?.toString() ?? '';
      final tenderStatus = tender['statusDetails']?.toString() ?? tender['status']?.toString() ?? '';
      final tenderMethod = tender['procurementMethodDetails']?.toString() ?? '';
      ocdsHtml.write('<h2>Detalle licitación (OCDS)</h2>');
      if (tenderTitle.isNotEmpty) ocdsHtml.write('<p><strong>${esc(tenderTitle)}</strong></p>');
      if (tenderDesc.isNotEmpty) ocdsHtml.write('<p style="color:#374151;margin:4px 0">${esc(tenderDesc)}</p>');
      if (tenderStatus.isNotEmpty || tenderMethod.isNotEmpty) {
        ocdsHtml.write('<p style="font-size:11px;color:#64748b;margin:4px 0">');
        if (tenderStatus.isNotEmpty) ocdsHtml.write('Estado: <strong>${esc(tenderStatus)}</strong>');
        if (tenderMethod.isNotEmpty) ocdsHtml.write(' &nbsp;·&nbsp; Modalidad: <strong>${esc(tenderMethod)}</strong>');
        ocdsHtml.write('</p>');
      }

      // Buyer
      if (buyer.isNotEmpty) {
        final bName = _cleanName(buyer['name']?.toString());
        final bId = (buyer['identifier'] as Map?)?['id']?.toString() ?? '';
        final bAddr = (buyer['address'] as Map?)?['streetAddress']?.toString() ?? '';
        final bRegion = (buyer['address'] as Map?)?['region']?.toString() ?? '';
        final bContact = (buyer['contactPoint'] as Map?)?['name']?.toString() ?? '';
        ocdsHtml.write('<h2 style="margin-top:12px">Comprador</h2>');
        ocdsHtml.write('<table style="max-width:480px"><tbody>');
        if (bName.isNotEmpty) ocdsHtml.write('<tr><td class="fl">Nombre</td><td>${esc(bName)}</td></tr>');
        if (bId.isNotEmpty) ocdsHtml.write('<tr><td class="fl">RUT/ID</td><td>${esc(bId)}</td></tr>');
        if (bAddr.isNotEmpty) ocdsHtml.write('<tr><td class="fl">Dirección</td><td>${esc(bAddr)}</td></tr>');
        if (bRegion.isNotEmpty) ocdsHtml.write('<tr><td class="fl">Región</td><td>${esc(bRegion)}</td></tr>');
        if (bContact.isNotEmpty) ocdsHtml.write('<tr><td class="fl">Contacto</td><td>${esc(bContact)}</td></tr>');
        ocdsHtml.write('</tbody></table>');
      }

      // Plazos
      String fmtRaw(String? s) {
        if (s == null) return '—';
        final d = DateTime.tryParse(s);
        return d != null ? fmtDate(d) : s;
      }
      final tenderPeriod = tender['tenderPeriod'] as Map? ?? {};
      final enquiryPeriod = tender['enquiryPeriod'] as Map? ?? {};
      final awardPeriod = tender['awardPeriod'] as Map? ?? {};
      final hasPlazos = tenderPeriod.isNotEmpty || enquiryPeriod.isNotEmpty || awardPeriod.isNotEmpty;
      if (hasPlazos) {
        ocdsHtml.write('<h2 style="margin-top:12px">Plazos licitación</h2>');
        ocdsHtml.write('<table style="max-width:480px"><tbody>');
        if (tenderPeriod['startDate'] != null) ocdsHtml.write('<tr><td class="fl">Publicación</td><td>${esc(fmtRaw(tenderPeriod['startDate']?.toString()))}</td></tr>');
        if (tenderPeriod['endDate'] != null) ocdsHtml.write('<tr><td class="fl">Cierre recepción</td><td>${esc(fmtRaw(tenderPeriod['endDate']?.toString()))}</td></tr>');
        if (enquiryPeriod['startDate'] != null) ocdsHtml.write('<tr><td class="fl">Inicio consultas</td><td>${esc(fmtRaw(enquiryPeriod['startDate']?.toString()))}</td></tr>');
        if (enquiryPeriod['endDate'] != null) ocdsHtml.write('<tr><td class="fl">Fin consultas</td><td>${esc(fmtRaw(enquiryPeriod['endDate']?.toString()))}</td></tr>');
        if (awardPeriod['startDate'] != null) ocdsHtml.write('<tr><td class="fl">Adjudicación</td><td>${esc(fmtRaw(awardPeriod['startDate']?.toString()))}</td></tr>');
        if (awardPeriod['endDate'] != null) ocdsHtml.write('<tr><td class="fl">Fin adjudicación</td><td>${esc(fmtRaw(awardPeriod['endDate']?.toString()))}</td></tr>');
        ocdsHtml.write('</tbody></table>');
      }

      // Items
      final items = (tender['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (items.isNotEmpty) {
        ocdsHtml.write('<h2 style="margin-top:12px">Ítems licitación (${items.length})</h2>');
        ocdsHtml.write('<table><thead><tr><th>#</th><th>Descripción</th><th>Clasificación</th><th>Cantidad</th><th>Unidad</th></tr></thead><tbody>');
        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          final desc = item['description']?.toString() ?? '';
          final classif = (item['classification'] as Map?)?['id']?.toString() ?? '';
          final qty = item['quantity']?.toString() ?? '';
          final unit = (item['unit'] as Map?)?['name']?.toString() ?? '';
          ocdsHtml.write('<tr><td>${i + 1}</td><td>${esc(desc)}</td><td>${esc(classif)}</td><td>${esc(qty)}</td><td>${esc(unit)}</td></tr>');
        }
        ocdsHtml.write('</tbody></table>');
      }

      // Bids / offers
      final bidsRelease = releases?.cast<Map<String, dynamic>>().lastWhere(
          (r) => r['bids'] != null,
          orElse: () => <String, dynamic>{});
      final bids = (bidsRelease?['bids']?['details'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (bids.isNotEmpty) {
        ocdsHtml.write('<h2 style="margin-top:12px">Ofertas recibidas (${bids.length})</h2>');
        ocdsHtml.write('<table><thead><tr><th>#</th><th>Proveedor</th><th>Monto</th><th>Estado</th><th>Fecha</th></tr></thead><tbody>');
        for (int i = 0; i < bids.length; i++) {
          final bid = bids[i];
          final tenderers = (bid['tenderers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final provName = tenderers.isNotEmpty ? _cleanName(tenderers.first['name']?.toString()) : '';
          final amount = bid['value']?['amount'];
          final currency = bid['value']?['currency']?.toString() ?? 'CLP';
          final amountStr = amount != null ? '$currency ${esc(amount.toString())}' : '—';
          final bidStatus = bid['status']?.toString() ?? '';
          final bidDate = fmtRaw(bid['date']?.toString());
          ocdsHtml.write('<tr><td>${i + 1}</td><td>${esc(provName)}</td><td>$amountStr</td><td>${esc(bidStatus)}</td><td>${esc(bidDate)}</td></tr>');
        }
        ocdsHtml.write('</tbody></table>');
      }
    }

    // ── Detalle Convenio Marco ──
    final convenioHtml = StringBuffer();
    if (_convenioData != null) {
      final cv = _convenioData!;
      final cvTitulo = cv['titulo']?.toString() ?? '';
      final cvComprador = cv['comprador']?.toString() ?? '';
      final cvConvenio = cv['convenioMarco']?.toString() ?? '';
      final cvEstado = cv['estado']?.toString() ?? '';
      final cvCampos = (cv['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final camposFiltrados = cvCampos
          .where((c) => (c['label']?.toString() ?? '').isNotEmpty && (c['valor']?.toString() ?? '').isNotEmpty)
          .toList();

      convenioHtml.write('<h2>Detalle Convenio Marco</h2>');
      if (cvTitulo.isNotEmpty) convenioHtml.write('<p><strong>${esc(cvTitulo)}</strong></p>');
      convenioHtml.write('<table style="max-width:480px;margin-top:8px"><tbody>');
      if (cvConvenio.isNotEmpty) convenioHtml.write('<tr><td class="fl">Convenio</td><td>${esc(cvConvenio)}</td></tr>');
      if (cvComprador.isNotEmpty) convenioHtml.write('<tr><td class="fl">Comprador</td><td>${esc(cvComprador)}</td></tr>');
      if (cvEstado.isNotEmpty) convenioHtml.write('<tr><td class="fl">Estado</td><td>${esc(cvEstado)}</td></tr>');
      for (final campo in camposFiltrados) {
        convenioHtml.write('<tr><td class="fl">${esc(campo['label']!.toString())}</td><td>${esc(campo['valor']!.toString())}</td></tr>');
      }
      convenioHtml.write('</tbody></table>');
    }

    final html = '''<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>${esc(institucion)}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         font-size: 13px; color: #1e293b; background: #fff; padding: 24px 32px; }
  h1 { font-size: 20px; font-weight: 700; color: #1e293b; margin-bottom: 4px; }
  h2 { font-size: 14px; font-weight: 600; color: #374151; margin: 20px 0 8px; border-bottom: 1px solid #e2e8f0; padding-bottom: 4px; }
  .subtitle { font-size: 12px; color: #64748b; margin-bottom: 12px; }
  .badge { display:inline-block; padding: 2px 10px; border-radius: 12px; font-size: 11px; font-weight: 600; color:#fff; margin-left: 8px; }
  .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 12px 0; }
  .info-card { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 10px 14px; }
  .info-card .label { font-size: 11px; color: #94a3b8; margin-bottom: 2px; }
  .info-card .value { font-size: 14px; font-weight: 600; color: #1e293b; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 8px; }
  th { background: #f1f5f9; text-align: left; padding: 6px 8px; font-weight: 600; color: #475569; border: 1px solid #e2e8f0; }
  td { padding: 5px 8px; border: 1px solid #e2e8f0; vertical-align: top; }
  .fl { color: #64748b; white-space: nowrap; }
  a { color: #5b21b6; word-break: break-all; }
  .footer { margin-top: 24px; font-size: 10px; color: #94a3b8; text-align: right; }
  @media print {
    body { padding: 0; }
    a { color: #5b21b6; }
  }
</style>
<script>window.addEventListener('load', () => window.print());</script>
</head>
<body>
<h1>${esc(institucion)} <span class="badge" style="background:$estadoColor">${esc(estado)}</span></h1>
<div class="subtitle">${esc(p.modalidadCompra)}${p.idLicitacion != null ? ' &nbsp;·&nbsp; ID: ${esc(p.idLicitacion!)}' : ''}${p.idCotizacion != null ? ' &nbsp;·&nbsp; Cot: ${esc(p.idCotizacion!)}' : ''}</div>
<div class="subtitle">${esc(p.productos)}</div>

<div class="info-grid">
  <div class="info-card"><div class="label">Valor mensual</div><div class="value">${esc(fmtVal(p.valorMensual))}</div></div>
  <div class="info-card"><div class="label">Período contrato</div><div class="value">${esc(fmtDate(p.fechaInicio))} → ${esc(fmtDate(p.fechaTermino))}</div></div>
</div>

<h2>Fechas</h2>
<table style="max-width:420px"><tbody>$fechaRows</tbody></table>

$ocHtml
$reclamosHtml
$certHtml
$docsHtml
$notasHtml
$ocdsHtml
$convenioHtml

<div class="footer">Generado el ${esc(fmtDate(DateTime.now()))}</div>
</body>
</html>''';

    final bytes = utf8.encode(html);
    final blob = web.Blob(
        [bytes.toJS].toJS, web.BlobPropertyBag(type: 'text/html;charset=utf-8'));
    final url = web.URL.createObjectURL(blob);
    web.window.open(url, '_blank');
    Future.delayed(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
  }

  // ─── HEADER ───────────────────────────────────────────────────────────────

  // ─── Timeline cadena contractual ─────────────────────────────────────────

  Widget _buildCadenaTimeline(List<Proyecto> cadena, List<Proyecto> sucesores) {
    // "Último de la cadena de ancestros" = el que se está viendo
    final ultimoId = cadena.isNotEmpty ? cadena.last.id : _proyecto.id;
    bool esViewing(Proyecto p) => p.id == _proyecto.id;
    bool esUltimo(Proyecto p) => p.id == ultimoId;

    String fmtRango(Proyecto p) {
      String y(DateTime? d) => d != null ? '${d.year}' : '—';
      final ini = y(p.fechaInicio ?? p.fechaCreacion);
      final fin = p.fechaTermino != null ? y(p.fechaTermino) : 'hoy';
      return '$ini – $fin';
    }

    String fmtMonto(Proyecto p) {
      final m = p.montoTotalOC;
      if (m == null || m == 0) return '';
      if (m >= 1e9) return '\$${(m / 1e9).toStringAsFixed(1)}B';
      if (m >= 1e6) return '\$${(m / 1e6).toStringAsFixed(1)}M';
      return '\$${_fmt(m.toInt())}';
    }

    Widget buildNodo(Proyecto p, {
      required bool isLast,
      required bool isSucesor,
      required bool showLine,
    }) {
      final esAqui = esViewing(p);
      final esVigente = isSucesor && sucesores.length == 1 && !esAqui;
      final nombre = _cleanName(p.productos).split('\n').first.trim();
      final monto = fmtMonto(p);
      final rango = fmtRango(p);

      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Dot + line
          SizedBox(
            width: 24,
            child: Column(children: [
              Container(
                width: esAqui ? 14 : 10,
                height: esAqui ? 14 : 10,
                margin: EdgeInsets.only(top: esAqui ? 3 : 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: esVigente
                      ? _primaryColor
                      : esAqui
                          ? _primaryColor.withValues(alpha: 0.45)
                          : Colors.grey.shade300,
                  border: (esVigente || esAqui)
                      ? Border.all(color: _primaryColor.withValues(alpha: 0.3), width: 3)
                      : null,
                  boxShadow: esVigente
                      ? [BoxShadow(color: _primaryColor.withValues(alpha: 0.25), blurRadius: 6, spreadRadius: 1)]
                      : null,
                ),
              ),
              if (showLine)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.only(top: 4),
                    color: Colors.grey.shade200,
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => DetalleProyectoView(proyecto: p)),
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: esAqui
                          ? _primaryColor.withValues(alpha: 0.04)
                          : esVigente
                              ? _primaryColor.withValues(alpha: 0.06)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: esVigente
                            ? _primaryColor.withValues(alpha: 0.18)
                            : esAqui
                                ? Colors.grey.shade200
                                : Colors.transparent,
                      ),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            if (esVigente) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(4)),
                                child: Text('VIGENTE', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                              ),
                            ] else if (esAqui) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(4)),
                                child: Text('AQUÍ', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                              ),
                            ],
                            Expanded(
                              child: Text(
                                nombre.isEmpty ? p.institucion : nombre,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: (esAqui || esVigente) ? FontWeight.w700 : FontWeight.w500,
                                  color: (esAqui || esVigente) ? const Color(0xFF1E293B) : Colors.grey.shade600,
                                ),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(rango, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                            if (monto.isNotEmpty) ...[
                              Container(width: 3, height: 3, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle)),
                              Text(monto, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                            ],
                          ]),
                        ]),
                      ),
                      // Botón eliminar solo en sucesores directos del proyecto actual
                      if (isSucesor && esViewing(cadena.isNotEmpty ? cadena.last : _proyecto))
                        GestureDetector(
                          onTap: () => _confirmarDesencadenar(p),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6, top: 2),
                            child: Icon(Icons.link_off_rounded, size: 15, color: Colors.red.shade300),
                          ),
                        )
                      else
                        Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade300),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    }

    final totalRenovaciones = cadena.length - 1 + sucesores.length;
    final renovLabel = '$totalRenovaciones renovación${totalRenovaciones != 1 ? 'es' : ''}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _primaryColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
              child: Text('PROYECTO', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: _primaryColor, letterSpacing: 0.8)),
            ),
            const SizedBox(width: 8),
            Text(renovLabel, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
            const Spacer(),
            // Botón eliminar todo encadenamiento (solo si hay sucesores y estamos en el proyecto actual = último de cadena)
            if (sucesores.isNotEmpty && esUltimo(_proyecto))
              GestureDetector(
                onTap: _confirmarDesencadenarTodo,
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded, size: 13, color: Colors.red.shade300),
                  const SizedBox(width: 3),
                  Text('Eliminar todo', style: GoogleFonts.inter(fontSize: 11, color: Colors.red.shade300, fontWeight: FontWeight.w500)),
                ]),
              ),
          ]),
          const SizedBox(height: 16),
          // Ancestros (cadena hasta el proyecto actual)
          ...cadena.asMap().entries.map((e) {
            final isLastAnc = e.key == cadena.length - 1;
            return buildNodo(e.value,
              isLast: isLastAnc && sucesores.isEmpty,
              isSucesor: false,
              showLine: !isLastAnc || sucesores.isNotEmpty,
            );
          }),
          // Sucesores directos del proyecto actual
          ...sucesores.asMap().entries.map((e) {
            final isLast = e.key == sucesores.length - 1;
            return buildNodo(e.value,
              isLast: isLast,
              isSucesor: true,
              showLine: !isLast,
            );
          }),
        ],
      ),
    );
  }

  Future<void> _confirmarDesencadenar(Proyecto sucesor) async {
    final nombre = _cleanName(sucesor.productos).split('\n').first.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar encadenamiento', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('¿Desvincular "${nombre.isEmpty ? sucesor.institucion : nombre}" de este proyecto?',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
    if (ok == true) await _desencadenarUno(sucesor.id);
  }

  Future<void> _confirmarDesencadenarTodo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar todo el encadenamiento', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('¿Deseas desvincular todos los proyectos encadenados desde éste?',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar todo', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
    if (ok == true) await _desencadenarTodo();
  }

  Future<void> _encadenarCon(Proyecto p) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/actualizarProyecto'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id': _proyecto.id, 'addProyectoContinuacionId': p.id}),
      );
      ProyectosService.instance.invalidate();
      if (!mounted) return;
      setState(() {
        _proyecto = _proyecto.copyWithAddContinuacion(p.id);
        _sugerencias = null;
      });
      await _cargarCadena();
    } catch (_) {}
  }

  Future<void> _desencadenarUno(String sucId) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/actualizarProyecto'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id': _proyecto.id, 'removeProyectoContinuacionId': sucId}),
      );
      ProyectosService.instance.invalidate();
      if (!mounted) return;
      setState(() {
        _proyecto = _proyecto.copyWithRemoveContinuacion(sucId);
        _sucesores = _sucesores?.where((p) => p.id != sucId).toList();
        _sugerencias = null;
      });
      await _cargarCadena();
    } catch (_) {}
  }

  Future<void> _desencadenarTodo() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/actualizarProyecto'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id': _proyecto.id, 'clearProyectoContinuacionIds': true}),
      );
      ProyectosService.instance.invalidate();
      if (!mounted) return;
      setState(() {
        _proyecto = _proyecto.copyWithClearContinuaciones();
        _cadena = null;
        _sucesores = null;
        _sugerencias = null;
      });
    } catch (_) {}
  }


  Widget _buildHeader(bool isMobile) {
    final hasFicha = _proyecto.modalidadCompra != 'Trato Directo' &&
        (_proyecto.idLicitacion != null ||
            _proyecto.urlConvenioMarco?.isNotEmpty == true);

    final subtitleText = [
      _proyecto.modalidadCompra,
      if (_proyecto.idLicitacion != null) 'ID: ${_proyecto.idLicitacion}',
      if (_proyecto.urlConvenioMarco?.isNotEmpty == true)
        'ID: ${_extractCmId(_proyecto.urlConvenioMarco!)}',
    ].join('  ·  ');

    final titleText = Text(
      _cleanName(_proyecto.institucion).toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: isMobile ? 22 : 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: const Color(0xFF1E293B),
      ),
    );

    final badgesRow = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _exportBadge(),
        if (hasFicha) _fichaButton(),
        if (_proyecto.estado == EstadoProyecto.finalizado ||
            _proyecto.proyectoContinuacionId?.isNotEmpty == true)
          _encadenarButton(),
        GestureDetector(
          onTap: _mostrarOpcionesEstado,
          child: _estadoBadge(_proyecto.estado),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile) ...[
          titleText,
          const SizedBox(height: 6),
          Text(subtitleText,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          badgesRow,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleText),
              const SizedBox(width: 12),
              badgesRow,
            ],
          ),
        if (!isMobile) ...[
          const SizedBox(height: 6),
          Text(subtitleText,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
        ],
        const SizedBox(height: 20),
        _buildStatRow(isMobile),
      ],
    );
  }

  Widget _buildStatRow(bool isMobile) {
    final dias = _diasRestantes();
    String diasStr;
    if (_proyecto.fechaTermino == null) {
      diasStr = '—';
    } else if (dias < 0) {
      diasStr = 'Vencido';
    } else if (dias < 30) {
      diasStr = '$dias días';
    } else {
      final meses = dias ~/ 30;
      final diasRestantes = dias % 30;
      diasStr = diasRestantes > 0 ? '$meses m $diasRestantes d' : '$meses meses';
    }
    final diasColor = dias < 0
        ? Colors.grey.shade400
        : dias < 30
            ? const Color(0xFFD97706)
            : const Color(0xFF16A34A);

    final stats = [
      _StatInfo(
        label: 'Valor Mensual',
        value: _proyecto.valorMensual != null
            ? '\$${_fmt(_proyecto.valorMensual!.toInt())}'
            : '—',
        valueColor: _primaryColor,
        icon: Icons.attach_money_rounded,
      ),
      _StatInfo(
        label: 'Vencimiento',
        value: diasStr,
        valueColor: diasColor,
        icon: Icons.hourglass_bottom,
      ),
      _StatInfo(
        label: 'Inicio',
        value: _fmtDate(_proyecto.fechaInicio),
        valueColor: const Color(0xFF1E293B),
        icon: Icons.play_circle_outline,
      ),
      _StatInfo(
        label: 'Término',
        value: _fmtDate(_proyecto.fechaTermino),
        valueColor: const Color(0xFF1E293B),
        icon: Icons.flag_outlined,
      ),
    ];

    if (isMobile) {
      return Column(
        children: [
          Row(children: [
            Expanded(child: _buildStatCard(stats[0])),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(stats[1])),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _buildStatCard(stats[2])),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(stats[3])),
          ]),
        ],
      );
    }

    return Row(
      children: stats
          .map((s) => Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.only(right: s == stats.last ? 0 : 10),
                  child: _buildStatCard(s),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildStatCard(_StatInfo s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.label,
            style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2),
          ),
          const SizedBox(height: 4),
          Text(
            s.value,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: s.valueColor,
              letterSpacing: -0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─── TABS ─────────────────────────────────────────────────────────────────

  Widget _buildTabs(bool isMobile) {
    final tabs = _tabs;
    final hasMultipleTabs = tabs.length > 1;

    // Build tab content list matching the same order as _tabs
    final tabContents = [
      _buildTabProyecto(isMobile),
      if (_proyecto.idLicitacion?.isNotEmpty == true ||
          _proyecto.modalidadCompra == 'Licitación Pública')
        _buildTabOcds(isMobile),
      if (_proyecto.urlConvenioMarco?.isNotEmpty == true) _buildTabDetalle(isMobile),
      if (_proyecto.idsOrdenesCompra.isNotEmpty) _buildTabOc(isMobile),
      if (_proyecto.idLicitacion?.isNotEmpty == true) _buildTabAnalisis(isMobile),
      if (_proyecto.idLicitacion?.isNotEmpty == true) _buildTabForo(isMobile),
      _buildTabCertificados(isMobile),
      _buildTabReclamos(isMobile),
    ];

    return Column(
      children: [
        if (hasMultipleTabs) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelStyle: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
              labelColor: _primaryColor,
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: _primaryColor,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: tabs,
            ),
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _tabController,
            builder: (_, __) {
              final idx = _tabController.index.clamp(0, tabContents.length - 1);
              return tabContents[idx];
            },
          ),
        ] else
          _buildTabProyecto(isMobile),
      ],
    );
  }

  // ─── TAB PROYECTO ─────────────────────────────────────────────────────────

  Widget _buildTabProyecto(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _appleSection([
          CampoEditable(
            label: 'INSTITUCIÓN',
            valor: _proyecto.institucion,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Institución',
              valorAnterior: _proyecto.institucion,
              valorNuevo: v,
              data: {'institucion': v},
            ),
          ),
          _sep(),
          CampoEditable(
            label: 'MODALIDAD DE COMPRA',
            valor: _proyecto.modalidadCompra,
            tipo: TipoCampo.opciones,
            opciones: _modalidades,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Modalidad',
              valorAnterior: _proyecto.modalidadCompra,
              valorNuevo: v,
              data: {'modalidadCompra': v},
            ),
          ),
          _sep(),
          CampoEditable(
            label: 'PRODUCTOS / SERVICIOS',
            valor: _proyecto.productos,
            tipo: _productosOpciones.isNotEmpty ? TipoCampo.chips : TipoCampo.texto,
            opciones: _productosOpciones.isNotEmpty ? _productosOpciones : null,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Productos',
              valorAnterior: _proyecto.productos,
              valorNuevo: v,
              data: {'productos': v},
            ),
          ),
          _sep(),
          CampoEditable(
            label: 'VALOR MENSUAL',
            valor: _proyecto.valorMensual != null
                ? _fmt(_proyecto.valorMensual!.toInt())
                : '',
            tipo: TipoCampo.numero,
            prefijo: '\$ ',
            placeholder: 'Agregar valor...',
            onGuardar: (v) {
              final num = double.tryParse(
                      v.replaceAll('.', '').replaceAll(',', '.')) ??
                  0;
              return _editarCampo(
                nombreCampo: 'Valor Mensual',
                valorAnterior:
                    _proyecto.valorMensual?.toString() ?? '',
                valorNuevo: v,
                data: {'valorMensual': num},
              );
            },
          ),
        ]),
        const SizedBox(height: 12),
        _appleSection([
          CampoEditable(
            label: 'FECHA DE INICIO',
            valor: _fmtDate(_proyecto.fechaInicio),
            tipo: TipoCampo.fecha,
            valorFecha: _proyecto.fechaInicio,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Fecha Inicio',
              valorAnterior: _fmtDate(_proyecto.fechaInicio),
              valorNuevo:
                  _fmtDate(v.isNotEmpty ? DateTime.tryParse(v) : null),
              data: {'fechaInicio': v.isNotEmpty ? v : null},
            ),
          ),
          _sep(),
          CampoEditable(
            label: 'FECHA DE TÉRMINO',
            valor: _fmtDate(_proyecto.fechaTermino),
            tipo: TipoCampo.fecha,
            valorFecha: _proyecto.fechaTermino,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Fecha Término',
              valorAnterior: _fmtDate(_proyecto.fechaTermino),
              valorNuevo:
                  _fmtDate(v.isNotEmpty ? DateTime.tryParse(v) : null),
              data: {'fechaTermino': v.isNotEmpty ? v : null},
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _appleSection([
          CampoEditable(
            label: 'RUTA DE IMPLEMENTACIÓN · INICIO',
            valor: _fmtDate(_proyecto.fechaInicioRuta),
            tipo: TipoCampo.fecha,
            valorFecha: _proyecto.fechaInicioRuta,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Fecha Inicio Ruta',
              valorAnterior: _fmtDate(_proyecto.fechaInicioRuta),
              valorNuevo:
                  _fmtDate(v.isNotEmpty ? DateTime.tryParse(v) : null),
              data: {'fechaInicioRuta': v.isNotEmpty ? v : null},
            ),
          ),
          _sep(),
          CampoEditable(
            label: 'RUTA DE IMPLEMENTACIÓN · TÉRMINO',
            valor: _fmtDate(_proyecto.fechaTerminoRuta),
            tipo: TipoCampo.fecha,
            valorFecha: _proyecto.fechaTerminoRuta,
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Fecha Término Ruta',
              valorAnterior: _fmtDate(_proyecto.fechaTerminoRuta),
              valorNuevo:
                  _fmtDate(v.isNotEmpty ? DateTime.tryParse(v) : null),
              data: {'fechaTerminoRuta': v.isNotEmpty ? v : null},
            ),
          ),
        ]),
        if (_proyecto.estadoManual == 'En Evaluación') ...[
          const SizedBox(height: 12),
          _buildPostulacionFechasCard(),
        ],
        if (_proyecto.modalidadCompra == 'Licitación Pública') ...[
          const SizedBox(height: 12),
          _appleSection([
            CampoEditable(
              label: 'ID LICITACIÓN',
              valor: _proyecto.idLicitacion ?? '',
              placeholder: 'Agregar ID...',
              onGuardar: (v) => _editarCampo(
                nombreCampo: 'ID Licitación',
                valorAnterior: _proyecto.idLicitacion ?? '',
                valorNuevo: v,
                data: {'idLicitacion': v},
              ),
            ),
            _sep(),
            _buildDocumentosField(),
            _sep(),
            _buildOcIdField(),
          ]),
        ],
        if (_proyecto.modalidadCompra == 'Convenio Marco') ...[
          const SizedBox(height: 12),
          _appleSection([
            CampoEditable(
              label: 'ID COTIZACIÓN',
              valor: _proyecto.idCotizacion ?? '',
              placeholder: 'Agregar ID cotización...',
              onGuardar: (v) => _editarCampo(
                nombreCampo: 'ID Cotización',
                valorAnterior: _proyecto.idCotizacion ?? '',
                valorNuevo: v,
                data: {'idCotizacion': v},
              ),
            ),
            _sep(),
            CampoEditable(
              label: 'URL CONVENIO MARCO',
              valor: _proyecto.urlConvenioMarco ?? '',
              placeholder: 'https://conveniomarco2.mercadopublico.cl/...',
              onGuardar: (v) async {
                await _editarCampo(
                  nombreCampo: 'URL Convenio Marco',
                  valorAnterior: _proyecto.urlConvenioMarco ?? '',
                  valorNuevo: v,
                  data: {'urlConvenioMarco': v},
                );
                if (v.isNotEmpty && mounted) {
                  await _cargarConvenio(forceRefresh: true);
                  _rebuildTabController();
                }
              },
            ),
            _sep(),
            _buildDocumentosField(),
            _sep(),
            _buildOcIdField(),
          ]),
        ],
        if (_proyecto.modalidadCompra != 'Licitación Pública' &&
            _proyecto.modalidadCompra != 'Convenio Marco') ...[
          const SizedBox(height: 12),
          _appleSection([
            _buildDocumentosField(),
            _sep(),
            _buildOcIdField(),
          ]),
        ],
        const SizedBox(height: 12),
        _appleSection([
          CampoEditable(
            label: 'NOTAS',
            valor: _proyecto.notas ?? '',
            tipo: TipoCampo.multilinea,
            placeholder: 'Agregar observaciones...',
            onGuardar: (v) => _editarCampo(
              nombreCampo: 'Notas',
              valorAnterior: _proyecto.notas ?? '',
              valorNuevo: v,
              data: {'notas': v},
            ),
          ),
        ]),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _mostrarHistorial,
          icon: const Icon(Icons.history_outlined, size: 16),
          label: const Text('Ver historial de cambios'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade500,
            textStyle: GoogleFonts.inter(fontSize: 13),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
        ),
        const SizedBox(height: 24),
        Divider(color: Colors.grey.shade200),
        const SizedBox(height: 8),
        Center(
         child: TextButton.icon(
          onPressed: _borrarProyecto,
          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
          label: Text('Borrar proyecto',
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w500)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            overlayColor: Colors.red.shade50,
          ),
        ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _borrarProyecto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.delete_outline, color: Colors.red.shade400, size: 22),
          const SizedBox(width: 10),
          Text('Borrar proyecto',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_proyecto.institucion,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Esta acción no es reversible. El proyecto y todos sus datos serán eliminados permanentemente.',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade700, height: 1.4)),
              ),
            ]),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('Borrar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/eliminarProyecto'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id': _proyecto.id}),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Proyecto eliminado', style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: ${resp.statusCode}', style: GoogleFonts.inter()),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: GoogleFonts.inter()),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  // ─── OC IDS FIELD ─────────────────────────────────────────────────────────

  Widget _buildOcIdField() {
    final ids = _proyecto.idsOrdenesCompra;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ÓRDENES DE COMPRA',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          if (ids.isEmpty)
            Text('Sin órdenes de compra', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300)),
          ...ids.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: Text(e.value,
                    style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500)),
              ),
              InkWell(
                onTap: () => _eliminarOc(e.value),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                ),
              ),
            ]),
          )),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _mostrarPopupBuscarOC(context,
                useAward: _proyecto.modalidadCompra == 'Trato Directo' ||
                    _proyecto.modalidadCompra == 'Convenio Marco'),
            borderRadius: BorderRadius.circular(8),
            child: Row(children: [
              Icon(Icons.add, size: 14, color: _primaryColor.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text('Agregar OC', style: GoogleFonts.inter(fontSize: 13, color: _primaryColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarOc(String id) async {
    final newList = List<String>.from(_proyecto.idsOrdenesCompra)..remove(id);
    await _editarCampo(
      nombreCampo: 'Orden de Compra',
      valorAnterior: id,
      valorNuevo: '',
      data: {'idsOrdenesCompra': newList},
    );
    setState(() {
      final idx = _proyecto.idsOrdenesCompra.indexOf(id);
      if (idx >= 0 && idx < _ocDataList.length) _ocDataList.removeAt(idx);
    });
    _rebuildTabController();
  }

  // ─── DOCUMENTOS FIELD ─────────────────────────────────────────────────────

  Widget _buildDocumentosField() {
    final docs = _proyecto.documentos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DOCUMENTOS',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          if (docs.isEmpty)
            Text('Sin documentos adjuntos', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300)),
          ...docs.asMap().entries.map((e) {
            final doc = e.value;
            final label = doc.nombre ?? _fileNameFromUrl(doc.url);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(doc.tipo,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _abrirDocumento(doc.url, label),
                    borderRadius: BorderRadius.circular(4),
                    child: Row(children: [
                      Icon(Icons.attach_file, size: 12, color: _primaryColor.withValues(alpha: 0.6)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(label,
                            style: GoogleFonts.inter(fontSize: 13, color: _primaryColor, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ),
                ),
                InkWell(
                  onTap: () => _eliminarDocumento(e.key),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _mostrarPopupAgregarDocumento(context),
            borderRadius: BorderRadius.circular(8),
            child: Row(children: [
              Icon(Icons.add, size: 14, color: _primaryColor.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text('Cargar archivo', style: GoogleFonts.inter(fontSize: 13, color: _primaryColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarDocumento(int index) async {
    final newList = List.from(_proyecto.documentos)..removeAt(index);
    await _editarCampo(
      nombreCampo: 'Documento',
      valorAnterior: _proyecto.documentos[index].url,
      valorNuevo: '',
      data: {'documentos': newList.map((d) => d.toJson()).toList()},
    );
  }

  Future<void> _mostrarPopupAgregarDocumento(BuildContext context) async {
    final tipos = _tiposDocumento.isNotEmpty ? _tiposDocumento : ['Contrato', 'Orden de Compra', 'Acta', 'Otro'];
    String? tipoSel = tipos.first;
    PickedFile? picked;
    bool uploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Cargar archivo',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TIPO DE DOCUMENTO',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: tipoSel,
                  items: tipos.map((t) => DropdownMenuItem(value: t,
                      child: Text(t, style: GoogleFonts.inter(fontSize: 14)))).toList(),
                  onChanged: uploading ? null : (v) => setS(() => tipoSel = v),
                  decoration: InputDecoration(
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('ARCHIVO',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                if (picked == null)
                  OutlinedButton.icon(
                    onPressed: uploading ? null : () async {
                      final file = await UploadService.instance.pickFile();
                      if (file != null) setS(() => picked = file);
                    },
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: Text('Seleccionar archivo',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.insert_drive_file_outlined, size: 16,
                          color: _primaryColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(picked!.name,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (!uploading)
                        InkWell(
                          onTap: () => setS(() => picked = null),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                          ),
                        ),
                    ]),
                  ),
                if (uploading) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor)),
                    const SizedBox(width: 8),
                    Text('Subiendo archivo…',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: (picked == null || uploading) ? null : () async {
                setS(() => uploading = true);
                try {
                  final url = await UploadService.instance.upload(
                    bytes: picked!.bytes,
                    filename: picked!.name,
                    storagePath: 'proyectos/${_proyecto.id}/documentos',
                  );
                  final newDoc = DocumentoProyecto(tipo: tipoSel!, url: url, nombre: picked!.name);
                  final newList = [..._proyecto.documentos, newDoc];
                  if (ctx.mounted) Navigator.pop(ctx);
                  _editarCampo(
                    nombreCampo: 'Documento',
                    valorAnterior: '',
                    valorNuevo: '${newDoc.tipo}: ${newDoc.nombre ?? newDoc.url}',
                    data: {'documentos': newList.map((d) => d.toJson()).toList()},
                  );
                } catch (e) {
                  if (ctx.mounted) {
                    setS(() => uploading = false);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Error al subir archivo: $e'),
                      backgroundColor: Colors.red.shade700,
                    ));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: uploading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Cargar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarPopupBuscarOC(BuildContext context, {bool useAward = false}) async {
    final ctrl = TextEditingController();
    Map<String, dynamic>? preview;
    bool buscando = false;
    String? errorBusqueda;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> buscar() async {
              final id = ctrl.text.trim();
              if (id.isEmpty) return;
              setS(() { buscando = true; errorBusqueda = null; preview = null; });
              try {
                final Uri uri;
                if (useAward) {
                  uri = Uri.parse('$_baseUrl/buscarLicitacionPorId?id=${Uri.encodeComponent(id)}&type=award');
                } else {
                  uri = Uri.parse('$_baseUrl/buscarOrdenCompra?id=${Uri.encodeComponent(id)}');
                }
                final resp = await http.get(uri).timeout(const Duration(seconds: 25));
                if (resp.statusCode == 200) {
                  final data = json.decode(resp.body);
                  // Normalizar OCDS award → mismo formato que OC para el preview
                  Map<String, dynamic> parsed = data is Map<String, dynamic> ? data : {};
                  if (useAward) {
                    try {
                      final releases = data['releases'] as List?;
                      if (releases != null && releases.isNotEmpty) {
                        final release = releases[0] as Map<String, dynamic>;
                        final awards = release['awards'] as List?;
                        final award = (awards != null && awards.isNotEmpty)
                            ? awards[0] as Map<String, dynamic>
                            : <String, dynamic>{};
                        final suppliers = award['suppliers'] as List?;
                        parsed = {
                          'Nombre': award['title'] ?? release['tender']?['title'] ?? id,
                          'Proveedor': {'Nombre': suppliers?.isNotEmpty == true ? suppliers![0]['name'] : ''},
                          'Total': award['value']?['amount'],
                          '_moneda': award['value']?['currency'] ?? '',
                          'Estado': award['status'] ?? '',
                          'Fechas': {'FechaCreacion': award['date'] ?? ''},
                        };
                      }
                    } catch (_) {}
                  }
                  setS(() { preview = parsed; buscando = false; });
                } else {
                  String msg;
                  try { msg = json.decode(resp.body)['error']?.toString() ?? 'Error ${resp.statusCode}'; }
                  catch (_) { msg = 'Error ${resp.statusCode}'; }
                  setS(() { errorBusqueda = msg; buscando = false; });
                }
              } catch (e) {
                setS(() { errorBusqueda = e.toString(); buscando = false; });
              }
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('ID Orden de Compra',
                  style: GoogleFonts.inter(
                      fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              hintText: 'Ej: 2097-241-SE14',
                              hintStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.grey.shade300),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                            ),
                            style: GoogleFonts.inter(fontSize: 14),
                            onSubmitted: (_) => buscar(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: buscando ? null : buscar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: buscando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : Text('Buscar',
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (errorBusqueda != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 14, color: Color(0xFFDC2626)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(errorBusqueda!,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFFDC2626))),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (preview != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _bgColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (preview!['Nombre'] != null)
                              Text(
                                preview!['Nombre'].toString(),
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1E293B)),
                              ),
                            const SizedBox(height: 6),
                            if (preview!['Proveedor']?['Nombre'] != null)
                              _ocPreviewRow('Proveedor',
                                  preview!['Proveedor']['Nombre'].toString()),
                            if (preview!['Total'] != null)
                              _ocPreviewRow('Monto Total',
                                  preview!['_moneda'] != null && preview!['_moneda'].toString().isNotEmpty && preview!['_moneda'] != 'CLP'
                                      ? '${_fmt((preview!['Total'] as num).toDouble().round())} ${preview!['_moneda']}'
                                      : '\$ ${_fmt((preview!['Total'] as num).toInt())}'),
                            if (preview!['Estado'] != null)
                              _ocPreviewRow('Estado', preview!['Estado'].toString()),
                            if (preview!['Fechas']?['FechaCreacion'] != null)
                              _ocPreviewRow('Fecha Creación',
                                  _fmtDateStr(preview!['Fechas']['FechaCreacion'].toString())),
                          ],
                        ),
                      ),
                    ],
                  ],
                )),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancelar',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: Colors.grey.shade500)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newId = ctrl.text.trim();
                    if (newId.isEmpty) { Navigator.of(ctx).pop(); return; }
                    final newList = [..._proyecto.idsOrdenesCompra, newId];
                    Navigator.of(ctx).pop();
                    await _editarCampo(
                      nombreCampo: 'Orden de Compra',
                      valorAnterior: '',
                      valorNuevo: newId,
                      data: {'idsOrdenesCompra': newList},
                    );
                    if (mounted) {
                      await _cargarOc();
                      _rebuildTabController();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Guardar',
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _ocPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.inter(
                fontSize: 12, color: Colors.grey.shade500),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF1E293B),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB OCDS ─────────────────────────────────────────────────────────────

  Future<void> _reintentarOcds() async {
    ProyectosService.instance.invalidate();
    final proyectos = await ProyectosService.instance.load(forceRefresh: true);
    final updated = proyectos.where((p) => p.id == _proyecto.id).firstOrNull;
    if (updated != null && mounted) {
      setState(() => _proyecto = updated);
      if (updated.idLicitacion?.isNotEmpty == true) {
        _rebuildTabController();
        _cargarOcds();
      }
    }
  }

  // ── Sección MP API (fallback cuando OCDS no está disponible) ────────────

  Widget _buildMpApiSection(Map<String, dynamic> data, bool isMobile) {
    final listado =
        (data['Listado'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (listado.isEmpty) {
      return Center(
        child: Text('Sin datos de API Mercado Público',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
      );
    }
    final item = listado.first;
    final comprador = item['Comprador'] as Map<String, dynamic>? ?? {};
    final fechas = item['Fechas'] as Map<String, dynamic>? ?? {};

    String fmtIso(String? iso) {
      if (iso == null || iso.isEmpty) return '—';
      final d = DateTime.tryParse(iso);
      if (d == null) return '—';
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    Widget infoCard(String title, List<(String, String?)> rows) {
      final visible = rows.where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();
      if (visible.isEmpty) return const SizedBox();
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(title,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B))),
          ),
          const Divider(height: 1),
          ...visible.map((r) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 160,
                    child: Text(r.$1,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ),
                  Expanded(
                    child: Text(r.$2!,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E293B))),
                  ),
                ]),
              )),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Aviso fuente
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 15, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Datos de API Mercado Público — OCDS aún no disponible para esta licitación.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E)),
              ),
            ),
          ]),
        ),
        infoCard('Licitación', [
          ('Nombre', item['Nombre']?.toString()),
          ('Código', item['CodigoExterno']?.toString()),
          ('Estado', item['Estado']?.toString()),
          ('Tipo', item['Tipo']?.toString()),
          ('Monto estimado', item['MontoEstimado'] != null
              ? '${item['MontoEstimado']} ${item['Moneda'] ?? ''}'
              : null),
          ('Duración', item['Tiempo'] != null
              ? '${item['Tiempo']} ${item['UnidadTiempo']?.toString() == '2' ? 'meses' : 'días'}'
              : null),
        ]),
        infoCard('Comprador', [
          ('Organismo', comprador['NombreOrganismo']?.toString()),
          ('Dirección', comprador['DireccionUnidad']?.toString()),
          ('Comuna', comprador['ComunaUnidad']?.toString()),
          ('Región', comprador['RegionUnidad']?.toString()),
        ]),
        infoCard('Fechas', [
          ('Publicación', fmtIso(fechas['FechaPublicacion']?.toString())),
          ('Inicio', fmtIso(fechas['FechaInicio']?.toString())),
          ('Cierre', fmtIso(fechas['FechaCierre']?.toString())),
          ('Apertura Técnica', fmtIso(fechas['FechaActoAperturaTecnica']?.toString())),
          ('Apertura Económica', fmtIso(fechas['FechaActoAperturaEconomica']?.toString())),
          ('Adjudicación (est.)', fmtIso(fechas['FechaEstimadaAdjudicacion']?.toString())),
          ('Firma (est.)', fmtIso(fechas['FechaEstimadaFirma']?.toString())),
        ]),
        Center(
          child: TextButton.icon(
            onPressed: () => _cargarOcds(forceRefresh: true),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text('Buscar OCDS', style: GoogleFonts.inter()),
          ),
        ),
      ]),
    );
  }

  Widget _buildTabOcds(bool isMobile) {
    if (_proyecto.idLicitacion?.isNotEmpty != true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sync_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Sin ID de licitación registrado',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            const SizedBox(height: 4),
            Text(
              'Edita el proyecto y agrega el ID\npara cargar los datos OCDS.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _reintentarOcds,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Actualizar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }
    if (_cargandoOcds) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator()));
    }
    if (_errorOcds != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline,
                size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(_errorOcds!,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _cargarOcds(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reintentar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }
    if (_ocdsData == null) {
      if (_mpApiData != null) return _buildMpApiSection(_mpApiData!, isMobile);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('No se pudieron cargar los datos',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _cargarOcds(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reintentar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }

    final releases =
        (_ocdsData!['releases'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    if (releases.isEmpty) {
      if (_mpApiData != null) return _buildMpApiSection(_mpApiData!, isMobile);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Sin datos OCDS',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _cargarOcds(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reintentar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }

    final last = releases.last;
    final bidRelease = releases.lastWhere(
      (r) {
        final bids = r['bids']?['details'] as List?;
        return bids != null && bids.isNotEmpty;
      },
      orElse: () => <String, dynamic>{},
    );

    final tender =
        last['tender'] as Map<String, dynamic>? ?? {};
    final buyer = (last['parties'] as List?)
        ?.cast<Map<String, dynamic>>()
        .firstWhere(
            (p) => (p['roles'] as List?)?.contains('buyer') == true,
            orElse: () => {});
    final bids =
        (bidRelease['bids']?['details'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
    // Fallback: tender.tenderers when bids.details is empty
    final tenderers = bids.isEmpty
        ? ((tender['tenderers'] as List?)?.cast<Map<String, dynamic>>() ?? [])
        : <Map<String, dynamic>>[];
    final items =
        (tender['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _refreshBar(_ocdsLastFetch, () => _cargarOcds(forceRefresh: true), loading: _cargandoOcds),
        const SizedBox(height: 12),
        _ocdsHero(tender),
        const SizedBox(height: 16),
        if (buyer != null && buyer.isNotEmpty) ...[
          _sectionLabel('ENTIDAD COMPRADORA'),
          _buyerCard(buyer),
          const SizedBox(height: 16),
        ],
        _sectionLabel('PLAZOS'),
        _plazosCard(tender),
        const SizedBox(height: 16),
        if (items.isNotEmpty) ...[
          _sectionLabel('ÍTEMS LICITADOS'),
          ...items.asMap().entries
              .map((e) => _itemCard(e.value, e.key + 1, e.key < items.length - 1)),
          const SizedBox(height: 16),
        ],
        if (bids.isNotEmpty) ...[
          _sectionLabel('OFERTAS RECIBIDAS'),
          ...bids.asMap().entries.map((e) => _ofertaCard(e.value, e.key + 1)),
        ],
        if (tenderers.isNotEmpty) ...[
          _sectionLabel('OFERENTES (${tenderers.length})'),
          _tenderersCard(tenderers),
        ],
      ],
    );
  }

  // ─── TAB DETALLE (CONVENIO MARCO) ─────────────────────────────────────────

  Widget _buildTabDetalle(bool isMobile) {
    final url = _proyecto.urlConvenioMarco!;

    if (_cargandoConvenio && _convenioData == null) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator()));
    }
    if (_errorConvenio != null && _convenioData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(_errorConvenio!,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _cargarConvenio(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reintentar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }

    final data = _convenioData;
    final id = _extractCmId(url);
    final tituloRaw = data?['titulo']?.toString() ?? '';
    final titulo = tituloRaw.startsWith('UNIDAD DE COMPRA: ')
        ? tituloRaw.substring('UNIDAD DE COMPRA: '.length)
        : tituloRaw;
    final comprador = data?['comprador']?.toString() ?? '';
    final convenioMarco = data?['convenioMarco']?.toString() ?? '';
    final estado = data?['estado']?.toString() ?? '';
    final campos = (data?['campos'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((c) => (c['label']?.toString().isNotEmpty == true) &&
                (c['valor']?.toString().isNotEmpty == true))
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _refreshBar(_convenioLastFetch, () => _cargarConvenio(forceRefresh: true), loading: _cargandoConvenio),
        const SizedBox(height: 12),

        // Hero card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('CM: $id',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 10),
              Text(
                titulo.isNotEmpty ? titulo : 'Convenio Marco',
                style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3),
              ),
              if (estado.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(estado,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.75))),
              ],
              if (convenioMarco.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.folder_outlined,
                      size: 12, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(convenioMarco,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7))),
                  ),
                ]),
              ],
            ],
          ),
        ),

        if (comprador.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel('ENTIDAD COMPRADORA'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.account_balance_outlined,
                      size: 20, color: _primaryColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(comprador,
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E293B))),
                ),
              ],
            ),
          ),
        ],

        if (campos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel('INFORMACIÓN'),
          Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: campos.asMap().entries.map((e) {
                final campo = e.value;
                final isLast = e.key == campos.length - 1;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              campo['label']?.toString() ?? '',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              campo['valor']?.toString() ?? '',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF1E293B),
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ]),
                  ),
                  if (!isLast)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ]);
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 16),
        // Open in browser button
        InkWell(
          onTap: () => web.window.open(url, '_blank'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _primaryColor.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.open_in_new, size: 16, color: _primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(url,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _primaryColor,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _ocdsHero(Map<String, dynamic> tender) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tender['statusDetails'] != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tender['statusDetails'].toString(),
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            tender['title']?.toString() ?? '',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          if (tender['description'] != null) ...[
            const SizedBox(height: 8),
            Text(
              tender['description'].toString(),
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (tender['procurementMethodDetails'] != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.label_outline,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
              Text(
                tender['procurementMethodDetails'].toString(),
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buyerCard(Map<String, dynamic> buyer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_outlined,
                size: 20, color: _primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cleanName(buyer['name']?.toString()),
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B)),
                ),
                if (buyer['identifier']?['id'] != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'RUT ${buyer['identifier']['id']}',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
                if (buyer['address'] != null) ...[
                  const SizedBox(height: 8),
                  _buyerRow(Icons.location_on_outlined,
                      buyer['address']?['streetAddress']?.toString()),
                  if (buyer['address']?['region'] != null)
                    _buyerRow(Icons.map_outlined,
                        buyer['address']?['region']?.toString()),
                ],
                if (buyer['contactPoint']?['name'] != null) ...[
                  const SizedBox(height: 4),
                  _buyerRow(Icons.person_outline,
                      buyer['contactPoint']['name'].toString()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buyerRow(IconData icon, String? text) {
    if (text == null || text.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade400),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }

  Widget _plazosCard(Map<String, dynamic> tender) {
    final plazos = <_PlazoInfo>[];

    final tp = tender['tenderPeriod'];
    if (tp != null) {
      plazos.add(_PlazoInfo('Publicación', _fmtDateStr(tp['startDate']?.toString()), Icons.event_outlined));
      plazos.add(_PlazoInfo('Cierre recepción', _fmtDateStr(tp['endDate']?.toString()), Icons.lock_outline));
    }
    final eq = tender['enquiryPeriod'];
    if (eq != null) {
      plazos.add(_PlazoInfo('Consultas', '${_fmtDateStr(eq['startDate']?.toString())} – ${_fmtDateStr(eq['endDate']?.toString())}', Icons.help_outline));
    }
    final ap = tender['awardPeriod'];
    if (ap != null) {
      plazos.add(_PlazoInfo('Adjudicación', '${_fmtDateStr(ap['startDate']?.toString())} – ${_fmtDateStr(ap['endDate']?.toString())}', Icons.gavel));
    }

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: plazos.asMap().entries.map((e) {
          final p = e.value;
          final isLast = e.key == plazos.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: _bgColor,
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(p.icon,
                          size: 16, color: _primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label,
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2)),
                          const SizedBox(height: 2),
                          Text(p.value,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: const Color(0xFF1E293B),
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(height: 1, indent: 60, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _itemCard(
      Map<String, dynamic> item, int numero, bool showDivider) {
    return Container(
      margin: EdgeInsets.only(bottom: showDivider ? 0 : 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: showDivider
            ? const Border(
                bottom:
                    BorderSide(color: Color(0xFFF2F2F7), width: 1))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                child: Text('$numero',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _primaryColor)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['description']?.toString() ?? '',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF1E293B),
                        height: 1.4),
                  ),
                  if (item['classification']?['id'] != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'UNSPSC ${item['classification']['id']}',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              color: _primaryColor,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (item['quantity'] != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${item['quantity']} ${item['unit']?['name'] ?? ''}',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade400),
                        ),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tenderersCard(List<Map<String, dynamic>> tenderers) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Montos de ofertas no disponibles vía OCDS',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
              )),
            ]),
          ),
          const Divider(height: 1),
          ...tenderers.asMap().entries.map((e) {
            final t = e.value;
            final nombre = _cleanName(t['name']?.toString());
            final id = t['id']?.toString() ?? '';
            final isLast = e.key == tenderers.length - 1;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(7)),
                    child: Center(child: Text('${e.key + 1}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _primaryColor))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                    if (id.isNotEmpty)
                      Text(id, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
                  ])),
                ]),
              ),
              if (!isLast) const Divider(height: 1, indent: 56, endIndent: 16),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _ofertaCard(Map<String, dynamic> bid, int numero) {
    final tenderer = (bid['tenderers'] as List?)
        ?.cast<Map<String, dynamic>>()
        .firstOrNull;
    final nombre = _cleanName(tenderer?['name']?.toString());
    final amount = bid['value']?['amount'];
    final currency = bid['value']?['currency'] ?? 'CLP';
    final estado = bid['status']?.toString() ?? '';
    final fecha = _fmtDateStr(bid['date']?.toString());
    final isGanadora = estado == 'valid' && numero == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isGanadora
            ? Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isGanadora
                      ? const Color(0xFFDCFCE7)
                      : _bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$numero',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isGanadora
                          ? const Color(0xFF16A34A)
                          : _primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nombre.isNotEmpty ? nombre : 'Oferente $numero',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              _estadoOfertaBadge(estado),
            ],
          ),
          if (amount != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(
                    'Monto oferta',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade400),
                  ),
                  const Spacer(),
                  Text(
                    '\$ ${_fmt((amount as num).toInt())} $currency',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _primaryColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.calendar_today_outlined,
                size: 12, color: Colors.grey.shade300),
            const SizedBox(width: 5),
            Text(fecha,
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey.shade400)),
          ]),
        ],
      ),
    );
  }

  Widget _estadoOfertaBadge(String estado) {
    Color bg, fg;
    String label;
    switch (estado) {
      case 'valid':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        label = 'Válida';
        break;
      case 'disqualified':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        label = 'Descalificada';
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = Colors.grey.shade500;
        label = estado;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  // ─── TAB ORDEN DE COMPRA ──────────────────────────────────────────────────

  Widget _buildTabOc(bool isMobile) {
    // Skeleton when nothing loaded yet
    if (_cargandoOc && _ocDataList.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _OcSkeletonCard(height: 90),
          const SizedBox(height: 12),
          _OcSkeletonCard(height: 200),
          const SizedBox(height: 12),
          _OcSkeletonCard(height: 200),
        ]),
      );
    }
    if (_errorOc != null && _ocDataList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline,
                size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(_errorOc!,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _cargarOc,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reintentar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }
    if (_ocDataList.isEmpty && !_cargandoOc) {
      return Center(
          child: Text('Sin datos de Orden de Compra',
              style: GoogleFonts.inter(color: Colors.grey.shade500)));
    }

    final ocsLoaded = _ocDataList.whereType<Map<String, dynamic>>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ocsLoaded.length > 1) ...[
          _ocResumenCard(ocsLoaded),
          const SizedBox(height: 12),
        ],
        for (int i = 0; i < _proyecto.idsOrdenesCompra.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          if (i < _ocDataList.length)
            _ocDataList[i] != null
              ? _buildOcSection(_ocDataList[i]!, _proyecto.idsOrdenesCompra[i])
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Expanded(child: Text('No se pudo cargar OC ${_proyecto.idsOrdenesCompra[i]}',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400))),
                    TextButton.icon(
                      onPressed: () => _recargarUnaOc(_proyecto.idsOrdenesCompra[i]),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: Text('Reintentar', style: GoogleFonts.inter(fontSize: 12)),
                    ),
                  ]),
                )
          else if (_cargandoOc)
            _OcSkeletonCard(height: 200),
        ],
      ],
    );
  }

  Widget _ocMontoRow({
    required String label,
    required String valor,
    required bool esTotal,
    Widget? labelSuffix,
    Color? colorTotal,
  }) {
    final totalColor = colorTotal ?? _primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: GoogleFonts.inter(
              fontSize: esTotal ? 13 : 12,
              fontWeight: esTotal ? FontWeight.w600 : FontWeight.w400,
              color: esTotal ? const Color(0xFF1E293B) : Colors.grey.shade500,
            )),
        if (labelSuffix != null) ...[const SizedBox(width: 6), labelSuffix],
        const Spacer(),
        Text(valor,
            style: GoogleFonts.inter(
              fontSize: esTotal ? 15 : 13,
              fontWeight: esTotal ? FontWeight.w800 : FontWeight.w500,
              color: esTotal ? totalColor : const Color(0xFF1E293B),
            )),
      ]),
    );
  }

  Color _ocEstadoColor(String estado) {
    final e = estado.toLowerCase();
    if (e.contains('acept')) return const Color(0xFF16A34A);
    if (e.contains('recep') || e.contains('conforme')) return const Color(0xFF0369A1);
    if (e.contains('rechaz') || e.contains('cancel')) return const Color(0xFFDC2626);
    if (e.contains('pend') || e.contains('enviad')) return const Color(0xFFD97706);
    return Colors.grey.shade500;
  }

  Widget _ocResumenCard(List<Map<String, dynamic>> ocs) {
    // Sumar solo CLP directos + UF ya convertidas a CLP (campo _totalCLP)
    // Si existe montoTotalOC guardado (ya convertido), usarlo directamente
    final totalAcum = _proyecto.montoTotalOC ?? ocs.fold<double>(0, (s, oc) {
      final ocId = oc['Codigo']?.toString();
      final moneda = _detectarMoneda(oc, ocId: ocId);
      if (moneda == 'UF') {
        // Usar valor CLP ya convertido si disponible, si no omitir del total
        return s + ((oc['_totalCLP'] as num?)?.toDouble() ?? 0);
      }
      return s + ((oc['Total'] as num?)?.toDouble() ?? 0);
    });
    final estadoCount = <String, int>{};
    for (final oc in ocs) {
      final e = oc['Estado']?.toString() ?? 'Desconocido';
      estadoCount[e] = (estadoCount[e] ?? 0) + 1;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TOTAL ACUMULADO', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 3),
            Text('\$ ${_fmt(totalAcum.toInt())}',
                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _primaryColor, letterSpacing: -0.5)),
            Text('Solo CLP · UF incluida como valor convertido',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(10)),
            child: Text('${ocs.length} OC${ocs.length != 1 ? 's' : ''}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _primaryColor)),
          ),
        ]),
        if (estadoCount.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: estadoCount.entries.map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _ocEstadoColor(e.key), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('${e.value}× ${e.key}', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
          ])).toList()),
        ],
      ]),
    );
  }

  Widget _buildOcSection(Map<String, dynamic> oc, String ocId) {
    final proveedor = oc['Proveedor'] as Map<String, dynamic>? ?? {};
    final items = (oc['Items']?['Listado'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final fechas = oc['Fechas'] as Map<String, dynamic>? ?? {};
    final estado = oc['Estado']?.toString() ?? '';
    final codigo = oc['Codigo']?.toString() ?? '';
    final nombre = oc['Nombre']?.toString() ?? '';
    final total = oc['Total'];
    final neto = oc['TotalNeto'];
    final pctIva = oc['PorcentajeIva'];
    final impuestos = oc['Impuestos'];
    final financiamiento = oc['Financiamiento']?.toString() ?? '';
    final moneda = _detectarMoneda(oc, ocId: ocId);
    final esUF = moneda == 'UF';
    final ufDia = esUF ? (oc['_ufValueDia'] as num?)?.toDouble() : null;
    final totalCLP = esUF ? (oc['_totalCLP'] as num?)?.toDouble() : null;

    final fechaEnvioVal = fechas['FechaEnvio'] != null
        ? _fmtDateStr(fechas['FechaEnvio'].toString()) : null;
    final fechaAceptVal = fechas['FechaAceptacion'] != null
        ? _fmtDateStr(fechas['FechaAceptacion'].toString()) : null;

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Refresh bar
        Container(
          color: _bgColor.withValues(alpha: 0.6),
          child: _refreshBar(_ocLastFetchMap[ocId], () => _recargarUnaOc(ocId), loading: _cargandoOc),
        ),

        // Header: código + estado
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(children: [
            Text(codigo, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (estado.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _ocEstadoColor(estado).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _ocEstadoColor(estado).withValues(alpha: 0.3)),
                ),
                child: Text(estado, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _ocEstadoColor(estado))),
              ),
          ]),
        ),

        // Nombre
        if (nombre.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(nombre, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B), letterSpacing: -0.2)),
          ),

        const SizedBox(height: 16),
        const Divider(height: 1),

        // Proveedor
        if (proveedor.isNotEmpty)
          LayoutBuilder(builder: (ctx, box) {
            Widget dateCol(String label, String val) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(val, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600)),
              ],
            );

            final narrow = box.maxWidth < 380;

            Widget? datesWidget;
            if (fechaEnvioVal != null && fechaAceptVal != null) {
              datesWidget = narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      dateCol('Envío', fechaEnvioVal),
                      const SizedBox(height: 8),
                      dateCol('Aceptación', fechaAceptVal),
                    ])
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      dateCol('Envío', fechaEnvioVal),
                      const SizedBox(width: 16),
                      dateCol('Aceptación', fechaAceptVal),
                    ]);
            } else if (fechaEnvioVal != null) {
              datesWidget = dateCol('Envío', fechaEnvioVal);
            } else if (fechaAceptVal != null) {
              datesWidget = dateCol('Aceptación', fechaAceptVal);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.business_outlined, size: 16, color: _primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(proveedor['Nombre']?.toString() ?? '',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                  if (proveedor['RutSucursal'] != null)
                    Text('RUT ${proveedor['RutSucursal']}',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
                ])),
                if (datesWidget != null) ...[
                  const SizedBox(width: 12),
                  datesWidget,
                ],
              ]),
            );
          }),

        const Divider(height: 1),

        // Montos — layout contable: label izquierda, valor derecha, apilados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(children: [
            if (neto != null) _ocMontoRow(
              label: 'Neto',
              valor: esUF ? '${(neto as num).toStringAsFixed(2)} UF' : '\$ ${_fmt((neto as num).toInt())}',
              esTotal: false,
            ),
            if (impuestos != null) _ocMontoRow(
              label: pctIva != null ? 'IVA ${(pctIva as num).toInt()}%' : 'Impuesto',
              valor: esUF ? '${(impuestos as num).toStringAsFixed(2)} UF' : '\$ ${_fmt((impuestos as num).toInt())}',
              esTotal: false,
            ),
            if (neto != null || impuestos != null)
              Divider(height: 12, color: Colors.grey.shade100),
            if (total != null) _ocMontoRow(
              label: esUF ? 'Total  ' : 'Total',
              labelSuffix: esUF
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('UF', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFB45309))),
                    )
                  : null,
              valor: esUF ? '${(total as num).toStringAsFixed(2)} UF' : '\$ ${_fmt((total as num).toInt())}',
              esTotal: true,
            ),
            if (esUF && totalCLP != null) ...[
              const SizedBox(height: 6),
              _ocMontoRow(
                label: 'Total CLP',
                labelSuffix: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('≈', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                ),
                valor: '\$ ${_fmt(totalCLP.toInt())}',
                esTotal: true,
                colorTotal: Colors.green.shade700,
              ),
            ],
            if (esUF && ufDia != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Spacer(),
                  Text('UF al día de emisión: \$ ${_fmt(ufDia.toInt())}',
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                ]),
              ),
          ]),
        ),

        if (financiamiento.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              Text('Financiamiento', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
              const SizedBox(width: 12),
              Expanded(child: Text(financiamiento, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500))),
            ]),
          ),
        ],

        // Ítems compactos
        if (items.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ÍTEMS', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 10),
              ...items.asMap().entries.map((e) {
                final item = e.value;
                final nombreItem = item['Producto']?.toString() ?? '';
                final desc = item['EspecificacionProveedor']?.toString().isNotEmpty == true
                    ? item['EspecificacionProveedor'].toString()
                    : item['EspecificacionComprador']?.toString() ?? '';
                final totalItem = item['Total'];
                return Padding(
                  padding: EdgeInsets.only(bottom: e.key < items.length - 1 ? 12 : 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 22, height: 22, decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(6)),
                        child: Center(child: Text('${e.key + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _primaryColor)))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (nombreItem.isNotEmpty) Text(nombreItem, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                      if (desc.isNotEmpty && desc != nombreItem) ...[
                        const SizedBox(height: 2),
                        Text(desc, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500, height: 1.35), maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ])),
                    if (totalItem != null) ...[
                      const SizedBox(width: 10),
                      Text('\$ ${_fmt((totalItem as num).toInt())}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _primaryColor)),
                    ],
                  ]),
                );
              }),
            ]),
          ),
        ],

        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildHistorialItem(Map<String, dynamic> item) {
    final campo = item['campo']?.toString() ?? '';
    final antes = item['valorAnterior']?.toString() ?? '—';
    final despues = item['valorNuevo']?.toString() ?? '—';
    final fechaStr = item['fecha']?.toString();
    final fecha =
        fechaStr != null ? DateTime.tryParse(fechaStr) : null;

    final antesVacio = antes.isEmpty || antes == '—';
    final despuesVacio = despues.isEmpty || despues == '—';
    final String accion;
    final Color accionColor;
    if (antesVacio && !despuesVacio) {
      accion = 'Se agrega';
      accionColor = const Color(0xFF059669);
    } else if (!antesVacio && despuesVacio) {
      accion = 'Se elimina';
      accionColor = const Color(0xFFDC2626);
    } else {
      accion = 'Se modifica';
      accionColor = const Color(0xFF0EA5E9);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(campo,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(accion,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: accionColor)),
              ]),
            ),
            if (fecha != null)
              Text(_fmtHistorialFecha(fecha),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Expanded(
                child: Text(antes,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                        decoration: TextDecoration.lineThrough),
                    overflow: TextOverflow.ellipsis),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward,
                    size: 12, color: Colors.grey.shade300),
              ),
              Expanded(
                child: Text(despues,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _fmtHistorialFecha(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year &&
        d.month == now.month &&
        d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  // ─── TAB CERTIFICADOS ─────────────────────────────────────────────────────

  String _genId() => DateTime.now().millisecondsSinceEpoch.toString();

  // ─── TAB ANÁLISIS ──────────────────────────────────────────────────────────

  void _abrirFichaProveedor(BuildContext context, String rut, String nombre) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FichaProveedorSheet(rut: rut, nombre: nombre),
    );
  }

  void _abrirFichaOrganismo(BuildContext context, String rut, String nombre) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FichaOrganismoSheet(rut: rut, nombre: nombre),
    );
  }

  Future<void> _cargarAnalisis({bool forceRefresh = false}) async {
    if (_analisisCargando) return;
    if (mounted) setState(() { _analisisCargando = true; _analisisError = null; });

    final idLic = _proyecto.idLicitacion!;
    final db = FirebaseFirestore.instance;
    final cacheDoc = db.collection('analisis_licitacion').doc(idLic);

    try {
      // ── Fast path: leer desde Firestore caché ──────────────────────────────
      if (!forceRefresh) {
        final snap = await cacheDoc.get();
        if (snap.exists) {
          final d = snap.data()!;
          final fetchedAt = (d['fetchedAt'] as Timestamp?)?.toDate();
          final age = fetchedAt != null ? DateTime.now().difference(fetchedAt) : null;
          if (age != null && age.inDays < 7) {
            _aplicarAnalisis(d);
            return;
          }
        }
      }

      // ── Consulta BigQuery (primera vez o refresco) ─────────────────────────
      final bq = BigQueryService.instance;
      final results = await Future.wait([
        bq.obtenerCompetidoresLicitacion(idLic),
        bq.obtenerGanadorLicitacion(idLic),
      ]);
      final competidores = results[0];
      final ganadorOcs   = results[1];

      String? rutGanador, nombreGanador, rutOrganismo;
      if (ganadorOcs.isNotEmpty) {
        final p = ganadorOcs.first;
        rutGanador    = p['rut_proveedor']?.toString();
        nombreGanador = p['NombreProveedor']?.toString();
        rutOrganismo  = p['RutUnidadCompra']?.toString();
      }

      List<Map<String, dynamic>> historialOcs = [], permanencia = [], predicciones = [];
      final futures = <Future>[];
      if (rutGanador != null) {
        futures.add(bq.obtenerHistorialGanador(rutGanador, rutOrganismo: rutOrganismo).then((r) {
          historialOcs = (r['ocs'] as List).cast<Map<String, dynamic>>();
          permanencia  = (r['permanencia'] as List).cast<Map<String, dynamic>>();
        }));
      }
      if (rutOrganismo != null) {
        futures.add(bq.obtenerPrediccionOrganismo(rutOrganismo).then((r) { predicciones = r; }));
      }
      if (futures.isNotEmpty) await Future.wait(futures);

      // ── Guardar caché + snapshot de historial ─────────────────────────────
      final payload = {
        'competidores':    competidores,
        'ganadorOcs':      ganadorOcs,
        'historialGanador': historialOcs,
        'permanencia':     permanencia,
        'predicciones':    predicciones,
        'rutGanador':      rutGanador,
        'nombreGanador':   nombreGanador,
        'rutOrganismo':    rutOrganismo,
        'fetchedAt':       FieldValue.serverTimestamp(),
      };
      try {
        await cacheDoc.set(payload);
        // Snapshot para historial de tendencias (sin fetchedAt genérico)
        await cacheDoc.collection('historial').add({
          'fechaConsulta':      FieldValue.serverTimestamp(),
          'totalCompetidores':  competidores.length,
          'rutGanador':         rutGanador,
          'nombreGanador':      nombreGanador,
          'rutOrganismo':       rutOrganismo,
          'montoAdjudicado':    ganadorOcs.isNotEmpty ? ganadorOcs.first['monto_calculado_oc']?.toString() : null,
          'totalOcsHistorial':  historialOcs.length,
          'totalPredicciones':  predicciones.length,
          // Snapshot ligero de competidores para análisis de tendencia
          'competidoresSnapshot': competidores.map((c) => {
            'rut':    c['rut_competidor'],
            'nombre': c['nombre_competidor'],
            'monto':  c['monto_ofertado']?.toString(),
          }).toList(),
        });
      } catch (cacheErr) {
        // No bloquear si Firestore falla al guardar
        debugPrint('analisis cache write error: $cacheErr');
      }

      _aplicarAnalisis({
        'competidores': competidores, 'ganadorOcs': ganadorOcs,
        'historialGanador': historialOcs, 'permanencia': permanencia,
        'predicciones': predicciones, 'rutGanador': rutGanador,
        'nombreGanador': nombreGanador, 'rutOrganismo': rutOrganismo,
      });
    } catch (e) {
      if (mounted) setState(() { _analisisError = e.toString(); _analisisCargando = false; });
    }
  }

  /// Aplica los datos de análisis (desde caché o BQ) al estado de la vista.
  void _aplicarAnalisis(Map<String, dynamic> d) {
    if (!mounted) return;
    setState(() {
      _competidores       = (d['competidores']     as List? ?? []).cast<Map<String, dynamic>>();
      _ganadorOcs         = (d['ganadorOcs']        as List? ?? []).cast<Map<String, dynamic>>();
      _historialGanador   = (d['historialGanador']  as List? ?? []).cast<Map<String, dynamic>>();
      _permanenciaGanador = (d['permanencia']       as List? ?? []).cast<Map<String, dynamic>>();
      _predicciones       = (d['predicciones']      as List? ?? []).cast<Map<String, dynamic>>();
      _rutGanador         = d['rutGanador']    as String?;
      _nombreGanador      = d['nombreGanador'] as String?;
      _rutOrganismo       = d['rutOrganismo']  as String?;
      _analisisCargando   = false;
    });
  }

  Widget _buildTabAnalisis(bool isMobile) {
    final loaded = _competidores.isNotEmpty || _ganadorOcs.isNotEmpty || _predicciones.isNotEmpty;

    if (!loaded && !_analisisCargando) {
      return _AnalisisEmptyState(onCargar: _cargarAnalisis);
    }
    if (_analisisCargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF5B21B6))),
      );
    }
    if (_analisisError != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text('Error al cargar análisis:', style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade400)),
          const SizedBox(height: 4),
          Text(_analisisError!, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          TextButton(onPressed: _cargarAnalisis, child: const Text('Reintentar')),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sección A: Competidores
        if (_competidores.isNotEmpty)
          _AnalisisCompetidoresCard(
            competidores: _competidores,
            rutGanador: _rutGanador,
            ganadorOcs: _ganadorOcs,
            proyectoTieneOC: _proyecto.idsOrdenesCompra.isNotEmpty,
            onVerFichaProveedor: (rut, nombre) => _abrirFichaProveedor(context, rut, nombre),
          ),
        if (_competidores.isNotEmpty) const SizedBox(height: 14),

        // Sección B: Ganador + historial
        if (_ganadorOcs.isNotEmpty)
          _AnalisisGanadorCard(
            ganadorOcs: _ganadorOcs,
            historialOcs: _historialGanador,
            permanencia: _permanenciaGanador,
            nombreGanador: _nombreGanador,
            rutGanador: _rutGanador,
            rutOrganismo: _rutOrganismo,
            proyectoTieneOC: _proyecto.idsOrdenesCompra.isNotEmpty,
            onVerFichaProveedor: (rut, nombre) => _abrirFichaProveedor(context, rut, nombre),
            onVerFichaOrganismo: (rut, nombre) => _abrirFichaOrganismo(context, rut, nombre),
          ),
        if (_ganadorOcs.isNotEmpty) const SizedBox(height: 14),

        // Sección C: Predicción próxima compra
        if (_predicciones.isNotEmpty)
          _AnalisisPrediccionCard(predicciones: _predicciones, rutOrganismo: _rutOrganismo),
        if (_predicciones.isNotEmpty) const SizedBox(height: 14),

        if (_competidores.isEmpty && _ganadorOcs.isEmpty && _predicciones.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Sin datos disponibles para esta licitación en BigQuery.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
          ),

        // Botón actualizar
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _analisisCargando ? null : () => _cargarAnalisis(forceRefresh: true),
            icon: const Icon(Icons.refresh, size: 15),
            label: Text('Actualizar análisis', style: GoogleFonts.inter(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: _primaryColor),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── TAB FORO ─────────────────────────────────────────────────────────────

  Widget _buildTabForo(bool isMobile) {
    final pad = isMobile ? 12.0 : 20.0;

    if (_cargandoForo && _foroEnquiries.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(strokeWidth: 2)));
    }

    final filtered = _foroQuery.isEmpty
        ? _foroEnquiries
        : _foroEnquiries.where((e) {
            final desc = (e['description'] ?? '').toString().toLowerCase();
            final ans  = (e['answer']      ?? '').toString().toLowerCase();
            return desc.contains(_foroQuery) || ans.contains(_foroQuery);
          }).toList();

    String? fechaStr;
    if (_foroFechaCache != null) {
      final d = _foroFechaCache!;
      fechaStr =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Barra caché + actualizar
      Container(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          if (fechaStr != null) ...[
            Icon(Icons.cloud_done_outlined, size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(fechaStr,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          ] else if (_foroCargado)
            Icon(Icons.cloud_off_outlined, size: 13, color: Colors.grey.shade300),
          if (_licitacionCerrada) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 12, color: Colors.grey.shade400),
          ],
          const Spacer(),
          InkWell(
            onTap: _cargandoForo ? null : () => _cargarForo(forceRefresh: true),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _cargandoForo
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
                  : const Icon(Icons.refresh, size: 18, color: _primaryColor),
            ),
          ),
          const SizedBox(width: 6),
          // Botón Resumen IA
          if (_foroEnquiries.isNotEmpty)
            InkWell(
              onTap: _cargandoResumen ? null : () => _mostrarResumenForo(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B21B6).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _cargandoResumen
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
                    : const Icon(Icons.auto_awesome, size: 18, color: _primaryColor),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),

      // Buscador
      TextField(
        controller: _foroSearch,
        style: GoogleFonts.inter(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar en preguntas y respuestas…',
          hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
          suffixIcon: _foroQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                  onPressed: () => _foroSearch.clear(),
                  padding: EdgeInsets.zero,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor)),
        ),
      ),
      const SizedBox(height: 12),

      // Contador
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(Icons.forum_outlined, size: 13, color: Colors.grey.shade400),
          const SizedBox(width: 5),
          Text(
            _foroQuery.isEmpty
                ? '${_foroEnquiries.length} consulta${_foroEnquiries.length != 1 ? 's' : ''}'
                : '${filtered.length} de ${_foroEnquiries.length}',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
          ),
        ]),
      ),

      // Lista
      if (_foroEnquiries.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          alignment: Alignment.center,
          child: Text(
            _foroCargado ? 'No hay consultas registradas para esta licitación' : 'Cargando foro…',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
          ),
        )
      else if (filtered.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          alignment: Alignment.center,
          child: Text('Sin resultados para "$_foroQuery"',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
        )
      else
        ...filtered.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _foroItemCard(e),
            )),
    ]);
  }

  Widget _foroItemCard(Map<String, dynamic> e) {
    final pregunta = e['description']?.toString() ?? '';
    final respuesta = e['answer']?.toString() ?? '';
    final fechaP = _fmtDateStr(e['date']?.toString() ?? '');
    final fechaR = _fmtDateStr(e['dateAnswered']?.toString() ?? '');
    final tieneRespuesta = respuesta.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Pregunta
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('P',
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF3B82F6))),
              ),
              const SizedBox(width: 6),
              Text(fechaP,
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 6),
            Text(pregunta,
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF334155), height: 1.5)),
          ]),
        ),
        // Respuesta o sin respuesta
        if (tieneRespuesta)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('R',
                      style: GoogleFonts.inter(
                          fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                ),
                const SizedBox(width: 6),
                Text(fechaR,
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 5),
              Text(respuesta,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF166534),
                      height: 1.5,
                      fontWeight: FontWeight.w500)),
            ]),
          )
        else
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Text('Sin respuesta',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.orange.shade400)),
          ),
      ]),
    );
  }

  Widget _buildTabCertificados(bool isMobile) {
    final certs = _proyecto.certificados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 14, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Los certificados quedan asociados al proyecto: ${_proyecto.idLicitacion ?? _proyecto.idCotizacion ?? '(sin ID de licitación)'}',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF1D4ED8)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (certs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.workspace_premium_outlined, size: 36, color: Colors.grey.shade200),
              const SizedBox(height: 8),
              Text('Sin certificados cargados',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            ]),
          )
        else
          _appleSection([
            for (int i = 0; i < certs.length; i++) ...[
              if (i > 0) _sep(),
              _buildCertificadoItem(certs[i]),
            ],
          ]),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _mostrarPopupAgregarCertificado(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, size: 16, color: _primaryColor.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text('Agregar certificado de experiencia',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: _primaryColor.withValues(alpha: 0.8))),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildCertificadoItem(CertificadoExperiencia cert) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.workspace_premium_outlined, size: 18, color: Color(0xFF3B82F6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cert.descripcion,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Emisión: ${_fmtDate(cert.fechaEmision)}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
                  const SizedBox(width: 10),
                  Icon(Icons.date_range_outlined, size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Contrato: ${_fmtDate(_proyecto.fechaInicio)} – ${_fmtDate(_proyecto.fechaTermino)}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
                ]),
                if (cert.url?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _abrirDocumento(cert.url!, cert.url!),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.attach_file, size: 12, color: _primaryColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 3),
                      Text('Ver documento',
                          style: GoogleFonts.inter(fontSize: 12, color: _primaryColor.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: () => _eliminarCertificado(cert.id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarCertificado(String id) async {
    final newList = _proyecto.certificados.where((c) => c.id != id).toList();
    await _editarCampo(
      nombreCampo: 'Certificado',
      valorAnterior: id,
      valorNuevo: '',
      data: {'certificados': newList.map((c) => c.toJson()).toList()},
    );
  }

  Future<void> _mostrarPopupAgregarCertificado(BuildContext context) async {
    final descCtrl = TextEditingController();
    DateTime? fechaEmision;
    PickedFile? pickedFile;
    bool uploading = false;

    final idContrato = _proyecto.idLicitacion?.isNotEmpty == true
        ? _proyecto.idLicitacion!
        : _proyecto.idCotizacion?.isNotEmpty == true
            ? _proyecto.idCotizacion!
            : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Agregar certificado',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogLabel('DESCRIPCIÓN'),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: _dialogInputDeco('Ej: Certificado de cumplimiento contrato...'),
                ),
                const SizedBox(height: 12),
                _dialogLabel('FECHA EMISIÓN (REFERENCIAL)'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: fechaEmision ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setS(() => fechaEmision = picked);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        fechaEmision != null ? _fmtDate(fechaEmision) : 'Seleccionar fecha...',
                        style: GoogleFonts.inter(fontSize: 14,
                            color: fechaEmision != null ? const Color(0xFF1E293B) : Colors.grey.shade300),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                _dialogLabel('DOCUMENTO (OPCIONAL)'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final file = await UploadService.instance.pickFile();
                    if (file != null) setS(() => pickedFile = file);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.upload_file_outlined, size: 16,
                          color: pickedFile != null ? _primaryColor : Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedFile != null ? pickedFile!.name : 'Seleccionar archivo...',
                          style: GoogleFonts.inter(fontSize: 13,
                              color: pickedFile != null ? const Color(0xFF1E293B) : Colors.grey.shade300),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pickedFile != null)
                        GestureDetector(
                          onTap: () => setS(() => pickedFile = null),
                          child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(Icons.article_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        idContrato != null
                            ? 'Contrato $idContrato | ${_fmtDate(_proyecto.fechaInicio)} – ${_fmtDate(_proyecto.fechaTermino)}'
                            : 'Contrato: ${_fmtDate(_proyecto.fechaInicio)} – ${_fmtDate(_proyecto.fechaTermino)}',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: uploading ? null : () async {
                final desc = descCtrl.text.trim();
                if (desc.isEmpty) return;
                setS(() => uploading = true);
                String? url;
                if (pickedFile != null) {
                  try {
                    url = await UploadService.instance.upload(
                      bytes: pickedFile!.bytes,
                      filename: pickedFile!.name,
                      storagePath: 'proyectos/${_proyecto.id}/certificados',
                    );
                  } catch (e) {
                    if (ctx.mounted) {
                      setS(() => uploading = false);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('Error al subir archivo: $e'),
                        backgroundColor: Colors.red.shade700,
                      ));
                    }
                    return;
                  }
                }
                final newCert = CertificadoExperiencia(
                  id: _genId(),
                  descripcion: desc,
                  fechaEmision: fechaEmision,
                  url: url,
                );
                final newList = [..._proyecto.certificados, newCert];
                if (ctx.mounted) Navigator.pop(ctx);
                _editarCampo(
                  nombreCampo: 'Certificado',
                  valorAnterior: '',
                  valorNuevo: newCert.descripcion,
                  data: {'certificados': newList.map((c) => c.toJson()).toList()},
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Agregar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB RECLAMOS ─────────────────────────────────────────────────────────

  Widget _buildTabReclamos(bool isMobile) {
    final reclamos = _proyecto.reclamos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reclamos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.gavel_outlined, size: 36, color: Colors.grey.shade200),
              const SizedBox(height: 8),
              Text('Sin reclamos registrados',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            ]),
          )
        else
          Column(
            children: [
              for (int i = 0; i < reclamos.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _buildReclamoCard(reclamos[i]),
              ],
            ],
          ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _mostrarPopupAgregarReclamo(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, size: 16, color: _primaryColor.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text('Registrar reclamo',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: _primaryColor.withValues(alpha: 0.8))),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildReclamoCard(Reclamo reclamo) {
    return _ReclamoCard(
      reclamo: reclamo,
      proyectoId: _proyecto.id,
      fmtDate: _fmtDate,
      tiposDocumento: _tiposDocumento,
      onEliminar: () => _eliminarReclamo(reclamo.id),
      onUpdate: _actualizarReclamo,
    );
  }

  Future<void> _actualizarReclamo(Reclamo updated) async {
    final newList = _proyecto.reclamos
        .map((r) => r.id == updated.id ? updated : r)
        .toList();
    await _editarCampo(
      nombreCampo: 'Reclamo',
      valorAnterior: '',
      valorNuevo: updated.estado,
      data: {'reclamos': newList.map((r) => r.toJson()).toList()},
    );
  }

  Future<void> _eliminarReclamo(String id) async {
    final newList = _proyecto.reclamos.where((r) => r.id != id).toList();
    await _editarCampo(
      nombreCampo: 'Reclamo',
      valorAnterior: id,
      valorNuevo: '',
      data: {'reclamos': newList.map((r) => r.toJson()).toList()},
    );
  }

  Future<void> _mostrarPopupAgregarReclamo(BuildContext context) async {
    final descCtrl = TextEditingController();
    DateTime? fechaReclamo;
    PickedFile? pickedFile;
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Registrar reclamo',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogLabel('DESCRIPCIÓN DEL RECLAMO'),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  autofocus: true,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: _dialogInputDeco('Describe el motivo del reclamo...'),
                ),
                const SizedBox(height: 12),
                _dialogLabel('FECHA DE INGRESO'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: fechaReclamo ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setS(() => fechaReclamo = picked);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        fechaReclamo != null ? _fmtDate(fechaReclamo) : 'Seleccionar fecha...',
                        style: GoogleFonts.inter(fontSize: 14,
                            color: fechaReclamo != null ? const Color(0xFF1E293B) : Colors.grey.shade300),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                _dialogLabel('DOCUMENTO (OPCIONAL)'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final file = await UploadService.instance.pickFile();
                    if (file != null) setS(() => pickedFile = file);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.upload_file_outlined, size: 16,
                          color: pickedFile != null ? _primaryColor : Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedFile != null ? pickedFile!.name : 'Seleccionar archivo...',
                          style: GoogleFonts.inter(fontSize: 13,
                              color: pickedFile != null ? const Color(0xFF1E293B) : Colors.grey.shade300),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pickedFile != null)
                        GestureDetector(
                          onTap: () => setS(() => pickedFile = null),
                          child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: uploading ? null : () async {
                final desc = descCtrl.text.trim();
                if (desc.isEmpty) return;
                setS(() => uploading = true);
                String? url;
                if (pickedFile != null) {
                  try {
                    url = await UploadService.instance.upload(
                      bytes: pickedFile!.bytes,
                      filename: pickedFile!.name,
                      storagePath: 'proyectos/${_proyecto.id}/reclamos',
                    );
                  } catch (e) {
                    if (ctx.mounted) {
                      setS(() => uploading = false);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('Error al subir archivo: $e'),
                        backgroundColor: Colors.red.shade700,
                      ));
                    }
                    return;
                  }
                }
                final newReclamo = Reclamo(
                  id: _genId(),
                  descripcion: desc,
                  fechaReclamo: fechaReclamo,
                  documentos: url != null ? [DocumentoProyecto(tipo: 'Documento', url: url)] : [],
                  estado: 'Pendiente',
                );
                final newList = [..._proyecto.reclamos, newReclamo];
                if (ctx.mounted) Navigator.pop(ctx);
                _editarCampo(
                  nombreCampo: 'Reclamo',
                  valorAnterior: '',
                  valorNuevo: newReclamo.descripcion,
                  data: {'reclamos': newList.map((r) => r.toJson()).toList()},
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Registrar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // Este popup ya no se usa directamente — la respuesta se maneja desde _ReclamoCard

  // ─── DIALOG HELPERS ───────────────────────────────────────────────────────

  Widget _dialogLabel(String label) => Text(label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
          color: Colors.grey.shade400, letterSpacing: 0.5));

  InputDecoration _dialogInputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
      );

  // ─── HELPERS UI ───────────────────────────────────────────────────────────

  // ── POSTULACIÓN: sincroniza fechas desde OCDS / Convenio Marco y muestra card read-only ─────

  /// Parsea "DD/MM/YYYY HH:MM" o "DD/MM/YYYY" al ISO 8601 string, o null si falla.
  static String? _parseCmDate(String? val) {
    if (val == null || val.isEmpty) return null;
    // Tomar solo la parte de fecha (primeros 10 chars "DD/MM/YYYY")
    final part = val.trim().split(' ').first;
    final pieces = part.split('/');
    if (pieces.length != 3) return null;
    final day = int.tryParse(pieces[0]);
    final month = int.tryParse(pieces[1]);
    final year = int.tryParse(pieces[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime.utc(year, month, day).toIso8601String();
  }

  Future<void> _sincronizarFechasDesdeConvenio() async {
    if (_convenioData == null) return;
    if (_proyecto.estadoManual != 'En Evaluación') return;

    final campos = (_convenioData!['campos'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];
    if (campos.isEmpty) return;

    // Construir mapa label → valor (case-insensitive)
    final campoMap = <String, String>{};
    for (final c in campos) {
      final label = c['label']?.toString().toLowerCase().trim() ?? '';
      final valor = c['valor']?.toString().trim() ?? '';
      if (label.isNotEmpty && valor.isNotEmpty) campoMap[label] = valor;
    }

    String? findDate(List<String> keys) {
      for (final k in keys) {
        final v = campoMap[k];
        if (v != null) return _parseCmDate(v);
      }
      return null;
    }

    final updates = <String, dynamic>{'id': _proyecto.id};
    if (_proyecto.fechaPublicacion == null) {
      final d = findDate(['inicio de publicación', 'inicio de publicacion']);
      if (d != null) updates['fechaPublicacion'] = d;
    }
    if (_proyecto.fechaCierre == null) {
      final d = findDate(['fin de publicación', 'fin de publicacion']);
      if (d != null) updates['fechaCierre'] = d;
    }
    if (_proyecto.fechaConsultas == null) {
      final d = findDate(['inicio de evaluación', 'inicio de evaluacion']);
      if (d != null) updates['fechaConsultas'] = d;
    }
    if (_proyecto.fechaAdjudicacion == null) {
      final d = findDate(['fin de evaluación', 'fin de evaluacion']);
      if (d != null) updates['fechaAdjudicacion'] = d;
    }

    if (updates.length <= 1) return;

    try {
      await http.post(Uri.parse('$_baseUrl/actualizarProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updates));
      ProyectosService.instance.invalidate();
    } catch (_) {}
  }

  Future<void> _sincronizarFechasDesdeOcds() async {
    if (_ocdsData == null) return;
    if (_proyecto.estadoManual != 'En Evaluación') return;

    final releases = (_ocdsData!['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (releases.isEmpty) return;
    final tender = releases.last['tender'] as Map<String, dynamic>? ?? {};

    final tp = tender['tenderPeriod'] as Map<String, dynamic>?;
    final eq = tender['enquiryPeriod'] as Map<String, dynamic>?;
    final ap = tender['awardPeriod'] as Map<String, dynamic>?;

    final updates = <String, dynamic>{'id': _proyecto.id};
    if (_proyecto.fechaPublicacion == null && tp?['startDate'] != null)       updates['fechaPublicacion'] = tp!['startDate'];
    if (_proyecto.fechaCierre == null && tp?['endDate'] != null)             updates['fechaCierre'] = tp!['endDate'];
    if (_proyecto.fechaConsultasInicio == null && eq?['startDate'] != null)  updates['fechaConsultasInicio'] = eq!['startDate'];
    if (_proyecto.fechaConsultas == null && eq?['endDate'] != null)          updates['fechaConsultas'] = eq!['endDate'];
    if (_proyecto.fechaAdjudicacion == null && ap?['startDate'] != null)     updates['fechaAdjudicacion'] = ap!['startDate'];
    if (_proyecto.fechaAdjudicacionFin == null && ap?['endDate'] != null)    updates['fechaAdjudicacionFin'] = ap!['endDate'];

    if (updates.length <= 1) return; // solo 'id' → nada que actualizar

    try {
      await http.post(Uri.parse('$_baseUrl/actualizarProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updates));
      ProyectosService.instance.invalidate();
    } catch (_) {}
  }

  Widget _buildPostulacionFechasCard() {
    // Resolve dates: prefer already-synced fields on proyecto, fallback to live ocdsData
    Map<String, dynamic>? tender;
    if (_ocdsData != null) {
      final releases = (_ocdsData!['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (releases.isNotEmpty) {
        tender = releases.last['tender'] as Map<String, dynamic>?;
      }
    }

    String resolve(DateTime? field, String? ocdsKey) {
      if (field != null) return _fmtDate(field);
      if (ocdsKey != null) return _fmtDateStr(ocdsKey);
      return '—';
    }

    final tp = tender?['tenderPeriod'] as Map<String, dynamic>?;
    final eq = tender?['enquiryPeriod'] as Map<String, dynamic>?;
    final ap = tender?['awardPeriod'] as Map<String, dynamic>?;

    final rows = [
      ('Publicación', resolve(_proyecto.fechaPublicacion, tp?['startDate']?.toString()), const Color(0xFF6366F1)),
      ('Cierre ofertas', resolve(_proyecto.fechaCierre, tp?['endDate']?.toString()), const Color(0xFFEF4444)),
      ('Consultas', resolve(_proyecto.fechaConsultas, eq?['endDate']?.toString()), const Color(0xFF0EA5E9)),
      ('Adjudicación', resolve(_proyecto.fechaAdjudicacion, ap?['startDate']?.toString()), const Color(0xFFF59E0B)),
    ];

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text('POSTULACIÓN · FECHAS',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400, letterSpacing: 0.5)),
            const Spacer(),
            if (_cargandoOcds)
              SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey.shade400))
            else
              Text('Mercado Público',
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16, runSpacing: 10,
            children: rows.map((r) => SizedBox(
              width: 140,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.$1, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(r.$2, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                    color: r.$2 == '—' ? Colors.grey.shade300 : r.$3)),
              ]),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _appleSection(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: children),
    );
  }

  Widget _sep() =>
      const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade400,
            letterSpacing: 0.5),
      ),
    );
  }

  Widget _estadoBadge(String estado) {
    final item = _estados.firstWhere((e) => e.nombre == estado,
        orElse: () => EstadoItem(nombre: estado, color: '64748B'));
    final label = estado.replaceFirst(RegExp(r'^\d+-'), '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: item.bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: item.fgColor)),
    );
  }

  /// Opens document: bottom sheet on mobile, new tab on desktop.
  void _abrirDocumento(String url, String nombre) =>
      abrirDocumento(context, url, nombre);
}

// Top-level helper so both State classes can use it.
void abrirDocumento(BuildContext ctx, String url, String nombre) {
  final isMobile = MediaQuery.of(ctx).size.width < 700;
  if (!isMobile) {
    web.window.open(url, '_blank');
    return;
  }
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (bCtx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(bCtx).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF5B21B6).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insert_drive_file_outlined,
                color: Color(0xFF5B21B6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(nombre,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(bCtx);
              web.window.open(url, '_blank');
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text('Abrir documento',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B21B6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    ),
  );
}

class _StatInfo {
  final String label;
  final String value;
  final Color valueColor;
  final IconData icon;
  const _StatInfo(
      {required this.label,
      required this.value,
      required this.valueColor,
      required this.icon});
}

class _PlazoInfo {
  final String label;
  final String value;
  final IconData icon;
  const _PlazoInfo(this.label, this.value, this.icon);
}

// ─── RECLAMO CARD ────────────────────────────────────────────────────────────

class _ReclamoCard extends StatefulWidget {
  final Reclamo reclamo;
  final String proyectoId;
  final String Function(DateTime?) fmtDate;
  final List<String> tiposDocumento;
  final VoidCallback onEliminar;
  final Future<void> Function(Reclamo) onUpdate;

  const _ReclamoCard({
    required this.reclamo,
    required this.proyectoId,
    required this.fmtDate,
    required this.tiposDocumento,
    required this.onEliminar,
    required this.onUpdate,
  });

  @override
  State<_ReclamoCard> createState() => _ReclamoCardState();
}

class _ReclamoCardState extends State<_ReclamoCard> {
  static const _primaryColor = Color(0xFF5B21B6);
  bool _expanded = false;
  static const _maxLines = 3;

  // ── helpers ──

  void _abrirDocumento(String url, String nombre) =>
      abrirDocumento(context, url, nombre);

  Widget _docRow(DocumentoProyecto doc, {VoidCallback? onRemove}) {
    final label = doc.nombre ?? doc.url;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(doc.tipo,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => _abrirDocumento(doc.url, label),
            child: Row(children: [
              Icon(Icons.attach_file, size: 12, color: _primaryColor.withValues(alpha: 0.6)),
              const SizedBox(width: 3),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(fontSize: 12, color: _primaryColor.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500, decoration: TextDecoration.underline),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
        if (onRemove != null)
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close, size: 13, color: Colors.grey.shade400),
            ),
          ),
      ]),
    );
  }

  Widget _addDocLink(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 13, color: _primaryColor.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(fontSize: 12, color: _primaryColor.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Future<void> _showAddDocDialog({
    required String title,
    required List<DocumentoProyecto> existing,
    required Future<void> Function(DocumentoProyecto) onAdd,
    required String storagePath,
  }) async {
    final tipos = widget.tiposDocumento.isNotEmpty
        ? widget.tiposDocumento
        : ['Contrato', 'Orden de Compra', 'Acta', 'Otro'];
    String? tipoSel = tipos.first;
    PickedFile? picked;
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title,
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B))),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TIPO DE DOCUMENTO',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: tipoSel,
                  items: tipos.map((t) => DropdownMenuItem(value: t,
                      child: Text(t, style: GoogleFonts.inter(fontSize: 14)))).toList(),
                  onChanged: isUploading ? null : (v) => setS(() => tipoSel = v),
                  decoration: InputDecoration(
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('ARCHIVO',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                if (picked == null)
                  OutlinedButton.icon(
                    onPressed: isUploading ? null : () async {
                      final file = await UploadService.instance.pickFile();
                      if (file != null) setS(() => picked = file);
                    },
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: Text('Seleccionar archivo',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.insert_drive_file_outlined, size: 16,
                          color: _primaryColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(picked!.name,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (!isUploading)
                        InkWell(
                          onTap: () => setS(() => picked = null),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                          ),
                        ),
                    ]),
                  ),
                if (isUploading) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
                    ),
                    const SizedBox(width: 8),
                    Text('Subiendo archivo…',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: (picked == null || isUploading) ? null : () async {
                setS(() => isUploading = true);
                try {
                  final url = await UploadService.instance.upload(
                    bytes: picked!.bytes,
                    filename: picked!.name,
                    storagePath: storagePath,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await onAdd(DocumentoProyecto(
                    tipo: tipoSel ?? tipos.first,
                    url: url,
                    nombre: picked!.name,
                  ));
                } catch (e) {
                  if (ctx.mounted) {
                    setS(() => isUploading = false);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Error al subir archivo: $e'),
                      backgroundColor: Colors.red.shade700,
                    ));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text('Agregar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRespuestaDialog() async {
    final reclamo = widget.reclamo;
    final descCtrl = TextEditingController(text: reclamo.descripcionRespuesta ?? '');
    DateTime? fechaRespuesta = reclamo.fechaRespuesta;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Respuesta de la entidad',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B))),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.gavel_outlined, size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(reclamo.descripcion,
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E)),
                        overflow: TextOverflow.ellipsis)),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('DESCRIPCIÓN DE LA RESPUESTA',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  autofocus: true,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Describe la respuesta recibida...',
                    hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300),
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('FECHA DE RESPUESTA',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: fechaRespuesta ?? DateTime.now(),
                      firstDate: DateTime(2000), lastDate: DateTime(2100),
                    );
                    if (picked != null) setS(() => fechaRespuesta = picked);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        fechaRespuesta != null
                            ? widget.fmtDate(fechaRespuesta)
                            : 'Seleccionar fecha...',
                        style: GoogleFonts.inter(fontSize: 14,
                            color: fechaRespuesta != null
                                ? const Color(0xFF1E293B)
                                : Colors.grey.shade300),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final updated = Reclamo(
                  id: reclamo.id,
                  descripcion: reclamo.descripcion,
                  fechaReclamo: reclamo.fechaReclamo,
                  documentos: reclamo.documentos,
                  estado: 'Respondido',
                  fechaRespuesta: fechaRespuesta,
                  descripcionRespuesta: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  documentosRespuesta: reclamo.documentosRespuesta,
                );
                widget.onUpdate(updated);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text('Guardar respuesta',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final reclamo = widget.reclamo;
    final respondido = reclamo.estado == 'Respondido';

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: respondido ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  respondido ? Icons.check_circle_outline : Icons.pending_outlined,
                  size: 16,
                  color: respondido ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: respondido ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(reclamo.estado,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                            color: respondido ? const Color(0xFF16A34A) : const Color(0xFFD97706))),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 3),
                  Text(widget.fmtDate(reclamo.fechaReclamo),
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
                ]),
              ),
              InkWell(
                onTap: widget.onEliminar,
                borderRadius: BorderRadius.circular(6),
                child: Padding(padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.grey.shade400)),
              ),
            ]),
          ),

          // ── Descripción ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                reclamo.descripcion,
                maxLines: _expanded ? null : _maxLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151), height: 1.6),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(_expanded ? 'Ver menos' : 'Ver más',
                      style: GoogleFonts.inter(fontSize: 12,
                          color: _primaryColor.withValues(alpha: 0.55), fontWeight: FontWeight.w500)),
                ),
              ),
            ]),
          ),

          // ── Documentos del reclamo ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (reclamo.documentos.isNotEmpty) ...[
                Text('DOCUMENTOS',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                ...reclamo.documentos.asMap().entries.map((e) => _docRow(
                  e.value,
                  onRemove: () {
                    final newDocs = List<DocumentoProyecto>.from(reclamo.documentos)..removeAt(e.key);
                    widget.onUpdate(Reclamo(
                      id: reclamo.id, descripcion: reclamo.descripcion,
                      fechaReclamo: reclamo.fechaReclamo, documentos: newDocs,
                      estado: reclamo.estado, fechaRespuesta: reclamo.fechaRespuesta,
                      descripcionRespuesta: reclamo.descripcionRespuesta,
                      documentosRespuesta: reclamo.documentosRespuesta,
                    ));
                  },
                )),
              ],
              _addDocLink('Agregar documento', () => _showAddDocDialog(
                title: 'Agregar documento al reclamo',
                existing: reclamo.documentos,
                storagePath: 'proyectos/${widget.proyectoId}/reclamos/${reclamo.id}',
                onAdd: (doc) async {
                  final newDocs = [...reclamo.documentos, doc];
                  await widget.onUpdate(Reclamo(
                    id: reclamo.id, descripcion: reclamo.descripcion,
                    fechaReclamo: reclamo.fechaReclamo, documentos: newDocs,
                    estado: reclamo.estado, fechaRespuesta: reclamo.fechaRespuesta,
                    descripcionRespuesta: reclamo.descripcionRespuesta,
                    documentosRespuesta: reclamo.documentosRespuesta,
                  ));
                },
              )),
            ]),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, indent: 20, endIndent: 20),
          const SizedBox(height: 14),

          // ── Sección respuesta ──
          if (respondido) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.reply, size: 13, color: Color(0xFF16A34A)),
                  const SizedBox(width: 5),
                  Text('RESPUESTA DE LA ENTIDAD',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                          color: const Color(0xFF16A34A), letterSpacing: 0.4)),
                  const Spacer(),
                  if (reclamo.fechaRespuesta != null)
                    Text(widget.fmtDate(reclamo.fechaRespuesta),
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _showRespuestaDialog,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.edit_outlined, size: 13, color: Colors.grey.shade400),
                    ),
                  ),
                ]),
                if (reclamo.descripcionRespuesta?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(reclamo.descripcionRespuesta!,
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151), height: 1.6)),
                ],
                const SizedBox(height: 10),
                if (reclamo.documentosRespuesta.isNotEmpty) ...[
                  Text('DOCUMENTOS RESPUESTA',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
                          color: Colors.grey.shade400, letterSpacing: 0.4)),
                  const SizedBox(height: 6),
                  ...reclamo.documentosRespuesta.asMap().entries.map((e) => _docRow(
                    e.value,
                    onRemove: () {
                      final newDocs = List<DocumentoProyecto>.from(reclamo.documentosRespuesta)..removeAt(e.key);
                      widget.onUpdate(Reclamo(
                        id: reclamo.id, descripcion: reclamo.descripcion,
                        fechaReclamo: reclamo.fechaReclamo, documentos: reclamo.documentos,
                        estado: reclamo.estado, fechaRespuesta: reclamo.fechaRespuesta,
                        descripcionRespuesta: reclamo.descripcionRespuesta,
                        documentosRespuesta: newDocs,
                      ));
                    },
                  )),
                ],
                _addDocLink('Agregar documento de respuesta', () => _showAddDocDialog(
                  title: 'Agregar documento de respuesta',
                  existing: reclamo.documentosRespuesta,
                  storagePath: 'proyectos/${widget.proyectoId}/reclamos/${reclamo.id}/respuesta',
                  onAdd: (doc) async {
                    final newDocs = [...reclamo.documentosRespuesta, doc];
                    await widget.onUpdate(Reclamo(
                      id: reclamo.id, descripcion: reclamo.descripcion,
                      fechaReclamo: reclamo.fechaReclamo, documentos: reclamo.documentos,
                      estado: reclamo.estado, fechaRespuesta: reclamo.fechaRespuesta,
                      descripcionRespuesta: reclamo.descripcionRespuesta,
                      documentosRespuesta: newDocs,
                    ));
                  },
                )),
              ]),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: InkWell(
                onTap: _showRespuestaDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.reply, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text('Cargar respuesta de la entidad',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── OC Skeleton card ──────────────────────────────────────────────────────────

class _OcSkeletonCard extends StatefulWidget {
  final double height;
  const _OcSkeletonCard({this.height = 160});

  @override
  State<_OcSkeletonCard> createState() => _OcSkeletonCardState();
}

class _OcSkeletonCardState extends State<_OcSkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box({double? width, double height = 12, double radius = 6}) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Color.lerp(
              const Color(0xFFEDF0F3), const Color(0xFFF7F9FB), _anim.value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _box(width: 80, height: 10),
            const Spacer(),
            _box(width: 50, height: 22, radius: 20),
          ]),
          const SizedBox(height: 14),
          _box(height: 14),
          const SizedBox(height: 10),
          _box(width: 180, height: 10),
          const Spacer(),
          _box(height: 10),
        ],
      ),
    );
  }
}

// ── Dialog: Encadenar proyecto ────────────────────────────────────────────────

class _EncadenarDialog extends StatefulWidget {
  final List<Proyecto> candidatos;
  final Proyecto actual;

  const _EncadenarDialog({required this.candidatos, required this.actual});

  @override
  State<_EncadenarDialog> createState() => _EncadenarDialogState();
}

class _EncadenarDialogState extends State<_EncadenarDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _cleanName(String name) {
    const prefixes = [
      'MUNICIPALIDAD DE ', 'I. MUNICIPALIDAD DE ', 'ILUSTRE MUNICIPALIDAD DE ',
      'SERVICIO DE SALUD ', 'HOSPITAL ', 'MINISTERIO DE ',
    ];
    var n = name.toUpperCase().trim();
    for (final p in prefixes) {
      if (n.startsWith(p)) return n.substring(p.length);
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.candidatos.where((p) {
      if (q.isEmpty) return true;
      return p.institucion.toLowerCase().contains(q) ||
          p.productos.toLowerCase().contains(q) ||
          p.id.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.institucion.compareTo(b.institucion));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Encadenar proyecto',
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text('Selecciona el proyecto que continúa este contrato.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar por institución o productos…',
                  hintStyle: GoogleFonts.inter(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('Sin resultados',
                          style: GoogleFonts.inter(color: Colors.grey.shade400)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          title: Text(
                            _cleanName(p.institucion),
                            style: GoogleFonts.inter(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            p.productos,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: p.proyectoContinuacionId?.isNotEmpty == true
                              ? const Icon(Icons.link, size: 14, color: Color(0xFF10B981))
                              : null,
                          onTap: () => Navigator.of(ctx).pop(p),
                        );
                      },
                    ),
            ),
            // Cancel
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancelar',
                    style: GoogleFonts.inter(color: Colors.grey.shade600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ANÁLISIS: Estado vacío ──────────────────────────────────────────────────

class _AnalisisEmptyState extends StatelessWidget {
  final VoidCallback onCargar;
  const _AnalisisEmptyState({required this.onCargar});
  static const _primary = Color(0xFF5B21B6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.analytics_outlined, size: 32, color: _primary),
          ),
          const SizedBox(height: 16),
          Text('Análisis de inteligencia competitiva',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Consulta BigQuery para obtener competidores, ganador,\nhistorial del organismo y predicción de próxima compra.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500, height: 1.5)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCargar,
            icon: const Icon(Icons.query_stats, size: 16),
            label: Text('Cargar análisis', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── ANÁLISIS: Competidores ──────────────────────────────────────────────────

class _AnalisisCompetidoresCard extends StatelessWidget {
  final List<Map<String, dynamic>> competidores;
  final String? rutGanador;
  final List<Map<String, dynamic>> ganadorOcs;
  final bool proyectoTieneOC;
  final void Function(String rut, String nombre)? onVerFichaProveedor;

  const _AnalisisCompetidoresCard({
    required this.competidores,
    required this.rutGanador,
    required this.ganadorOcs,
    required this.proyectoTieneOC,
    this.onVerFichaProveedor,
  });

  static const _primary = Color(0xFF5B21B6);

  String _fmtMonto(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final montos = competidores
        .map((c) => (c['monto_ofertado'] is num) ? (c['monto_ofertado'] as num).toDouble() : 0.0)
        .where((m) => m > 0)
        .toList();
    final minMonto = montos.isNotEmpty ? montos.reduce((a, b) => a < b ? a : b) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: _primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.groups_outlined, size: 16, color: _primary),
                ),
                const SizedBox(width: 10),
                Text('Competidores (${competidores.length})',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                if (proyectoTieneOC) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Ganado', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
                  ),
                ],
              ],
            ),
          ),
          // Header tabla
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Competidor', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400))),
                SizedBox(width: 90, child: Text('Monto ofertado', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400))),
                const SizedBox(width: 8),
                SizedBox(width: 60, child: Text('Rol', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400))),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: competidores.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (_, i) {
              final c = competidores[i];
              final rut = c['rut_competidor']?.toString() ?? '';
              final esGanador = rutGanador != null && rut == rutGanador;
              final monto = (c['monto_ofertado'] is num) ? (c['monto_ofertado'] as num).toDouble() : 0.0;
              final esMenor = monto > 0 && monto == minMonto;
              return InkWell(
                onTap: rut.isNotEmpty && onVerFichaProveedor != null
                    ? () => onVerFichaProveedor!(rut, c['nombre_competidor']?.toString() ?? rut)
                    : null,
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['nombre_competidor']?.toString() ?? '—',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: esGanador ? FontWeight.w700 : FontWeight.w500,
                                  color: esGanador ? _primary : const Color(0xFF1E293B)),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (rut.isNotEmpty)
                            Text('RUT $rut · toca para ver ficha', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (esMenor) const Icon(Icons.arrow_downward, size: 12, color: Color(0xFF10B981)),
                          Text(_fmtMonto(c['monto_ofertado']),
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: esMenor ? const Color(0xFF10B981) : const Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: Text(c['quien_oferta']?.toString() ?? '—',
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── ANÁLISIS: Ganador + historial ───────────────────────────────────────────

class _AnalisisGanadorCard extends StatelessWidget {
  final List<Map<String, dynamic>> ganadorOcs;
  final List<Map<String, dynamic>> historialOcs;
  final List<Map<String, dynamic>> permanencia;
  final String? nombreGanador;
  final String? rutGanador;
  final String? rutOrganismo;
  final bool proyectoTieneOC;
  final void Function(String rut, String nombre)? onVerFichaProveedor;
  final void Function(String rut, String nombre)? onVerFichaOrganismo;

  const _AnalisisGanadorCard({
    required this.ganadorOcs,
    required this.historialOcs,
    required this.permanencia,
    required this.nombreGanador,
    required this.rutGanador,
    required this.rutOrganismo,
    required this.proyectoTieneOC,
    this.onVerFichaProveedor,
    this.onVerFichaOrganismo,
  });

  static const _primary = Color(0xFF5B21B6);

  String _fmtMonto(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final primera = ganadorOcs.first;
    final montoAdj = primera['monto_calculado_oc'];
    final organismo = primera['OrganismoPublico']?.toString() ?? '—';

    // Permanencia: priorizar el registro que coincide con el organismo actual
    final permTop = permanencia.isNotEmpty
        ? (permanencia.firstWhere(
              (p) => p['proveedor_rut']?.toString() == rutGanador &&
                     (rutOrganismo == null || p['cliente_nombre']?.toString().isNotEmpty == true),
              orElse: () => permanencia.first,
            ))
        : null;
    final permAniosRaw = permTop?['permanencia_anios'];
    final permAnios = permAniosRaw != null
        ? (permAniosRaw is num ? permAniosRaw.toStringAsFixed(1) : permAniosRaw.toString())
        : null;

    // Alerta estratégica: más de 3 años (36 meses) con el mismo organismo
    final esSospechoso = permAniosRaw is num && permAniosRaw > 3;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.emoji_events_outlined, size: 16, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(proyectoTieneOC ? 'Proveedor adjudicado' : 'Ganador de la licitación',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Datos del ganador
          _row('Proveedor', nombreGanador ?? '—'),
          if (rutGanador != null) _row('RUT', rutGanador!),
          _row('Organismo', organismo),
          _row('Monto adjudicado', _fmtMonto(montoAdj)),
          if (primera['FechaEnvio'] != null) _row('Fecha OC', primera['FechaEnvio'].toString().substring(0, 10)),

          // Permanencia
          if (permTop != null) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade100),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.history, size: 14, color: esSospechoso ? const Color(0xFFEF4444) : Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    esSospechoso
                        ? 'Proveedor arraigado — $permAnios años con este organismo'
                        : 'Relación de $permAnios años con ${permTop['cliente_nombre'] ?? 'este organismo'}',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: esSospechoso ? const Color(0xFFEF4444) : Colors.grey.shade600),
                  ),
                ),
              ],
            ),
            if (historialOcs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${historialOcs.length} OC${historialOcs.length != 1 ? 's' : ''} con este organismo · Categoría: ${permTop['categoria_nombre'] ?? '—'}',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ],

          // Historial reciente
          if (historialOcs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade100),
            const SizedBox(height: 8),
            Text('Últimas ${historialOcs.length > 5 ? 5 : historialOcs.length} OC con este organismo',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            ...historialOcs.take(5).map((oc) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(oc['CodigoLicitacion']?.toString() ?? oc['ID']?.toString() ?? '—',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)))),
                  Text(_fmtMonto(oc['monto_calculado_oc']),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _primary)),
                  const SizedBox(width: 8),
                  Text(oc['FechaEnvio']?.toString().substring(0, 10) ?? '—',
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                ],
              ),
            )),
          ],

          // Botones Ver ficha
          if (onVerFichaProveedor != null || onVerFichaOrganismo != null) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade100),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (rutGanador != null && onVerFichaProveedor != null)
                  OutlinedButton.icon(
                    onPressed: () => onVerFichaProveedor!(rutGanador!, nombreGanador ?? rutGanador!),
                    icon: const Icon(Icons.person_search_outlined, size: 14),
                    label: Text('Ficha proveedor', style: GoogleFonts.inter(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: BorderSide(color: _primary.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                if (rutOrganismo != null && onVerFichaOrganismo != null)
                  OutlinedButton.icon(
                    onPressed: () => onVerFichaOrganismo!(rutOrganismo!, primera['OrganismoPublico']?.toString() ?? rutOrganismo!),
                    icon: const Icon(Icons.domain_outlined, size: 14),
                    label: Text('Ficha organismo', style: GoogleFonts.inter(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0EA5E9),
                      side: BorderSide(color: const Color(0xFF0EA5E9).withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400))),
        Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)))),
      ],
    ),
  );
}

// ── ANÁLISIS: Predicción próxima compra ────────────────────────────────────

class _AnalisisPrediccionCard extends StatelessWidget {
  final List<Map<String, dynamic>> predicciones;
  final String? rutOrganismo;

  const _AnalisisPrediccionCard({required this.predicciones, required this.rutOrganismo});

  static const _primary = Color(0xFF5B21B6);

  String _fmtFecha(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  String _fmtMonto(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    return '\$${(n / 1000).toStringAsFixed(0)}K';
  }

  Color _urgencyColor(String? fechaStr) {
    if (fechaStr == null) return Colors.grey.shade300;
    final fecha = DateTime.tryParse(fechaStr);
    if (fecha == null) return Colors.grey.shade300;
    final dias = fecha.difference(DateTime.now()).inDays;
    if (dias < 0) return const Color(0xFFEF4444);
    if (dias <= 30) return const Color(0xFFF59E0B);
    if (dias <= 90) return const Color(0xFF10B981);
    return Colors.grey.shade300;
  }

  @override
  Widget build(BuildContext context) {
    // Ordenar: más próximas primero
    final sorted = [...predicciones]..sort((a, b) {
      final fa = a['Proxima_Compra_Estimada']?.toString() ?? '';
      final fb = b['Proxima_Compra_Estimada']?.toString() ?? '';
      return fa.compareTo(fb);
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: _primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.calendar_today_outlined, size: 16, color: _primary),
                ),
                const SizedBox(width: 10),
                Text('Predicción de próxima compra',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Por categoría — ${sorted.length} registros para este organismo',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sorted.length > 10 ? 10 : sorted.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (_, i) {
              final r = sorted[i];
              final proxima = r['Proxima_Compra_Estimada']?.toString();
              final color = _urgencyColor(proxima);
              final dias = proxima != null ? DateTime.tryParse(proxima)?.difference(DateTime.now()).inDays : null;
              final diasStr = dias != null
                  ? (dias < 0 ? 'Vencida' : dias == 0 ? 'Hoy' : 'en $dias días')
                  : '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4, height: 40,
                      margin: const EdgeInsets.only(right: 12, top: 2),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['Categoria_Nombre_Referencia']?.toString() ?? 'Categoría ${r['codigoCategoria']}',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${r['Proveedor_Nombre'] ?? '—'} · ${_fmtMonto(r['MontoTotal_CLP'])} histórico',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_fmtFecha(proxima),
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                        Text(diasStr, style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          if (sorted.length > 10)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('+ ${sorted.length - 10} categorías más',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── FICHA ORGANISMO ─────────────────────────────────────────────────────────

class _FichaOrganismoSheet extends StatefulWidget {
  final String rut;
  final String nombre;
  const _FichaOrganismoSheet({required this.rut, required this.nombre});

  @override
  State<_FichaOrganismoSheet> createState() => _FichaOrganismoSheetState();
}

class _FichaOrganismoSheetState extends State<_FichaOrganismoSheet> {
  static const _primary = Color(0xFF0EA5E9);
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>> _proveedores = [];

  bool _filtroTI = true;
  int _filtroPlazo = 0; // 0=todos, 12, 36, 48 meses

  List<Map<String, dynamic>> get _proveedoresFiltrados {
    var lista = _proveedores;
    if (_filtroTI) {
      lista = lista.where((p) {
        final act = (p['actividad_proveedor']?.toString() ?? '').toUpperCase();
        return act.contains('INFORM') || act.contains('SOFTW') ||
               act.contains('TECNO') || act.contains('HARDWARE') ||
               act.contains('COMPUTAC') || act.contains('DIGIT');
      }).toList();
    }
    if (_filtroPlazo > 0) {
      final corte = DateTime.now().subtract(Duration(days: _filtroPlazo * 30));
      lista = lista.where((p) {
        final s = p['ultima_oc']?.toString() ?? '';
        if (s.length < 10) return false;
        final d = DateTime.tryParse(s.substring(0, 10));
        return d != null && d.isAfter(corte);
      }).toList();
    }
    return lista;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await BigQueryService.instance.obtenerFichaOrganismo(widget.rut);
      if (mounted) {
        setState(() {
          _resumen = data['resumen'] as Map<String, dynamic>?;
          _proveedores = (data['proveedores'] as List? ?? []).cast<Map<String, dynamic>>();
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _cargando = false; });
      }
    }
  }

  String _fmtMonto(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.domain_outlined, size: 20, color: _primary)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.nombre, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('RUT ${widget.rut}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
            ])),
          ]),
        ),
        Divider(color: Colors.grey.shade100),
        Expanded(child: _cargando
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
            ? Center(child: Text('Error: $_error', style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade400)))
            : ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
                // ── KPI cards ──────────────────────────────────────────────
                if (_resumen != null) ...[
                  Row(children: [
                    _kpiCell('Total OCs', _resumen!['total_ocs']?.toString() ?? '—', Icons.receipt_long_outlined),
                    const SizedBox(width: 8),
                    _kpiCell('Gasto total', _fmtMonto(_resumen!['gasto_total']), Icons.monetization_on_outlined),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _kpiCell('Actividad', _resumen!['ActividadComprador']?.toString() ?? '—', Icons.category_outlined),
                    const SizedBox(width: 8),
                    _kpiCell('Región', _resumen!['RegionUnidadCompra']?.toString() ?? '—', Icons.location_on_outlined),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _kpiCell('Primera OC', _fmtFecha(_resumen!['primera_oc']), Icons.calendar_today_outlined),
                    const SizedBox(width: 8),
                    _kpiCell('Última OC', _fmtFecha(_resumen!['ultima_oc']), Icons.update_outlined),
                  ]),
                  const SizedBox(height: 20),
                ],
                // ── Chips de filtro ────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _chip('TI', _filtroTI, () => setState(() => _filtroTI = !_filtroTI), Icons.computer_outlined),
                    const SizedBox(width: 8),
                    _chip('12 meses', _filtroPlazo == 12, () => setState(() => _filtroPlazo = _filtroPlazo == 12 ? 0 : 12), Icons.schedule_outlined),
                    const SizedBox(width: 8),
                    _chip('36 meses', _filtroPlazo == 36, () => setState(() => _filtroPlazo = _filtroPlazo == 36 ? 0 : 36), Icons.schedule_outlined),
                    const SizedBox(width: 8),
                    _chip('48 meses', _filtroPlazo == 48, () => setState(() => _filtroPlazo = _filtroPlazo == 48 ? 0 : 48), Icons.schedule_outlined),
                  ]),
                ),
                const SizedBox(height: 12),
                // ── Cabecera proveedores ───────────────────────────────────
                Row(children: [
                  Text('Top proveedores', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text('${_proveedoresFiltrados.length}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _primary)),
                  ),
                ]),
                const SizedBox(height: 10),
                // ── Lista proveedores ──────────────────────────────────────
                if (_proveedoresFiltrados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sin proveedores para los filtros aplicados',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400))),
                  )
                else
                  ..._proveedoresFiltrados.asMap().entries.map((e) {
                    final i = e.key;
                    final p = e.value;
                    final maxMonto = _proveedoresFiltrados
                        .map((x) => (x['monto_total'] is num) ? (x['monto_total'] as num).toDouble() : 0.0)
                        .fold(1.0, (a, b) => a > b ? a : b);
                    final monto = (p['monto_total'] is num) ? (p['monto_total'] as num).toDouble() : 0.0;
                    final pct = maxMonto > 0 ? monto / maxMonto : 0.0;
                    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 20, height: 20, alignment: Alignment.center,
                            decoration: BoxDecoration(color: i < 3 ? _primary.withValues(alpha: 0.1) : Colors.grey.shade100, shape: BoxShape.circle),
                            child: Text('${i + 1}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: i < 3 ? _primary : Colors.grey.shade400))),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p['nombre_proveedor']?.toString() ?? '—',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(_fmtMonto(p['monto_total']), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _primary)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: pct, minHeight: 3,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation(_primary.withValues(alpha: 0.6)))),
                      const SizedBox(height: 2),
                      Text('${p['total_ocs']} OCs · ${_fmtFecha(p['primera_oc'])} → ${_fmtFecha(p['ultima_oc'])}',
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                    ]));
                  }),
              ]),
        ),
      ]),
    );
  }

  String _fmtFecha(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.length >= 10) return s.substring(0, 10);
    return '—';
  }

  Widget _kpiCell(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap, IconData icon) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? _primary : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: selected ? Colors.white : Colors.grey.shade500),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade600)),
      ]),
    ),
  );

}

// ── FICHA PROVEEDOR ─────────────────────────────────────────────────────────

class _FichaProveedorSheet extends StatefulWidget {
  final String rut;
  final String nombre;
  const _FichaProveedorSheet({required this.rut, required this.nombre});

  @override
  State<_FichaProveedorSheet> createState() => _FichaProveedorSheetState();
}

class _FichaProveedorSheetState extends State<_FichaProveedorSheet> {
  static const _primary = Color(0xFF5B21B6);
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>> _organismos = [];
  List<Map<String, dynamic>> _permanencia = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await BigQueryService.instance.obtenerFichaProveedor(widget.rut);
      if (mounted) {
        setState(() {
          _resumen = data['resumen'] as Map<String, dynamic>?;
          _organismos = (data['organismos'] as List? ?? []).cast<Map<String, dynamic>>();
          _permanencia = (data['permanencia'] as List? ?? []).cast<Map<String, dynamic>>();
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _cargando = false; });
      }
    }
  }

  String _fmtMonto(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_search_outlined, size: 20, color: _primary)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.nombre, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('RUT ${widget.rut}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
            ])),
          ]),
        ),
        Divider(color: Colors.grey.shade100),
        Expanded(child: _cargando
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
            ? Center(child: Text('Error: $_error', style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade400)))
            : ListView(controller: ctrl, padding: const EdgeInsets.all(20), children: [
                if (_resumen != null) ...[
                  _kpiRow([
                    ('Total OCs', _resumen!['total_ocs']?.toString() ?? '—', Icons.receipt_long_outlined),
                    ('Monto total', _fmtMonto(_resumen!['monto_total']), Icons.monetization_on_outlined),
                    ('Región', _resumen!['RegionProveedor']?.toString() ?? '—', Icons.location_on_outlined),
                  ]),
                  const SizedBox(height: 6),
                  if (_resumen!['ActividadProveedor'] != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                      child: Text(_resumen!['ActividadProveedor'].toString(),
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
                    ),
                  const SizedBox(height: 8),
                ],
                if (_permanencia.isNotEmpty) ...[
                  Text('Relaciones de largo plazo', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  ..._permanencia.map((p) {
                    final meses = p['permanencia_meses'];
                    final anios = meses is num ? (meses / 12.0).toStringAsFixed(1) : '—';
                    final esSospechoso = meses is num && meses > 36;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: esSospechoso ? const Color(0xFFEF4444).withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: esSospechoso ? const Color(0xFFEF4444).withValues(alpha: 0.2) : Colors.transparent),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['cliente_nombre']?.toString() ?? '—',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${p['categoria_nombre'] ?? '—'} · ${p['cantidad_oc_emitidas']} OCs',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('$anios años', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
                              color: esSospechoso ? const Color(0xFFEF4444) : _primary)),
                          Text('~${p['promedio_dias_entre_compras']?.toStringAsFixed(0) ?? '—'} días/OC',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                        ]),
                      ]),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                Text('Organismos compradores', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                const SizedBox(height: 10),
                ..._organismos.asMap().entries.map((e) {
                  final i = e.key;
                  final o = e.value;
                  final maxMonto = _organismos.isEmpty ? 1.0
                      : _organismos.map((x) => (x['monto_total'] is num) ? (x['monto_total'] as num).toDouble() : 0.0).reduce((a, b) => a > b ? a : b);
                  final monto = (o['monto_total'] is num) ? (o['monto_total'] as num).toDouble() : 0.0;
                  final pct = maxMonto > 0 ? monto / maxMonto : 0.0;
                  return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 20, height: 20, alignment: Alignment.center,
                          decoration: BoxDecoration(color: i < 3 ? _primary.withValues(alpha: 0.1) : Colors.grey.shade100, shape: BoxShape.circle),
                          child: Text('${i + 1}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: i < 3 ? _primary : Colors.grey.shade400))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(o['OrganismoPublico']?.toString() ?? '—',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(_fmtMonto(o['monto_total']), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _primary)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: pct, minHeight: 3,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation(_primary.withValues(alpha: 0.6)))),
                    const SizedBox(height: 2),
                    Text('${o['total_ocs']} OCs · última: ${(o['ultima_oc']?.toString() ?? '').length >= 10 ? o['ultima_oc'].toString().substring(0, 10) : '—'}',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                  ]));
                }),
              ]),
        ),
      ]),
    );
  }

  Widget _kpiRow(List<(String, String, IconData)> items) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: items.map((item) => Expanded(child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(item.$3, size: 14, color: Colors.grey.shade400),
        const SizedBox(height: 4),
        Text(item.$2, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(item.$1, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
      ]),
    ))).toList()),
  );
}

// ─── Bottom sheet: Resumen IA del Foro ────────────────────────────────────────


// ─── Bottom sheet: Resumen IA del Foro ────────────────────────────────────────

class _ForoResumenSheet extends StatefulWidget {
  final String nombreProyecto;
  final String? resumenInicial;
  final Future<String?> Function() onGenerar;

  const _ForoResumenSheet({
    required this.nombreProyecto,
    required this.resumenInicial,
    required this.onGenerar,
  });

  @override
  State<_ForoResumenSheet> createState() => _ForoResumenSheetState();
}

class _ForoResumenSheetState extends State<_ForoResumenSheet> {
  String? _resumen;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _resumen = widget.resumenInicial;
    if (_resumen == null) _generar();
  }

  Future<void> _generar() async {
    setState(() => _cargando = true);
    try {
      final r = await widget.onGenerar();
      if (mounted) setState(() => _resumen = r);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B21B6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF5B21B6)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Resumen del Foro',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                if (widget.nombreProyecto.isNotEmpty)
                  Text(widget.nombreProyecto,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF5B21B6)),
                tooltip: 'Regenerar resumen',
                onPressed: _cargando ? null : _generar,
              ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: Colors.grey.shade400),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cargando
                ? const _ResumenSkeleton()
                : _resumen == null
                    ? Center(child: Text('No se pudo generar el resumen.',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)))
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        children: _buildMarkdown(_resumen!),
                      ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _buildMarkdown(String text) {
    final widgets = <Widget>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();
      if (line.startsWith('### ')) {
        widgets.add(_mdHeading(line.substring(4), level: 3));
      } else if (line.startsWith('## ')) {
        widgets.add(_mdHeading(line.substring(3), level: 2));
      } else if (line.startsWith('# ')) {
        widgets.add(_mdHeading(line.substring(2), level: 1));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(_mdBullet(line.substring(2)));
      } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        widgets.add(_mdBullet(line.replaceFirst(RegExp(r'^\d+\.\s'), '')));
      } else if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else {
        widgets.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: _richText(line)));
      }
    }
    return widgets;
  }

  Widget _mdHeading(String text, {required int level}) {
    final sizes = {1: 16.0, 2: 14.0, 3: 13.0};
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(text.replaceAll('**', ''),
          style: GoogleFonts.inter(fontSize: sizes[level] ?? 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
    );
  }

  Widget _mdBullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5, left: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, right: 8),
        child: Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF5B21B6))),
      ),
      Expanded(child: _richText(text)),
    ]),
  );

  Widget _richText(String text) {
    final spans = <TextSpan>[];
    final boldRe = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in boldRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.5),
        children: spans,
      ),
    );
  }
}

// ─── Skeleton de carga para el resumen IA ────────────────────────────────────

class _ResumenSkeleton extends StatefulWidget {
  const _ResumenSkeleton();

  @override
  State<_ResumenSkeleton> createState() => _ResumenSkeletonState();
}

class _ResumenSkeletonState extends State<_ResumenSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.9).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final color = Color.lerp(Colors.grey.shade200, Colors.grey.shade300, _anim.value)!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // Título sección
            _bar(color, width: 140, height: 13),
            const SizedBox(height: 14),
            // Bullets
            for (int i = 0; i < 4; i++) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                _circle(color),
                const SizedBox(width: 8),
                Expanded(child: _bar(color, height: 11)),
              ]),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 20),
            // Título sección 2
            _bar(color, width: 180, height: 13),
            const SizedBox(height: 14),
            _bar(color, height: 11),
            const SizedBox(height: 8),
            _bar(color, width: double.infinity, height: 11),
            const SizedBox(height: 8),
            _bar(color, width: 200, height: 11),
            const SizedBox(height: 20),
            // Título sección 3
            _bar(color, width: 100, height: 13),
            const SizedBox(height: 14),
            for (int i = 0; i < 2; i++) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                _circle(color),
                const SizedBox(width: 8),
                Expanded(child: _bar(color, height: 11)),
              ]),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _bar(Color color, {double? width, double height = 12}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
  );

  Widget _circle(Color color) => Container(
    width: 6, height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
