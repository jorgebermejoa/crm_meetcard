import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../app_shell.dart';
import '../models/configuracion.dart';
import '../models/proyecto.dart';
import '../services/config_service.dart';
import '../services/proyectos_service.dart';
import 'app_breadcrumbs.dart';
import 'proyecto_form_dialog.dart';

// Top-level helper: strips "|" suffix and "Unidad de compra:" prefix from institution name
String _cleanInst(String raw) {
  var s = raw.split('|').first.trim();
  if (s.toLowerCase().startsWith('unidad de compra:')) {
    s = s.substring('unidad de compra:'.length).trim();
  }
  return s;
}

class ProyectosView extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;

  const ProyectosView({super.key, this.onOpenMenu, this.onBack});

  @override
  State<ProyectosView> createState() => _ProyectosViewState();
}

class _ProyectosViewState extends State<ProyectosView>
    with TickerProviderStateMixin {
  static const _primaryColor = Color(0xFF5B21B6);
  static const _pageSize = 10;

  late final TabController _tabController;

  // Data
  List<Proyecto> _proyectos = [];
  bool _cargando = true;
  String? _error;

  // Gantt mode: 'contrato' | 'ruta' | 'postulacion'
  String _ganttMode = 'contrato';
  // Expanded rows (postulación mode — show milestones)
  final Set<String> _ganttExpandedRows = {};
  // Window override (null = auto-fit data range)
  DateTime? _ganttWindowStart;
  DateTime? _ganttWindowEnd;

  // Filters
  String? _filterInstitucion;
  Set<String> _filterProductos = {};
  String? _filterModalidad;
  String? _filterEstado;
  String? _filterReclamo;   // 'Pendiente' | 'Respondido'
  String? _filterVencer;    // '30 días' | '3 meses' | '6 meses' | '12 meses'

  // Pagination
  int _currentPage = 0;

  // Sorting
  int? _sortColumn;
  bool _sortAscending = true;

  // Config
  List<String> _cfgModalidades = [
    'Licitación Pública',
    'Convenio Marco',
    'Trato Directo',
    'Otro'
  ];
  List<EstadoItem> _cfgEstados = [
    EstadoItem(nombre: 'Vigente', color: '10B981'),
    EstadoItem(nombre: 'X Vencer', color: 'F59E0B'),
    EstadoItem(nombre: 'Finalizado', color: '64748B'),
    EstadoItem(nombre: 'Sin fecha', color: 'EF4444'),
  ];
  List<ProductoItem> _cfgProductos = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargar();
    ConfigService.instance.load().then((cfg) {
      if (!mounted) return;
      setState(() {
        if (cfg.modalidades.isNotEmpty) _cfgModalidades = cfg.modalidades;
        if (cfg.estados.isNotEmpty) _cfgEstados = cfg.estados;
        if (cfg.productos.isNotEmpty) _cfgProductos = cfg.productos;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool forceRefresh = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final list =
          await ProyectosService.instance.load(forceRefresh: forceRefresh);
      if (mounted) setState(() { _proyectos = list; _cargando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _cargando = false; });
    }
  }

  void _clearFilters() {
    setState(() {
      _filterInstitucion = null;
      _filterProductos = {};
      _filterModalidad = null;
      _filterEstado = null;
      _filterReclamo = null;
      _filterVencer = null;
      _currentPage = 0;
    });
  }

  void _setSort(int col) {
    setState(() {
      if (_sortColumn == col) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = col;
        _sortAscending = true;
      }
      _currentPage = 0;
    });
  }

  List<Proyecto> _applySorting(List<Proyecto> list) {
    if (_sortColumn == null) return list;
    final sorted = [...list];
    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 0:
          cmp = a.institucion.compareTo(b.institucion);
          break;
        case 1:
          cmp = a.productos.compareTo(b.productos);
          break;
        case 2:
          cmp = (a.valorMensual ?? 0).compareTo(b.valorMensual ?? 0);
          break;
        case 3:
          cmp = (a.fechaInicio ?? DateTime(0))
              .compareTo(b.fechaInicio ?? DateTime(0));
          break;
        case 4:
          cmp = (a.fechaTermino ?? DateTime(0))
              .compareTo(b.fechaTermino ?? DateTime(0));
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProyectoFormDialog(isEditing: false),
    );
    if (result != null) _cargar(forceRefresh: true);
  }

  Future<void> _openEditDialog(Proyecto proyecto, {String? tab}) async {
    final extra = tab != null
        ? {'proyecto': proyecto, 'tab': tab}
        : proyecto;
    await context.push('/proyectos/${proyecto.id}', extra: extra);
    _cargar(forceRefresh: true);
  }

  List<Proyecto> _applyFilters(List<Proyecto> all) {
    return all.where((p) {
      if (_filterInstitucion != null && _filterInstitucion!.isNotEmpty) {
        if (!p.institucion
            .toLowerCase()
            .contains(_filterInstitucion!.toLowerCase())) { return false; }
      }
      if (_filterProductos.isNotEmpty) {
        final pp = p.productos.split(',').map((s) => s.trim()).toSet();
        if (!_filterProductos.any((prod) => pp.contains(prod))) return false;
      }
      if (_filterModalidad != null && _filterModalidad!.isNotEmpty) {
        if (p.modalidadCompra != _filterModalidad) return false;
      }
      if (_filterEstado != null && _filterEstado!.isNotEmpty) {
        if (p.estado != _filterEstado) return false;
      }
      if (_filterReclamo != null) {
        if (_filterReclamo == 'Pendiente') {
          if (!p.reclamos.any((r) => r.estado == 'Pendiente')) return false;
        } else {
          if (!p.reclamos.any((r) => r.estado != 'Pendiente' &&
              (r.fechaRespuesta != null || (r.descripcionRespuesta?.isNotEmpty == true)))) {
            return false;
          }
        }
      }
      if (_filterVencer != null) {
        final dias = _vencerDias(_filterVencer!);
        final ft = p.fechaTermino;
        if (ft == null) return false;
        final now = DateTime.now();
        final limite = now.add(Duration(days: dias));
        if (!ft.isAfter(now) || !ft.isBefore(limite)) return false;
      }
      return true;
    }).toList();
  }

  static int _vencerDias(String periodo) {
    switch (periodo) {
      case '30 días': return 30;
      case '3 meses': return 90;
      case '6 meses': return 180;
      default: return 365;
    }
  }

  Widget _buildAppBar(bool isMobile) {
    final hPad = isMobile ? 20.0 : 32.0;
    return buildBreadcrumbAppBar(
      context: context,
      hPad: hPad,
      onOpenMenu: openAppDrawer,
      crumbs: [BreadcrumbItem('Proyectos')],
    );
  }

  void _showExportMenu(BuildContext context) {
    final filtered = _applySorting(_applyFilters(_proyectos));
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Exportar proyectos',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text('${filtered.length} proyecto${filtered.length != 1 ? 's' : ''}${_hasActiveFilters ? ' (con filtros aplicados)' : ''}',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          _exportOption(Icons.table_chart_outlined, 'Exportar a Excel (CSV)',
              'Abrir en Excel o Google Sheets', () {
            Navigator.pop(context);
            _exportCSV(filtered);
          }),
          const SizedBox(height: 8),
          _exportOption(Icons.print_outlined, 'Imprimir / PDF',
              'Usa el diálogo de impresión del navegador', () async {
            Navigator.pop(context);
            await Future.delayed(const Duration(milliseconds: 400));
            web.window.print();
          }),
        ]),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filterInstitucion != null || _filterProductos.isNotEmpty ||
      _filterModalidad != null || _filterEstado != null ||
      _filterReclamo != null || _filterVencer != null;

  Widget _exportOption(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: const Color(0xFFF8FAFC),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: const Color(0xFF5B21B6).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: const Color(0xFF5B21B6)),
      ),
      title: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
          color: const Color(0xFF1E293B))),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
      onTap: onTap,
    );
  }

  void _exportCSV(List<Proyecto> proyectos) {
    final buf = StringBuffer();
    buf.writeln('ID,Institución,Productos,Modalidad,Estado,Valor Mensual,Fecha Inicio,Fecha Término');
    for (final p in proyectos) {
      String esc(String s) => '"${s.replaceAll('"', '""')}"';
      buf.writeln([
        esc(p.id),
        esc(_cleanInst(p.institucion)),
        esc(p.productos),
        esc(p.modalidadCompra),
        esc(p.estado),
        p.valorMensual?.toStringAsFixed(0) ?? '',
        p.fechaInicio != null ? '${p.fechaInicio!.day}/${p.fechaInicio!.month}/${p.fechaInicio!.year}' : '',
        p.fechaTermino != null ? '${p.fechaTermino!.day}/${p.fechaTermino!.month}/${p.fechaTermino!.year}' : '',
      ].join(','));
    }
    // Prepend UTF-8 BOM so Excel auto-detects encoding and renders accents correctly
    final bytes = utf8.encode('\uFEFF${buf.toString()}');
    final blob = web.Blob([bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = 'proyectos_${DateTime.now().millisecondsSinceEpoch}.csv';
    web.document.body!.appendChild(anchor);
    anchor.click();
    web.document.body!.removeChild(anchor);
    web.URL.revokeObjectURL(url);
  }

  // ── RESUMEN TAB content ────────────────────────────────────────────────────

  Widget _buildTabResumen(bool isMobile) {
    final vigentes = _proyectos.where((p) => p.estado == EstadoProyecto.vigente).toList();
    final xVencer = _proyectos.where((p) => p.estado == EstadoProyecto.xVencer).toList();
    final activos = [...vigentes, ...xVencer];

    final reclamosPendientes = <({Proyecto proyecto, Reclamo reclamo})>[];
    int reclamosFinalizados = 0;
    for (final p in _proyectos) {
      for (final r in p.reclamos) {
        if (r.estado == 'Pendiente') {
          reclamosPendientes.add((proyecto: p, reclamo: r));
        } else if (r.fechaRespuesta != null ||
            (r.descripcionRespuesta?.isNotEmpty == true)) {
          reclamosFinalizados++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKpiRow(activos.length, _proyectos,
            reclamosPendientes.length, reclamosFinalizados, xVencer.length, isMobile),
        if (reclamosPendientes.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildReclamosPendientes(reclamosPendientes, isMobile),
        ],
        const SizedBox(height: 24),
        _buildGanttSection(_proyectos, isMobile),
      ],
    );
  }

  // ── KPI ROW ────────────────────────────────────────────────────────────────

  void _goToProyectosFiltered(String? estado) {
    setState(() { _filterEstado = estado; _currentPage = 0; });
    _tabController.animateTo(1);
  }

  void _goToReclamosFiltered(String reclamo) {
    setState(() { _filterReclamo = reclamo; _currentPage = 0; });
    _tabController.animateTo(1);
  }

  void _goToVencerFiltered(int dias) {
    final label = dias == 30 ? '30 días' : dias == 90 ? '3 meses' : dias == 180 ? '6 meses' : '12 meses';
    setState(() { _filterVencer = label; _currentPage = 0; });
    _tabController.animateTo(1);
  }

  Widget _buildKpiRow(int activos, List<Proyecto> proyectos, int reclamosPend,
      int reclamosFinalizados, int xVencer, bool isMobile) {
    final cards = [
      _ProyectosKpiCard(proyectos: proyectos, onNavigate: _goToProyectosFiltered),
      _ValorMensualCard(proyectos: proyectos, onNavigate: _goToProyectosFiltered),
      _ReclamosCard(pendientes: reclamosPend, finalizados: reclamosFinalizados, onNavigate: _goToReclamosFiltered),
      _XVencerKpiCard(proyectos: proyectos, onNavigate: _goToVencerFiltered),
    ];

    Widget actionBadges() => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _actionBadge(
              icon: Icons.file_download_outlined,
              tooltip: 'Exportar',
              onTap: () => _showExportMenu(context),
            ),
            const SizedBox(width: 6),
            _actionBadge(
              icon: Icons.refresh,
              tooltip: 'Actualizar',
              loading: _cargando,
              onTap: _cargando ? null : () => _cargar(forceRefresh: true),
            ),
          ],
        );

    if (isMobile) {
      return Column(children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: cards[2]),
          const SizedBox(width: 12),
          Expanded(child: cards[3]),
        ]),
        const SizedBox(height: 8),
        actionBadges(),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: cards.asMap().entries.map((e) {
            return Expanded(
              child: Padding(
                padding:
                    EdgeInsets.only(right: e.key < cards.length - 1 ? 14 : 0),
                child: e.value,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        actionBadges(),
      ],
    );
  }

  Widget _actionBadge({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF64748B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF5B21B6)),
                )
              : Icon(icon, size: 14, color: const Color(0xFF64748B)),
        ),
      ),
    );
  }

  // ── RECLAMOS PENDIENTES ────────────────────────────────────────────────────

  Widget _buildReclamosPendientes(
      List<({Proyecto proyecto, Reclamo reclamo})> items, bool isMobile) {
    // Group by project, keeping earliest pending fechaReclamo
    final Map<String, ({Proyecto proyecto, int count, DateTime? fecha})> byProject = {};
    for (final item in items) {
      final id = item.proyecto.id;
      final fecha = item.reclamo.fechaReclamo;
      if (byProject.containsKey(id)) {
        final prev = byProject[id]!;
        final earliest = (prev.fecha == null || (fecha != null && fecha.isBefore(prev.fecha!)))
            ? fecha : prev.fecha;
        byProject[id] = (proyecto: item.proyecto, count: prev.count + 1, fecha: earliest);
      } else {
        byProject[id] = (proyecto: item.proyecto, count: 1, fecha: fecha);
      }
    }
    final proyectosConReclamos = byProject.values.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.warning_amber_rounded,
                size: 14, color: Color(0xFFDC2626)),
            const SizedBox(width: 6),
            Text(
              '${items.length} RECLAMO${items.length > 1 ? 'S' : ''} PENDIENTE${items.length > 1 ? 'S' : ''}',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFDC2626),
                  letterSpacing: 0.3),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      ...proyectosConReclamos.map((entry) =>
          _buildReclamoPendienteCard(entry.proyecto, entry.count, entry.fecha, isMobile)),
    ]);
  }

  Widget _buildReclamoPendienteCard(
      Proyecto proyecto, int count, DateTime? fechaIngreso, bool isMobile) {
    String? fechaStr;
    if (fechaIngreso != null) {
      fechaStr = 'Ingresado el ${fechaIngreso.day.toString().padLeft(2, '0')}/'
          '${fechaIngreso.month.toString().padLeft(2, '0')}/'
          '${fechaIngreso.year}';
    }
    return GestureDetector(
      onTap: () => _openEditDialog(proyecto, tab: 'reclamos'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA), width: 1),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Row(children: [
          const Icon(Icons.gavel_outlined, size: 15, color: Color(0xFFDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _cleanInst(proyecto.institucion),
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                ),
                if (fechaStr != null) ...[
                  const SizedBox(height: 2),
                  Text(fechaStr,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ],
            ),
          ),
          if (count > 1) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$count',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: const Color(0xFFDC2626))),
            ),
          ],
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
        ]),
      ),
    );
  }

  static const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

  /// Para proyectos en Postulación con idLicitacion pero sin fechaPublicacion,
  /// obtiene las fechas desde OCDS y las guarda en Firestore automáticamente.
  Future<void> _sincronizarPostulacionDesdeOcds() async {
    final pendientes = _proyectos.where((p) =>
        p.estadoManual == EstadoProyecto.postulacion &&
        p.idLicitacion != null &&
        p.idLicitacion!.isNotEmpty &&
        (p.fechaPublicacion == null || p.fechaConsultasInicio == null)).toList();

    if (pendientes.isEmpty) return;

    bool huboActualizaciones = false;
    for (final p in pendientes) {
      try {
        final resp = await http.get(
            Uri.parse('$_cfBase/buscarLicitacionPorId?id=${Uri.encodeComponent(p.idLicitacion!)}'))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) continue;

        final data = json.decode(resp.body) as Map<String, dynamic>;
        final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (releases.isEmpty) continue;
        final tender = releases.last['tender'] as Map<String, dynamic>? ?? {};

        final tp = tender['tenderPeriod'] as Map<String, dynamic>?;
        final eq = tender['enquiryPeriod'] as Map<String, dynamic>?;
        final ap = tender['awardPeriod'] as Map<String, dynamic>?;

        final updates = <String, dynamic>{'id': p.id};
        if (p.fechaPublicacion == null && tp?['startDate'] != null) updates['fechaPublicacion'] = tp!['startDate'];
        if (p.fechaCierre == null && tp?['endDate'] != null)         updates['fechaCierre'] = tp!['endDate'];
        if (p.fechaConsultasInicio == null && eq?['startDate'] != null) updates['fechaConsultasInicio'] = eq!['startDate'];
        if (p.fechaConsultas == null && eq?['endDate'] != null)         updates['fechaConsultas'] = eq!['endDate'];
        if (p.fechaAdjudicacion == null && ap?['startDate'] != null)    updates['fechaAdjudicacion'] = ap!['startDate'];
        if (p.fechaAdjudicacionFin == null && ap?['endDate'] != null)   updates['fechaAdjudicacionFin'] = ap!['endDate'];

        if (updates.length <= 1) continue;

        await http.post(Uri.parse('$_cfBase/actualizarProyecto'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updates));
        huboActualizaciones = true;
      } catch (_) {}
    }

    if (huboActualizaciones) _cargar(forceRefresh: true);
  }

  // ── GANTT HELPERS ──────────────────────────────────────────────────────────

  DateTime startOf(Proyecto p, {required bool isRuta, required bool isPostulacion}) {
    if (isPostulacion) return p.fechaPublicacion!;
    if (isRuta) return p.fechaInicioRuta!;
    return p.fechaInicio!;
  }

  DateTime endOf(Proyecto p, {required bool isRuta, required bool isPostulacion}) {
    if (isPostulacion) return p.fechaCierre!;
    if (isRuta) return p.fechaTerminoRuta!;
    return p.fechaTermino!;
  }

  // ── GANTT ──────────────────────────────────────────────────────────────────

  Widget _buildGanttSection(List<Proyecto> proyectos, bool isMobile) {
    final isRuta = _ganttMode == 'ruta';
    final isPostulacion = _ganttMode == 'postulacion';

    bool hasDates(Proyecto p) {
      if (isPostulacion) return p.fechaPublicacion != null && p.fechaCierre != null && p.fechaCierre!.isAfter(p.fechaPublicacion!);
      if (isRuta) return p.fechaInicioRuta != null && p.fechaTerminoRuta != null && p.fechaTerminoRuta!.isAfter(p.fechaInicioRuta!);
      return p.fechaInicio != null && p.fechaTermino != null && p.fechaTermino!.isAfter(p.fechaInicio!);
    }

    // Pre-filter by estado before date check
    final byEstado = isPostulacion
        ? proyectos.where((p) => p.estado == EstadoProyecto.postulacion).toList()
        : proyectos.where((p) => p.estado == EstadoProyecto.vigente).toList();

    final withDates = byEstado.where(hasDates).toList()
      ..sort((a, b) => startOf(a, isRuta: isRuta, isPostulacion: isPostulacion)
          .compareTo(startOf(b, isRuta: isRuta, isPostulacion: isPostulacion)));

    final String emptyMsg = isPostulacion
        ? 'Ningún proyecto en estado Postulación tiene fechas de publicación y cierre registradas.'
        : isRuta
            ? 'Ningún proyecto tiene fechas de ruta de implementación registradas.'
            : '';

    if (withDates.isEmpty && _ganttMode == 'contrato') return const SizedBox();
    if (withDates.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildGanttHeader(isMobile, autoStart: DateTime.now(), autoEnd: DateTime.now(), stepMonths: 1),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Expanded(child: Text(emptyMsg, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500))),
          ]),
        ),
      ]);
    }

    DateTime startOf2(Proyecto p) => startOf(p, isRuta: isRuta, isPostulacion: isPostulacion);
    // Bar ends at fechaCierre (cierre recepción ofertas); adjudicación is a separate milestone.
    DateTime endOf2(Proyecto p) => endOf(p, isRuta: isRuta, isPostulacion: isPostulacion);

    final dataStart = startOf2(withDates.first);
    final dataEnd = withDates.map((p) => endOf2(p)).reduce((a, b) => a.isAfter(b) ? a : b);
    // Add 2-week padding on each side for visual comfort
    final autoStart = dataStart.subtract(const Duration(days: 14));
    final autoEnd = dataEnd.add(const Duration(days: 14));
    final rangeStart = _ganttWindowStart ?? autoStart;
    final rangeEnd = _ganttWindowEnd ?? autoEnd;
    final totalDays =
        rangeEnd.difference(rangeStart).inDays.toDouble().clamp(1.0, 36500.0);
    final spanMonths = (totalDays / 30).round();

    // Adaptive step: yearly for long spans, quarterly, or monthly
    final int stepMonths;
    if (spanMonths > 24) {
      stepMonths = 12;
    } else if (spanMonths > 12) {
      stepMonths = 6;
    } else if (spanMonths > 6) {
      stepMonths = 3;
    } else {
      stepMonths = 1;
    }

    final labelW = isMobile ? 100.0 : 190.0;
    final dateW = (isPostulacion || isRuta) ? 78.0 : 58.0;
    const barH = 20.0;
    const rowH = 48.0;
    const headerH = 36.0;

    const monthNames = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];

    List<({double frac, String label, bool isMajor})> buildMarkers() {
      final markers = <({double frac, String label, bool isMajor})>[];
      // Snap to first tick: round up to nearest stepMonths boundary
      int startMonth = rangeStart.month;
      int startYear = rangeStart.year;
      // advance to next step boundary
      final rem = (startMonth - 1) % stepMonths;
      if (rem != 0) {
        startMonth += stepMonths - rem;
        if (startMonth > 12) {
          startMonth -= 12;
          startYear++;
        }
      }
      var cursor = DateTime(startYear, startMonth, 1);
      while (cursor.isBefore(rangeEnd) || cursor.isAtSameMomentAs(rangeEnd)) {
        final days = cursor.difference(rangeStart).inDays.toDouble();
        final frac = (days / totalDays).clamp(0.0, 1.0);
        final isMajor = cursor.month == 1 || stepMonths == 12;
        final yearStr = isMobile
            ? "'${(cursor.year % 100).toString().padLeft(2, '0')}"
            : cursor.year.toString();
        final label = stepMonths >= 12
            ? yearStr
            : isMajor
                ? '${monthNames[cursor.month - 1]}\n$yearStr'
                : monthNames[cursor.month - 1];
        markers.add((frac: frac, label: label, isMajor: isMajor));
        var nextMonth = cursor.month + stepMonths;
        var nextYear = cursor.year;
        while (nextMonth > 12) {
          nextMonth -= 12;
          nextYear++;
        }
        cursor = DateTime(nextYear, nextMonth, 1);
      }
      return markers;
    }

    // Day-level ticks for short spans (postulación / ruta)
    final bool useDayMarkers = (isPostulacion || isRuta) && totalDays <= 60;
    List<({double frac, String label, bool isMajor})> buildDayMarkers(int stepDays) {
      final result = <({double frac, String label, bool isMajor})>[];
      var cursor = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
      while (cursor.isBefore(rangeEnd)) {
        final days = cursor.difference(rangeStart).inDays.toDouble();
        final frac = (days / totalDays).clamp(0.0, 1.0);
        final isMajor = cursor.day == 1 || stepDays >= 7;
        final label = '${cursor.day.toString().padLeft(2, '0')}/${cursor.month.toString().padLeft(2, '0')}';
        result.add((frac: frac, label: label, isMajor: isMajor));
        cursor = cursor.add(Duration(days: stepDays));
      }
      return result;
    }

    // Compute adaptive step from chart width (called inside LayoutBuilder)
    int adaptiveStepDays(double chartW) {
      const minPixels = 34.0; // min px between ticks to avoid overlap
      final maxTicks = (chartW / minPixels).floor().clamp(2, 200);
      final raw = (totalDays / maxTicks).ceil();
      if (raw <= 1) return 1;
      if (raw <= 2) return 2;
      if (raw <= 3) return 3;
      if (raw <= 7) return 7;
      if (raw <= 14) return 14;
      return 30;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildGanttHeader(isMobile, autoStart: autoStart, autoEnd: autoEnd, stepMonths: stepMonths),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: LayoutBuilder(builder: (ctx, constraints) {
          final chartW = (constraints.maxWidth - labelW - dateW - 16)
              .clamp(40.0, 10000.0);
          final markers = useDayMarkers ? buildDayMarkers(adaptiveStepDays(chartW)) : buildMarkers();

          // Today fraction
          final todayDays = DateTime.now()
              .difference(rangeStart)
              .inDays
              .toDouble()
              .clamp(0.0, totalDays);
          final todayFrac = todayDays / totalDays;

          Widget todayLine() {
            if (todayFrac <= 0 || todayFrac >= 1) return const SizedBox();
            return Positioned(
              left: todayFrac * chartW,
              top: 0,
              bottom: 0,
              width: 1.5,
              child: Container(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.55)),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(width: labelW + 8),
                SizedBox(
                  width: chartW,
                  height: headerH,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // Tick lines
                      ...markers.map((m) => Positioned(
                            left: m.frac * chartW,
                            top: m.isMajor ? 0 : headerH * 0.4,
                            bottom: 0,
                            width: m.isMajor ? 1.5 : 1,
                            child: Container(
                                color: m.isMajor
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade200),
                          )),
                      // Today tick in header
                      if (todayFrac > 0 && todayFrac < 1)
                        Positioned(
                          left: todayFrac * chartW,
                          top: 0,
                          bottom: 0,
                          width: 1.5,
                          child: Container(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.55)),
                        ),
                      // Labels
                      ...markers.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final m = entry.value;
                        final left =
                            (m.frac * chartW + 4).clamp(0.0, chartW - 38.0);
                        // Stagger odd day-marker labels lower to prevent overlap on mobile
                        final top = (useDayMarkers && idx.isOdd) ? 14.0 : 0.0;
                        return Positioned(
                          left: left,
                          top: top,
                          child: Text(
                            m.label,
                            style: GoogleFonts.inter(
                              fontSize: m.isMajor ? 10 : 9,
                              fontWeight: m.isMajor
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: m.isMajor
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                              height: 1.3,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ]),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
              // ── Project rows ──
              ...withDates.map((p) {
                final startDays = startOf2(p)
                    .difference(rangeStart)
                    .inDays
                    .toDouble()
                    .clamp(0.0, totalDays);
                final endDays = endOf2(p)
                    .difference(rangeStart)
                    .inDays
                    .toDouble()
                    .clamp(0.0, totalDays);
                final leftFrac = startDays / totalDays;
                final widthFrac =
                    ((endDays - startDays) / totalDays).clamp(0.0, 1.0);

                Color barColor;
                if (isPostulacion) {
                  barColor = const Color(0xFF6366F1);
                } else {
                  switch (p.estado) {
                    case EstadoProyecto.vigente:
                      barColor = const Color(0xFF10B981);
                      break;
                    case EstadoProyecto.xVencer:
                      barColor = const Color(0xFFF59E0B);
                      break;
                    default:
                      barColor = Colors.grey.shade300;
                  }
                }

                final instFull = p.institucion.split('|').first.trim();
                final instDisplay = instFull
                    .replaceAll(RegExp(r'\bI(?:LUSTRE)?\b\.?\s+MUNICIPALIDAD\b', caseSensitive: false), 'I.M.')
                    .replaceAll(RegExp(r'\bMUNICIPALIDAD\b', caseSensitive: false), 'Mpal.');

                final isExpanded = _ganttExpandedRows.contains(p.id);

                // Milestone helpers for postulación
                Widget milestoneRow() {
                  if (!isPostulacion || !isExpanded) return const SizedBox();
                  const milestoneH = 32.0;
                  final milestones = <({DateTime date, String label, Color color})>[];
                  if (p.fechaConsultas != null) milestones.add((date: p.fechaConsultas!, label: 'Consultas', color: const Color(0xFF0EA5E9)));
                  if (p.fechaAdjudicacion != null) milestones.add((date: p.fechaAdjudicacion!, label: 'Adjudicación', color: const Color(0xFFF59E0B)));
                  if (milestones.isEmpty) return const SizedBox();
                  return SizedBox(
                    height: milestoneH,
                    child: Row(children: [
                      SizedBox(width: labelW + 8),
                      SizedBox(
                        width: chartW,
                        height: milestoneH,
                        child: Stack(clipBehavior: Clip.hardEdge, children: [
                          ...markers.map((m) => Positioned(
                                left: m.frac * chartW, top: 0, bottom: 0, width: 1,
                                child: Container(color: Colors.grey.shade100))),
                          todayLine(),
                          ...milestones.map((ms) {
                            final msDays = ms.date.difference(rangeStart).inDays.toDouble().clamp(0.0, totalDays);
                            final msFrac = msDays / totalDays;
                            final labelLeft = (msFrac * chartW - 24).clamp(0.0, chartW - 56.0);
                            return Stack(children: [
                              Positioned(
                                left: msFrac * chartW - 1,
                                top: 0, bottom: 4, width: 2,
                                child: Container(color: ms.color.withValues(alpha: 0.7)),
                              ),
                              Positioned(
                                left: labelLeft, top: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: ms.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                                  child: Text(ms.label,
                                      style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: ms.color)),
                                ),
                              ),
                            ]);
                          }),
                        ]),
                      ),
                    ]),
                  );
                }

                // ── Milestone bottom sheet helper (mobile expand) ─────────
                void showMilestoneSheet(String label, DateTime? inicio, DateTime? fin, Color color) {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Center(child: Container(width: 32, height: 3, margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                          Row(children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(label, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                          ]),
                          const SizedBox(height: 12),
                          if (inicio != null) Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Icon(Icons.play_circle_outline, size: 14, color: Colors.grey.shade400),
                              const SizedBox(width: 6),
                              Text('Inicio  ', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                              Text(_fmtDt(inicio), style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151), fontWeight: FontWeight.w500)),
                            ]),
                          ),
                          if (fin != null) Row(children: [
                            Icon(Icons.stop_circle_outlined, size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 6),
                            Text('Fin      ', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                            Text(_fmtDt(fin), style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151), fontWeight: FontWeight.w500)),
                          ]),
                        ]),
                      ),
                    ),
                  );
                }

                // Mobile-only: expanded detail row with tappable milestones
                Widget mobileExpandedRow() {
                  if (!isMobile || !isPostulacion || !isExpanded) return const SizedBox();
                  final hasMilestones = p.fechaConsultas != null || p.fechaAdjudicacion != null;
                  if (!hasMilestones) return const SizedBox();

                  Widget chip(String label, DateTime? inicio, DateTime? fin, Color color) {
                    if (inicio == null && fin == null) return const SizedBox();
                    final rangeText = (inicio != null && fin != null)
                        ? '${_fmtDt(inicio)} – ${_fmtDt(fin)}'
                        : _fmtDt(inicio ?? fin);
                    return GestureDetector(
                      onTap: () => showMilestoneSheet(label, inicio, fin, color),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('$label: ', style: GoogleFonts.inter(fontSize: 9, color: Colors.grey.shade500)),
                        Text(rangeText, style: GoogleFonts.inter(fontSize: 9, color: color, fontWeight: FontWeight.w500)),
                      ]),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.only(left: (isPostulacion ? 16.0 : 0) + labelW + 16, bottom: 6),
                    child: Wrap(spacing: 14, runSpacing: 4, children: [
                      if (p.fechaConsultas != null || p.fechaConsultasInicio != null)
                        chip('Consultas', p.fechaConsultasInicio, p.fechaConsultas, const Color(0xFF0EA5E9)),
                      if (p.fechaAdjudicacion != null || p.fechaAdjudicacionFin != null)
                        chip('Adjudicación', p.fechaAdjudicacion, p.fechaAdjudicacionFin, const Color(0xFFF59E0B)),
                    ]),
                  );
                }

                // ── Bar row (all sizes) ───────────────────────────────────
                final barTooltip = isPostulacion
                    ? 'Publicación: ${_fmtDt(startOf2(p))}\nCierre recepción: ${_fmtDt(endOf2(p))}'
                    : isRuta
                        ? 'Inicio: ${_fmtDt(startOf2(p))}\nFin: ${_fmtDt(endOf2(p))}'
                        : 'Inicio: ${_formatDate(startOf2(p))}\nFin: ${_formatDate(endOf2(p))}';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: rowH,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Expand toggle (postulación only)
                          if (isPostulacion)
                            GestureDetector(
                              onTap: () => setState(() {
                                if (isExpanded) {
                                  _ganttExpandedRows.remove(p.id);
                                } else {
                                  _ganttExpandedRows.add(p.id);
                                }
                              }),
                              child: SizedBox(
                                width: 16,
                                child: Icon(
                                  isExpanded ? Icons.expand_less : Icons.expand_more,
                                  size: 14,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                          // Label column — tapping navigates to project
                          GestureDetector(
                            onTap: () => _openEditDialog(p),
                            child: Tooltip(
                              message: instFull,
                              preferBelow: true,
                              child: SizedBox(
                                width: isPostulacion ? labelW - 16 : labelW,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      instDisplay,
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 10 : 11,
                                        color: const Color(0xFF374151),
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      (isPostulacion || isRuta)
                                          ? _fmtDt(startOf2(p))
                                          : _fmtDateShort(startOf2(p)),
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        color: Colors.grey.shade400,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Chart area — tooltip shows exact date range
                          Tooltip(
                            message: barTooltip,
                            preferBelow: true,
                            child: SizedBox(
                              width: chartW,
                              height: rowH,
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  // Track
                                  Positioned(
                                    top: (rowH - barH) / 2,
                                    height: barH,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  // Grid lines
                                  ...markers.map((m) => Positioned(
                                        left: m.frac * chartW,
                                        top: 0,
                                        bottom: 0,
                                        width: m.isMajor ? 1.5 : 1,
                                        child: Container(
                                            color: m.isMajor
                                                ? Colors.grey.shade200
                                                : Colors.grey.shade100),
                                      )),
                                  // Today line
                                  todayLine(),
                                  // Bar
                                  Positioned(
                                    left: leftFrac * chartW,
                                    width: (widthFrac * chartW).clamp(4.0, chartW),
                                    top: (rowH - barH) / 2,
                                    height: barH,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: barColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // End date
                          SizedBox(
                            width: dateW,
                            child: Text(
                              (isPostulacion || isRuta)
                                  ? _fmtDt(endOf2(p))
                                  : _fmtDateShort(endOf2(p)),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isMobile) milestoneRow(),
                    mobileExpandedRow(),
                  ],
                );
              }),
              const SizedBox(height: 4),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 8),
              // Legend
              if (isMobile)
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (isPostulacion) ...[
                      _legendItem(const Color(0xFF6366F1), 'Publicación → Cierre'),
                      _legendItem(const Color(0xFF0EA5E9), 'Consultas', isLine: true),
                      _legendItem(const Color(0xFFF59E0B), 'Adjudicación', isLine: true),
                    ] else ...[
                      _legendItem(const Color(0xFF10B981), 'Vigente'),
                      _legendItem(const Color(0xFFF59E0B), 'X Vencer'),
                      _legendItem(Colors.grey.shade300, 'Finalizado'),
                    ],
                    _legendItem(const Color(0xFF6366F1).withValues(alpha: 0.55), 'Hoy', isLine: true),
                  ],
                )
              else
                Row(children: [
                  SizedBox(width: (isPostulacion ? 16 : 0) + labelW + 8),
                  if (isPostulacion) ...[
                    _legendItem(const Color(0xFF6366F1), 'Publicación → Cierre'),
                    const SizedBox(width: 14),
                    _legendItem(const Color(0xFF0EA5E9), 'Consultas', isLine: true),
                    const SizedBox(width: 14),
                    _legendItem(const Color(0xFFF59E0B), 'Adjudicación', isLine: true),
                  ] else ...[
                    _legendItem(const Color(0xFF10B981), 'Vigente'),
                    const SizedBox(width: 14),
                    _legendItem(const Color(0xFFF59E0B), 'X Vencer'),
                    const SizedBox(width: 14),
                    _legendItem(Colors.grey.shade300, 'Finalizado'),
                  ],
                  const SizedBox(width: 14),
                  _legendItem(const Color(0xFF6366F1).withValues(alpha: 0.55), 'Hoy', isLine: true),
                ]),
            ],
          );
        }),
      ),
    ]);
  }

  Widget _buildGanttHeader(bool isMobile, {
    DateTime? autoStart,
    DateTime? autoEnd,
    int stepMonths = 3,
  }) {
    const activeColor = Color(0xFF5B21B6);
    const inactiveColor = Color(0xFF94A3B8);
    final tabs = [
      ('contrato', 'Contrato'),
      ('ruta', 'Implementación'),
      ('postulacion', 'Postulación'),
    ];

    final subtitles = {
      'contrato': '',
      'ruta': 'Implementación por proyecto',
      'postulacion': 'Publicación y cierre de ofertas por proyecto',
    };

    final hasWindow = _ganttWindowStart != null || _ganttWindowEnd != null;
    final ws = _ganttWindowStart ?? autoStart;
    final we = _ganttWindowEnd ?? autoEnd;

    void shiftWindow(int months) {
      if (ws == null || we == null) return;
      setState(() {
        _ganttWindowStart = DateTime(ws.year, ws.month + months, ws.day);
        _ganttWindowEnd = DateTime(we.year, we.month + months, we.day);
      });
    }

    void zoomWindow(int deltaMonths) {
      if (ws == null || we == null) return;
      final curMonths = we.difference(ws).inDays ~/ 30;
      final newMonths = (curMonths + deltaMonths).clamp(1, 120);
      final center = ws.add(Duration(days: we.difference(ws).inDays ~/ 2));
      setState(() {
        _ganttWindowStart = DateTime(center.year, center.month - newMonths ~/ 2, center.day);
        _ganttWindowEnd = DateTime(center.year, center.month + (newMonths - newMonths ~/ 2), center.day);
      });
    }

    Widget navBtn(IconData icon, VoidCallback? onTap, {String? tooltip}) {
      final btn = GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: onTap != null ? const Color(0xFFF1F5F9) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Icon(icon, size: 14,
              color: onTap != null ? const Color(0xFF475569) : Colors.grey.shade300),
        ),
      );
      return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
    }

    // Mode toggle pill
    final modeTabs = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.map((t) {
          final isActive = _ganttMode == t.$1;
          return GestureDetector(
            onTap: () {
              setState(() {
                _ganttMode = t.$1;
                _ganttWindowStart = null;
                _ganttWindowEnd = null;
                _ganttExpandedRows.clear();
              });
              if (t.$1 == 'postulacion') _sincronizarPostulacionDesdeOcds();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isActive
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
                    : [],
              ),
              child: Text(t.$2,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? activeColor : inactiveColor,
                  )),
            ),
          );
        }).toList(),
      ),
    );

    // Nav buttons row (null-safe: only shown when window is defined)
    List<Widget> navButtons() => [
      navBtn(Icons.chevron_left, () => shiftWindow(-stepMonths), tooltip: 'Retroceder'),
      const SizedBox(width: 4),
      navBtn(Icons.chevron_right, () => shiftWindow(stepMonths), tooltip: 'Avanzar'),
      const SizedBox(width: 6),
      navBtn(Icons.remove, () => zoomWindow(stepMonths * 2), tooltip: 'Alejar'),
      const SizedBox(width: 4),
      navBtn(Icons.add, () => zoomWindow(-stepMonths * 2), tooltip: 'Acercar'),
      if (hasWindow) ...[
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() { _ganttWindowStart = null; _ganttWindowEnd = null; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.grey.shade200)),
            child: Text('Reset', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF475569))),
          ),
        ),
      ],
      const SizedBox(width: 8),
    ];

    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Línea de Tiempo',
            style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B))),
        if ((subtitles[_ganttMode] ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitles[_ganttMode]!,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleWidget),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: navButtons()),
            ],
          ),
          const SizedBox(height: 8),
          modeTabs,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titleWidget),
        if (ws != null && we != null) ...navButtons(),
        modeTabs,
      ],
    );
  }

  Widget _legendItem(Color color, String label, {bool isLine = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      isLine
          ? Container(
              width: 2,
              height: 12,
              color: color,
              margin: const EdgeInsets.symmetric(horizontal: 3),
            )
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
      const SizedBox(width: 5),
      Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, color: Colors.grey.shade500)),
    ]);
  }

  // ── PROYECTOS TAB content ──────────────────────────────────────────────────

  Widget _buildTabProyectos(bool isMobile) {
    final filtered = _applySorting(_applyFilters(_proyectos));
    final totalPages = (filtered.length / _pageSize).ceil();
    final pageStart = _currentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length);
    final pageItems =
        filtered.isEmpty ? <Proyecto>[] : filtered.sublist(pageStart, pageEnd);

    final total = _proyectos.length;
    final postulacion = _proyectos.where((p) => p.estado == EstadoProyecto.postulacion).length;
    final enEvaluacion = _proyectos.where((p) => p.estado == 'En Evaluación').length;
    final vigentes = _proyectos.where((p) => p.estado == EstadoProyecto.vigente).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryRow(total, postulacion, enEvaluacion, vigentes, isMobile),
        const SizedBox(height: 16),
        _buildFilterRow(_proyectos, isMobile),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _buildEmptyState()
        else if (isMobile)
          _buildMobileCards(pageItems)
        else
          _buildDesktopTable(pageItems),
        if (totalPages > 1) ...[
          const SizedBox(height: 16),
          _buildPagination(totalPages, filtered.length),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileFab = screenWidth < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: isMobileFab
          ? FloatingActionButton(
              onPressed: _openCreateDialog,
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.add, size: 24),
            )
          : null,
      body: LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final hPad = isMobile ? 20.0 : 32.0;

        return Column(
          children: [
            _buildAppBar(isMobile),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('Error al cargar proyectos',
                                  style: GoogleFonts.inter(
                                      color: Colors.red.shade600)),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _cargar,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: Text('Reintentar',
                                    style: GoogleFonts.inter()),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Center(
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 880),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    hPad, isMobile ? 16 : 24, hPad, 48),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Tab bar — Apple style matching HomeView
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: TabBar(
                                        controller: _tabController,
                                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                                        labelStyle: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                        unselectedLabelStyle:
                                            GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w400),
                                        labelColor: _primaryColor,
                                        unselectedLabelColor:
                                            Colors.grey.shade400,
                                        indicatorColor: _primaryColor,
                                        indicatorSize:
                                            TabBarIndicatorSize.tab,
                                        dividerColor: Colors.transparent,
                                        tabs: const [
                                          Tab(text: 'Resumen'),
                                          Tab(text: 'Proyectos'),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    // Tab content inline (no TabBarView)
                                    AnimatedBuilder(
                                      animation: _tabController,
                                      builder: (_, __) {
                                        if (_tabController.index == 0) {
                                          return _buildTabResumen(isMobile);
                                        }
                                        return _buildTabProyectos(isMobile);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSummaryRow(
      int total, int postulacion, int enEvaluacion, int vigentes, bool isMobile) {
    final summaryCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Flexible(child: _summaryChip('Total $total', null, const Color(0xFF1E293B))),
          _divider(),
          Flexible(child: _summaryChip(
              'Postulación $postulacion', const Color(0xFF6366F1), const Color(0xFF6366F1))),
          _divider(),
          Flexible(child: _summaryChip(
              'En Evaluación $enEvaluacion', const Color(0xFF0EA5E9), const Color(0xFF0EA5E9))),
          _divider(),
          Flexible(child: _summaryChip(
              'Vigentes $vigentes', const Color(0xFF10B981), const Color(0xFF10B981))),
        ],
      ),
    );

    final newButton = SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add, size: 18),
        label: Text(
          isMobile ? 'Nuevo' : 'Nuevo Proyecto',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
        ),
      ),
    );

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: summaryCard,
      );
    }

    return Row(
      children: [
        Expanded(child: summaryCard),
        const SizedBox(width: 16),
        newButton,
      ],
    );
  }

  Widget _summaryChip(String label, Color? dotColor, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dotColor != null) ...[
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textColor),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child:
            Container(width: 1, height: 16, color: Colors.grey.shade200),
      );

  Widget _buildFilterRow(List<Proyecto> all, bool isMobile) {
    final activeCount = [
      _filterInstitucion,
      _filterModalidad,
      _filterEstado,
      _filterReclamo,
      _filterVencer,
    ].where((v) => v != null).length + (_filterProductos.isNotEmpty ? 1 : 0);

    final hasFilters = activeCount > 0;

    // Active filter chips shown inline
    final activeChips = <Widget>[
      if (_filterInstitucion != null)
        _activeChip(_filterInstitucion!.split('|').first.trim(),
            () => setState(() { _filterInstitucion = null; _currentPage = 0; })),
      if (_filterProductos.isNotEmpty)
        _activeChip(_filterProductos.join(', '),
            () => setState(() { _filterProductos = {}; _currentPage = 0; })),
      if (_filterModalidad != null)
        _activeChip(_filterModalidad!,
            () => setState(() { _filterModalidad = null; _currentPage = 0; })),
      if (_filterEstado != null)
        _activeChip(_filterEstado!,
            () => setState(() { _filterEstado = null; _currentPage = 0; })),
      if (_filterReclamo != null)
        _activeChip('Reclamo: $_filterReclamo',
            () => setState(() { _filterReclamo = null; _currentPage = 0; })),
      if (_filterVencer != null)
        _activeChip('Vencer: $_filterVencer',
            () => setState(() { _filterVencer = null; _currentPage = 0; })),
    ];

    return Row(
      children: [
        // Filter icon button
        GestureDetector(
          onTap: () => _showFiltersSheet(all),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: hasFilters
                  ? _primaryColor.withValues(alpha: 0.08)
                  : Colors.white,
              border: Border.all(
                color: hasFilters ? _primaryColor : Colors.grey.shade200,
                width: hasFilters ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 15,
                    color: hasFilters ? _primaryColor : Colors.grey.shade500),
                if (activeCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$activeCount',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Active filter chips
        if (activeChips.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: activeChips
                    .expand((c) => [c, const SizedBox(width: 6)])
                    .toList()
                  ..removeLast(),
              ),
            ),
          ),
        ],
        if (hasFilters) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _clearFilters,
            child: Icon(Icons.close, size: 15, color: Colors.grey.shade400),
          ),
        ],
      ],
    );
  }

  Widget _activeChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 11, color: _primaryColor),
          ),
        ],
      ),
    );
  }

  void _showFiltersSheet(List<Proyecto> all) {
    final modalidades = _cfgModalidades;
    final estados = _cfgEstados.map((e) => e.nombre).toList();
    final allProducts = _cfgProductos.map((p) => p.abreviatura).toList()..sort();
    final instituciones = all
        .map((p) => p.institucion)
        .toSet()
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // local copies to update sheet live
          void applyAndRefresh(VoidCallback fn) {
            fn();
            setSheet(() {});
          }

          Widget sectionTitle(String t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(t,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.5)),
              );

          Widget chipGroup(
              List<String> items, String? selected,
              void Function(String?) onTap,
              {String Function(String)? label}) {
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final item in items)
                GestureDetector(
                  onTap: () {
                    applyAndRefresh(() => setState(() {
                          if (selected == item) {
                            onTap(null);
                          } else {
                            onTap(item);
                          }
                          _currentPage = 0;
                        }));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected == item
                          ? _primaryColor
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(label?.call(item) ?? item,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: selected == item
                                ? Colors.white
                                : Colors.grey.shade700)),
                  ),
                ),
            ]);
          }

          Widget multiChipGroup(List<String> items, Set<String> selected) {
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final item in items)
                GestureDetector(
                  onTap: () {
                    applyAndRefresh(() => setState(() {
                          if (selected.contains(item)) {
                            _filterProductos = Set.from(selected)..remove(item);
                          } else {
                            _filterProductos = Set.from(selected)..add(item);
                          }
                          _currentPage = 0;
                        }));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected.contains(item)
                          ? _primaryColor
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: selected.contains(item)
                                ? Colors.white
                                : Colors.grey.shade700)),
                  ),
                ),
            ]);
          }

          final activeCount = [
            _filterInstitucion,
            _filterModalidad,
            _filterEstado,
            _filterReclamo,
            _filterVencer,
          ].where((v) => v != null).length +
              (_filterProductos.isNotEmpty ? 1 : 0);

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                // Handle + header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(children: [
                    Center(
                      child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Text('Filtros',
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B))),
                      if (activeCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: _primaryColor,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('$activeCount',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                      ],
                      const Spacer(),
                      if (activeCount > 0)
                        TextButton(
                          onPressed: () {
                            applyAndRefresh(() => _clearFilters());
                          },
                          child: Text('Limpiar todo',
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: Colors.red.shade400)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.grey.shade400,
                      ),
                    ]),
                    const Divider(height: 20),
                  ]),
                ),
                // Scrollable content
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      // Institución
                      sectionTitle('INSTITUCIÓN'),
                      GestureDetector(
                        onTap: () async {
                          final sel = await showDialog<String>(
                            context: ctx,
                            builder: (_) => _FilterSearchDialog(
                              hint: 'Institución',
                              value: _filterInstitucion,
                              items: instituciones,
                              displayLabel: (s) => s.split('|').first.trim(),
                            ),
                          );
                          if (sel == '\x00') {
                            applyAndRefresh(() => setState(
                                () { _filterInstitucion = null; _currentPage = 0; }));
                          } else if (sel != null) {
                            applyAndRefresh(() => setState(
                                () { _filterInstitucion = sel; _currentPage = 0; }));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _filterInstitucion != null
                                ? _primaryColor.withValues(alpha: 0.06)
                                : Colors.grey.shade50,
                            border: Border.all(
                                color: _filterInstitucion != null
                                    ? _primaryColor.withValues(alpha: 0.3)
                                    : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                _filterInstitucion != null
                                    ? _filterInstitucion!.split('|').first.trim()
                                    : 'Seleccionar institución…',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: _filterInstitucion != null
                                        ? const Color(0xFF1E293B)
                                        : Colors.grey.shade400),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              _filterInstitucion != null
                                  ? Icons.close
                                  : Icons.search,
                              size: 16,
                              color: _filterInstitucion != null
                                  ? _primaryColor
                                  : Colors.grey.shade400,
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Productos
                      sectionTitle('PRODUCTOS'),
                      multiChipGroup(allProducts, _filterProductos),
                      const SizedBox(height: 20),

                      // Contratación
                      sectionTitle('CONTRATACIÓN'),
                      chipGroup(modalidades, _filterModalidad,
                          (v) => _filterModalidad = v),
                      const SizedBox(height: 20),

                      // Estado
                      sectionTitle('ESTADO'),
                      chipGroup(estados, _filterEstado,
                          (v) => _filterEstado = v),
                      const SizedBox(height: 20),

                      // Reclamos
                      sectionTitle('RECLAMOS'),
                      chipGroup(const ['Pendiente', 'Respondido'],
                          _filterReclamo, (v) => _filterReclamo = v),
                      const SizedBox(height: 20),

                      // Por Vencer
                      sectionTitle('POR VENCER'),
                      chipGroup(
                          const ['30 días', '3 meses', '6 meses', '12 meses'],
                          _filterVencer, (v) => _filterVencer = v),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterButton({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String Function(String)? displayLabel,
  }) {
    final display = value != null ? (displayLabel?.call(value) ?? value) : null;
    final isActive = value != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showFilterDialog(
          hint: hint, value: value, items: items,
          onChanged: onChanged, displayLabel: displayLabel ?? (s) => s,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: isActive ? _primaryColor : Colors.grey.shade200,
              width: isActive ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                display ?? hint,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isActive ? const Color(0xFF1E293B) : Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  Future<void> _showFilterDialog({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String Function(String) displayLabel,
  }) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _FilterSearchDialog(
        hint: hint, value: value, items: items, displayLabel: displayLabel,
      ),
    );
    if (selected == '\x00') {
      onChanged(null);
    } else if (selected != null) {
      onChanged(selected);
    }
  }

  Widget _productsButton() {
    final allProducts = _cfgProductos.map((p) => p.abreviatura).toList()..sort();
    final isActive = _filterProductos.isNotEmpty;
    final display = isActive ? _filterProductos.join(', ') : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showMultiFilterDialog(allProducts),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: isActive ? _primaryColor : Colors.grey.shade200,
              width: isActive ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                display ?? 'Productos',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isActive ? const Color(0xFF1E293B) : Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  Future<void> _showMultiFilterDialog(List<String> allProducts) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _MultiFilterDialog(
        allItems: allProducts,
        selected: Set.from(_filterProductos),
      ),
    );
    if (result != null) {
      setState(() { _filterProductos = result; _currentPage = 0; });
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No hay proyectos',
                style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Crea el primer proyecto con el botón "Nuevo Proyecto"',
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(List<Proyecto> items) {
    const cols = [
      'Institución',
      'Productos',
      'Valor Mensual',
      'Fecha de Inicio',
      'Fecha de Término'
    ];
    final flexes = [5, 2, 2, 2, 2];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: cols.asMap().entries.map((e) {
                final colIdx = e.key;
                final isActive = _sortColumn == colIdx;
                return Expanded(
                  flex: flexes[colIdx],
                  child: GestureDetector(
                    onTap: () => _setSort(colIdx),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.value,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? _primaryColor
                                : Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          isActive
                              ? (_sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward)
                              : Icons.unfold_more,
                          size: 13,
                          color: isActive
                              ? _primaryColor
                              : Colors.grey.shade300,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final p = entry.value;
            final isLast = idx == items.length - 1;
            return _buildTableRow(p, flexes, isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildTableRow(Proyecto p, List<int> flexes, bool isLast) {
    return InkWell(
      onTap: () => _openEditDialog(p),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: Colors.grey.shade50)),
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(12))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              flex: flexes[0],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_cleanInst(p.institucion),
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF1E293B)),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (_projectDisplayId(p) != null)
                        _projectDisplayId(p)!,
                      p.modalidadCompra,
                    ].join(' · '),
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey.shade400),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (p.reclamos.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _reclamoBadge(p),
                  ],
                ],
              ),
            ),
            Expanded(
                flex: flexes[1],
                child: _productosCell(p.productos)),
            Expanded(
                flex: flexes[2],
                child: Text(
                  p.valorMensual != null
                      ? '\$ ${_fmt(p.valorMensual!.toInt())}'
                      : '—',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: const Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                )),
            Expanded(
                flex: flexes[3],
                child: Text(_formatDate(p.fechaInicio),
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.grey.shade600))),
            Expanded(
              flex: flexes[4],
              child: Row(
                children: [
                  _fechaDot(p.fechaTermino, p.estado),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(_formatDate(p.fechaTermino),
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCards(List<Proyecto> items) {
    if (items.isEmpty) return _buildEmptyState();
    return Column(
      children: items.map((p) => _buildMobileCard(p)).toList(),
    );
  }

  Widget _buildMobileCard(Proyecto p) {
    final estadoItem = _cfgEstados.firstWhere(
        (e) => e.nombre == p.estado,
        orElse: () => EstadoItem(nombre: p.estado, color: '64748B'));
    final idLabel = _projectDisplayId(p);

    return GestureDetector(
      onTap: () => _openEditDialog(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header strip with estado color
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: estadoItem.colorValue, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(p.estado,
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: estadoItem.colorValue)),
                  const Spacer(),
                  if (idLabel != null)
                    Text(idLabel,
                        style: GoogleFonts.inter(
                            fontSize: 10, color: Colors.grey.shade400)),
                ],
              ),
            ),
            // Main content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_cleanInst(p.institucion),
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E293B)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (p.productos.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.productos,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (p.valorMensual != null) ...[
                        Text('\$ ${_fmt(p.valorMensual!.toInt())}',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500)),
                        const SizedBox(width: 10),
                      ],
                      if (p.fechaTermino != null) ...[
                        Icon(Icons.calendar_today_outlined,
                            size: 11, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(_formatDate(p.fechaTermino),
                            style: GoogleFonts.inter(
                                fontSize: 12, color: Colors.grey.shade500)),
                      ],
                      const Spacer(),
                      Flexible(child: Text(p.modalidadCompra,
                          style: GoogleFonts.inter(
                              fontSize: 10, color: Colors.grey.shade400),
                          overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination(int totalPages, int totalItems) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Página ${_currentPage + 1} de $totalPages  ($totalItems proyectos)',
          style:
              GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _currentPage > 0
              ? () => setState(() => _currentPage--)
              : null,
          color: _primaryColor,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _currentPage < totalPages - 1
              ? () => setState(() => _currentPage++)
              : null,
          color: _primaryColor,
        ),
      ],
    );
  }

  Widget _reclamoBadge(Proyecto p) {
    final hasPendiente = p.reclamos.any((r) => r.estado == 'Pendiente');
    final color = hasPendiente ? const Color(0xFFDC2626) : const Color(0xFF10B981);
    final bg = hasPendiente ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final label = hasPendiente ? 'Reclamo pendiente' : 'Reclamo respondido';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _productosCell(String productos) {
    final abrevs = productos
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return _ProductosChipsCell(
        abrevs: abrevs, cfgProductos: _cfgProductos);
  }

  Widget _fechaDot(DateTime? fecha, String estado) {
    if (fecha == null) {
      return const SizedBox(width: 8, height: 8);
    }
    final item = _cfgEstados.firstWhere((e) => e.nombre == estado,
        orElse: () => EstadoItem(nombre: estado, color: '64748B'));
    return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            color: item.colorValue, shape: BoxShape.circle));
  }

  /// Strips the "CM: " prefix that Firestore stores in idCotizacion.
  String _cleanCmId(String id) =>
      id.startsWith('CM: ') ? id.substring(4) : id;

  /// Extracts the convenio marco ID from its URL (e.g. ".../id/5802363-3205ZEZE").
  String? _cmIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'/id/([^/\?#]+)').firstMatch(url);
    return match?.group(1);
  }

  /// Returns the best display ID for a project (licitación ID, clean CM id, or CM from URL).
  String? _projectDisplayId(Proyecto p) {
    if (p.idLicitacion?.isNotEmpty == true) return p.idLicitacion;
    if (p.idCotizacion?.isNotEmpty == true) return _cleanCmId(p.idCotizacion!);
    return _cmIdFromUrl(p.urlConvenioMarco);
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  static const _monthAbbr = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  String _fmtDateShort(DateTime? dt) {
    if (dt == null) return '—';
    return "${_monthAbbr[dt.month - 1]} '${dt.year.toString().substring(2)}";
  }

  /// DD/MM HH:mm h — used in Gantt postulación / ruta for exact times.
  String _fmtDt(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}h';
  }

  String _fmt(int n) {
    final str = n.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(str[i]);
      count++;
    }
    return buf.toString().split('').reversed.join('');
  }
}

