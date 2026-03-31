import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';

class TabAnalisisBq extends StatelessWidget {
  const TabAnalisisBq({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        if (provider.analisisCargando) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
            ),
          );
        }

        if (provider.analisisError != null) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Error al cargar análisis:',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade400),
                ),
                const SizedBox(height: 4),
                Text(
                  provider.analisisError!,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => provider.cargarAnalisisBq(forceRefresh: true),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        final hasData = provider.competidores.isNotEmpty || 
                        provider.ganadorOcs.isNotEmpty || 
                        provider.predicciones.isNotEmpty;

        if (!hasData) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Sin datos disponibles para esta licitación en BigQuery.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (provider.competidores.isNotEmpty)
              _AnalisisCompetidoresCard(
                competidores: provider.competidores,
                rutGanador: provider.rutGanador,
                ganadorOcs: provider.ganadorOcs,
                proyectoTieneOC: provider.proyecto.idsOrdenesCompra.isNotEmpty,
              ),
            const SizedBox(height: 14),
            if (provider.ganadorOcs.isNotEmpty)
              _AnalisisGanadorCard(
                ganadorOcs: provider.ganadorOcs,
                historialOcs: provider.historialGanador,
                permanencia: provider.permanenciaGanador,
                nombreGanador: provider.nombreGanador,
                rutGanador: provider.rutGanador,
                rutOrganismo: provider.rutOrganismo,
                proyectoTieneOC: provider.proyecto.idsOrdenesCompra.isNotEmpty,
              ),
            const SizedBox(height: 14),
            if (provider.predicciones.isNotEmpty)
              _AnalisisPrediccionCard(
                predicciones: provider.predicciones,
                rutOrganismo: provider.rutOrganismo,
              ),
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
