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
import 'walkthrough.dart';

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
  String _ganttMode = 'postulacion';
  // Expanded rows (postulación mode — show milestones)
  final Set<String> _ganttExpandedRows = {};
  // Window override (null = auto-fit data range)
  DateTime? _ganttWindowStart;
  DateTime? _ganttWindowEnd;

  // Filters — Proyectos tab
  String? _filterInstitucion;
  Set<String> _filterProductos = {};
  String? _filterModalidad;
  String? _filterEstado;
  String? _filterReclamo;   // 'Pendiente' | 'Respondido'
  String? _filterVencer;    // '30 días' | '3 meses' | '6 meses' | '12 meses'
  int? _filterQuarterYear;
  int? _filterQuarterQ;
  bool _filterQuarterOnlyWithOC = false;
  bool _filterQuarterIsChurn = false;
  bool _filterQuarterOnlyIngresos = false; // solo vigente/xVencer/finalizado (gráfico Monto Mensual)

  // Pagination — Proyectos tab
  int _currentPage = 0;

  // Filters — Documentación tab
  String? _docFilterInstitucion;
  Set<String> _docFilterProductos = {};
  String? _docFilterModalidad;
  String? _docFilterEstado;
  Set<String> _docFilterTipos = {};
  int _docCurrentPage = 0;
  bool _docSortAscending = false; // false = más reciente primero

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
    _tabController = TabController(length: 3, vsync: this);
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
      _filterQuarterYear = null;
      _filterQuarterQ = null;
      _filterQuarterOnlyWithOC = false;
      _currentPage = 0;
    });
  }

  void _clearDocFilters() {
    setState(() {
      _docFilterInstitucion = null;
      _docFilterProductos = {};
      _docFilterModalidad = null;
      _docFilterEstado = null;
      _docFilterTipos = {};
      _docCurrentPage = 0;
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
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
    // Pre-compute active institutions set for churn renewal check (O(n) once)
    final renovadas = (_filterQuarterYear != null &&
            _filterQuarterQ != null &&
            _filterQuarterIsChurn)
        ? all
            .where((o) =>
                o.idsOrdenesCompra.isNotEmpty &&
                o.estado != EstadoProyecto.finalizado)
            .map((o) => o.institucion.trim().toLowerCase())
            .toSet()
        : null;

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
        if (p.estado != _filterEstado) { return false; }
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
      if (_filterQuarterYear != null && _filterQuarterQ != null) {
        if (_filterQuarterIsChurn) {
          // Show projects that count as churn for this quarter
          if (p.idsOrdenesCompra.isEmpty) return false;
          if (p.estado != EstadoProyecto.finalizado) return false;
          final fechaFin = p.fechaTermino;
          if (fechaFin == null) return false;
          final q = ((fechaFin.month - 1) ~/ 3) + 1;
          if (fechaFin.year != _filterQuarterYear || q != _filterQuarterQ) return false;
          final graceDate = fechaFin.add(const Duration(days: 90));
          if (graceDate.isAfter(DateTime.now())) return false;
          if (p.proyectoContinuacionId != null && p.proyectoContinuacionId!.isNotEmpty) return false;
          final inst = p.institucion.trim().toLowerCase();
          final tieneRenovacion = renovadas!.contains(inst) ||
              all.any((o) =>
                  o.id != p.id &&
                  o.idsOrdenesCompra.isNotEmpty &&
                  o.institucion.trim().toLowerCase() == inst &&
                  (o.fechaInicio ?? o.fechaCreacion) != null &&
                  (o.fechaInicio ?? o.fechaCreacion)!.isAfter(fechaFin));
          if (tieneRenovacion) return false;
        } else {
          if (_filterQuarterOnlyWithOC && p.idsOrdenesCompra.isEmpty) return false;
          if (_filterQuarterOnlyIngresos &&
              p.estado != EstadoProyecto.vigente &&
              p.estado != EstadoProyecto.xVencer &&
              p.estado != EstadoProyecto.finalizado) { return false; }
          final fecha = p.fechaInicio ?? p.fechaCreacion;
          if (fecha == null) return false;
          final q = ((fecha.month - 1) ~/ 3) + 1;
          if (fecha.year != _filterQuarterYear || q != _filterQuarterQ) return false;
        }
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
              'Genera una tabla HTML lista para imprimir o guardar como PDF', () {
            Navigator.pop(context);
            _exportPDF(filtered);
          }),
        ]),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filterInstitucion != null || _filterProductos.isNotEmpty ||
      _filterModalidad != null || _filterEstado != null ||
      _filterReclamo != null || _filterVencer != null ||
      _filterQuarterYear != null;

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

  void _exportPDF(List<Proyecto> proyectos) {
    String fmtDate(DateTime? d) => d != null
        ? '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
        : '—';
    String fmtNum(double n) {
      final digits = n.toInt().toString();
      final buf = StringBuffer();
      for (int i = 0; i < digits.length; i++) {
        if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
        buf.write(digits[i]);
      }
      return buf.toString();
    }
    String fmtVal(double? v) => v != null ? '\$${fmtNum(v)}' : '—';
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    // ── KPI computations (same as KPI cards) ──────────────────────────────────
    final now = DateTime.now();
    final all = _proyectos; // use full list for KPIs, filtered list for table

    final kpiTotal      = all.length;
    final kpiActivos    = all.where((p) =>
        p.estado == EstadoProyecto.vigente || p.estado == EstadoProyecto.xVencer).length;
    final kpiVigentes   = all.where((p) => p.estado == EstadoProyecto.vigente).length;
    final kpiXVencer    = all.where((p) => p.estado == EstadoProyecto.xVencer).length;
    bool esPostulacion(Proyecto p) => p.estadoManual == 'En Evaluación';
    final kpiPostulacion = all.where(esPostulacion).length;
    final kpiFinalizados = all.where((p) => p.estado == EstadoProyecto.finalizado).length;

    final kpiValorTotal = all.fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));
    final kpiValorVigente = all
        .where((p) => p.estado == EstadoProyecto.vigente)
        .fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));
    final kpiValorPostulacion = all
        .where(esPostulacion)
        .fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));

    final kpiReclPend = all.fold<int>(
        0, (s, p) => s + p.reclamos.where((r) => r.estado == 'Pendiente').length);
    final kpiReclResp = all.fold<int>(
        0, (s, p) => s + p.reclamos.where((r) => r.estado == 'Respondido').length);

    final kpiVencer30  = all.where((p) {
      final ft = p.fechaTermino;
      return ft != null && ft.isAfter(now) && ft.isBefore(now.add(const Duration(days: 30)));
    }).length;
    final kpiVencer90  = all.where((p) {
      final ft = p.fechaTermino;
      return ft != null && ft.isAfter(now) && ft.isBefore(now.add(const Duration(days: 90)));
    }).length;
    final kpiVencer180 = all.where((p) {
      final ft = p.fechaTermino;
      return ft != null && ft.isAfter(now) && ft.isBefore(now.add(const Duration(days: 180)));
    }).length;
    final kpiVencer365 = all.where((p) {
      final ft = p.fechaTermino;
      return ft != null && ft.isAfter(now) && ft.isBefore(now.add(const Duration(days: 365)));
    }).length;

    String kpiCard(String label, String value, String color) =>
        '<div class="kpi-card"><div class="kpi-label">$label</div>'
        '<div class="kpi-value" style="color:$color">$value</div></div>';

    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final html = StringBuffer('''<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Proyectos — Mercado Público</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: Arial, Helvetica, sans-serif; font-size: 11px; color: #1E293B; padding: 20px; }
.header { margin-bottom: 14px; }
.header h1 { font-size: 18px; font-weight: 700; }
.header p { font-size: 10px; color: #64748B; margin-top: 3px; }
/* KPI section */
.kpi-section { margin-bottom: 18px; }
.kpi-section h2 { font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase;
  letter-spacing: 0.5px; margin-bottom: 8px; }
.kpi-group { display: flex; gap: 8px; margin-bottom: 8px; flex-wrap: wrap; }
.kpi-card { flex: 1; min-width: 100px; background: #F8FAFC; border: 1px solid #E2E8F0;
  border-radius: 8px; padding: 8px 10px; }
.kpi-label { font-size: 9px; color: #64748B; font-weight: 600; text-transform: uppercase;
  letter-spacing: 0.3px; margin-bottom: 4px; }
.kpi-value { font-size: 16px; font-weight: 700; }
/* Table */
table { width: 100%; border-collapse: collapse; }
.table-title { font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase;
  letter-spacing: 0.5px; margin-bottom: 8px; }
thead th { background: #5B21B6; color: #fff; padding: 7px 8px; text-align: left;
  font-size: 10px; font-weight: 700; }
tbody td { padding: 6px 8px; border-bottom: 1px solid #E2E8F0; font-size: 10px; vertical-align: top; }
tbody tr:nth-child(even) td { background: #F8FAFC; }
@page { margin: 15mm; }
@media print { body { padding: 0; } .kpi-card { break-inside: avoid; } }
</style>
</head>
<body>
<div class="header">
  <h1>Buscador Mercado Público</h1>
  <p>Informe de proyectos · $dateStr${_hasActiveFilters ? ' · Con filtros aplicados' : ''}</p>
</div>

<div class="kpi-section">
  <h2>Resumen de proyectos</h2>
  <div class="kpi-group">
    ${kpiCard('Total', '$kpiTotal', '#1E293B')}
    ${kpiCard('Activos', '$kpiActivos', '#5B21B6')}
    ${kpiCard('Vigentes', '$kpiVigentes', '#10B981')}
    ${kpiCard('X Vencer', '$kpiXVencer', '#F59E0B')}
    ${kpiCard('Postulación', '$kpiPostulacion', '#6366F1')}
    ${kpiCard('Finalizados', '$kpiFinalizados', '#64748B')}
  </div>
  <div class="kpi-group">
    ${kpiCard('Valor Total', '\$${fmtNum(kpiValorTotal)}', '#5B21B6')}
    ${kpiCard('Valor Vigente', '\$${fmtNum(kpiValorVigente)}', '#10B981')}
    ${kpiCard('Valor Postulación', '\$${fmtNum(kpiValorPostulacion)}', '#6366F1')}
    ${kpiCard('Reclamos Pend.', '$kpiReclPend', '#EF4444')}
    ${kpiCard('Reclamos Resp.', '$kpiReclResp', '#64748B')}
  </div>
  <div class="kpi-group">
    ${kpiCard('Por Vencer 30 días', '$kpiVencer30', '#F59E0B')}
    ${kpiCard('Por Vencer 3 meses', '$kpiVencer90', '#F59E0B')}
    ${kpiCard('Por Vencer 6 meses', '$kpiVencer180', '#F59E0B')}
    ${kpiCard('Por Vencer 12 meses', '$kpiVencer365', '#F59E0B')}
  </div>
</div>

<p class="table-title">Detalle de ${proyectos.length} proyecto${proyectos.length != 1 ? 's' : ''}${_hasActiveFilters ? ' (con filtros)' : ''}</p>
<table>
<thead>
<tr>
  <th>#</th><th>Institución</th><th>Productos</th><th>Modalidad</th>
  <th>Estado</th><th>Valor Mensual</th><th>F. Inicio</th><th>F. Término</th>
</tr>
</thead>
<tbody>
''');

    for (int i = 0; i < proyectos.length; i++) {
      final p = proyectos[i];
      html.write('<tr>');
      html.write('<td>${i + 1}</td>');
      html.write('<td>${esc(_cleanInst(p.institucion))}</td>');
      html.write('<td>${esc(p.productos)}</td>');
      html.write('<td>${esc(p.modalidadCompra)}</td>');
      html.write('<td>${esc(p.estado)}</td>');
      html.write('<td>${fmtVal(p.valorMensual)}</td>');
      html.write('<td>${fmtDate(p.fechaInicio)}</td>');
      html.write('<td>${fmtDate(p.fechaTermino)}</td>');
      html.write('</tr>\n');
    }

    html.write('''</tbody>
</table>
<script>window.addEventListener('load', function() { window.print(); });</script>
</body>
</html>''');

    final bytes = utf8.encode(html.toString());
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    web.window.open(url, '_blank');
    // Revoke after a short delay to allow the new tab to load
    Future.delayed(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
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

  void _goToQuarterFiltered(int year, int quarter,
      {bool onlyWithOC = false, bool onlyIngresos = false}) {
    setState(() {
      _filterQuarterYear = year;
      _filterQuarterQ = quarter;
      _filterQuarterOnlyWithOC = onlyWithOC;
      _filterQuarterIsChurn = false;
      _filterQuarterOnlyIngresos = onlyIngresos;
      _currentPage = 0;
    });
    _tabController.animateTo(1);
  }

  void _goToChurnQuarterFiltered(int year, int quarter) {
    setState(() {
      _filterQuarterYear = year;
      _filterQuarterQ = quarter;
      _filterQuarterOnlyWithOC = false;
      _filterQuarterIsChurn = true;
      _filterQuarterOnlyIngresos = false;
      _currentPage = 0;
    });
    _tabController.animateTo(1);
  }

  Widget _buildKpiRow(int activos, List<Proyecto> proyectos, int reclamosPend,
      int reclamosFinalizados, int xVencer, bool isMobile) {
    final kpiCards = [
      _ProyectosKpiCard(proyectos: proyectos, onNavigate: _goToProyectosFiltered),
      _ValorMensualCard(proyectos: proyectos, onNavigate: _goToProyectosFiltered),
      _ReclamosCard(pendientes: reclamosPend, finalizados: reclamosFinalizados, onNavigate: _goToReclamosFiltered),
      _XVencerKpiCard(proyectos: proyectos, onNavigate: _goToVencerFiltered),
    ];
    final chartCards = [
      _ClientesChartCard(
        proyectos: proyectos,
        onQuarterTap: (y, q, {bool onlyWithOC = false, bool onlyIngresos = false}) =>
            _goToQuarterFiltered(y, q, onlyWithOC: onlyWithOC, onlyIngresos: onlyIngresos),
        onChurnQuarterTap: (y, q) => _goToChurnQuarterFiltered(y, q),
      ),
      _FacturacionChartCard(
        proyectos: proyectos,
        onQuarterTap: (y, q, {bool onlyWithOC = false, bool onlyIngresos = false}) =>
            _goToQuarterFiltered(y, q, onlyWithOC: onlyWithOC, onlyIngresos: onlyIngresos),
      ),
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
      return _KpiCarouselMobile(
        kpiCards: kpiCards,
        chartCards: chartCards,
        actionBadges: actionBadges(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < kpiCards.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: kpiCards[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 200,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: chartCards[0]),
              const SizedBox(width: 14),
              Expanded(child: chartCards[1]),
            ],
          ),
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

  // ── KPI CAROUSEL ──────────────────────────────────────────────────────────
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

  /// Para proyectos en Evaluación con idLicitacion pero sin fechaPublicacion,
  /// obtiene las fechas desde OCDS y las guarda en Firestore automáticamente.
  Future<void> _sincronizarPostulacionDesdeOcds() async {
    final pendientes = _proyectos.where((p) =>
        p.estadoManual == 'En Evaluación' &&
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
        ? proyectos.where((p) => p.estadoManual == 'En Evaluación').toList()
        : proyectos.where((p) => p.estado == EstadoProyecto.vigente).toList();

    final withDates = byEstado.where(hasDates).toList()
      ..sort((a, b) => startOf(a, isRuta: isRuta, isPostulacion: isPostulacion)
          .compareTo(startOf(b, isRuta: isRuta, isPostulacion: isPostulacion)));

    final String emptyMsg = isPostulacion
        ? 'Ningún proyecto en estado En Evaluación tiene fechas de publicación y cierre registradas.'
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
                  color: const Color(0xFF5B21B6).withValues(alpha: 0.55)),
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
                              color: const Color(0xFF5B21B6)
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

                const barColor = Color(0xFF5B21B6);

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
                    _legendItem(const Color(0xFF5B21B6), isPostulacion ? 'Publicación → Cierre' : 'Período'),
                    if (isPostulacion) ...[
                      _legendItem(const Color(0xFF0EA5E9), 'Consultas', isLine: true),
                      _legendItem(const Color(0xFFF59E0B), 'Adjudicación', isLine: true),
                    ],
                    _legendItem(const Color(0xFF5B21B6).withValues(alpha: 0.55), 'Hoy', isLine: true),
                  ],
                )
              else
                Row(children: [
                  SizedBox(width: (isPostulacion ? 16 : 0) + labelW + 8),
                  _legendItem(const Color(0xFF5B21B6), isPostulacion ? 'Publicación → Cierre' : 'Período'),
                  if (isPostulacion) ...[
                    const SizedBox(width: 14),
                    _legendItem(const Color(0xFF0EA5E9), 'Consultas', isLine: true),
                    const SizedBox(width: 14),
                    _legendItem(const Color(0xFFF59E0B), 'Adjudicación', isLine: true),
                  ],
                  const SizedBox(width: 14),
                  _legendItem(const Color(0xFF5B21B6).withValues(alpha: 0.55), 'Hoy', isLine: true),
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
      ('postulacion', 'En Evaluación'),
      ('ruta', 'Implementación'),
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
    final enEvaluacion = _proyectos.where((p) => p.estadoManual == 'En Evaluación').length;
    final vigentes = _proyectos.where((p) => p.estado == EstadoProyecto.vigente).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryRow(total, enEvaluacion, vigentes, isMobile),
        const SizedBox(height: 16),
        _buildFilterRow(_proyectos, isMobile),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _buildEmptyState()
        else if (isMobile || MediaQuery.of(context).size.width < 800)
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
    final isMobileAppBar = screenWidth < 700;
    final hPadAppBar = isMobileAppBar ? 20.0 : 32.0;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: buildBreadcrumbAppBar(
        context: context,
        hPad: hPadAppBar,
        onOpenMenu: openAppDrawer,
        crumbs: [BreadcrumbItem('Proyectos')],
        actions: const [HelpToggleButton()],
      ),
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
        final isMobile = constraints.maxWidth < 900;
        final hPad = isMobile ? 20.0 : 32.0;

        return _cargando
                  ? SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 880),
                          child: _buildSkeletonDashboard(hPad),
                        ),
                      ),
                    )
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
                                        isScrollable: false,
                                        tabAlignment: TabAlignment.fill,
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
                                          Tab(text: 'Documentación'),
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
                                        if (_tabController.index == 2) {
                                          return _buildTabDocumentacion(isMobile);
                                        }
                                        return _buildTabProyectos(isMobile);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
      }),
    );
  }

  Widget _buildSummaryRow(
      int total, int enEvaluacion, int vigentes, bool isMobile) {
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
          Expanded(child: _summaryChip('Total $total', null, const Color(0xFF1E293B))),
          _divider(),
          Expanded(child: _summaryChip('En Evaluación $enEvaluacion', const Color(0xFF0EA5E9), const Color(0xFF0EA5E9))),
          _divider(),
          Expanded(child: _summaryChip('Vigentes $vigentes', const Color(0xFF10B981), const Color(0xFF10B981))),
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
      return summaryCard;
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (dotColor != null) ...[
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor),
              overflow: TextOverflow.ellipsis),
        ),
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
    ].where((v) => v != null).length +
        (_filterProductos.isNotEmpty ? 1 : 0) +
        (_filterQuarterYear != null ? 1 : 0);

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
        _activeChip(
            _filterEstado!,
            () => setState(() { _filterEstado = null; _currentPage = 0; })),
      if (_filterReclamo != null)
        _activeChip('Reclamo: $_filterReclamo',
            () => setState(() { _filterReclamo = null; _currentPage = 0; })),
      if (_filterVencer != null)
        _activeChip('Vencer: $_filterVencer',
            () => setState(() { _filterVencer = null; _currentPage = 0; })),
      if (_filterQuarterYear != null && _filterQuarterQ != null)
        _activeChip(
            _filterQuarterIsChurn
                ? 'Pérdidas Q$_filterQuarterQ · $_filterQuarterYear'
                : 'Q$_filterQuarterQ · $_filterQuarterYear',
            () => setState(() {
              _filterQuarterYear = null;
              _filterQuarterQ = null;
              _filterQuarterOnlyWithOC = false;
              _filterQuarterIsChurn = false;
              _filterQuarterOnlyIngresos = false;
              _currentPage = 0;
            })),
    ];

    final filterButton = GestureDetector(
      onTap: () => _showFiltersSheet(all),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hasFilters ? _primaryColor.withValues(alpha: 0.08) : Colors.white,
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
                    color: _primaryColor, borderRadius: BorderRadius.circular(10)),
                child: Text('$activeCount',
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );

    return Row(
      children: [
        // Active filter chips (left side)
        if (activeChips.isNotEmpty)
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
          )
        else
          const Spacer(),
        if (hasFilters) ...[
          GestureDetector(
            onTap: _clearFilters,
            child: Icon(Icons.close, size: 15, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
        ],
        // Filter icon button (right side)
        filterButton,
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
    // Deduplicate case-insensitively so names differing only in casing/spaces don't repeat
    final instSeen = <String>{};
    final instituciones = <String>[];
    for (final p in all) {
      final norm = p.institucion.trim().toUpperCase();
      if (norm.isEmpty) continue;
      if (instSeen.add(norm)) instituciones.add(norm);
    }
    instituciones.sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF475569))),
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
                // Handle + header (ProyectoFormDialog style)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                  child: Column(children: [
                    Center(
                      child: Container(
                          width: 32, height: 3,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: Row(children: [
                          Text('Filtros',
                              style: GoogleFonts.inter(
                                  fontSize: 18,
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
                        ]),
                      ),
                      if (activeCount > 0)
                        TextButton(
                          onPressed: () {
                            applyAndRefresh(() => _clearFilters());
                          },
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8)),
                          child: Text('Limpiar',
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: Colors.red.shade400)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ]),
                ),
                // Scrollable content
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    children: [
                      // Institución
                      sectionTitle('Institución'),
                      GestureDetector(
                        onTap: () async {
                          final sel = await showDialog<String>(
                            context: ctx,
                            builder: (_) => _FilterSearchDialog(
                              hint: 'Institución',
                              value: _filterInstitucion,
                              items: instituciones,
                              displayLabel: (s) => s,
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
                                : const Color(0xFFF8FAFC),
                            border: Border.all(
                                color: _filterInstitucion != null
                                    ? _primaryColor.withValues(alpha: 0.3)
                                    : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
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
                      sectionTitle('Productos'),
                      multiChipGroup(allProducts, _filterProductos),
                      const SizedBox(height: 20),

                      // Contratación
                      sectionTitle('Contratación'),
                      chipGroup(modalidades, _filterModalidad,
                          (v) => _filterModalidad = v),
                      const SizedBox(height: 20),

                      // Estado
                      sectionTitle('Estado'),
                      chipGroup(estados, _filterEstado,
                          (v) => _filterEstado = v),
                      const SizedBox(height: 20),

                      // Reclamos
                      sectionTitle('Reclamos'),
                      chipGroup(const ['Pendiente', 'Respondido'],
                          _filterReclamo, (v) => _filterReclamo = v),
                      const SizedBox(height: 20),

                      // Por Vencer
                      sectionTitle('Por Vencer'),
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

  // ── Documentación tab ───────────────────────────────────────────────────────

  List<_DocItem> _buildDocItems(List<Proyecto> proyectos) {
    final items = <_DocItem>[];
    for (final p in proyectos) {
      final estadoItem = _cfgEstados.firstWhere(
          (e) => e.nombre == p.estado,
          orElse: () => EstadoItem(nombre: p.estado, color: '64748B'));
      final color = estadoItem.colorValue;

      for (final doc in p.documentos) {
        final tipo = doc.tipo.isNotEmpty ? doc.tipo : 'Documento';
        items.add(_DocItem(
          tipoDoc: tipo,
          proyecto: p,
          descripcion: doc.nombre?.isNotEmpty == true ? doc.nombre! : tipo,
          fecha: null,
          labelFecha: null,
          urls: [doc.url],
          color: color,
        ));
      }
      for (final cert in p.certificados) {
        items.add(_DocItem(
          tipoDoc: 'Certificado',
          proyecto: p,
          descripcion: cert.descripcion,
          fecha: cert.fechaEmision,
          labelFecha: 'Emisión',
          urls: cert.url != null ? [cert.url!] : [],
          color: color,
        ));
      }
      for (final rec in p.reclamos) {
        final tipoDoc = rec.estado == 'Respondido'
            ? 'Reclamo Respondido'
            : 'Reclamo Pendiente';
        items.add(_DocItem(
          tipoDoc: tipoDoc,
          proyecto: p,
          descripcion: rec.descripcion,
          fecha: rec.fechaReclamo,
          labelFecha: 'Ingreso',
          fechaSecundaria: rec.fechaRespuesta,
          labelFechaSecundaria: rec.fechaRespuesta != null ? 'Respuesta' : null,
          urls: [
            ...rec.documentos.map((d) => d.url).where((u) => u.isNotEmpty),
            ...rec.documentosRespuesta.map((d) => d.url).where((u) => u.isNotEmpty),
          ],
          color: color,
        ));
      }
    }
    return items;
  }

  List<_DocItem> _applyDocFilters(List<_DocItem> all) {
    return all.where((item) {
      final p = item.proyecto;
      if (_docFilterInstitucion != null && _docFilterInstitucion!.isNotEmpty) {
        if (!p.institucion.toLowerCase().contains(_docFilterInstitucion!.toLowerCase())) return false;
      }
      if (_docFilterProductos.isNotEmpty) {
        final pp = p.productos.split(',').map((s) => s.trim()).toSet();
        if (!_docFilterProductos.any((prod) => pp.contains(prod))) return false;
      }
      if (_docFilterModalidad != null && _docFilterModalidad!.isNotEmpty) {
        if (p.modalidadCompra != _docFilterModalidad) return false;
      }
      if (_docFilterEstado != null && _docFilterEstado!.isNotEmpty) {
        if (p.estado != _docFilterEstado) return false;
      }
      if (_docFilterTipos.isNotEmpty) {
        if (!_docFilterTipos.contains(item.tipoDoc)) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildTabDocumentacion(bool isMobile) {
    final allItems = _buildDocItems(_proyectos);
    final filtered = _applyDocFilters(allItems)
      ..sort((a, b) {
        final da = a.fecha ?? DateTime(0);
        final db = b.fecha ?? DateTime(0);
        return _docSortAscending ? da.compareTo(db) : db.compareTo(da);
      });
    final totalPages = (filtered.length / _pageSize).ceil();
    final pageStart = _docCurrentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length);
    final pageItems = filtered.isEmpty ? <_DocItem>[] : filtered.sublist(pageStart, pageEnd);

    // Active doc filter count
    final activeCount = [
      _docFilterInstitucion,
      _docFilterModalidad,
      _docFilterEstado,
    ].where((v) => v != null).length +
        (_docFilterProductos.isNotEmpty ? 1 : 0) +
        (_docFilterTipos.isNotEmpty ? 1 : 0);
    final hasFilters = activeCount > 0;

    // Available tipo options from current data
    final allTipos = allItems.map((i) => i.tipoDoc).toSet().toList()..sort();

    final docFilterButton = GestureDetector(
      onTap: () => _showDocFiltersSheet(allTipos),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hasFilters ? _primaryColor.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(
              color: hasFilters ? _primaryColor : Colors.grey.shade200,
              width: hasFilters ? 1.5 : 1.0),
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
                    color: _primaryColor, borderRadius: BorderRadius.circular(10)),
                child: Text('$activeCount',
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );

    Widget docFilterRow() => Row(
      children: [
        if (hasFilters)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_docFilterInstitucion != null)
                    _activeChip(_docFilterInstitucion!.split('|').first.trim(),
                        () => setState(() { _docFilterInstitucion = null; _docCurrentPage = 0; })),
                  if (_docFilterProductos.isNotEmpty)
                    _activeChip(_docFilterProductos.join(', '),
                        () => setState(() { _docFilterProductos = {}; _docCurrentPage = 0; })),
                  if (_docFilterModalidad != null)
                    _activeChip(_docFilterModalidad!,
                        () => setState(() { _docFilterModalidad = null; _docCurrentPage = 0; })),
                  if (_docFilterEstado != null)
                    _activeChip(_docFilterEstado!,
                        () => setState(() { _docFilterEstado = null; _docCurrentPage = 0; })),
                  if (_docFilterTipos.isNotEmpty)
                    _activeChip(_docFilterTipos.join(', '),
                        () => setState(() { _docFilterTipos = {}; _docCurrentPage = 0; })),
                ].expand((c) => [c, const SizedBox(width: 6)]).toList()..removeLast(),
              ),
            ),
          )
        else
          const Spacer(),
        if (hasFilters) ...[
          GestureDetector(
            onTap: () => setState(() { _clearDocFilters(); }),
            child: Icon(Icons.close, size: 15, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
        ],
        GestureDetector(
          onTap: () => setState(() {
            _docSortAscending = !_docSortAscending;
            _docCurrentPage = 0;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _docSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 15,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        docFilterButton,
      ],
    );

    Widget docPagination() {
      if (totalPages <= 1) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _docCurrentPage > 0
                  ? () => setState(() => _docCurrentPage--)
                  : null,
              color: _primaryColor,
            ),
            Text(
              '${_docCurrentPage + 1} / $totalPages',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _docCurrentPage < totalPages - 1
                  ? () => setState(() => _docCurrentPage++)
                  : null,
              color: _primaryColor,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))]),
          child: Row(
            children: [
              Expanded(child: _summaryChip('Total ${allItems.length}', null, const Color(0xFF1E293B))),
              _divider(),
              Expanded(child: _summaryChip('Certificados ${allItems.where((i) => i.tipoDoc == 'Certificado').length}',
                  const Color(0xFF0EA5E9), const Color(0xFF0EA5E9))),
              _divider(),
              Expanded(child: _summaryChip('Reclamos ${allItems.where((i) => i.tipoDoc.startsWith('Reclamo')).length}',
                  const Color(0xFFEF4444), const Color(0xFFEF4444))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        docFilterRow(),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Sin documentos',
                      style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          )
        else
          Column(
            children: pageItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildDocCard(item, isMobile),
            )).toList(),
          ),
        docPagination(),
      ],
    );
  }

  Widget _buildDocCard(_DocItem item, bool isMobile) {
    final p = item.proyecto;
    final idLabel = p.idLicitacion?.isNotEmpty == true
        ? p.idLicitacion
        : p.idCotizacion?.isNotEmpty == true
            ? p.idCotizacion
            : p.idsOrdenesCompra.isNotEmpty
                ? p.idsOrdenesCompra.first
                : null;

    return GestureDetector(
      onTap: () => _openEditDialog(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header strip: tipo + ID/modalidad
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: item.color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item.tipoDoc,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                          color: item.color),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (idLabel != null)
                      Text(idLabel,
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400),
                          overflow: TextOverflow.ellipsis),
                    Text(p.modalidadCompra,
                        style: GoogleFonts.inter(fontSize: 9, color: Colors.grey.shade300),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ]),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Document description (main title)
                  Text(item.descripcion,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E293B)),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  // Institution (small)
                  const SizedBox(height: 2),
                  Text(_cleanInst(p.institucion),
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  // Products
                  if (p.productos.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(p.productos,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  // Dates
                  if (item.fecha != null || item.fechaSecundaria != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (item.fecha != null && item.labelFecha != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 11, color: Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Text('${item.labelFecha}: ${_formatDate(item.fecha)}',
                                  style: GoogleFonts.inter(
                                      fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        if (item.fechaSecundaria != null && item.labelFechaSecundaria != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 11, color: Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Text('${item.labelFechaSecundaria}: ${_formatDate(item.fechaSecundaria)}',
                                  style: GoogleFonts.inter(
                                      fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                      ],
                    ),
                  ],
                  // Document links
                  if (item.urls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.urls.asMap().entries.map((e) {
                        final idx = e.key;
                        final url = e.value;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                          onTap: () {
                            web.window.open(url, '_blank');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _primaryColor.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new, size: 12, color: _primaryColor),
                                const SizedBox(width: 4),
                                Text(item.urls.length > 1 ? 'Doc ${idx + 1}' : 'Ver documento',
                                    style: GoogleFonts.inter(
                                        fontSize: 11, fontWeight: FontWeight.w500,
                                        color: _primaryColor)),
                              ],
                            ),
                          ),
                        ));
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocFiltersSheet(List<String> tipoOptions) {
    final modalidades = _cfgModalidades;
    final estados = _cfgEstados.map((e) => e.nombre).toList();
    final allProducts = _cfgProductos.map((p) => p.abreviatura).toList()..sort();
    final instSeen2 = <String>{};
    final instituciones = <String>[];
    for (final p in _proyectos) {
      final norm = p.institucion.trim().toUpperCase();
      if (norm.isEmpty) continue;
      if (instSeen2.add(norm)) instituciones.add(norm);
    }
    instituciones.sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void applyAndRefresh(VoidCallback fn) {
            fn();
            setSheet(() {});
          }

          Widget sectionTitle(String t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(t,
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: const Color(0xFF475569))),
              );

          Widget chipGroup(List<String> items, String? selected,
              void Function(String?) onTap) {
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final item in items)
                GestureDetector(
                  onTap: () {
                    applyAndRefresh(() => setState(() {
                          onTap(selected == item ? null : item);
                          _docCurrentPage = 0;
                        }));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected == item ? _primaryColor : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item,
                        style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w500,
                            color: selected == item ? Colors.white : Colors.grey.shade700)),
                  ),
                ),
            ]);
          }

          Widget multiChipGroup(List<String> items, Set<String> selected,
              void Function(Set<String>) onChanged) {
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final item in items)
                GestureDetector(
                  onTap: () {
                    applyAndRefresh(() => setState(() {
                          final next = Set<String>.from(selected);
                          if (next.contains(item)) { next.remove(item); } else { next.add(item); }
                          onChanged(next);
                          _docCurrentPage = 0;
                        }));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected.contains(item) ? _primaryColor : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item,
                        style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w500,
                            color: selected.contains(item) ? Colors.white : Colors.grey.shade700)),
                  ),
                ),
            ]);
          }

          final activeCount = [
            _docFilterInstitucion,
            _docFilterModalidad,
            _docFilterEstado,
          ].where((v) => v != null).length +
              (_docFilterProductos.isNotEmpty ? 1 : 0) +
              (_docFilterTipos.isNotEmpty ? 1 : 0);

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                  child: Column(children: [
                    Center(
                      child: Container(
                          width: 32, height: 3,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: Row(children: [
                          Text('Filtros documentos',
                              style: GoogleFonts.inter(fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E293B))),
                          if (activeCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: _primaryColor,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text('$activeCount',
                                  style: GoogleFonts.inter(fontSize: 11,
                                      fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                          ],
                        ]),
                      ),
                      if (activeCount > 0)
                        TextButton(
                          onPressed: () { applyAndRefresh(() => _clearDocFilters()); },
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8)),
                          child: Text('Limpiar',
                              style: GoogleFonts.inter(fontSize: 13,
                                  color: Colors.red.shade400)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    children: [
                      // Tipo de documento
                      sectionTitle('Tipo de documento'),
                      multiChipGroup(tipoOptions, _docFilterTipos,
                          (v) => _docFilterTipos = v),
                      const SizedBox(height: 20),

                      // Institución
                      sectionTitle('Institución'),
                      GestureDetector(
                        onTap: () async {
                          final sel = await showDialog<String>(
                            context: ctx,
                            builder: (_) => _FilterSearchDialog(
                              hint: 'Institución',
                              value: _docFilterInstitucion,
                              items: instituciones,
                              displayLabel: (s) => s,
                            ),
                          );
                          if (sel == '\x00') {
                            applyAndRefresh(() => setState(
                                () { _docFilterInstitucion = null; _docCurrentPage = 0; }));
                          } else if (sel != null) {
                            applyAndRefresh(() => setState(
                                () { _docFilterInstitucion = sel; _docCurrentPage = 0; }));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _docFilterInstitucion != null
                                ? _primaryColor.withValues(alpha: 0.06)
                                : const Color(0xFFF8FAFC),
                            border: Border.all(
                                color: _docFilterInstitucion != null
                                    ? _primaryColor.withValues(alpha: 0.3)
                                    : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                _docFilterInstitucion != null
                                    ? _docFilterInstitucion!.split('|').first.trim()
                                    : 'Seleccionar institución…',
                                style: GoogleFonts.inter(fontSize: 13,
                                    color: _docFilterInstitucion != null
                                        ? const Color(0xFF1E293B)
                                        : Colors.grey.shade400),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              _docFilterInstitucion != null ? Icons.close : Icons.search,
                              size: 16,
                              color: _docFilterInstitucion != null
                                  ? _primaryColor : Colors.grey.shade400,
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Productos
                      sectionTitle('Productos'),
                      multiChipGroup(allProducts, _docFilterProductos,
                          (v) => _docFilterProductos = v),
                      const SizedBox(height: 20),

                      // Contratación
                      sectionTitle('Contratación'),
                      chipGroup(modalidades, _docFilterModalidad,
                          (v) => _docFilterModalidad = v),
                      const SizedBox(height: 20),

                      // Estado del proyecto
                      sectionTitle('Estado del proyecto'),
                      chipGroup(estados, _docFilterEstado,
                          (v) => _docFilterEstado = v),
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
                      children: [
                        Flexible(
                          child: Text(
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
                  Expanded(
                    child: Text(p.estado,
                        style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: estadoItem.colorValue),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (idLabel != null)
                        Text(idLabel,
                            style: GoogleFonts.inter(
                                fontSize: 10, color: Colors.grey.shade400),
                            overflow: TextOverflow.ellipsis),
                      Text(p.modalidadCompra,
                          style: GoogleFonts.inter(
                              fontSize: 9, color: Colors.grey.shade300),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (p.valorMensual != null)
                        Text('\$ ${_fmt(p.valorMensual!.toInt())}',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500)),
                      if (p.fechaTermino != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 11, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(_formatDate(p.fechaTermino),
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
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

// ── Skeleton loading ──────────────────────────────────────────────────────────

class _SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkeletonBox({this.width, this.height = 16, this.radius = 8});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
              const Color(0xFFEDF0F3), const Color(0xFFF7F9FB), _anim.value),
        ),
      ),
    );
  }
}

Widget _buildSkeletonDashboard(double hPad) {
  const gap = SizedBox(width: 14);
  const vGap = SizedBox(height: 14);

  Widget skCard({double height = 100}) => Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBox(width: 60, height: 10),
            const SizedBox(height: 10),
            _SkeletonBox(width: 120, height: 22, radius: 6),
            const Spacer(),
            _SkeletonBox(height: 8, radius: 4),
          ],
        ),
      );

  return Padding(
    padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab bar placeholder
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: _SkeletonBox(height: 28, radius: 8)),
            gap,
            Expanded(child: _SkeletonBox(height: 28, radius: 8)),
            gap,
            Expanded(child: _SkeletonBox(height: 28, radius: 8)),
          ]),
        ),
        const SizedBox(height: 20),
        // KPI row: 4 cards
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < 4; i++) ...[
                if (i > 0) gap,
                Expanded(child: skCard(height: 100)),
              ],
            ],
          ),
        ),
        vGap,
        // Chart row: 2 cards
        SizedBox(
          height: 200,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: skCard(height: 200)),
            gap,
            Expanded(child: skCard(height: 200)),
          ]),
        ),
        const SizedBox(height: 20),
        // List skeleton rows
        for (int i = 0; i < 6; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              _SkeletonBox(width: 8, height: 8, radius: 4),
              const SizedBox(width: 12),
              Expanded(child: _SkeletonBox(height: 12)),
              const SizedBox(width: 24),
              _SkeletonBox(width: 60, height: 12),
            ]),
          ),
        ],
      ],
    ),
  );
}