class _ProductosChipsCell extends StatefulWidget {
  final List<String> abrevs;
  final List<ProductoItem> cfgProductos;
  const _ProductosChipsCell(
      {required this.abrevs, required this.cfgProductos});

  @override
  State<_ProductosChipsCell> createState() => _ProductosChipsCellState();
}

class _ProductosChipsCellState extends State<_ProductosChipsCell> {
  final _scrollCtrl = ScrollController();
  bool _hasOverflow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkOverflow());
    _scrollCtrl.addListener(_checkOverflow);
  }

  void _checkOverflow() {
    if (!_scrollCtrl.hasClients) return;
    final hasMore =
        _scrollCtrl.position.maxScrollExtent > 0 &&
            _scrollCtrl.position.pixels <
                _scrollCtrl.position.maxScrollExtent - 1;
    if (hasMore != _hasOverflow) setState(() => _hasOverflow = hasMore);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollCtrl,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.abrevs.map((abv) {
              final cfg = widget.cfgProductos
                  .where((p) => p.abreviatura == abv)
                  .firstOrNull;
              final bg =
                  cfg != null ? cfg.bgColor : const Color(0xFFF2F2F7);
              final fg =
                  cfg != null ? cfg.fgColor : const Color(0xFF64748B);
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(abv,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: fg)),
                ),
              );
            }).toList(),
          ),
        ),
        if (_hasOverflow)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.85)
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Reclamos Carousel Card ─────────────────────────────────────────────────────

