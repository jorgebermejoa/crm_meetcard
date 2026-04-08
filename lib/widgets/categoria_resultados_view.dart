import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'shared/skeleton_loader.dart';

import 'licitaciones_table.dart';
import 'detalle_licitacion.dart';
import 'detalle_convenio_marco.dart';
import '../core/theme/app_colors.dart';

// ── Skeleton shimmer ──────────────────────────────────────────────────────────

class CategoriaResultadosView extends StatefulWidget {
  final String prefix;          // uno o varios separados por coma: "43,81"
  final String nombre;
  final int total;

  const CategoriaResultadosView({
    super.key,
    required this.prefix,
    required this.nombre,
    required this.total,
  });

  @override
  State<CategoriaResultadosView> createState() => _CategoriaResultadosViewState();
}

class _CategoriaResultadosViewState extends State<CategoriaResultadosView> {
  static const _primaryColor = AppColors.primary;
  static const _pageSize = 20;

  List<LicitacionUI> _todas = [];
  bool _cargando = false;
  int _clientPagina = 0;
  Map<String, dynamic>? _seleccionada;

  // Filters
  bool _soloAbiertas = false;
  DateTimeRange? _rangoPublicacion;
  DateTimeRange? _rangoCierre;
  String _busqueda = '';
  final _searchCtrl = TextEditingController();
  bool _disparandoIngesta = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _dispararIngesta() async {
    if (_disparandoIngesta) return;
    setState(() => _disparandoIngesta = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
      final resp = await http
          .get(
            Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/dispararIngestaOCDS'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 560));
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ingesta completada. Recargando…',
                  style: GoogleFonts.inter(fontSize: 13)),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          _cargarTodo();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error ${resp.statusCode}',
                  style: GoogleFonts.inter(fontSize: 13)),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: GoogleFonts.inter(fontSize: 13)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _disparandoIngesta = false);
    }
  }

  Future<void> _cargarTodo() async {
    if (_cargando) return;
    setState(() { _cargando = true; _todas = []; });
    String? cursor;
    try {
      while (true) {
        final uri = Uri.parse(
          'https://us-central1-licitaciones-prod.cloudfunctions.net/obtenerLicitacionesPorCategoria'
          '?prefix=${Uri.encodeComponent(widget.prefix)}&limit=50'
          '${cursor != null ? '&cursor=${Uri.encodeComponent(cursor)}' : ''}',
        );
        final response = await http.get(uri);
        if (response.statusCode != 200) break;
        final body = json.decode(response.body);
        final List<dynamic> items = body['resultados'] ?? [];
        final String? next = body['nextCursor'];
        final nuevas = items.map((item) {
          final m = item as Map<String, dynamic>;
          return LicitacionUI(
            m['id']?.toString() ?? 'S/I',
            m['titulo']?.toString() ?? 'Sin título',
            m['descripcion']?.toString() ?? 'Sin descripción',
            m['fechaPublicacion']?.toString() ?? 'S/F',
            m['fechaCierre']?.toString() ?? 'S/F',
            rawData: m,
          );
        }).toList();
        if (mounted) setState(() => _todas.addAll(nuevas));
        if (next == null || next.isEmpty) break;
        cursor = next;
      }
    } catch (e) {
      debugPrint('Error cargando categoría: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<LicitacionUI> get _filtradas {
    final q = _busqueda.toLowerCase().trim();
    return _todas.where((l) {
      if (_soloAbiertas && !l.esVigente) return false;
      if (_rangoPublicacion != null) {
        final d = l.fechaPublicacionDate;
        if (d == null) return false;
        if (d.isBefore(_rangoPublicacion!.start)) return false;
        if (d.isAfter(_rangoPublicacion!.end.add(const Duration(days: 1)))) return false;
      }
      if (_rangoCierre != null) {
        final d = l.fechaCierreDate;
        if (d == null) return false;
        if (d.isBefore(_rangoCierre!.start)) return false;
        if (d.isAfter(_rangoCierre!.end.add(const Duration(days: 1)))) return false;
      }
      if (q.isNotEmpty) {
        final comprador = l.rawData['comprador']?.toString().toLowerCase() ?? '';
        if (!l.id.toLowerCase().contains(q) &&
            !l.titulo.toLowerCase().contains(q) &&
            !l.descripcion.toLowerCase().contains(q) &&
            !comprador.contains(q)) { return false; }
      }
      return true;
    }).toList();
  }


  Future<void> _seleccionarRango(bool esPublicacion) async {
    final initial = esPublicacion
        ? (_rangoPublicacion ?? DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now()))
        : (_rangoCierre ?? DateTimeRange(
            start: DateTime.now(),
            end: DateTime.now().add(const Duration(days: 30))));

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primaryColor,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (esPublicacion) {
          _rangoPublicacion = picked;
        } else {
          _rangoCierre = picked;
        }
      });
    }
  }

  String _fmtRango(DateTimeRange r) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().substring(2)}';
    return '${fmt(r.start)} – ${fmt(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    final filtradas = _filtradas;
    final abiertas = _todas.where((l) => l.esVigente).length;
    final cerradas = _todas.length - abiertas;
    final totalPages = filtradas.isEmpty ? 1 : (filtradas.length / _pageSize).ceil();
    final pageStart = _clientPagina * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtradas.length);
    final pageItems = filtradas.isEmpty ? <LicitacionUI>[] : filtradas.sublist(pageStart, pageEnd);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceAlt,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _disparandoIngesta
                ? const SizedBox(
                    width: 36, height: 36,
                    child: Center(child: SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))))
                : Tooltip(
                    message: 'Buscar nuevas licitaciones',
                    child: IconButton(
                      onPressed: _dispararIngesta,
                      icon: const Icon(Icons.cloud_download_outlined, size: 20),
                      color: _primaryColor,
                    ),
                  ),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.nombre,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
            _cargando && _todas.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: SkeletonBox(width: 160, height: 10),
                  )
                : Text(
                    _cargando
                        ? '${_fmt(_todas.length)} cargados…'
                        : '${_fmt(_todas.length)} licitaciones encontradas',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: _seleccionada == null ? 1 : 2,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 32, isMobile ? 12 : 24,
                  isMobile ? 16 : 32, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Search bar ────────────────────────────────────────
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() { _busqueda = v; _clientPagina = 0; }),
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Buscar por ID, título, organismo o descripción…',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                          suffixIcon: _busqueda.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                                  onPressed: () => setState(() { _busqueda = ''; _searchCtrl.clear(); _clientPagina = 0; }),
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _primaryColor, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ── Filter row ────────────────────────────────────────
                      _buildFilterRow(abiertas, cerradas, isMobile),
                      const SizedBox(height: 16),
                      // ── Results ───────────────────────────────────────────
                      if (_cargando && _todas.isEmpty)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.only(top: 60),
                                child: CircularProgressIndicator()))
                      else if (!_cargando && _todas.isEmpty)
                        _buildEmptyState()
                      else if (filtradas.isEmpty)
                        _buildNoMatchState()
                      else
                        LicitacionesTable(
                          licitaciones: pageItems,
                          selected: isMobile ? null : _seleccionada,
                          onSelected: (data) {
                            if (isMobile) {
                              // Detectar si es Convenio Marco o Licitación Pública
                              if (data['id']?.toString().contains('CM') == true ||
                                  data['convenioMarco'] != null) {
                                // Es Convenio Marco
                                mostrarDetalleConvenioMarcoSheet(context, data);
                              } else {
                                // Es Licitación Pública
                                mostrarDetalleLicitacionSheet(context, data);
                              }
                            } else {
                              setState(() => _seleccionada = data);
                            }
                          },
                        ),
                      // ── Skeleton (cargando más) ────────────────────────────
                      if (_cargando && _todas.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(children: List.generate(3, (_) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const SkeletonBox(width: 100, height: 10),
                                  const SkeletonBox(width: 52, height: 20, radius: 20),
                                ]),
                                const SizedBox(height: 12),
                                const SkeletonBox(width: double.infinity, height: 11),
                                const SizedBox(height: 6),
                                const SkeletonBox(width: 200, height: 11),
                                const SizedBox(height: 14),
                                Row(children: const [
                                  SkeletonBox(width: 80, height: 9),
                                  SizedBox(width: 16),
                                  SkeletonBox(width: 80, height: 9),
                                ]),
                              ]),
                            ),
                          ))),
                        ),
                      // ── Pagination ────────────────────────────────────────
                      if (filtradas.isNotEmpty && totalPages > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _pageBtn(Icons.chevron_left, _clientPagina > 0,
                                  () => setState(() => _clientPagina--)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text('Página ${_clientPagina + 1} de $totalPages',
                                    style: GoogleFonts.inter(
                                        fontSize: 13, color: Colors.grey.shade600)),
                              ),
                              _pageBtn(Icons.chevron_right,
                                  _clientPagina < totalPages - 1,
                                  () => setState(() => _clientPagina++)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_seleccionada != null && !isMobile)
            DetalleLicitacionSidebar(
              rawData: _seleccionada!,
              onClose: () => setState(() => _seleccionada = null),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(int abiertas, int cerradas, bool isMobile) {
    final hasDateFilter = _rangoPublicacion != null || _rangoCierre != null;

    final toggleAbiertas = GestureDetector(
      onTap: () => setState(() { _soloAbiertas = !_soloAbiertas; _clientPagina = 0; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _soloAbiertas ? _primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _soloAbiertas ? _primaryColor : Colors.grey.shade200),
          boxShadow: [
            if (_soloAbiertas)
              BoxShadow(
                  color: _primaryColor.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: _soloAbiertas
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.success,
                  shape: BoxShape.circle)),
          const SizedBox(width: 6),
          if (_cargando && _todas.isEmpty)
            const SkeletonBox(width: 60, height: 10)
          else
            Text(
              _soloAbiertas
                  ? 'Solo abiertas ($abiertas)'
                  : 'Todas (${_todas.length})',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _soloAbiertas ? Colors.white : Colors.grey.shade700),
            ),
        ]),
      ),
    );

    Widget dateFilterBtn(String label, DateTimeRange? range, bool esPublicacion) {
      final active = range != null;
      return GestureDetector(
        onTap: () => _seleccionarRango(esPublicacion),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? _primaryColor.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active
                    ? _primaryColor.withValues(alpha: 0.3)
                    : Colors.grey.shade200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.date_range_outlined,
                size: 13,
                color: active ? _primaryColor : Colors.grey.shade400),
            const SizedBox(width: 5),
            Text(
              active ? '$label: ${_fmtRango(range)}' : label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: active ? _primaryColor : Colors.grey.shade600),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() {
                  if (esPublicacion) { _rangoPublicacion = null; } else { _rangoCierre = null; }
                  _clientPagina = 0;
                }),
                child:
                    Icon(Icons.close, size: 12, color: _primaryColor),
              ),
            ],
          ]),
        ),
      );
    }

    final filters = [
      toggleAbiertas,
      const SizedBox(width: 8),
      dateFilterBtn('Publicadas', _rangoPublicacion, true),
      const SizedBox(width: 8),
      dateFilterBtn('Cierre', _rangoCierre, false),
      if (hasDateFilter) ...[
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() {
            _rangoPublicacion = null;
            _rangoCierre = null;
            _clientPagina = 0;
          }),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text('Limpiar',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.grey.shade500)),
          ),
        ),
      ],
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: filters),
    );
  }

  Widget _buildEmptyState() => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Sin resultados para esta categoría',
                style: GoogleFonts.inter(color: Colors.grey.shade400)),
          ]),
        ),
      );

  Widget _buildNoMatchState() => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.filter_alt_off_outlined,
                size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No hay licitaciones con los filtros aplicados',
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade400)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() {
                _soloAbiertas = false;
                _rangoPublicacion = null;
                _rangoCierre = null;
                _clientPagina = 0;
              }),
              child: Text('Limpiar filtros',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _primaryColor,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      );

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) =>
      IconButton(
        icon: Icon(icon, size: 20),
        onPressed: enabled ? onTap : null,
        color: _primaryColor,
        disabledColor: Colors.grey.shade300,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );

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