// ── Shared KPI card shell ──────────────────────────────────────────────────────

class _KpiCardShell extends StatefulWidget {
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
  State<_KpiCardShell> createState() => _KpiCardShellState();
}

class _KpiCardShellState extends State<_KpiCardShell>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _iconCtrl;
  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;

  @override
  void initState() {
    super.initState();
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _iconScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut),
    );
    _iconOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _iconCtrl,
          curve: const Interval(0.0, 0.55, curve: Curves.easeOut)),
    );
    _iconCtrl.value = 1.0; // start fully visible, no animation on first build
  }

  @override
  void didUpdateWidget(_KpiCardShell old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _iconCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canTap = widget.onTap != null;
    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) { if (canTap) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          widget.onSwipe(d.primaryVelocity! < 0);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.09 : 0.05),
                  blurRadius: _hovered ? 12 : 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(widget.label,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500),
                      maxLines: 2),
                ),
                FadeTransition(
                  opacity: _iconOpacity,
                  child: ScaleTransition(
                    scale: _iconScale,
                    child: widget.icon,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            widget.value,
            const SizedBox(height: 8),
            // Bottom row: dots (left) + Apple-style arrow (right, hover only)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSwipe(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: Row(
                          children: List.generate(widget.pageCount, (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: i == widget.currentIndex ? 12 : 5,
                            height: 4,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: i == widget.currentIndex
                                  ? widget.color
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )),
                        ),
                      ),
                    ),
                    // Apple-style chevron — only when tappable and hovered
                    if (canTap)
                      AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedSlide(
                          offset: _hovered ? Offset.zero : const Offset(0.3, 0),
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                  ],
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
              fontSize: 20,
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
    (label: 'Proyectos\nEn Evaluación', estado: 'En Evaluación',            color: Color(0xFF6366F1), activos: false),
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
              fontSize: 20,
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
      if (p.estado != EstadoProyecto.vigente && p.estado != EstadoProyecto.xVencer) return false;
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
              fontSize: 20,
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
    (label: 'Valor Mensual\nEn Evaluación', short: 'En Evaluación', estado: 'En Evaluación',            color: Color(0xFF0EA5E9)),
    (label: 'Valor Mensual\nTotal',       short: 'Total',       estado: null as String?,            color: Color(0xFF5B21B6)),
  ];

  static String _fmt(double n) {
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toInt()}';
  }

  static String _fmtFull(double n) {
    final str = n.toInt().toString();
    final buf = StringBuffer('\$');
    final len = str.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_idx];
    final filtered = page.estado == null
        ? widget.proyectos.toList()
        : widget.proyectos.where((p) => p.estado == page.estado).toList();
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
      value: Tooltip(
        message: total > 0 ? _fmtFull(total) : '',
        preferBelow: false,
        child: Text(
          total > 0 ? _fmt(total) : '—',
          style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: const Color(0xFF1E293B)),
        ),
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

