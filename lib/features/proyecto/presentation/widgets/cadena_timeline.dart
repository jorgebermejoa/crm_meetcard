import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../providers/detalle_proyecto_provider.dart';

class CadenaTimeline extends StatelessWidget {
  const CadenaTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DetalleProyectoProvider>();
    final cadena = provider.cadena;
    final sucesores = provider.sucesores;
    final proyectoActual = provider.proyecto;

    if (cadena.length <= 1 && sucesores.isEmpty) return const SizedBox();

    final totalRenovaciones = (cadena.isNotEmpty ? cadena.length - 1 : 0) + sucesores.length;
    final renovLabel = '$totalRenovaciones renovación${totalRenovaciones != 1 ? 'es' : ''}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LÍNEA DE TIEMPO',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).primaryColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                renovLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Antecesores
          ...cadena.asMap().entries.map((e) {
            final isLastAnc = e.key == cadena.length - 1;
            return _buildNodo(
              context,
              e.value,
              proyectoActual: proyectoActual,
              isLast: isLastAnc && sucesores.isEmpty,
              showLine: !isLastAnc || sucesores.isNotEmpty,
            );
          }),
          // Sucesores
          ...sucesores.asMap().entries.map((e) {
            final isLast = e.key == sucesores.length - 1;
            return _buildNodo(
              context,
              e.value,
              proyectoActual: proyectoActual,
              isLast: isLast,
              showLine: !isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNodo(
    BuildContext context,
    ProyectoEntity p, {
    required ProyectoEntity proyectoActual,
    required bool isLast,
    required bool showLine,
  }) {
    final esAqui = p.id == proyectoActual.id;
    final primaryColor = Theme.of(context).primaryColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: esAqui ? 12 : 8,
                  height: esAqui ? 12 : 8,
                  margin: EdgeInsets.only(top: esAqui ? 4 : 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: esAqui ? primaryColor : Colors.grey.shade300,
                    border: esAqui ? Border.all(color: primaryColor.withValues(alpha: 0.2), width: 3) : null,
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.institucion,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: esAqui ? FontWeight.w700 : FontWeight.w500,
                      color: esAqui ? const Color(0xFF1E293B) : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateRange(p),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade400,
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

  String _formatDateRange(ProyectoEntity p) {
    if (p.fechaInicio == null && p.fechaTermino == null) return 'Sin fechas';
    final start = p.fechaInicio != null ? p.fechaInicio!.year.toString() : '?';
    final end = p.fechaTermino != null ? p.fechaTermino!.year.toString() : 'Actual';
    return '$start - $end';
  }
}