// ── Shared KPI card shell ──────────────────────────────────────────────────────

class _KpiCardShell extends StatelessWidget {
  final String label;
  final Color color;
  final Widget icon;
  final Widget value;
  final int pageCount;
  final int currentIndex;
  final void Function(bool forward) onSwipe;
  final VoidCallback? onTap;

  const _KpiCardShell({
    required this.label,
    required this.color,
    required this.icon,
    required this.value,
    required this.pageCount,
    required this.currentIndex,
    required this.onSwipe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          onSwipe(d.primaryVelocity! < 0);
        },
        child: Container(
          height: 130,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500),
                      maxLines: 2),
                ),
                icon,
              ],
            ),
            const SizedBox(height: 10),
            value,
            const Spacer(),
            // Dots — tappable on web to advance carousel
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSwipe(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pageCount, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == currentIndex ? 12 : 5,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == currentIndex ? color : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ReclamosCard extends StatefulWidget {
  final int pendientes;
  final int finalizados;
  final void Function(String)? onNavigate;
  const _ReclamosCard({required this.pendientes, required this.finalizados, this.onNavigate});

  @override
  State<_ReclamosCard> createState() => _ReclamosCardState();
}

class _ReclamosCardState extends State<_ReclamosCard> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final isPendientes = _idx == 0;
    final count = isPendientes ? widget.pendientes : widget.finalizados;
    final label = isPendientes ? 'Reclamos\nPendientes' : 'Reclamos\nFinalizados';
    final color = isPendientes
        ? (widget.pendientes > 0 ? const Color(0xFFDC2626) : Colors.grey.shade400)
        : (widget.finalizados > 0 ? const Color(0xFF10B981) : Colors.grey.shade400);
    final iconData = isPendientes ? Icons.gavel_outlined : Icons.check_circle_outline;

    return _KpiCardShell(
      label: label,
      color: color,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(iconData, size: 15, color: color),
      ),
      value: Text(count.toString(),
          style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: const Color(0xFF1E293B))),
      pageCount: 2,
      currentIndex: _idx,
      onSwipe: (_) => setState(() => _idx = _idx == 0 ? 1 : 0),
      onTap: widget.onNavigate != null
          ? () => widget.onNavigate!(isPendientes ? 'Pendiente' : 'Respondido')
          : null,
    );
  }
}

