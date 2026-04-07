import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../../domain/entities/proyecto_entity.dart';
import '../../../../core/utils/responsive_helper.dart';
import '../../../../models/configuracion.dart';
import '../providers/detalle_proyecto_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/proyecto_display_utils.dart';

class HeaderSection extends StatelessWidget {
  const HeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DetalleProyectoProvider>();
    final proyecto = provider.proyecto;
    final isMobile = ResponsiveHelper.isMobile(context);

    final titleText = Text(
      ProyectoDisplayUtils.cleanInst(proyecto.institucion).toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: isMobile ? 22 : 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
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
    final provider = context.read<DetalleProyectoProvider>();
    final estado = proyecto.calculatedStatus;
    final cfgEstados = provider.cfgEstados;
    final item = cfgEstados.firstWhere(
      (e) => e.nombre == estado,
      orElse: () => EstadoItem(nombre: estado, color: '94A3B8'),
    );
    final color = item.colorValue;

    final estadoBadge = GestureDetector(
      onTap: () => _showEstadoPicker(context, proyecto, cfgEstados, provider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              estado.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: color),
          ],
        ),
      ),
    );

    // Build "Ver Ficha" URL: LP uses MP URL, CM uses urlFicha
    final esConvenioMarco = proyecto.modalidadCompra
        .toLowerCase()
        .contains('convenio marco');
    String? fichaUrl;
    if (!esConvenioMarco && proyecto.idLicitacion != null) {
      fichaUrl =
          'http://www.mercadopublico.cl/Procurement/Modules/RFB/DetailsAcquisition.aspx?idlicitacion=${proyecto.idLicitacion}';
    } else if (esConvenioMarco) {
      if (proyecto.urlFicha != null && proyecto.urlFicha!.isNotEmpty) {
        fichaUrl = proyecto.urlFicha;
      } else if (proyecto.urlConvenioMarco != null && proyecto.urlConvenioMarco!.isNotEmpty) {
        fichaUrl = proyecto.urlConvenioMarco;
      }
    }

    final fichaBadge = fichaUrl != null
        ? GestureDetector(
            onTap: () => web.window.open(fichaUrl!, '_blank'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text(
                    'VER FICHA',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;

    if (fichaBadge == null) return estadoBadge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [estadoBadge, const SizedBox(width: 8), fichaBadge],
    );
  }

  Future<void> _showEstadoPicker(
    BuildContext context,
    ProyectoEntity proyecto,
    List<EstadoItem> cfgEstados,
    DetalleProyectoProvider provider,
  ) async {
    final nuevoEstado = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalleEstadoPickerSheet(
        estadoActual: proyecto.calculatedStatus,
        cfgEstados: cfgEstados,
      ),
    );
    if (nuevoEstado == null) return;
    final valor = nuevoEstado.isEmpty ? null : nuevoEstado;
    await provider.updateEstadoManual(valor);
  }

  Widget _buildStatRow(BuildContext context, ProyectoEntity proyecto, bool isMobile, DetalleProyectoProvider provider) {
    final stats = [
      _StatItem(
        label: 'VALOR MENSUAL',
        value: proyecto.valorMensualEfectivo != null
            ? '\$ ${provider.fmt(proyecto.valorMensualEfectivo)}'
            : '—',
        icon: Icons.attach_money,
        hasAumento: proyecto.proyectoContinuacionIds.isEmpty &&
            proyecto.aumentos.any((a) => a.valorMensual != null),
      ),
      _StatItem(
        label: 'VENCIMIENTO',
        value: _getVencimientoLabel(proyecto),
        icon: Icons.timer_outlined,
        hasAumento: proyecto.proyectoContinuacionIds.isEmpty &&
            proyecto.aumentos.isNotEmpty,
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
      // 2-column grid for mobile
      final rows = <Widget>[];
      for (int i = 0; i < stats.length; i += 2) {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _statCard(stats[i])),
            if (i + 1 < stats.length) ...[
              const SizedBox(width: 12),
              Expanded(child: _statCard(stats[i + 1])),
            ] else
              const Expanded(child: SizedBox()),
          ],
        ));
        if (i + 2 < stats.length) rows.add(const SizedBox(height: 12));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
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
        border: Border.all(
          color: s.hasAumento ? const Color(0xFFF59E0B).withValues(alpha: 0.35) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                s.label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              if (s.hasAumento) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'AUMENTADO',
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF59E0B),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.value,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _getVencimientoLabel(ProyectoEntity p) {
    final termino = p.fechaTerminoEfectiva;
    if (termino == null) return '—';
    final now = DateTime.now();
    final diff = termino.difference(now).inDays;
    if (diff < 0) return 'Vencido';
    if (diff < 30) return '$diff día${diff == 1 ? '' : 's'}';
    // Count calendar months precisely
    int months = (termino.year - now.year) * 12 + (termino.month - now.month);
    if (termino.day < now.day) months--;
    if (months < 0) months = 0;
    if (months < 24) return '$months mes${months == 1 ? '' : 'es'}';
    final years = months ~/ 12;
    final remMonths = months % 12;
    if (remMonths == 0) return '$years año${years == 1 ? '' : 's'}';
    return '$years año${years == 1 ? '' : 's'} $remMonths mes${remMonths == 1 ? '' : 'es'}';
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final bool hasAumento;
  _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    this.hasAumento = false,
  });
}

class _DetalleEstadoPickerSheet extends StatelessWidget {
  final String estadoActual;
  final List<EstadoItem> cfgEstados;

  const _DetalleEstadoPickerSheet({
    required this.estadoActual,
    required this.cfgEstados,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Cambiar estado',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...cfgEstados.map((e) {
            final isSelected = e.nombre == estadoActual;
            return InkWell(
              onTap: () => Navigator.pop(context, e.nombre),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: e.colorValue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        e.nombre,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            );
          }),
          const Divider(height: 1),
          InkWell(
            onTap: () => Navigator.pop(context, ''),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Automático (según fechas del contrato)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  if (estadoActual.isEmpty)
                    const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
