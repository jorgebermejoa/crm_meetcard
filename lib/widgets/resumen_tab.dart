import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/proyecto.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/proyecto_display_utils.dart';
import '../core/utils/string_utils.dart';
import 'kpi_cards.dart';
import 'kpi_carousel_mobile.dart';
import 'gantt_section.dart';
import 'shared/dev_tooltip.dart';

/// Tab "Resumen" de la vista de proyectos.
/// Recibe callbacks de navegación para que el widget padre controle
/// el TabController sin acoplar este widget a él.
class ResumenTab extends StatelessWidget {
  final bool isMobile;
  final void Function(String? estado) onGoToProyectosFiltrados;
  final void Function(String reclamo) onGoToReclamosFiltrados;
  final void Function(int dias) onGoToVencerFiltrados;
  final VoidCallback onShowExport;

  const ResumenTab({
    super.key,
    required this.isMobile,
    required this.onGoToProyectosFiltrados,
    required this.onGoToReclamosFiltrados,
    required this.onGoToVencerFiltrados,
    required this.onShowExport,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProyectosProvider>();
    final vigentes = provider.proyectos.where((p) => p.estado == EstadoProyecto.vigente).toList();
    final xVencer  = provider.proyectos.where((p) => p.estado == EstadoProyecto.xVencer).toList();
    final activos  = [...vigentes, ...xVencer];

    final reclamosPendientes = <({Proyecto proyecto, Reclamo reclamo})>[];
    int reclamosFinalizados = 0;
    for (final p in provider.proyectos) {
      for (final r in p.reclamos) {
        if (r.estado == 'Pendiente') {
          reclamosPendientes.add((proyecto: p, reclamo: r));
        } else if (r.fechaRespuesta != null || (r.descripcionRespuesta?.isNotEmpty == true)) {
          reclamosFinalizados++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KpiRow(
          activos: activos.length,
          proyectos: provider.proyectos,
          reclamosPend: reclamosPendientes.length,
          reclamosFinalizados: reclamosFinalizados,
          xVencer: xVencer.length,
          isMobile: isMobile,
          onGoToProyectosFiltrados: onGoToProyectosFiltrados,
          onGoToReclamosFiltrados: onGoToReclamosFiltrados,
          onGoToVencerFiltrados: onGoToVencerFiltrados,
          onShowExport: onShowExport,
          cargando: provider.cargando,
          onRefresh: () => provider.cargar(forceRefresh: true),
        ),
        if (reclamosPendientes.isNotEmpty) ...[
          const SizedBox(height: 24),
          DevTooltip(
            filePath: 'lib/widgets/resumen_tab.dart',
            description: 'Sección reclamos pendientes (_ReclamosPendientes)',
            child: _ReclamosPendientes(
              items: reclamosPendientes,
              isMobile: isMobile,
            ),
          ),
        ],
        const SizedBox(height: 24),
        DevTooltip(
          filePath: 'lib/widgets/gantt_section.dart',
          description: 'Sección Gantt — línea de tiempo de proyectos',
          child: GanttSection(isMobile: isMobile),
        ),
      ],
    );
  }
}



// ── KPI Row ───────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int activos;
  final List<Proyecto> proyectos;
  final int reclamosPend;
  final int reclamosFinalizados;
  final int xVencer;
  final bool isMobile;
  final void Function(String?) onGoToProyectosFiltrados;
  final void Function(String) onGoToReclamosFiltrados;
  final void Function(int) onGoToVencerFiltrados;
  final VoidCallback onShowExport;
  final bool cargando;
  final VoidCallback onRefresh;

  const _KpiRow({
    required this.activos,
    required this.proyectos,
    required this.reclamosPend,
    required this.reclamosFinalizados,
    required this.xVencer,
    required this.isMobile,
    required this.onGoToProyectosFiltrados,
    required this.onGoToReclamosFiltrados,
    required this.onGoToVencerFiltrados,
    required this.onShowExport,
    required this.cargando,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final kpiCards = [
      DevTooltip(filePath: 'lib/widgets/kpi_cards.dart', description: 'KPI — Total proyectos activos', child: ProyectosKpiCard(proyectos: proyectos, onNavigate: onGoToProyectosFiltrados)),
      DevTooltip(filePath: 'lib/widgets/kpi_cards.dart', description: 'KPI — Valor mensual total', child: ValorMensualCard(proyectos: proyectos, onNavigate: onGoToProyectosFiltrados)),
      DevTooltip(filePath: 'lib/widgets/kpi_cards.dart', description: 'KPI — Reclamos pendientes', child: ReclamosCard(pendientes: reclamosPend, finalizados: reclamosFinalizados, onNavigate: onGoToReclamosFiltrados)),
      DevTooltip(filePath: 'lib/widgets/kpi_cards.dart', description: 'KPI — Proyectos por vencer', child: XVencerKpiCard(proyectos: proyectos, onNavigate: onGoToVencerFiltrados)),
    ];

    Widget actionBadges() => Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ActionBadge(icon: Icons.file_download_outlined, tooltip: 'Exportar', onTap: onShowExport),
        const SizedBox(width: 6),
        _ActionBadge(icon: Icons.refresh, tooltip: 'Actualizar', loading: cargando, onTap: onRefresh),
      ],
    );

    final screenW = MediaQuery.of(context).size.width;

    if (screenW < 600) {
      return KpiCarouselMobile(kpiCards: kpiCards, chartCards: const [], actionBadges: actionBadges());
    }

    if (screenW < 900) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [Expanded(child: kpiCards[0]), const SizedBox(width: 14), Expanded(child: kpiCards[1])]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: kpiCards[2]), const SizedBox(width: 14), Expanded(child: kpiCards[3])]),
          const SizedBox(height: 8),
          actionBadges(),
        ],
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
        const SizedBox(height: 8),
        actionBadges(),
      ],
    );
  }
}