// ── KPI Carousel — Mobile ────────────────────────────────────────────────────

class _KpiCarouselMobile extends StatefulWidget {
  final List<Widget> kpiCards;
  final List<Widget> chartCards;
  final Widget actionBadges;
  const _KpiCarouselMobile({required this.kpiCards, required this.chartCards, required this.actionBadges});

  @override
  State<_KpiCarouselMobile> createState() => _KpiCarouselMobileState();
}

class _KpiCarouselMobileState extends State<_KpiCarouselMobile> {
  late final PageController _ctrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _kpiPages => (widget.kpiCards.length / 2).ceil();
  int get _totalPages => _kpiPages + widget.chartCards.length;

  Widget _buildPage(int pageIndex) {
    if (pageIndex < _kpiPages) {
      final i = pageIndex * 2;
      final first = widget.kpiCards[i];
      final second = i + 1 < widget.kpiCards.length ? widget.kpiCards[i + 1] : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: 10),
          Expanded(child: second ?? const SizedBox()),
        ],
      );
    } else {
      return widget.chartCards[pageIndex - _kpiPages];
    }
  }

  void _goTo(int page) {
    _ctrl.animateToPage(page,
        duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF6D28D9);
    final total = _totalPages;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            children: [
              PageView.builder(
                controller: _ctrl,
                itemCount: total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildPage(i),
                ),
              ),
              if (_page > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _goTo(_page - 1),
                      child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 6)
                          ],
                        ),
                        child: const Icon(Icons.chevron_left_rounded,
                            size: 20, color: primaryColor),
                      ),
                    ),
                  ),
                ),
              if (_page < total - 1)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _goTo(_page + 1),
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 6)
                          ],
                        ),
                        child: const Icon(Icons.chevron_right_rounded,
                            size: 20, color: primaryColor),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (i) =>
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == _page ? 16 : 6,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == _page ? primaryColor : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        widget.actionBadges,
      ],
    );
  }
}

