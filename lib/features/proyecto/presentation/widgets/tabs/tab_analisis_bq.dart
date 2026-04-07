import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:myapp/widgets/shared/skeleton_loader.dart';
import 'package:myapp/widgets/shared/async_builder.dart';
import '../../../../../core/theme/app_colors.dart';

class TabAnalisisBq extends StatelessWidget {
  const TabAnalisisBq({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final hasData = provider.competidores.isNotEmpty ||
                        provider.ganadorOcs.isNotEmpty ||
                        provider.predicciones.isNotEmpty;

        return AsyncBuilder(
          loading: provider.analisisCargando,
          error: provider.analisisError,
          hasData: hasData,
          skeleton: _buildAnalisisSkeleton(),
          onRetry: () => provider.cargarAnalisisBq(forceRefresh: true),
          emptyMessage: 'Sin datos disponibles para esta licitación en BigQuery.',
          builder: (context) => LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 600;

              final competidoresCard = provider.competidores.isNotEmpty
                  ? _AnalisisCompetidoresCard(
                      competidores: provider.competidores,
                      rutGanador: provider.rutGanador,
                      ganadorOcs: provider.ganadorOcs,
                      proyectoTieneOC: provider.proyecto.idsOrdenesCompra.isNotEmpty,
                    )
                  : null;
              final ganadorCard = provider.ganadorOcs.isNotEmpty
                  ? _AnalisisGanadorCard(
                      ganadorOcs: provider.ganadorOcs,
                      historialOcs: provider.historialGanador,
                      permanencia: provider.permanenciaGanador,
                      nombreGanador: provider.nombreGanador,
                      rutGanador: provider.rutGanador,
                      rutOrganismo: provider.rutOrganismo,
                      proyectoTieneOC: provider.proyecto.idsOrdenesCompra.isNotEmpty,
                    )
                  : null;
              final prediccionCard = provider.predicciones.isNotEmpty
                  ? _AnalisisPrediccionCard(
                      predicciones: provider.predicciones,
                      rutOrganismo: provider.rutOrganismo,
                    )
                  : null;

              final cards = [competidoresCard, ganadorCard, prediccionCard]
                  .whereType<Widget>()
                  .toList();

              Widget content;
              if (!twoCol || cards.length < 2) {
                content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: cards
                      .map((c) => Padding(padding: const EdgeInsets.only(bottom: 14), child: c))
                      .toList(),
                );
              } else {
                // 2-column grid for tablet+
                final rows = <Widget>[];
                for (int i = 0; i < cards.length; i += 2) {
                  rows.add(Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[i]),
                      if (i + 1 < cards.length) ...[
                        const SizedBox(width: 14),
                        Expanded(child: cards[i + 1]),
                      ] else
                        const Expanded(child: SizedBox()),
                    ],
                  ));
                  if (i + 2 < cards.length) rows.add(const SizedBox(height: 14));
                }
                content = Column(children: rows);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => provider.cargarAnalisisBq(forceRefresh: true),
                      icon: const Icon(Icons.refresh, size: 15),
                      label: Text('Actualizar análisis', style: GoogleFonts.inter(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAnalisisSkeleton() {
    Widget card({required Color accent, required int rows, double? barWidth}) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 24, height: 24, decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6))),
              const SizedBox(width: 10),
              SkeletonBox(width: 140, height: 12, radius: 4),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(rows, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SkeletonBox(width: 90, height: 10, radius: 4),
                const SizedBox(width: 12),
                SkeletonBox(width: barWidth ?? (140 - i * 12), height: 10, radius: 4),
              ],
            ),
          )),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        card(accent: AppColors.violet, rows: 5, barWidth: null), // Competidores
        card(accent: AppColors.primaryMuted, rows: 3, barWidth: 160),  // Ganador
        card(accent: AppColors.success, rows: 3, barWidth: 120),  // Prediccion
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AnalisisCompetidoresCard extends StatelessWidget {
  final List<Map<String, dynamic>> competidores;
  final String? rutGanador;
  final List<Map<String, dynamic>> ganadorOcs;
  final bool proyectoTieneOC;

  const _AnalisisCompetidoresCard({
    required this.competidores,
    required this.rutGanador,
    required this.ganadorOcs,
    required this.proyectoTieneOC,
  });

  @override
  Widget build(BuildContext context) {
    // Basic implementation mirroring original UI
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Competidores (${competidores.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // ... list of competidores
          ],
        ),
      ),
    );
  }
}

class _AnalisisGanadorCard extends StatelessWidget {
  final List<Map<String, dynamic>> ganadorOcs;
  final List<Map<String, dynamic>> historialOcs;
  final String? permanencia;
  final String? nombreGanador;
  final String? rutGanador;
  final String? rutOrganismo;
  final bool proyectoTieneOC;

  const _AnalisisGanadorCard({
    required this.ganadorOcs,
    required this.historialOcs,
    required this.permanencia,
    required this.nombreGanador,
    required this.rutGanador,
    required this.rutOrganismo,
    required this.proyectoTieneOC,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detalle del Ganador', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _infoRow('Proveedor', nombreGanador ?? '—'),
            _infoRow('Permanencia', permanencia ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label: ', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _AnalisisPrediccionCard extends StatelessWidget {
  final List<Map<String, dynamic>> predicciones;
  final String? rutOrganismo;

  const _AnalisisPrediccionCard({
    required this.predicciones,
    required this.rutOrganismo,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Predicción Próxima Compra', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // ... prediction logic
          ],
        ),
      ),
    );
  }
}