class _ActionBadge extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionBadge({required this.icon, required this.tooltip, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.textMuted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : Icon(icon, size: 14, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

// ── Reclamos Pendientes ───────────────────────────────────────────────────────

class _ReclamosPendientes extends StatelessWidget {
  final List<({Proyecto proyecto, Reclamo reclamo})> items;
  final bool isMobile;

  const _ReclamosPendientes({required this.items, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final Map<String, ({Proyecto proyecto, int count, DateTime? fecha})> byProject = {};
    for (final item in items) {
      final id = item.proyecto.id;
      final fecha = item.reclamo.fechaReclamo;
      if (byProject.containsKey(id)) {
        final prev = byProject[id]!;
        final earliest = (prev.fecha == null || (fecha != null && fecha.isBefore(prev.fecha!))) ? fecha : prev.fecha;
        byProject[id] = (proyecto: item.proyecto, count: prev.count + 1, fecha: earliest);
      } else {
        byProject[id] = (proyecto: item.proyecto, count: 1, fecha: fecha);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.errorSurface, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.errorDark),
              const SizedBox(width: 6),
              Text(
                '${items.length} RECLAMO${items.length > 1 ? 'S' : ''} PENDIENTE${items.length > 1 ? 'S' : ''}',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.errorDark, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...byProject.values.map((e) => _ReclamoPendienteCard(proyecto: e.proyecto, count: e.count, fechaIngreso: e.fecha)),
      ],
    );
  }
}

class _ReclamoPendienteCard extends StatelessWidget {
  final Proyecto proyecto;
  final int count;
  final DateTime? fechaIngreso;

  const _ReclamoPendienteCard({required this.proyecto, required this.count, this.fechaIngreso});

  @override
  Widget build(BuildContext context) {
    final fechaStr = fechaIngreso != null
        ? 'Ingresado el ${fechaIngreso!.day.toString().padLeft(2, '0')}/${fechaIngreso!.month.toString().padLeft(2, '0')}/${fechaIngreso!.year}'
        : null;

    return GestureDetector(
      onTap: () {
        final entity = proyecto.toEntity();
        final slug = modalidadSlug(proyecto.modalidadCompra);
        final cid = contractIdForUrl(proyecto.id, idLicitacion: proyecto.idLicitacion, idCotizacion: proyecto.idCotizacion, urlConvenioMarco: proyecto.urlConvenioMarco);
        context.go('/proyectos/$slug/$cid', extra: {'proyecto': entity, 'tab': 'Reclamos'});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Row(
          children: [
            const Icon(Icons.gavel_outlined, size: 15, color: AppColors.errorDark),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ProyectoDisplayUtils.cleanInst(proyecto.institucion),
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  if (fechaStr != null) ...[
                    const SizedBox(height: 2),
                    Text(fechaStr, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ],
              ),
            ),
            if (count > 1) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.errorSurface, borderRadius: BorderRadius.circular(12)),
                child: Text('$count', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.errorDark)),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }
}