// ── Chart helpers ─────────────────────────────────────────────────────────────

typedef _QData = ({String label, int year, int quarter, double value});

List<_QData> _groupByQuarter(
    List<Proyecto> proyectos, double Function(Proyecto) getValue,
    {bool onlyWithOC = false}) {
  final map = <(int, int), double>{};
  for (final p in proyectos) {
    if (onlyWithOC && p.idsOrdenesCompra.isEmpty) continue;
    final fecha = p.fechaInicio ?? p.fechaCreacion;
    if (fecha == null) continue;
    final q = ((fecha.month - 1) ~/ 3) + 1;
    final key = (fecha.year, q);
    map[key] = (map[key] ?? 0) + getValue(p);
  }
  final entries = map.entries.toList()
    ..sort((a, b) {
      final yc = a.key.$1.compareTo(b.key.$1);
      return yc != 0 ? yc : a.key.$2.compareTo(b.key.$2);
    });
  return entries
      .map((e) => (
            label: 'Q${e.key.$2}',
            year: e.key.$1,
            quarter: e.key.$2,
            value: e.value,
          ))
      .toList();
}

/// Devuelve lista donde cada elemento es el año como String si cambió respecto
/// al anterior (primera barra de ese año), o null si el año es el mismo.
/// [abbreviated] usa formato corto: '24 en lugar de 2024.
List<String?> _yearLabels(List<_QData> data, {bool abbreviated = false}) {
  int? lastYear;
  return data.map((d) {
    if (d.year != lastYear) {
      lastYear = d.year;
      return abbreviated
          ? "'${(d.year % 100).toString().padLeft(2, '0')}"
          : d.year.toString();
    }
    return null;
  }).toList();
}