// ── Proyectos Carousel Card ────────────────────────────────────────────────────

class _ProyectosKpiCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(String? estado)? onNavigate;
  const _ProyectosKpiCard({required this.proyectos, this.onNavigate});

  @override
  State<_ProyectosKpiCard> createState() => _ProyectosKpiCardState();
}

class _ProyectosKpiCardState extends State<_ProyectosKpiCard> {
  int _idx = 3; // default: Postulación

  static const _pages = [
    (label: 'Proyectos\nActivos',     estado: null as String?,            color: Color(0xFF5B21B6), activos: true),
    (label: 'Proyectos\nVigentes',    estado: EstadoProyecto.vigente,     color: Color(0xFF10B981), activos: false),
    (label: 'Proyectos\nX Vencer',    estado: EstadoProyecto.xVencer,     color: Color(0xFFF59E0B), activos: false),
    (label: 'Proyectos\nPostulación', estado: EstadoProyecto.postulacion, color: Color(0xFF6366F1), activos: false),
    (label: 'Proyectos\nFinalizados', estado: EstadoProyecto.finalizado,  color: Color(0xFF64748B), activos: false),
    (label: 'Proyectos\nTotal',       estado: null as String?,            color: Color(0xFF0EA5E9), activos: false),
  ];

  int _count() {
    final page = _pages[_idx];
    if (page.activos) {
      return widget.proyectos.where((p) =>
        p.estado == EstadoProyecto.vigente || p.estado == EstadoProyecto.xVencer).length;
    }
    if (page.estado == null) return widget.proyectos.length;
    return widget.proyectos.where((p) => p.estado == page.estado).length;
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_idx];
    final count = _count();
    final color = page.color;

