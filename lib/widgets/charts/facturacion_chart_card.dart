import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/proyecto.dart';
import '../walkthrough.dart';
import 'chart_helpers.dart';
import 'chart_widgets.dart';
import '../../core/theme/app_colors.dart';

class FacturacionChartCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(
    int year,
    int quarter, {
    bool onlyWithOC,
    bool onlyIngresos,
  })?
      onQuarterTap;
  const FacturacionChartCard({super.key, required this.proyectos, this.onQuarterTap});

  @override
  State<FacturacionChartCard> createState() => _FacturacionChartCardState();
}

class _FacturacionChartCardState extends State<FacturacionChartCard> {
  int _view = 0; // 0=barras mensual, 1=línea acumulada, 2=total OC

  static const _color = Color(0xFFA78BFA);
  static const _colorOC = AppColors.success;

  static String _fmt(double n) {
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final dataMensual = groupByQuarter(
      widget.proyectos
          .where(
            (p) =>
                p.estado == EstadoProyecto.vigente ||
                p.estado == EstadoProyecto.xVencer ||
                p.estado == EstadoProyecto.finalizado,
          )
          .toList(),
      (p) => p.valorMensual ?? 0,
    ).where((d) => d.year >= 2021).toList();
    final dataOC = groupByQuarter(
      widget.proyectos,
      (p) => p.montoTotalOC ?? 0,
      onlyWithOC: true,
    ).where((d) => d.value > 0).toList();
    final yLabelsMensual = yearLabels(dataMensual, abbreviated: true);
    final yLabelsOC = yearLabels(dataOC, abbreviated: true);

    final cum = <double>[];
    double s = 0;
    for (final d in dataMensual) {
      s += d.value;
      cum.add(s);
    }

    final (title, color, child) = switch (_view) {
      1 => (
          'Facturación Mensual Acumulada',
          _color,
          dataMensual.isEmpty
              ? emptyChartWidget()
              : LineChartWidget(
                  labels: dataMensual.map((d) => d.label).toList(),
                  yearLabels: yLabelsMensual,
                  values: cum,
                  color: _color,
                  formatValue: _fmt,
                ),
        ),
      2 => (
          'Total Órdenes de Compra',
          _colorOC,
          dataOC.isEmpty
              ? emptyChartWidget()
              : BarChartWidget(
                  labels: dataOC.map((d) => d.label).toList(),
                  yearLabels: yLabelsOC,
                  values: dataOC.map((d) => d.value).toList(),
                  color: _colorOC,
                  formatValue: _fmt,
                  onBarTap: widget.onQuarterTap == null
                      ? null
                      : (i) {
                          final d = dataOC[i];
                          widget.onQuarterTap!(
                            d.year,
                            d.quarter,
                            onlyWithOC: true,
                          );
                        },
                ),
        ),
      _ => (
          'Monto Mensual / Quarter',
          _color,
          dataMensual.isEmpty
              ? emptyChartWidget()
              : BarChartWidget(
                  labels: dataMensual.map((d) => d.label).toList(),
                  yearLabels: yLabelsMensual,
                  values: dataMensual.map((d) => d.value).toList(),
                  color: _color,
                  formatValue: _fmt,
                  onBarTap: widget.onQuarterTap == null
                      ? null
                      : (i) {
                          final d = dataMensual[i];
                          widget.onQuarterTap!(
                            d.year,
                            d.quarter,
                            onlyWithOC: false,
                            onlyIngresos: true,
                          );
                        },
                ),
        ),
    };

    final viewLabels = ['M', 'T', '∑ OC'];
    final viewIcons = [
      Icons.bar_chart_rounded,
      Icons.show_chart_rounded,
      Icons.receipt_long_rounded,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.show_chart_rounded, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    HelpBadge(HelpStepsStore.instance.steps[3]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 3-option toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => GestureDetector(
                    onTap: () => setState(() => _view = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: _view == i
                            ? color.withValues(alpha: 0.12)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            viewIcons[i],
                            size: 12,
                            color: _view == i ? color : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            viewLabels[i],
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: _view == i ? color : Colors.grey.shade500,
                              fontWeight: _view == i
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}