/// Proyectos finalizados con OC que no tienen renovación (nueva OC de la misma
/// institución con fechaInicio posterior). Se agrupa por quarter de fechaTermino.
List<_QData> _churnByQuarter(List<Proyecto> proyectos) {
  // Instituciones que tienen algún proyecto activo (con OC, no finalizado)
  final renovadas = <String>{};
  for (final p in proyectos) {
    if (p.idsOrdenesCompra.isEmpty) continue;
    if (p.estado == EstadoProyecto.finalizado) continue;
    renovadas.add(p.institucion.trim().toLowerCase());
  }

  final map = <(int, int), double>{};
  for (final p in proyectos) {
    if (p.idsOrdenesCompra.isEmpty) continue;
    if (p.estado != EstadoProyecto.finalizado) continue;
    final fechaFin = p.fechaTermino;
    if (fechaFin == null) continue;
    final inst = p.institucion.trim().toLowerCase();

    // Tiene renovación si hay otro proyecto con OC de la misma institución
    // cuyo fechaInicio es posterior a la fecha de término de éste
    final tieneRenovacion = renovadas.contains(inst) ||
        proyectos.any((o) =>
            o.id != p.id &&
            o.idsOrdenesCompra.isNotEmpty &&
            o.institucion.trim().toLowerCase() == inst &&
            (o.fechaInicio ?? o.fechaCreacion) != null &&
            (o.fechaInicio ?? o.fechaCreacion)!.isAfter(fechaFin));

    // Período de gracia: 90 días desde fechaTermino antes de contar como churn
    final graceDate = fechaFin.add(const Duration(days: 90));
    if (graceDate.isAfter(DateTime.now())) continue;

    // Encadenado explícitamente → no es churn
    if (p.proyectoContinuacionId != null && p.proyectoContinuacionId!.isNotEmpty) continue;

    if (!tieneRenovacion) {
      final q = ((fechaFin.month - 1) ~/ 3) + 1;
      final key = (fechaFin.year, q);
      map[key] = (map[key] ?? 0) + 1;
    }
  }

  final entries = map.entries.toList()
    ..sort((a, b) {
      final yc = a.key.$1.compareTo(b.key.$1);
      return yc != 0 ? yc : a.key.$2.compareTo(b.key.$2);
    });
  return entries
      .map((e) => (
            label: 'Q${e.key.$2}',
            year: e.key.$1,
            quarter: e.key.$2,
            value: e.value,
          ))
      .toList();
}