    return _KpiCardShell(
      label: page.label,
      color: color,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.folder_open_outlined, size: 15, color: color),
      ),
      value: Text(count.toString(),
          style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: const Color(0xFF1E293B))),
      pageCount: _pages.length,
      currentIndex: _idx,
      onSwipe: (forward) => setState(() =>
          _idx = forward ? (_idx + 1) % _pages.length : (_idx - 1 + _pages.length) % _pages.length),
      onTap: widget.onNavigate == null ? null : () {
        final page = _pages[_idx];
        widget.onNavigate!(page.activos ? null : page.estado);
      },
    );
  }
}

// ── X Vencer Carousel Card ─────────────────────────────────────────────────────

class _XVencerKpiCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(int dias)? onNavigate;
  const _XVencerKpiCard({required this.proyectos, this.onNavigate});

  @override
  State<_XVencerKpiCard> createState() => _XVencerKpiCardState();
}

class _XVencerKpiCardState extends State<_XVencerKpiCard> {
  int _idx = 1; // default: 3 meses

  static const _periodos = [
    (label: 'Por Vencer\n(30 días)',  dias: 30),
    (label: 'Por Vencer\n(3 meses)',  dias: 90),
    (label: 'Por Vencer\n(6 meses)',  dias: 180),
    (label: 'Por Vencer\n(12 meses)', dias: 365),
  ];

