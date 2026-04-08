import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../core/theme/app_colors.dart';
import 'shared/skeleton_loader.dart';

// ── Bottom sheet helper ────────────────────────────────────────────────────────

/// Muestra el detalle de un convenio marco como bottom sheet (mobile) o sidebar (desktop).
void mostrarDetalleConvenioMarcoSheet(
    BuildContext context, Map<String, dynamic> rawData) {
  final h = MediaQuery.of(context).size.height;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      height: h * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: DetalleConvenioMarcoSidebar(
            rawData: rawData,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PANEL DETALLE CONVENIO MARCO
// ══════════════════════════════════════════════════════════════════════════════

class DetalleConvenioMarcoSidebar extends StatefulWidget {
  final Map<String, dynamic> rawData;
  final VoidCallback onClose;

  const DetalleConvenioMarcoSidebar(
      {super.key, required this.rawData, required this.onClose});

  @override
  State<DetalleConvenioMarcoSidebar> createState() =>
      _DetalleConvenioMarcoSidebarState();
}

class _DetalleConvenioMarcoSidebarState extends State<DetalleConvenioMarcoSidebar>
    with SingleTickerProviderStateMixin {
  static const _cf =
      'https://us-central1-licitaciones-prod.cloudfunctions.net';
  static const _primary = AppColors.primary;
  static const _bg = AppColors.background;

  late TabController _tabController;
  bool _cargandoDetalles = false;
  Map<String, dynamic>? _detalles;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _detalles == null && !_cargandoDetalles) {
      _fetchDetalles();
    }
  }

  @override
  void didUpdateWidget(DetalleConvenioMarcoSidebar old) {
    super.didUpdateWidget(old);
    if (old.rawData['url'] != widget.rawData['url']) {
      setState(() {
        _detalles = null;
      });
      if (_tabController.index == 1) _fetchDetalles();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Obtiene detalles adicionales del convenio marco
  Future<void> _fetchDetalles() async {
    final url = widget.rawData['url']?.toString() ?? '';
    if (url.isEmpty) return;

    setState(() => _cargandoDetalles = true);
    try {
      final uri = Uri.parse(
        '$_cf/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(url)}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        setState(() => _detalles = data);
      }
    } catch (e) {
      debugPrint('Error fetching convenio marco details: $e');
    } finally {
      if (mounted) setState(() => _cargandoDetalles = false);
    }
  }

  void _abrirEnMercadoPublico() {
    final url = widget.rawData['url']?.toString();
    if (url != null && url.isNotEmpty) {
      web.window.open(url, '_blank');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    return Container(
      width: isMobile ? screenWidth : 520,
      color: _bg,
      child: Column(
        children: [
          _buildHeader(),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400),
              labelColor: _primary,
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: _primary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Información'),
                Tab(text: 'Calendario'),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _panelInformacion(),
                _panelCalendario(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final raw = widget.rawData;
    final titulo = raw['titulo']?.toString().isNotEmpty == true
        ? raw['titulo'].toString()
        : 'Detalle Convenio Marco';
    final comprador = raw['comprador']?.toString().isNotEmpty == true
        ? raw['comprador'].toString()
        : '';
    final estado = raw['estado']?.toString().isNotEmpty == true
        ? raw['estado'].toString()
        : 'Desconocido';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: AppColors.textMuted),
              ),
            ),
          ),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Estado badge
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      color: _estadoColor(estado).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estado,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _estadoColor(estado),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Abrir en Mercado Público button
                  InkWell(
                    onTap: _abrirEnMercadoPublico,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Abrir',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _primary)),
                          const SizedBox(width: 3),
                          const Icon(Icons.open_in_new,
                              size: 10, color: _primary),
                        ],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                // Título
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (comprador.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    comprador,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _estadoColor(String estado) {
    final lower = estado.toLowerCase();
    if (lower.contains('finalizada') || lower.contains('adjudicada')) {
      return AppColors.success;
    } else if (lower.contains('revocada') || lower.contains('desierta')) {
      return Colors.orange;
    } else if (lower.contains('desestimada')) {
      return Colors.red;
    } else if (lower.contains('evaluación') || lower.contains('abierta')) {
      return _primary;
    }
    return Colors.grey;
  }

  // ── Panel Información ──────────────────────────────────────────────────────

  Widget _panelInformacion() {
    final raw = widget.rawData;
    final campos = (raw['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final error = raw['fetchError']?.toString();

    if (error != null && error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Error al obtener detalles',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                error,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (campos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Sin información disponible',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Resumen superior
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _primary.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (raw['titulo']?.toString().isNotEmpty == true)
                  Text(
                    raw['titulo'].toString(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                if (raw['comprador']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Comprador: ${raw['comprador'].toString()}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textBody,
                    ),
                  ),
                ],
                if (raw['convenioMarco']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Convenio: ${raw['convenioMarco'].toString()}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textBody,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Campos en tarjetas
          ...campos.map((c) => _campoCarta(c)),
        ],
      ),
    );
  }

  Widget _campoCarta(Map<String, dynamic> campo) {
    final label = campo['label']?.toString() ?? 'Campo';
    final valor = campo['valor']?.toString() ?? '';

    if (valor.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              valor,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Panel Calendario ───────────────────────────────────────────────────────

  Widget _panelCalendario() {
    if (_cargandoDetalles) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 12),
              SizedBox(height: 10),
              SkeletonBox(width: 150, height: 14),
            ],
          ),
        ),
      );
    }

    final campos = (_detalles?['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Extraer fechas importantes
    final fechas = _extraerFechas(campos);

    if (fechas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Sin fechas disponibles',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final fechasList = fechas.entries.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calendario de Evaluación',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...fechasList.asMap().entries.map(
            (e) {
              final isLast = e.key == fechasList.length - 1;
              return _timelineItem(e.value, isLast);
            },
          ),
        ],
      ),
    );
  }

  Map<String, String> _extraerFechas(List<Map<String, dynamic>> campos) {
    final fechas = <String, String>{};
    for (final c in campos) {
      final label = c['label']?.toString().toLowerCase() ?? '';
      final valor = c['valor']?.toString() ?? '';
      if (valor.isEmpty) continue;

      // Prioridad: palabras clave en el label
      if (label.contains('inicio') && label.contains('publicac')) {
        fechas['Publicación'] = valor;
      } else if (label.contains('fin') && label.contains('publicac')) {
        fechas['Cierre de Publicación'] = valor;
      } else if (label.contains('inicio') && label.contains('evaluaci')) {
        fechas['Inicio Evaluación'] = valor;
      } else if (label.contains('fin') && label.contains('evaluaci')) {
        fechas['Fin Evaluación'] = valor;
      } else if (label.contains('plazo') && label.contains('evaluaci')) {
        fechas['Plazo Evaluación'] = valor;
      } else if (label.contains('plazo') && label.contains('publicaci')) {
        fechas['Plazo Publicación'] = valor;
      } else if (label.contains('vigencia') && label.contains('contratos')) {
        fechas['Vigencia Contrato'] = valor;
      } else if (label.contains('vigencia') && label.contains('cotizaci')) {
        fechas['Vigencia Cotización'] = valor;
      } else if (label.contains('plazo') && label.contains('preguntas')) {
        fechas['Plazo Preguntas'] = valor;
      }
    }
    return fechas;
  }

  Widget _timelineItem(MapEntry<String, String> item, bool isLast) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + line
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: _primary.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.key,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