/// Une dos listas de _QData en un timeline unificado.
/// Retorna labels, yearLabels, valores positivos y valores de churn alineados.
({
  List<String> labels,
  List<String?> yearLabels,
  List<double> positive,
  List<double> churn,
  List<(int, int)> keys,
}) _mergeDivergingData(List<_QData> positiveData, List<_QData> churnData,
    {bool abbreviated = false}) {
  final keys = <(int, int)>{};
  for (final d in [...positiveData, ...churnData]) {
    keys.add((d.year, d.quarter));
  }
  final extremes = keys.toList()
    ..sort((a, b) {
      final yc = a.$1.compareTo(b.$1);
      return yc != 0 ? yc : a.$2.compareTo(b.$2);
    });

  // Fill all intermediate quarters so gaps with 0 activity are visible
  final sorted = <(int, int)>[];
  if (extremes.isNotEmpty) {
    var cur = extremes.first;
    final last = extremes.last;
    while (cur.$1 < last.$1 || (cur.$1 == last.$1 && cur.$2 <= last.$2)) {
      sorted.add(cur);
      cur = cur.$2 < 4 ? (cur.$1, cur.$2 + 1) : (cur.$1 + 1, 1);
    }
  }

  final posMap = {for (final d in positiveData) (d.year, d.quarter): d.value};
  final negMap = {for (final d in churnData) (d.year, d.quarter): d.value};

  final qData = sorted
      .map((k) => (label: 'Q${k.$2}', year: k.$1, quarter: k.$2, value: 0.0))
      .toList();

  return (
    labels: sorted.map((k) => 'Q${k.$2}').toList(),
    yearLabels: _yearLabels(qData, abbreviated: abbreviated),
    positive: sorted.map((k) => posMap[k] ?? 0.0).toList(),
    churn: sorted.map((k) => negMap[k] ?? 0.0).toList(),
    keys: sorted,
  );
}

/// Clientes nuevos por quarter.
/// Cada institución se cuenta UNA sola vez, en el quarter de su PRIMERA OC.
/// Proyectos posteriores de la misma institución no suman como cliente nuevo.
List<_QData> _newClientsByQuarter(List<Proyecto> proyectos) {
  // Para cada institución, encontrar la fecha del proyecto con OC más antiguo
  final firstByInst = <String, DateTime>{};
  for (final p in proyectos) {
    if (p.idsOrdenesCompra.isEmpty) continue;
    final fecha = p.fechaInicio ?? p.fechaCreacion;
    if (fecha == null) continue;
    final inst = p.institucion.trim().toLowerCase();
    final existing = firstByInst[inst];
    if (existing == null || fecha.isBefore(existing)) {
      firstByInst[inst] = fecha;
    }
  }

  final map = <(int, int), double>{};
  for (final fecha in firstByInst.values) {
    final q = ((fecha.month - 1) ~/ 3) + 1;
    final key = (fecha.year, q);
    map[key] = (map[key] ?? 0) + 1;
  }

  final entries = map.entries.toList()
    ..sort((a, b) {
      final yc = a.key.$1.compareTo(b.key.$1);
      return yc != 0 ? yc : a.key.$2.compareTo(b.key.$2);
    });
  return entries
      .map((e) => (
            label: 'Q${e.key.$2}',
            year: e.key.$1,
            quarter: e.key.$2,
            value: e.value,
          ))
      .toList();
}

// ── Clients chart card ────────────────────────────────────────────────────────

class _ClientesChartCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(int year, int quarter, {bool onlyWithOC, bool onlyIngresos})? onQuarterTap;
  final void Function(int year, int quarter)? onChurnQuarterTap;
  const _ClientesChartCard({required this.proyectos, this.onQuarterTap, this.onChurnQuarterTap});

  @override
  State<_ClientesChartCard> createState() => _ClientesChartCardState();
}

class _ClientesChartCardState extends State<_ClientesChartCard> {
  bool _showLine = false;
  static const _color = Color(0xFF0EA5E9);

  @override
  Widget build(BuildContext context) {
    final data  = _newClientsByQuarter(widget.proyectos).where((d) => d.year >= 2021).toList();
    final churn = _churnByQuarter(widget.proyectos).where((d) => d.year >= 2021).toList();
    final merged = _mergeDivergingData(data, churn);

    // Clientes activos netos por quarter:
    // acumulado de (nuevos - bajas) → refleja la cartera real en cada momento
    final netValues = <double>[];
    double net = 0;
    for (int i = 0; i < merged.positive.length; i++) {
      final churnVal = i < merged.churn.length ? merged.churn[i] : 0.0;
      net = (net + merged.positive[i] - churnVal).clamp(0, double.infinity);
      netValues.add(net);
    }

    return _ChartCardShell(
      title: _showLine ? 'Cartera Activa Neta' : 'Clientes Nuevos / Quarter',
      icon: Icons.people_outline_rounded,
      color: _color,
      showLine: _showLine,
      onToggle: () => setState(() => _showLine = !_showLine),
      helpStep: _showLine ? HelpStepsStore.instance.steps[2] : HelpStepsStore.instance.steps[1],
      child: merged.labels.isEmpty
          ? _emptyChartWidget()
          : _showLine
              ? _LineChartWidget(
                  labels: merged.labels,
                  yearLabels: merged.yearLabels,
                  values: netValues,
                  color: _color,
                  integerValues: true,
                )
              : _BarChartWidget(
                  labels: merged.labels,
                  yearLabels: merged.yearLabels,
                  values: merged.positive,
                  churnValues: merged.churn,
                  color: _color,
                  integerValues: true,
                  onBarTap: widget.onQuarterTap == null ? null : (i) {
                    final k = merged.keys[i];
                    widget.onQuarterTap!(k.$1, k.$2, onlyWithOC: true);
                  },
                  onChurnBarTap: widget.onChurnQuarterTap == null ? null : (i) {
                    final k = merged.keys[i];
                    widget.onChurnQuarterTap!(k.$1, k.$2);
                  },
                ),
    );
  }
}

// ── Facturación chart card ────────────────────────────────────────────────────

class _FacturacionChartCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(int year, int quarter, {bool onlyWithOC, bool onlyIngresos})? onQuarterTap;
  const _FacturacionChartCard({required this.proyectos, this.onQuarterTap});

  @override
  State<_FacturacionChartCard> createState() => _FacturacionChartCardState();
}

class _FacturacionChartCardState extends State<_FacturacionChartCard> {
  int _view = 0; // 0=barras mensual, 1=línea acumulada, 2=total OC

  static const _color = Color(0xFFA78BFA);
  static const _colorOC = Color(0xFF10B981);

  static String _fmt(double n) {
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final dataMensual = _groupByQuarter(
        widget.proyectos.where((p) =>
            p.estado == EstadoProyecto.vigente ||
            p.estado == EstadoProyecto.xVencer ||
            p.estado == EstadoProyecto.finalizado).toList(),
        (p) => p.valorMensual ?? 0)
        .where((d) => d.year >= 2021).toList();
    final dataOC = _groupByQuarter(
        widget.proyectos, (p) => p.montoTotalOC ?? 0,
        onlyWithOC: true).where((d) => d.value > 0).toList();
    final yLabelsMensual = _yearLabels(dataMensual, abbreviated: true);
    final yLabelsOC = _yearLabels(dataOC, abbreviated: true);

    final cum = <double>[];
    double s = 0;
    for (final d in dataMensual) { s += d.value; cum.add(s); }

    final (title, color, child) = switch (_view) {
      1 => (
          'Facturación Mensual Acumulada',
          _color,
          dataMensual.isEmpty
              ? _emptyChartWidget()
              : _LineChartWidget(
                  labels: dataMensual.map((d) => d.label).toList(),
                  yearLabels: yLabelsMensual,
                  values: cum,
                  color: _color,
                  formatValue: _fmt,
                ),
        ),
      2 => (
          'Total Órdenes de Compra',
          _colorOC,
          dataOC.isEmpty
              ? _emptyChartWidget()
              : _BarChartWidget(
                  labels: dataOC.map((d) => d.label).toList(),
                  yearLabels: yLabelsOC,
                  values: dataOC.map((d) => d.value).toList(),
                  color: _colorOC,
                  formatValue: _fmt,
                  onBarTap: widget.onQuarterTap == null ? null : (i) {
                    final d = dataOC[i];
                    widget.onQuarterTap!(d.year, d.quarter, onlyWithOC: true);
                  },
                ),
        ),
      _ => (
          'Monto Mensual / Quarter',
          _color,
          dataMensual.isEmpty
              ? _emptyChartWidget()
              : _BarChartWidget(
                  labels: dataMensual.map((d) => d.label).toList(),
                  yearLabels: yLabelsMensual,
                  values: dataMensual.map((d) => d.value).toList(),
                  color: _color,
                  formatValue: _fmt,
                  onBarTap: widget.onQuarterTap == null ? null : (i) {
                    final d = dataMensual[i];
                    widget.onQuarterTap!(d.year, d.quarter, onlyWithOC: false, onlyIngresos: true);
                  },
                ),
        ),
    };

    final viewLabels = ['M', 'T', '∑ OC'];
    final viewIcons = [Icons.bar_chart_rounded, Icons.show_chart_rounded, Icons.receipt_long_rounded];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.show_chart_rounded, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(children: [
                  Flexible(child: Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
                  HelpBadge(HelpStepsStore.instance.steps[3]),
                ]),
              ),
              const SizedBox(width: 8),
              // 3-option toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) => GestureDetector(
                  onTap: () => setState(() => _view = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: _view == i ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(viewIcons[i], size: 12,
                            color: _view == i ? color : Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(viewLabels[i],
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                color: _view == i ? color : Colors.grey.shade500,
                                fontWeight: _view == i ? FontWeight.w600 : FontWeight.w400)),
                      ],
                    ),
                  ),
                )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Chart card shell (for Clientes card) ─────────────────────────────────────

