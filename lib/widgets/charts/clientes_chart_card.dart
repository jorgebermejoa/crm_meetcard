import 'package:flutter/material.dart';

import '../../../models/proyecto.dart';
import '../walkthrough.dart';
import 'chart_helpers.dart';
import 'chart_widgets.dart';
import '../../core/theme/app_colors.dart';

class ClientesChartCard extends StatefulWidget {
  final List<Proyecto> proyectos;
  final void Function(
    int year,
    int quarter, {
    bool onlyWithOC,
    bool onlyIngresos,
  })?
      onQuarterTap;
  final void Function(int year, int quarter)? onChurnQuarterTap;
  const ClientesChartCard({
    super.key,
    required this.proyectos,
    this.onQuarterTap,
    this.onChurnQuarterTap,
  });

  @override
  State<ClientesChartCard> createState() => _ClientesChartCardState();
}

class _ClientesChartCardState extends State<ClientesChartCard> {
  bool _showLine = false;
  static const _color = AppColors.primaryMuted;

  @override
  Widget build(BuildContext context) {
    final data = newClientsByQuarter(
      widget.proyectos,
    ).where((d) => d.year >= 2021).toList();
    final churn = churnByQuarter(
      widget.proyectos,
    ).where((d) => d.year >= 2021).toList();
    final merged = mergeDivergingData(data, churn);

    // Clientes activos netos por quarter:
    // acumulado de (nuevos - bajas) → refleja la cartera real en cada momento
    final netValues = <double>[];
    double net = 0;
    for (int i = 0; i < merged.positive.length; i++) {
      final churnVal = i < merged.churn.length ? merged.churn[i] : 0.0;
      net = (net + merged.positive[i] - churnVal).clamp(0, double.infinity);
      netValues.add(net);
    }

    return ChartCardShell(
      title: _showLine ? 'Cartera Activa Neta' : 'Clientes Nuevos / Quarter',
      icon: Icons.people_outline_rounded,
      color: _color,
      showLine: _showLine,
      onToggle: () => setState(() => _showLine = !_showLine),
      helpStep: _showLine
          ? HelpStepsStore.instance.steps[2]
          : HelpStepsStore.instance.steps[1],
      child: merged.labels.isEmpty
          ? emptyChartWidget()
          : _showLine
              ? LineChartWidget(
                  labels: merged.labels,
                  yearLabels: merged.yearLabels,
                  values: netValues,
                  color: _color,
                  integerValues: true,
                )
              : BarChartWidget(
                  labels: merged.labels,
                  yearLabels: merged.yearLabels,
                  values: merged.positive,
                  churnValues: merged.churn,
                  color: _color,
                  integerValues: true,
                  onBarTap: widget.onQuarterTap == null
                      ? null
                      : (i) {
                          final k = merged.keys[i];
                          widget.onQuarterTap!(k.$1, k.$2, onlyWithOC: true);
                        },
                  onChurnBarTap: widget.onChurnQuarterTap == null
                      ? null
                      : (i) {
                          final k = merged.keys[i];
                          widget.onChurnQuarterTap!(k.$1, k.$2);
                        },
                ),
    );
  }
}