  int _count(int dias) {
    final now = DateTime.now();
    final limite = now.add(Duration(days: dias));
    return widget.proyectos.where((p) {
      final ft = p.fechaTermino;
      if (ft == null) return false;
      return ft.isAfter(now) && ft.isBefore(limite);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final page = _periodos[_idx];
    final count = _count(page.dias);
    const color = Color(0xFFF59E0B);

    final activeColor = count > 0 ? color : Colors.grey.shade400;
    return _KpiCardShell(
      label: page.label,
      color: color,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: activeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.schedule_outlined, size: 15, color: activeColor),
      ),
      value: Text(count.toString(),
          style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: const Color(0xFF1E293B))),
      pageCount: _periodos.length,
      currentIndex: _idx,
      onSwipe: (forward) => setState(() =>
          _idx = forward ? (_idx + 1) % _periodos.length : (_idx - 1 + _periodos.length) % _periodos.length),
      onTap: widget.onNavigate != null ? () => widget.onNavigate!(page.dias) : null,
    );
  }
}

// ── Valor Mensual Carousel Card ────────────────────────────────────────────────

class _ValorMensualCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(String? estado)? onNavigate;
  const _ValorMensualCard({required this.proyectos, this.onNavigate});

  @override
  State<_ValorMensualCard> createState() => _ValorMensualCardState();
}