class _ChartCardShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool showLine;
  final VoidCallback onToggle;
  final Widget child;
  final WalkthroughStep? helpStep;

  const _ChartCardShell({
    required this.title,
    required this.icon,
    required this.color,
    required this.showLine,
    required this.onToggle,
    required this.child,
    this.helpStep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: Text(title,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                    if (helpStep != null) HelpBadge(helpStep!),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showLine ? Icons.bar_chart_rounded : Icons.show_chart_rounded,
                        size: 12,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        showLine ? 'Barras' : 'Tendencia',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Widget _emptyChartWidget() => Center(
      child: Text('Sin datos',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400)),
    );

// ── Bar chart widget ──────────────────────────────────────────────────────────

class _BarChartWidget extends StatefulWidget {
  final List<String> labels;
  /// Año a mostrar debajo del label cuando cambia (null = no mostrar)
  final List<String?> yearLabels;
  final List<double> values;
  /// Valores de churn (bajas) — barras rojas hacia abajo; misma longitud que values
  final List<double> churnValues;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;
  final void Function(int index)? onBarTap;
  final void Function(int index)? onChurnBarTap;

  const _BarChartWidget({
    required this.labels,
    required this.yearLabels,
    required this.values,
    this.churnValues = const [],
    required this.color,
    this.integerValues = false,
    this.formatValue,
    this.onBarTap,
    this.onChurnBarTap,
  });

  @override
  State<_BarChartWidget> createState() => _BarChartWidgetState();
}

class _BarChartWidgetState extends State<_BarChartWidget> {
  int? _hoveredIndex;

  String _fmt(double v) {
    if (widget.formatValue != null) return widget.formatValue!(v);
    return widget.integerValues ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  int? _indexAt(Offset local, Size size) {
    if (widget.labels.isEmpty || size.width == 0) return null;
    final slotW = size.width / widget.labels.length;
    final i = (local.dx / slotW).floor();
    if (i < 0 || i >= widget.labels.length) return null;
    return i;
  }

  bool _isChurnZone(Offset local, Size size) {
    if (widget.churnValues.isEmpty) return false;
    const topPad = 4.0;
    const axisH = 13.0 + 12.0;
    final totalH = size.height - axisH - topPad;
    final maxPos = widget.values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxNeg = widget.churnValues.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxNeg <= 0) return false;
    final posRatio = maxPos <= 0 ? 0.0 : maxPos / (maxPos + maxNeg);
    final zeroY = topPad + totalH * posRatio;
    return local.dy > zeroY;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return MouseRegion(
        cursor: (widget.onBarTap != null || widget.onChurnBarTap != null)
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onHover: (e) {
          final idx = _indexAt(e.localPosition, size);
          if (idx != _hoveredIndex) setState(() => _hoveredIndex = idx);
        },
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTapDown: (e) {
            final idx = _indexAt(e.localPosition, size);
            if (idx != null) {
              final isChurn = _isChurnZone(e.localPosition, size);
              if (isChurn &&
                  widget.onChurnBarTap != null &&
                  idx < widget.churnValues.length &&
                  widget.churnValues[idx] > 0) {
                widget.onChurnBarTap!(idx);
              } else if (widget.onBarTap != null) {
                widget.onBarTap!(idx);
              } else {
                setState(() => _hoveredIndex = _hoveredIndex == idx ? null : idx);
              }
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: _BarChartPainter(
                  labels: widget.labels,
                  yearLabels: widget.yearLabels,
                  values: widget.values,
                  churnValues: widget.churnValues,
                  color: widget.color,
                  integerValues: widget.integerValues,
                  formatValue: widget.formatValue,
                  hoveredIndex: _hoveredIndex,
                ),
                child: const SizedBox.expand(),
              ),
              if (_hoveredIndex != null)
                _BarTooltip(
                  index: _hoveredIndex!,
                  label: widget.labels[_hoveredIndex!],
                  yearLabel: widget.yearLabels[_hoveredIndex!],
                  valueText: _fmt(widget.values[_hoveredIndex!]),
                  churnText: widget.churnValues.length > _hoveredIndex! &&
                          widget.churnValues[_hoveredIndex!] > 0
                      ? '-${_fmt(widget.churnValues[_hoveredIndex!])}'
                      : null,
                  color: widget.color,
                  totalSlots: widget.labels.length,
                  chartWidth: size.width,
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _BarTooltip extends StatelessWidget {
  final int index;
  final String label;
  final String? yearLabel;
  final String valueText;
  final String? churnText;
  final Color color;
  final int totalSlots;
  final double chartWidth;

  const _BarTooltip({
    required this.index,
    required this.label,
    required this.yearLabel,
    required this.valueText,
    this.churnText,
    required this.color,
    required this.totalSlots,
    required this.chartWidth,
  });

  @override
  Widget build(BuildContext context) {
    const tooltipW = 92.0;
    final slotW = chartWidth / totalSlots;
    final cx = slotW * index + slotW / 2;
    final left = (cx - tooltipW / 2).clamp(0.0, chartWidth - tooltipW);
    // Reconstruct full label: e.g. "Q2 · 2024"
    final fullLabel = yearLabel != null ? '$label · $yearLabel' : label;

    return Positioned(
      left: left,
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: tooltipW,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fullLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.65))),
              const SizedBox(height: 3),
              Text(valueText,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              if (churnText != null) ...[
                const SizedBox(height: 2),
                Text(churnText!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFCA5A5))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<String> labels;
  final List<String?> yearLabels;
  final List<double> values;
  final List<double> churnValues;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;
  final int? hoveredIndex;

  static const _churnColor = Color(0xFFEF4444);

  const _BarChartPainter({
    required this.labels,
    required this.yearLabels,
    required this.values,
    this.churnValues = const [],
    required this.color,
    this.integerValues = false,
    this.formatValue,
    this.hoveredIndex,
  });

  void _drawCenteredText(Canvas canvas, String text, Offset center,
      TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || values.isEmpty) return;
    const quarterH = 13.0;
    const yearH = 12.0;
    const axisH = quarterH + yearH;
    const topPad = 4.0;
    final totalH = size.height - axisH - topPad;

    final maxPos = values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxNeg = churnValues.isEmpty
        ? 0.0
        : churnValues.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxPos <= 0 && maxNeg <= 0) return;

    // Zero line splits chart area proportionally
    final posRatio = maxNeg == 0 ? 1.0 : maxPos / (maxPos + maxNeg);
    final posH = totalH * posRatio;  // height above zero
    final negH = totalH - posH;       // height below zero
    final zeroY = topPad + posH;

    final n = labels.length;
    final slotW = size.width / n;
    final barW = slotW * 0.55;

    final quarterStyle = TextStyle(
        fontSize: 9, color: const Color(0xFF94A3B8), fontFamily: 'Inter');
    final yearStyle = TextStyle(
        fontSize: 8,
        color: const Color(0xFFCBD5E1),
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600);

    // Zero line (only when churn exists)
    if (maxNeg > 0) {
      canvas.drawLine(
        Offset(0, zeroY),
        Offset(size.width, zeroY),
        Paint()
          ..color = const Color(0xFFE2E8F0)
          ..strokeWidth = 1,
      );
    }

    for (int i = 0; i < n; i++) {
      final hovered = i == hoveredIndex;
      final cx = slotW * i + slotW / 2;

      // Positive bar (up from zero)
      if (maxPos > 0) {
        final bh = (values[i] / maxPos) * posH;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(cx - barW / 2, topPad, barW, posH),
                const Radius.circular(4)),
            Paint()
              ..color = color.withValues(alpha: hovered ? 0.14 : 0.08)
              ..style = PaintingStyle.fill);
        if (bh > 0) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(cx - barW / 2, zeroY - bh, barW, bh),
                  const Radius.circular(4)),
              Paint()
                ..color = hovered ? color.withValues(alpha: 0.85) : color
                ..style = PaintingStyle.fill);
        }
      }

      // Negative / churn bar (down from zero)
      if (maxNeg > 0 && i < churnValues.length && churnValues[i] > 0) {
        final bh = (churnValues[i] / maxNeg) * negH;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(cx - barW / 2, zeroY, barW, negH),
                const Radius.circular(4)),
            Paint()
              ..color = _churnColor.withValues(alpha: hovered ? 0.14 : 0.07)
              ..style = PaintingStyle.fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(cx - barW / 2, zeroY, barW, bh),
                const Radius.circular(4)),
            Paint()
              ..color = hovered
                  ? _churnColor.withValues(alpha: 0.85)
                  : _churnColor
              ..style = PaintingStyle.fill);
      }

      // Quarter label
      _drawCenteredText(canvas, labels[i],
          Offset(cx, size.height - axisH), quarterStyle, slotW);

      // Year label (only on year change)
      if (i < yearLabels.length && yearLabels[i] != null) {
        _drawCenteredText(canvas, yearLabels[i]!,
            Offset(cx, size.height - yearH), yearStyle, slotW * 2);
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.values != values ||
      old.churnValues != churnValues ||
      old.color != color ||
      old.labels != labels ||
      old.yearLabels != yearLabels ||
      old.hoveredIndex != hoveredIndex;
}

