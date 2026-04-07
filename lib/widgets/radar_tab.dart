import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/configuracion.dart';
import '../models/proyecto.dart';
import 'charts/facturacion_chart_card.dart';
import 'charts/clientes_chart_card.dart';
import 'shared/skeleton_loader.dart';
import '../core/theme/app_colors.dart';

// ── RADAR: KPI Row ─────────────────────────────────────────────────────────────────

class RadarKpiRow extends StatelessWidget {
  final int ganados;
  final int perdidos;
  final int enCurso;
  final double winRate;
  final double montoGanado;
  final String Function(double) fmtMonto;
  final bool isMobile;

  const RadarKpiRow({
    super.key,
    required this.ganados,
    required this.perdidos,
    required this.enCurso,
    required this.winRate,
    required this.montoGanado,
    required this.fmtMonto,
    required this.isMobile,
  });

  static const _primary = AppColors.primary;

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white, //
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rateStr = winRate > 0 ? '${winRate.toStringAsFixed(0)}%' : '–';
    final cards = [
      _kpiCard(
        'Ganadas',
        '$ganados',
        AppColors.success,
        Icons.emoji_events_outlined,
      ),
      _kpiCard(
        'Perdidas',
        '$perdidos',
        AppColors.error,
        Icons.close_outlined,
      ),
      _kpiCard(
        'En curso',
        '$enCurso',
        AppColors.warning,
        Icons.pending_outlined,
      ),
      _kpiCard('Win rate', rateStr, _primary, Icons.track_changes_outlined),
      _kpiCard(
        'Monto ganado',
        fmtMonto(montoGanado),
        AppColors.primaryMuted,
        Icons.monetization_on_outlined,
      ),
    ];

    if (isMobile) {
      return SizedBox(
        height: 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(width: 160, child: cards[i]),
        ),
      );
    }

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

// ── RADAR: Tabla de Oportunidades ──────────────────────────────────────────────────

class RadarOportunidadesCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool cargando;
  final String? error;
  final VoidCallback onCargar;

  const RadarOportunidadesCard({
    super.key,
    required this.rows,
    required this.cargando,
    required this.error,
    required this.onCargar,
  });

  static const _primary = AppColors.primary;

  String _fmtMonto(dynamic v) {
    if (v == null) return '–';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14), //
          boxShadow: [ //
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column( //
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container( //
                  padding: const EdgeInsets.all(6), //
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.radar, size: 16, color: _primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Radar de Oportunidades',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (cargando)
                  const SizedBox() // Handled in body
                else if (rows.isEmpty)
                  TextButton.icon(
                    onPressed: onCargar,
                    icon: const Icon(Icons.download_outlined, size: 15),
                    label: Text(
                      'Cargar',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18, color: _primary),
                    tooltip: 'Actualizar',
                    onPressed: onCargar,
                  ),
              ],
            ),
          ),

          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Error: $error',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.red.shade400,
                ),
              ),
            )
          else if (cargando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: List.generate(5, (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 80, height: 10, radius: 4),
                            const SizedBox(height: 6),
                            SkeletonBox(height: 14, radius: 6),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SkeletonBox(height: 14, radius: 6),
                      ),
                      const SizedBox(width: 12),
                      SkeletonBox(width: 60, height: 14, radius: 6),
                    ],
                  ),
                )),
              ),
            )
          else if (rows.isEmpty && !cargando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text(
                'Toca "Cargar" para consultar las oportunidades detectadas.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            )
          else if (rows.isNotEmpty) ...[
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Institución / Título',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Ganador actual',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'Monto',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, i) {
                final r = rows[i];
                final alerta = r['alerta_comercial']?.toString() ?? '';
                final menciona = r['menciona_seguridad'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['institucion']?.toString() ?? '–',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r['titulo']?.toString() ?? '–',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (alerta.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: menciona
                                      ? const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.1)
                                      : const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  alerta,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: menciona
                                        ? AppColors.success
                                        : AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r['ganador_actual']?.toString() ?? '–',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          _fmtMonto(r['monto']),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ── Estado badge clickable ──────────────────────────────────────────────────────────

class ProjectStatusDisplay extends StatelessWidget {
  final Proyecto proyecto;
  final List<EstadoItem> cfgEstados;
  final bool showLabel;
  final void Function(Proyecto)? onTap;
  final MainAxisAlignment alignment;

  const ProjectStatusDisplay({
    super.key,
    required this.proyecto,
    required this.cfgEstados,
    this.showLabel = true, //
    this.onTap,
    this.alignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final estadoItem = cfgEstados.firstWhere(
      (e) => e.nombre == proyecto.estado,
      orElse: () => EstadoItem(nombre: proyecto.estado, color: '64748B'),
    );

    return GestureDetector(
      onTap: onTap != null ? () => onTap!(proyecto) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), //
        decoration: BoxDecoration( //
          color: estadoItem.colorValue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: onTap != null
              ? Border.all(
                  color: estadoItem.colorValue.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignment,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: estadoItem.colorValue,
                shape: BoxShape.circle,
              ),
            ),
            if (showLabel) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  proyecto.estado,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: estadoItem.colorValue,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 13,
                color: estadoItem.colorValue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── RadarTab orquestador ───────────────────────────────────────────────────────

class RadarTab extends StatelessWidget {
  final bool isMobile;
  final void Function(int year, int quarter, {bool onlyWithOC, bool onlyIngresos}) onGoToQuarterFiltered;
  final void Function(int year, int quarter) onGoToChurnQuarterFiltered;

  const RadarTab({
    super.key,
    required this.isMobile,
    required this.onGoToQuarterFiltered,
    required this.onGoToChurnQuarterFiltered,
  });

  static String _fmtMonto(double n) {
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProyectosProvider>();
    final proyectos = provider.proyectos;

    // KPIs calculados desde los proyectos
    final enCurso = proyectos.where((p) => p.estadoManual == 'En Evaluación').length;
    final ganados = proyectos
        .where((p) =>
            p.estado == EstadoProyecto.vigente ||
            p.estado == EstadoProyecto.xVencer ||
            p.estado == EstadoProyecto.finalizado)
        .length;
    final total = ganados + enCurso;
    final winRate = total > 0 ? ganados / total * 100.0 : 0.0;
    final montoActivo = proyectos
        .where((p) =>
            p.estado == EstadoProyecto.vigente ||
            p.estado == EstadoProyecto.xVencer)
        .fold<double>(0, (sum, p) => sum + (p.valorMensual ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadarKpiRow(
          ganados: ganados,
          perdidos: 0,
          enCurso: enCurso,
          winRate: winRate,
          montoGanado: montoActivo,
          fmtMonto: _fmtMonto,
          isMobile: isMobile,
        ),
        const SizedBox(height: 24),
        _ChartRow(
          proyectos: proyectos,
          isMobile: isMobile,
          onQuarterTap: onGoToQuarterFiltered,
          onChurnTap: onGoToChurnQuarterFiltered,
        ),
        const SizedBox(height: 24),
        RadarOportunidadesCard(
          rows: provider.radarOportunidades,
          cargando: provider.radarCargando,
          error: provider.radarError,
          onCargar: () => provider.cargarRadar(forceRefresh: true),
        ),
      ],
    );
  }
}

// ── Charts row ────────────────────────────────────────────────────────────────

class _ChartRow extends StatelessWidget {
  final List<Proyecto> proyectos;
  final bool isMobile;
  final void Function(int year, int quarter, {bool onlyWithOC, bool onlyIngresos})? onQuarterTap;
  final void Function(int year, int quarter)? onChurnTap;

  const _ChartRow({
    required this.proyectos,
    required this.isMobile,
    this.onQuarterTap,
    this.onChurnTap,
  });

  @override
  Widget build(BuildContext context) {
    const h = 240.0;
    final fact = SizedBox(
      height: h,
      child: FacturacionChartCard(
        proyectos: proyectos,
        onQuarterTap: onQuarterTap,
      ),
    );
    final cli = SizedBox(
      height: h,
      child: ClientesChartCard(
        proyectos: proyectos,
        onQuarterTap: onQuarterTap,
        onChurnQuarterTap: onChurnTap,
      ),
    );

    if (isMobile) {
      return Column(children: [fact, const SizedBox(height: 12), cli]);
    }
    return Row(children: [
      Expanded(child: fact),
      const SizedBox(width: 14),
      Expanded(child: cli),
    ]);
  }
}