class _ValorMensualCardState extends State<_ValorMensualCard> {
  int _idx = 2; // default: Postulación

  static const _pages = [
    (label: 'Valor Mensual\nVigente',     short: 'Vigente',     estado: EstadoProyecto.vigente,    color: Color(0xFF10B981)),
    (label: 'Valor Mensual\nX Vencer',    short: 'X Vencer',    estado: EstadoProyecto.xVencer,    color: Color(0xFFF59E0B)),
    (label: 'Valor Mensual\nPostulación', short: 'Postulación', estado: EstadoProyecto.postulacion, color: Color(0xFF0EA5E9)),
    (label: 'Valor Mensual\nTotal',       short: 'Total',       estado: null as String?,            color: Color(0xFF5B21B6)),
  ];

  static String _fmt(double n) {
    final digits = n.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_idx];
    final filtered = page.estado != null
        ? widget.proyectos.where((p) => p.estado == page.estado)
        : widget.proyectos;
    final total = filtered.fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));
    final color = page.color;

    return _KpiCardShell(
      label: page.label,
      color: color,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.attach_money, size: 15, color: color),
      ),
      value: Text(
        total > 0 ? '\$ ${_fmt(total)}' : '—',
        style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: const Color(0xFF1E293B)),
      ),
      pageCount: _pages.length,
      currentIndex: _idx,
      onSwipe: (forward) => setState(() =>
          _idx = forward ? (_idx + 1) % _pages.length : (_idx - 1 + _pages.length) % _pages.length),
      onTap: widget.onNavigate == null ? null : () {
        widget.onNavigate!(_pages[_idx].estado);
      },
    );
  }
}