// ── Line chart widget ─────────────────────────────────────────────────────────

// _LineChartWidget: StatefulWidget con hover. Sin labels en cada punto —
// sólo muestra el último valor fijo y un tooltip flotante al hacer hover.
class _LineChartWidget extends StatefulWidget {
  final List<String> labels;
  final List<String?> yearLabels;
  final List<double> values;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;

  const _LineChartWidget({
    required this.labels,
    required this.yearLabels,
    required this.values,
    required this.color,
    this.integerValues = false,
    this.formatValue,
  });

  @override
  State<_LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<_LineChartWidget> {
  int? _hoveredIndex;

  String _fmt(double v) {
    if (widget.formatValue != null) return widget.formatValue!(v);
    return widget.integerValues ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  // Encuentra el índice del punto más cercano al X del mouse
  int? _indexAt(Offset local, Size size) {
    if (widget.values.isEmpty) return null;
    final n = widget.values.length;
    final stepX = n > 1 ? (size.width - 8) / (n - 1) : 0.0;
    double minDist = double.infinity;
    int? idx;
    for (int i = 0; i < n; i++) {
      final x = n > 1 ? 4.0 + i * stepX : size.width / 2;
      final d = (local.dx - x).abs();
      if (d < minDist) { minDist = d; idx = i; }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return MouseRegion(
        onHover: (e) {
          final idx = _indexAt(e.localPosition, size);
          if (idx != _hoveredIndex) setState(() => _hoveredIndex = idx);
        },
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTapDown: (e) {
            final idx = _indexAt(e.localPosition, size);
            setState(() => _hoveredIndex = _hoveredIndex == idx ? null : idx);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: _LineChartPainter(
                  labels: widget.labels,
                  yearLabels: widget.yearLabels,
                  values: widget.values,
                  color: widget.color,
                  integerValues: widget.integerValues,
                  formatValue: widget.formatValue,
                  hoveredIndex: _hoveredIndex,
                ),
                child: const SizedBox.expand(),
              ),
              if (_hoveredIndex != null)
                _LineTooltip(
                  index: _hoveredIndex!,
                  label: widget.labels[_hoveredIndex!],
                  yearLabel: widget.yearLabels.length > _hoveredIndex!
                      ? widget.yearLabels[_hoveredIndex!]
                      : null,
                  valueText: _fmt(widget.values[_hoveredIndex!]),
                  color: widget.color,
                  totalPoints: widget.values.length,
                  chartWidth: size.width,
                  chartHeight: size.height,
                  values: widget.values,
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _LineTooltip extends StatelessWidget {
  final int index;
  final String label;
  final String? yearLabel;
  final String valueText;
  final Color color;
  final int totalPoints;
  final double chartWidth;
  final double chartHeight;
  final List<double> values;

  const _LineTooltip({
    required this.index,
    required this.label,
    required this.yearLabel,
    required this.valueText,
    required this.color,
    required this.totalPoints,
    required this.chartWidth,
    required this.chartHeight,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    const quarterH = 13.0;
    const yearH = 12.0;
    const axisH = quarterH + yearH;
    const topPad = 16.0;
    final chartH = chartHeight - axisH - topPad;
    final maxVal = values.fold<double>(0, (m, v) => v > m ? v : m);

    final stepX = totalPoints > 1 ? (chartWidth - 8) / (totalPoints - 1) : 0.0;
    final px = totalPoints > 1 ? 4.0 + index * stepX : chartWidth / 2;
    final py = maxVal > 0 ? topPad + chartH * (1 - values[index] / maxVal) : topPad;

    const tooltipW = 96.0;
    const tooltipH = 52.0;
    final left = (px - tooltipW / 2).clamp(0.0, chartWidth - tooltipW);
    // Mostrar arriba del punto si hay espacio, abajo si no
    final top = (py - tooltipH - 10) < 0 ? py + 12 : py - tooltipH - 8;
    final fullLabel = yearLabel != null ? '$label · $yearLabel' : label;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: tooltipW,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fullLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.65))),
              const SizedBox(height: 3),
              Text(valueText,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<String> labels;
  final List<String?> yearLabels;
  final List<double> values;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;
  final int? hoveredIndex;

  const _LineChartPainter({
    required this.labels,
    required this.yearLabels,
    required this.values,
    required this.color,
    this.integerValues = false,
    this.formatValue,
    this.hoveredIndex,
  });

  String _fmt(double v) {
    if (formatValue != null) return formatValue!(v);
    return integerValues ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  void _drawCenteredText(Canvas canvas, String text, Offset center,
      TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || values.isEmpty) return;
    const quarterH = 13.0;
    const yearH = 12.0;
    const axisH = quarterH + yearH;
    const topPad = 16.0;
    final chartH = size.height - axisH - topPad;
    final maxVal = values.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxVal <= 0) return;

    final n = values.length;
    final stepX = n > 1 ? (size.width - 8) / (n - 1) : 0.0;

    final points = List.generate(n, (i) {
      final x = n > 1 ? 4.0 + i * stepX : size.width / 2;
      final y = topPad + chartH * (1 - values[i] / maxVal);
      return Offset(x, y);
    });

    // Gradient fill
    final fillPath = Path()..moveTo(points.first.dx, topPad + chartH);
    for (final p in points) { fillPath.lineTo(p.dx, p.dy); }
    fillPath..lineTo(points.last.dx, topPad + chartH)..close();
    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.01)],
          ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH))
          ..style = PaintingStyle.fill);

    // Smooth line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cp1 = Offset((points[i - 1].dx + points[i].dx) / 2, points[i - 1].dy);
      final cp2 = Offset((points[i - 1].dx + points[i].dx) / 2, points[i].dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = color..style = PaintingStyle.stroke
      ..strokeWidth = 2.0..strokeCap = StrokeCap.round);

    // Eje X: mostrar label solo cada Nth punto para no saturar
    // Siempre mostrar año cuando cambia; Q solo si hay espacio (n <= 8) o
    // si es el primer punto del año
    final quarterStyle = TextStyle(
        fontSize: 9, color: const Color(0xFF94A3B8), fontFamily: 'Inter');
    final yearStyle = TextStyle(
        fontSize: 8, color: const Color(0xFFCBD5E1),
        fontFamily: 'Inter', fontWeight: FontWeight.w600);
    final valueStyle = TextStyle(
        fontSize: 9, color: color, fontWeight: FontWeight.w600, fontFamily: 'Inter');

    // Umbral: mostrar Q label solo cuando hay espacio suficiente (slotX >= 18px)
    final showAllQ = stepX >= 18;

    for (int i = 0; i < n; i++) {
      final p = points[i];
      final isHovered = i == hoveredIndex;
      final isLast = i == n - 1;
      final isYearChange = i < yearLabels.length && yearLabels[i] != null;

      // Dot — más grande si está hovered
      final dotR = isHovered ? 4.5 : 2.5;
      canvas.drawCircle(p, dotR,
          Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(p, dotR, Paint()
        ..color = isHovered ? color : color.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHovered ? 2.5 : 1.5);

      // Valor: solo en el último punto (o si está hovered, lo maneja el tooltip)
      if (isLast) {
        _drawCenteredText(canvas, _fmt(values[i]),
            Offset(p.dx, p.dy - 13), valueStyle, 60);
      }

      // Q label: solo si cabe o es cambio de año
      if (showAllQ || isYearChange) {
        _drawCenteredText(canvas, labels[i],
            Offset(p.dx, size.height - axisH), quarterStyle, stepX.clamp(14, 50));
      }

      // Año: solo en cambio de año
      if (isYearChange) {
        _drawCenteredText(canvas, yearLabels[i]!,
            Offset(p.dx, size.height - yearH), yearStyle, 60);
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values || old.color != color ||
      old.labels != labels || old.yearLabels != yearLabels ||
      old.hoveredIndex != hoveredIndex;
}

// ── Unified document item for Documentación tab ────────────────────────────────

class _DocItem {
  final String tipoDoc;
  final Proyecto proyecto;
  final String descripcion;
  final DateTime? fecha;
  final String? labelFecha;
  final DateTime? fechaSecundaria;
  final String? labelFechaSecundaria;
  final List<String> urls;
  final Color color;

  const _DocItem({
    required this.tipoDoc,
    required this.proyecto,
    required this.descripcion,
    this.fecha,
    this.labelFecha,
    this.fechaSecundaria,
    this.labelFechaSecundaria,
    required this.urls,
    required this.color,
  });
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
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle + header — same style as bottom sheets
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 32, height: 3,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Text(widget.hint,
                          style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B))),
                    ),
                    if (widget.value != null)
                      TextButton(
                        onPressed: () => Navigator.pop(context, '\x00'),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: Text('Limpiar',
                            style: GoogleFonts.inter(
                                fontSize: 13, color: Colors.red.shade400)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                  ]),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
              ),
            ),
            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
            Divider(height: 1, color: Colors.grey.shade100),
            // Results list
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

