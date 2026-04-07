import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/detalle_proyecto_provider.dart';
import 'campo_editable.dart';

/// Sección "FECHAS LICITACIÓN" con auto-carga desde OCDS/API/CM.
///
/// - Se muestra siempre que el proyecto tenga idLicitacion o urlConvenioMarco.
/// - Al montar, si no hay datos externos, dispara cargarOcds() automáticamente.
/// - Cuando se encuentran fechas en el API que faltan en Firestore, ofrece
///   un botón "Sincronizar fechas" para guardarlas todas de una vez.
/// - Cada campo es individualmente editable vía CampoEditable.
class FechasLicitacionSection extends StatefulWidget {
  const FechasLicitacionSection({super.key});

  @override
  State<FechasLicitacionSection> createState() =>
      _FechasLicitacionSectionState();
}

class _FechasLicitacionSectionState extends State<FechasLicitacionSection> {
  bool _syncLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<DetalleProyectoProvider>();
      if (p.externalApiData == null && !p.cargandoExternalData) {
        p.cargarOcds();
      }
    });
  }

  /// Extrae fechas disponibles del externalApiData (OCDS o MP legacy).
  /// Retorna un Map con keys = nombre campo Firestore, value = String ISO o null.
  Map<String, String?> _extraerFechasApi(Map<String, dynamic> data) {
    // ── OCDS format ─────────────────────────────────────────────────────────
    final releases =
        (data['releases'] as List?)?.cast<Map<String, dynamic>>();
    if (releases != null && releases.isNotEmpty) {
      final tender =
          (releases.first['tender'] as Map<String, dynamic>?) ?? {};
      return {
        'fechaPublicacion': _str(
            tender['tenderPeriod']?['startDate'] ?? releases.first['date']),
        'fechaCierre': _str(tender['tenderPeriod']?['endDate']),
        'fechaConsultasInicio':
            _str(tender['enquiryPeriod']?['startDate']),
        'fechaConsultas': _str(tender['enquiryPeriod']?['endDate']),
        'fechaAdjudicacion': _str(tender['awardPeriod']?['startDate']),
        'fechaAdjudicacionFin': _str(tender['awardPeriod']?['endDate']),
      };
    }

    // ── MP legacy format ─────────────────────────────────────────────────────
    final listado =
        (data['Listado'] as List?)?.cast<Map<String, dynamic>>();
    if (listado != null && listado.isNotEmpty) {
      final fechas =
          (listado.first['Fechas'] as Map<String, dynamic>?) ?? {};
      return {
        'fechaPublicacion': _str(fechas['FechaPublicacion']),
        'fechaCierre': _str(fechas['FechaCierre']),
        'fechaConsultasInicio': _str(fechas['FechaInicio']),
        'fechaConsultas': _str(fechas['FechaFin']),
        'fechaAdjudicacion':
            _str(fechas['FechaEstimadaAdjudicacion']),
        'fechaAdjudicacionFin': null,
      };
    }

    // ── Convenio Marco ────────────────────────────────────────────────────────
    // CM devuelve datos planos; si hay fechas en el root las usamos
    return {
      'fechaPublicacion': _str(data['FechaPublicacion'] ?? data['fechaPublicacion']),
      'fechaCierre': _str(data['FechaCierre'] ?? data['fechaCierre']),
      'fechaConsultasInicio': null,
      'fechaConsultas': null,
      'fechaAdjudicacion': null,
      'fechaAdjudicacionFin': null,
    };
  }

  String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// ¿Hay al menos una fecha en apiDates que no esté en Firestore?
  bool _haySincronizables(
      Map<String, String?> apiDates, DetalleProyectoProvider p) {
    final proyecto = p.proyecto;
    final firestoreDates = {
      'fechaPublicacion': proyecto.fechaPublicacion,
      'fechaCierre': proyecto.fechaCierre,
      'fechaConsultasInicio': proyecto.fechaConsultasInicio,
      'fechaConsultas': proyecto.fechaConsultas,
      'fechaAdjudicacion': proyecto.fechaAdjudicacion,
      'fechaAdjudicacionFin': proyecto.fechaAdjudicacionFin,
    };
    return apiDates.entries.any(
      (e) => e.value != null && firestoreDates[e.key] == null,
    );
  }

  Future<void> _sincronizar(
      Map<String, String?> apiDates, DetalleProyectoProvider p) async {
    setState(() => _syncLoading = true);
    final proyecto = p.proyecto;
    final firestoreDates = {
      'fechaPublicacion': proyecto.fechaPublicacion,
      'fechaCierre': proyecto.fechaCierre,
      'fechaConsultasInicio': proyecto.fechaConsultasInicio,
      'fechaConsultas': proyecto.fechaConsultas,
      'fechaAdjudicacion': proyecto.fechaAdjudicacion,
      'fechaAdjudicacionFin': proyecto.fechaAdjudicacionFin,
    };
    final labels = {
      'fechaPublicacion': 'Fecha Publicación',
      'fechaCierre': 'Fecha Cierre',
      'fechaConsultasInicio': 'Inicio Consultas',
      'fechaConsultas': 'Cierre Consultas',
      'fechaAdjudicacion': 'Fecha Adjudicación',
      'fechaAdjudicacionFin': 'Fin Adjudicación',
    };

    for (final entry in apiDates.entries) {
      if (entry.value != null && firestoreDates[entry.key] == null) {
        await p.editField(entry.key, entry.value, labels[entry.key]!);
      }
    }
    // Marcar origen como 'ocds' o 'mp' según la fuente
    if (p.proyecto.origenFechas == null) {
      final data = p.externalApiData!;
      final origen = data.containsKey('releases')
          ? 'ocds'
          : data.containsKey('Listado')
              ? 'mp'
              : 'ocds';
      await p.editField('origenFechas', origen, 'Origen Fechas');
    }
    if (mounted) setState(() => _syncLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, p, _) {
        final proyecto = p.proyecto;

        // Solo mostrar si hay licitación o CM
        final tieneSource = proyecto.idLicitacion != null ||
            proyecto.urlConvenioMarco != null;
        if (!tieneSource) return const SizedBox.shrink();

        Map<String, String?>? apiDates;
        bool haySincronizables = false;

        if (p.externalApiData != null) {
          apiDates = _extraerFechasApi(p.externalApiData!);
          haySincronizables = _haySincronizables(apiDates, p);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Row(
                children: [
                  Text(
                    'FECHAS LICITACIÓN',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (proyecto.origenFechas != null) ...[
                    const SizedBox(width: 8),
                    _OrigenBadge(origen: proyecto.origenFechas!),
                  ],
                  const Spacer(),
                  // Botón sincronizar
                  if (p.cargandoExternalData)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (haySincronizables && !_syncLoading)
                    _SyncButton(
                      onTap: () => _sincronizar(apiDates!, p),
                    )
                  else if (_syncLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (p.externalApiData == null)
                    GestureDetector(
                      onTap: () => p.cargarOcds(forceRefresh: true),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              size: 13, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            'Cargar',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            // ── Campo editables ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _DateField(
                    label: 'PUBLICACIÓN',
                    firestoreVal:
                        p.fmtDateStr(proyecto.fechaPublicacion?.toIso8601String()),
                    apiVal: apiDates?['fechaPublicacion'],
                    campoDb: 'fechaPublicacion',
                    onSave: (v) =>
                        p.editField('fechaPublicacion', v, 'Fecha Publicación'),
                  ),
                  const Divider(height: 1, indent: 16),
                  _DateField(
                    label: 'CIERRE RECEPCIÓN',
                    firestoreVal:
                        p.fmtDateStr(proyecto.fechaCierre?.toIso8601String()),
                    apiVal: apiDates?['fechaCierre'],
                    campoDb: 'fechaCierre',
                    onSave: (v) =>
                        p.editField('fechaCierre', v, 'Fecha Cierre'),
                  ),
                  const Divider(height: 1, indent: 16),
                  _DateField(
                    label: 'INICIO CONSULTAS',
                    firestoreVal: p.fmtDateStr(
                        proyecto.fechaConsultasInicio?.toIso8601String()),
                    apiVal: apiDates?['fechaConsultasInicio'],
                    campoDb: 'fechaConsultasInicio',
                    onSave: (v) =>
                        p.editField('fechaConsultasInicio', v, 'Inicio Consultas'),
                  ),
                  const Divider(height: 1, indent: 16),
                  _DateField(
                    label: 'CIERRE CONSULTAS',
                    firestoreVal:
                        p.fmtDateStr(proyecto.fechaConsultas?.toIso8601String()),
                    apiVal: apiDates?['fechaConsultas'],
                    campoDb: 'fechaConsultas',
                    onSave: (v) =>
                        p.editField('fechaConsultas', v, 'Cierre Consultas'),
                  ),
                  const Divider(height: 1, indent: 16),
                  _DateField(
                    label: 'ADJUDICACIÓN',
                    firestoreVal:
                        p.fmtDateStr(proyecto.fechaAdjudicacion?.toIso8601String()),
                    apiVal: apiDates?['fechaAdjudicacion'],
                    campoDb: 'fechaAdjudicacion',
                    onSave: (v) =>
                        p.editField('fechaAdjudicacion', v, 'Fecha Adjudicación'),
                  ),
                  const Divider(height: 1, indent: 16),
                  _DateField(
                    label: 'FIN ADJUDICACIÓN',
                    firestoreVal: p.fmtDateStr(
                        proyecto.fechaAdjudicacionFin?.toIso8601String()),
                    apiVal: apiDates?['fechaAdjudicacionFin'],
                    campoDb: 'fechaAdjudicacionFin',
                    onSave: (v) => p.editField(
                        'fechaAdjudicacionFin', v, 'Fin Adjudicación'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── _DateField ────────────────────────────────────────────────────────────────

/// Campo de fecha editable. Si tiene valor de API pero no de Firestore,
/// muestra un chip "API" en azul indicando que hay una fecha disponible para aplicar.
class _DateField extends StatelessWidget {
  final String label;
  final String? firestoreVal; // ya formateado para display
  final String? apiVal;       // valor crudo del API (ISO string)
  final String campoDb;
  final Function(dynamic) onSave;

  const _DateField({
    required this.label,
    required this.firestoreVal,
    required this.apiVal,
    required this.campoDb,
    required this.onSave,
  });

  bool get _isEmpty =>
      firestoreVal == null ||
      firestoreVal!.isEmpty ||
      firestoreVal == '—';

  bool get _tieneApiVal => apiVal != null && apiVal!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        CampoEditable(
          label: label,
          valor: firestoreVal ?? '',
          campoDb: campoDb,
          isDate: true,
          onSave: onSave,
        ),
        // Badge "API" cuando hay valor disponible pero el campo está vacío
        if (_isEmpty && _tieneApiVal)
          Positioned(
            right: 16,
            child: GestureDetector(
              onTap: () => onSave(apiVal!),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_rounded,
                        size: 10, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 3),
                    Text(
                      'Aplicar',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── _SyncButton ───────────────────────────────────────────────────────────────

class _SyncButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SyncButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_rounded,
                size: 11, color: Color(0xFF3B82F6)),
            const SizedBox(width: 4),
            Text(
              'Sincronizar fechas',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _OrigenBadge ──────────────────────────────────────────────────────────────

class _OrigenBadge extends StatelessWidget {
  final String origen;
  const _OrigenBadge({required this.origen});

  @override
  Widget build(BuildContext context) {
    final isOcds = origen == 'ocds';
    final isMp = origen == 'mp';
    final color = isOcds
        ? const Color(0xFF2563EB)
        : isMp
            ? const Color(0xFF059669)
            : Colors.grey.shade500;
    final label = isOcds
        ? 'OCDS'
        : isMp
            ? 'MP API'
            : origen.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_rounded, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
