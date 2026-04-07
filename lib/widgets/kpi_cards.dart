import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/proyecto.dart';
import 'shared/kpi_card_shell.dart';
import '../core/theme/app_colors.dart';

class ProyectosKpiCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(String? estado)? onNavigate;
  const ProyectosKpiCard({super.key, required this.proyectos, this.onNavigate});

  @override
  State<ProyectosKpiCard> createState() => _ProyectosKpiCardState();
}

class _ProyectosKpiCardState extends State<ProyectosKpiCard> {
  int _idx = 3; // default: Postulación

  static const _pages = [
    (
      label: 'Proyectos\nActivos',
      estado: null as String?,
      color: AppColors.primary,
      activos: true,
    ),
    (
      label: 'Proyectos\nVigentes',
      estado: EstadoProyecto.vigente,
      color: AppColors.success,
      activos: false,
    ),
    (
      label: 'Proyectos\nX Vencer',
      estado: EstadoProyecto.xVencer,
      color: AppColors.warning,
      activos: false,
    ),
    (
      label: 'Proyectos\nEn Evaluación',
      estado: 'En Evaluación',
      color: AppColors.indigo,
      activos: false,
    ),
    (
      label: 'Proyectos\nFinalizados',
      estado: EstadoProyecto.finalizado,
      color: AppColors.textMuted,
      activos: false,
    ),
    (
      label: 'Proyectos\nTotal',
      estado: null as String?,
      color: AppColors.primaryMuted,
      activos: false,
    ),
  ];

  int _count() {
    final page = _pages[_idx];
    if (page.activos) {
      return widget.proyectos
          .where(
            (p) =>
                p.estado == EstadoProyecto.vigente ||
                p.estado == EstadoProyecto.xVencer,
          )
          .length;
    }
    if (page.estado == null) return widget.proyectos.length;
    return widget.proyectos.where((p) => p.estado == page.estado).length;
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_idx];
    final count = _count();
    final color = page.color;

    return KpiCardShell(
      label: page.label,
      color: color,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.folder_open_outlined, size: 15, color: color),
      ),
      value: Text(
        count.toString(),
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
      ),
      pageCount: _pages.length,
      currentIndex: _idx,
      onSwipe: (forward) => setState(
        () => _idx = forward
            ? (_idx + 1) % _pages.length
            : (_idx - 1 + _pages.length) % _pages.length,
      ),
      onTap: widget.onNavigate == null
          ? null
          : () {
              final page = _pages[_idx];
              widget.onNavigate!(page.activos ? null : page.estado);
            },
    );
  }
}

class ReclamosCard extends StatefulWidget {
  final int pendientes;
  final int finalizados;
  final void Function(String)? onNavigate;
  const ReclamosCard({
    super.key,
    required this.pendientes,
    required this.finalizados,
    this.onNavigate,
  });

  @override
  State<ReclamosCard> createState() => _ReclamosCardState();
}

class _ReclamosCardState extends State<ReclamosCard> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final isPendientes = _idx == 0;
    final count = isPendientes ? widget.pendientes : widget.finalizados;
    final label = isPendientes
        ? 'Reclamos\nPendientes'
        : 'Reclamos\nFinalizados';
    final color = isPendientes
        ? (widget.pendientes > 0
              ? AppColors.errorDark
              : Colors.grey.shade400)
        : (widget.finalizados > 0
              ? AppColors.success
              : Colors.grey.shade400);
    final iconData = isPendientes
        ? Icons.gavel_outlined
        : Icons.check_circle_outline;

    return KpiCardShell(
      label: label,
      color: color,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(iconData, size: 15, color: color),
      ),
      value: Text(
        count.toString(),
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
      ),
      pageCount: 2,
      currentIndex: _idx,
      onSwipe: (_) => setState(() => _idx = _idx == 0 ? 1 : 0),
      onTap: widget.onNavigate != null
          ? () => widget.onNavigate!(isPendientes ? 'Pendiente' : 'Respondido')
          : null,
    );
  }
}

class XVencerKpiCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(int dias)? onNavigate;
  const XVencerKpiCard({super.key, required this.proyectos, this.onNavigate});

  @override
  State<XVencerKpiCard> createState() => _XVencerKpiCardState();
}

class _XVencerKpiCardState extends State<XVencerKpiCard> {
  int _idx = 1; // default: 3 meses

  static const _periodos = [
    (label: 'Por Vencer\n(30 días)', dias: 30),
    (label: 'Por Vencer\n(3 meses)', dias: 90),
    (label: 'Por Vencer\n(6 meses)', dias: 180),
    (label: 'Por Vencer\n(12 meses)', dias: 365),
  ];

  int _count(int dias) {
    final now = DateTime.now();
    final limite = now.add(Duration(days: dias));
    return widget.proyectos.where((p) {
      if (p.estado != EstadoProyecto.vigente &&
          p.estado != EstadoProyecto.xVencer) {
        return false;
      }
      final ft = p.fechaTermino;
      if (ft == null) return false;
      return ft.isAfter(now) && ft.isBefore(limite);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final page = _periodos[_idx];
    final count = _count(page.dias);
    const color = AppColors.warning;

    final activeColor = count > 0 ? color : Colors.grey.shade400;
    return KpiCardShell(
      label: page.label,
      color: color,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.schedule_outlined, size: 15, color: activeColor),
      ),
      value: Text(
        count.toString(),
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
      ),
      pageCount: _periodos.length,
      currentIndex: _idx,
      onSwipe: (forward) => setState(
        () => _idx = forward
            ? (_idx + 1) % _periodos.length
            : (_idx - 1 + _periodos.length) % _periodos.length,
      ),
      onTap: widget.onNavigate != null
          ? () => widget.onNavigate!(page.dias)
          : null,
    );
  }
}

class ValorMensualCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(String? estado)? onNavigate;
  const ValorMensualCard({super.key, required this.proyectos, this.onNavigate});

  @override
  State<ValorMensualCard> createState() => _ValorMensualCardState();
}

class _ValorMensualCardState extends State<ValorMensualCard> {
  int _idx = 2; // default: Postulación

  static const _pages = [
    (
      label: 'Valor Mensual\nVigente',
      short: 'Vigente',
      estado: EstadoProyecto.vigente,
      color: AppColors.success,
    ),
    (
      label: 'Valor Mensual\nX Vencer',
      short: 'X Vencer',
      estado: EstadoProyecto.xVencer,
      color: AppColors.warning,
    ),
    (
      label: 'Valor Mensual\nEn Evaluación',
      short: 'En Evaluación',
      estado: 'En Evaluación',
      color: AppColors.primaryMuted,
    ),
    (
      label: 'Valor Mensual\nTotal',
      short: 'Total',
      estado: null as String?,
      color: AppColors.primary,
    ),
  ];

  static String _fmt(double n) {
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toInt()}';
  }

  static String _fmtFull(double n) {
    final str = n.toInt().toString();
    final buf = StringBuffer('\$');
    final len = str.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_idx];
    final filtered = page.estado == null
        ? widget.proyectos.toList()
        : widget.proyectos.where((p) => p.estado == page.estado).toList();
    final total = filtered.fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));
    final color = page.color;

    return KpiCardShell(
      label: page.label,
      color: color,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.attach_money, size: 15, color: color),
      ),
      value: Tooltip(
        message: total > 0 ? _fmtFull(total) : '',
        preferBelow: false,
        child: Text(
          total > 0 ? _fmt(total) : '—',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      pageCount: _pages.length,
      currentIndex: _idx,
      onSwipe: (forward) => setState(
        () => _idx = forward
            ? (_idx + 1) % _pages.length
            : (_idx - 1 + _pages.length) % _pages.length,
      ),
      onTap: widget.onNavigate == null
          ? null
          : () {
              widget.onNavigate!(_pages[_idx].estado);
            },
    );
  }
}