// ── Single-select searchable filter dialog ─────────────────────────────────────

class _FilterSearchDialog extends StatefulWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final String Function(String) displayLabel;
  const _FilterSearchDialog({
    required this.hint,
    required this.value,
    required this.items,
    required this.displayLabel,
  });
  @override
  State<_FilterSearchDialog> createState() => _FilterSearchDialogState();
}

class _FilterSearchDialogState extends State<_FilterSearchDialog> {
  final _ctrl = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() => _filtered = widget.items
          .where((s) => widget.displayLabel(s).toLowerCase().contains(q))
          .toList());
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.hint.toLowerCase()}...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF5B21B6), width: 1.5),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
            if (widget.value != null)
              InkWell(
                onTap: () => Navigator.pop(context, '\x00'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.clear, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    Text('Limpiar filtro',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade400)),
                  ]),
                ),
              ),
            Divider(height: 1, color: Colors.grey.shade100),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final item = _filtered[i];
                  final display = widget.displayLabel(item);
                  final isSelected = item == widget.value;
                  return InkWell(
                    onTap: () => Navigator.pop(context, item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: isSelected
                          ? const Color(0xFF5B21B6).withValues(alpha: 0.05)
                          : null,
                      child: Row(children: [
                        Expanded(
                          child: Text(display,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isSelected
                                    ? const Color(0xFF5B21B6)
                                    : const Color(0xFF1E293B),
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              )),
                        ),
                        if (isSelected)
                          const Icon(Icons.check, size: 16, color: Color(0xFF5B21B6)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Multi-select filter dialog (Productos) ─────────────────────────────────────

class _MultiFilterDialog extends StatefulWidget {
  final List<String> allItems;
  final Set<String> selected;
  const _MultiFilterDialog({required this.allItems, required this.selected});
  @override
  State<_MultiFilterDialog> createState() => _MultiFilterDialogState();
}

class _MultiFilterDialogState extends State<_MultiFilterDialog> {
  late Set<String> _selected;
  final _ctrl = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selected);
    _filtered = widget.allItems;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() => _filtered = widget.allItems
          .where((s) => s.toLowerCase().contains(q))
          .toList());
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar producto...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF5B21B6), width: 1.5),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final item = _filtered[i];
                  final isChecked = _selected.contains(item);
                  return InkWell(
                    onTap: () => setState(() {
                      if (isChecked) { _selected.remove(item); } else { _selected.add(item); }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isChecked ? const Color(0xFF5B21B6) : Colors.transparent,
                            border: Border.all(
                              color: isChecked ? const Color(0xFF5B21B6) : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: isChecked
                              ? const Icon(Icons.check, size: 12, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(item,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isChecked
                                  ? const Color(0xFF5B21B6)
                                  : const Color(0xFF1E293B),
                              fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                            )),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(children: [
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: Text('Limpiar',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade400)),
                  ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B21B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    elevation: 0,
                  ),
                  child: Text('Aplicar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
