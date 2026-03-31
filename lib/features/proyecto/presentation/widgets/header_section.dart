import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../../../../core/utils/responsive_helper.dart';
import '../providers/detalle_proyecto_provider.dart';

class HeaderSection extends StatelessWidget {
  const HeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DetalleProyectoProvider>();
    final proyecto = provider.proyecto;
    final isMobile = ResponsiveHelper.isMobile(context);

    final titleText = Text(
      proyecto.institucion.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: isMobile ? 22 : 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: const Color(0xFF1E293B),
      ),
    );

    final subtitleText = [
      proyecto.modalidadCompra,
      if (proyecto.idLicitacion != null) 'ID: ${proyecto.idLicitacion}',
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile) ...[
          titleText,
          const SizedBox(height: 6),
          Text(
            subtitleText,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          _buildBadges(context, proyecto),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleText),
              const SizedBox(width: 12),
              _buildBadges(context, proyecto),
            ],
          ),
        if (!isMobile) ...[
          const SizedBox(height: 6),
          Text(
            subtitleText,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
        const SizedBox(height: 24),
        _buildStatRow(context, proyecto, isMobile, provider),
      ],
    );
  }

  Widget _buildBadges(BuildContext context, ProyectoEntity proyecto) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _badge(
          label: proyecto.calculatedStatus.toUpperCase(),
          color: _getEstadoColor(proyecto.calculatedStatus),
        ),
      ],
    );
  }

  Widget _badge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _getEstadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'vigente': return const Color(0xFF16A34A);
      case 'por vencer': return const Color(0xFFD97706);
      case 'finalizado': return const Color(0xFF64748B);
      default: return const Color(0xFF94A3B8);
    }
  }

  Widget _buildStatRow(BuildContext context, ProyectoEntity proyecto, bool isMobile, DetalleProyectoProvider provider) {
    final stats = [
      _StatItem(
        label: 'VALOR MENSUAL',
        value: proyecto.valorMensual != null ? '\$ ${provider.fmt(proyecto.valorMensual)}' : '—',
        icon: Icons.attach_money,
      ),
      _StatItem(
        label: 'VENCIMIENTO',
        value: _getVencimientoLabel(proyecto),
        icon: Icons.timer_outlined,
      ),
      if (proyecto.fechaPublicacion != null)
        _StatItem(
          label: 'PUBLICACIÓN',
          value: provider.fmtDateStr(proyecto.fechaPublicacion!.toIso8601String()),
          icon: Icons.publish,
        ),
      if (proyecto.fechaCierre != null)
        _StatItem(
          label: 'CIERRE',
          value: provider.fmtDateStr(proyecto.fechaCierre!.toIso8601String()),
          icon: Icons.event_available,
        ),
      if (proyecto.montoTotalOC != null && proyecto.montoTotalOC! > 0)
        _StatItem(
          label: 'TOTAL OC',
          value: '\$ ${provider.fmt(proyecto.montoTotalOC)}',
          icon: Icons.shopping_cart_outlined,
        ),
    ];

    if (isMobile) {
      return Column(
        children: stats.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _statCard(s),
        )).toList(),
      );
    }

    return Row(
      children: stats.map((s) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: s == stats.last ? 0 : 12),
          child: _statCard(s),
        ),
      )).toList(),
    );
  }

  Widget _statCard(_StatItem s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.value,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  String _getVencimientoLabel(ProyectoEntity p) {
    if (p.fechaTermino == null) return '—';
    final diff = p.fechaTermino!.difference(DateTime.now()).inDays;
    if (diff < 0) return 'Vencido';
    if (diff < 30) return '$diff días';
    return '${(diff / 30).floor()} meses';
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  _StatItem({required this.label, required this.value, required this.icon});
}
