import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'licitaciones_table.dart';
import 'detalle_licitacion.dart';

class CategoriaResultadosView extends StatefulWidget {
  final String prefix;
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
  static const _primaryColor = Color(0xFF1E1B6B);

  List<LicitacionUI> _licitaciones = [];
  bool _cargando = false;
  int _paginaActual = 0;
  final Map<int, String?> _cursores = {0: null};
  bool _hayMas = true;
  Map<String, dynamic>? _seleccionada;

  // Filters
  bool _soloAbiertas = true;
  DateTimeRange? _rangoPublicacion;
  DateTimeRange? _rangoCierre;

  @override
  void initState() {
    super.initState();
    _cargarPagina(0);
  }

  Future<void> _cargarPagina(int pagina) async {
    if (_cargando) return;
    final cursor = _cursores[pagina];
    setState(() => _cargando = true);
    try {
      final uri = Uri.parse(
        'https://us-central1-licitaciones-prod.cloudfunctions.net/obtenerLicitacionesPorCategoria'
        '?prefix=${Uri.encodeComponent(widget.prefix)}&limit=20'
        '${cursor != null ? '&cursor=${Uri.encodeComponent(cursor)}' : ''}',
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final List<dynamic> items = body['resultados'] ?? [];
        final String? next = body['nextCursor'];
        setState(() {
          _paginaActual = pagina;
          _licitaciones = items.map((item) {
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
          if (next != null) {
            _cursores[pagina + 1] = next;
            _hayMas = true;
          } else {
            _hayMas = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Error cargando categoría: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<LicitacionUI> get _filtradas {
    return _licitaciones.where((l) {
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
    final abiertas = _licitaciones.where((l) => l.esVigente).length;
    final cerradas = _licitaciones.length - abiertas;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.nombre,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('${_fmt(widget.total)} licitaciones en la base de datos',
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
                      // ── Filter row ────────────────────────────────────────
                      _buildFilterRow(abiertas, cerradas, isMobile),
                      const SizedBox(height: 16),
                      // ── Results ───────────────────────────────────────────
                      if (_cargando && _licitaciones.isEmpty)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.only(top: 60),
                                child: CircularProgressIndicator()))
                      else if (!_cargando && _licitaciones.isEmpty)
                        _buildEmptyState()
                      else if (filtradas.isEmpty)
                        _buildNoMatchState()
                      else
                        LicitacionesTable(
                          licitaciones: filtradas,
                          selected: isMobile ? null : _seleccionada,
                          onSelected: (data) {
                            if (isMobile) {
                              mostrarDetalleLicitacionSheet(context, data);
                            } else {
                              setState(() => _seleccionada = data);
                            }
                          },
                        ),
                      // ── Pagination ────────────────────────────────────────
                      if (_licitaciones.isNotEmpty && !_cargando)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _pageBtn(Icons.chevron_left, _paginaActual > 0,
                                  () => _cargarPagina(_paginaActual - 1)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text('Página ${_paginaActual + 1}',
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: Colors.grey.shade600)),
                              ),
                              _pageBtn(Icons.chevron_right, _hayMas,
                                  () => _cargarPagina(_paginaActual + 1)),
                            ],
                          ),
                        )
                      else if (_cargando && _licitaciones.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))),
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
      onTap: () => setState(() => _soloAbiertas = !_soloAbiertas),
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
                      : const Color(0xFF10B981),
                  shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            _soloAbiertas
                ? 'Solo abiertas ($abiertas)'
                : 'Todas (${_licitaciones.length})',
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
                  if (esPublicacion) {
                    _rangoPublicacion = null;
                  } else {
                    _rangoCierre = null;
                  }
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
