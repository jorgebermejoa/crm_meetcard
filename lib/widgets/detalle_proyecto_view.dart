import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../app_shell.dart';
import '../models/configuracion.dart';
import '../models/proyecto.dart';
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
  static const _primaryColor = Color(0xFF1E1B6B);
  static const _bgColor = Color(0xFFF2F2F7);

  late Proyecto _proyecto;
  late TabController _tabController;

  Map<String, dynamic>? _ocdsData;
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

  List<String> _modalidades = ['Licitación Pública', 'Convenio Marco', 'Trato Directo', 'Otro'];
  List<String> _productosOpciones = [];
  List<String> _tiposDocumento = ['Contrato', 'Orden de Compra', 'Acta de Evaluación', 'Otro'];
  List<EstadoItem> _estados = [
    EstadoItem(nombre: 'Postulación', color: '6366F1'),
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
      const Tab(text: 'Certificados'),
      const Tab(text: 'Reclamos'),
    ];
  }

  int get _tabCount => _tabs.length;

  void _rebuildTabController() {
    _tabController.dispose();
    _tabController = TabController(length: _tabCount, vsync: this);
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
    super.dispose();
  }

  // ─── DATA ─────────────────────────────────────────────────────────────────

  Future<void> _cargarOcds({bool forceRefresh = false}) async {
    setState(() { _cargandoOcds = true; _errorOcds = null; });
    final idLic = _proyecto.idLicitacion!;
    // 1. Try cache
    if (!forceRefresh) {
      try {
        final cResp = await http.get(Uri.parse(
            '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=ocds'))
            .timeout(const Duration(seconds: 10));
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            if (mounted) {
              setState(() {
                _ocdsData = c['data'];
                _ocdsLastFetch = c['fetchedAt']?.toString();
                _cargandoOcds = false;
              });
              _sincronizarFechasDesdeOcds();
            }
            return;
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
      } else {
        if (mounted) setState(() { _errorOcds = 'Error ${resp.statusCode}'; _cargandoOcds = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorOcds = e.toString(); _cargandoOcds = false; });
    }
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
  }

  Future<Map<String, dynamic>?> _cargarUnaOc(String id, {bool forceRefresh = false}) async {
    final cacheKey = 'oc_$id';
    // 1. Try cache
    if (!forceRefresh) {
      try {
        final cResp = await http.get(Uri.parse(
            '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=${Uri.encodeComponent(cacheKey)}'))
            .timeout(const Duration(seconds: 10));
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
            if (mounted) setState(() => _ocLastFetchMap[id] = c['fetchedAt']?.toString());
            return c['data'] as Map<String, dynamic>;
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
    // 1. Try cache
    if (!forceRefresh) {
      try {
        final cResp = await http.get(Uri.parse(
            '$_baseUrl/obtenerCacheExterno?proyectoId=${_proyecto.id}&tipo=convenio'))
            .timeout(const Duration(seconds: 10));
        if (cResp.statusCode == 200) {
          final c = json.decode(cResp.body);
          if (c != null && c['data'] != null) {
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

  Widget _refreshBar(String? lastFetch, VoidCallback onRefresh) {
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
          onTap: onRefresh,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh, size: 14, color: _primaryColor.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text('Actualizar', style: GoogleFonts.inter(fontSize: 12, color: _primaryColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
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
                                  Expanded(child: Text(item.nombre, style: GoogleFonts.inter(fontSize: 14, color: isSelected ? item.fgColor : const Color(0xFF1E293B), fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400))),
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

  // ─── HEADER ───────────────────────────────────────────────────────────────

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

    final badgesRow = Row(
      children: [
        if (hasFicha) ...[
          _fichaButton(),
          const SizedBox(width: 8),
        ],
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
          badgesRow,
          const SizedBox(height: 8),
          titleText,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleText),
              const SizedBox(width: 12),
              badgesRow,
            ],
          ),
        const SizedBox(height: 6),
        Text(subtitleText,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
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
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: stats.map(_buildStatCard).toList(),
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
              isScrollable: false,
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
        if (_proyecto.estadoManual == EstadoProyecto.postulacion) ...[
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
      ],
    );
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
    if (_ocdsData == null) return const SizedBox();

    final releases =
        (_ocdsData!['releases'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    if (releases.isEmpty) {
      return Center(
          child: Text('Sin datos OCDS',
              style: GoogleFonts.inter(color: Colors.grey.shade500)));
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
        _refreshBar(_ocdsLastFetch, () => _cargarOcds(forceRefresh: true)),
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
        _refreshBar(_convenioLastFetch, () => _cargarConvenio(forceRefresh: true)),
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
    // Only full-block spinner when nothing loaded yet
    if (_cargandoOc && _ocDataList.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator()));
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor.withValues(alpha: 0.5))),
                const SizedBox(width: 12),
                Text('Cargando OC ${_proyecto.idsOrdenesCompra[i]}...',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
              ]),
            ),
        ],
      ],
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
    final totalAcum = ocs.fold<double>(0, (s, oc) => s + ((oc['Total'] as num?)?.toDouble() ?? 0));
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

    // Key date: aceptación > envío > creación
    String? fechaClaveLabel;
    String? fechaClaveVal;
    if (fechas['FechaAceptacion'] != null) {
      fechaClaveLabel = 'Aceptación';
      fechaClaveVal = _fmtDateStr(fechas['FechaAceptacion'].toString());
    } else if (fechas['FechaCancelacion'] != null) {
      fechaClaveLabel = 'Cancelación';
      fechaClaveVal = _fmtDateStr(fechas['FechaCancelacion'].toString());
    } else if (fechas['FechaEnvio'] != null) {
      fechaClaveLabel = 'Envío';
      fechaClaveVal = _fmtDateStr(fechas['FechaEnvio'].toString());
    } else if (fechas['FechaCreacion'] != null) {
      fechaClaveLabel = 'Creación';
      fechaClaveVal = _fmtDateStr(fechas['FechaCreacion'].toString());
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Refresh bar
        Container(
          color: _bgColor.withValues(alpha: 0.6),
          child: _refreshBar(_ocLastFetchMap[ocId], () => _recargarUnaOc(ocId)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.business_outlined, size: 16, color: _primaryColor)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(proveedor['Nombre']?.toString() ?? '', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                if (proveedor['RutSucursal'] != null)
                  Text('RUT ${proveedor['RutSucursal']}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
              ])),
              if (fechaClaveLabel != null) ...[
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fechaClaveLabel, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(fechaClaveVal ?? '', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600)),
                ]),
              ],
            ]),
          ),

        const Divider(height: 1),

        // Montos en fila
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            if (neto != null)
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NETO', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500, letterSpacing: 0.4)),
                const SizedBox(height: 4),
                Text('\$ ${_fmt((neto as num).toInt())}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
              ])),
            if (impuestos != null)
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pctIva != null ? 'IVA ${(pctIva as num).toInt()}%' : 'IMPUESTO',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500, letterSpacing: 0.4)),
                const SizedBox(height: 4),
                Text('\$ ${_fmt((impuestos as num).toInt())}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
              ])),
            if (total != null)
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TOTAL', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                const SizedBox(height: 4),
                Text('\$ ${_fmt((total as num).toInt())}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: _primaryColor)),
              ])),
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
    if (_proyecto.estadoManual != EstadoProyecto.postulacion) return;

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
    if (_proyecto.estadoManual != EstadoProyecto.postulacion) return;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: item.bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(estado,
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
              color: const Color(0xFF1E1B6B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insert_drive_file_outlined,
                color: Color(0xFF1E1B6B), size: 20),
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
              backgroundColor: const Color(0xFF1E1B6B),
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
  static const _primaryColor = Color(0xFF1E1B6B);
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
