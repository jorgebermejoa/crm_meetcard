import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../walkthrough.dart';
import '../../core/theme/app_colors.dart';

class ChartCardShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool showLine;
  final VoidCallback onToggle;
  final Widget child;
  final WalkthroughStep? helpStep;

  const ChartCardShell({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.showLine,
    required this.onToggle,
    required this.child,
    this.helpStep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
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
                  color: color.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
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
                    if (helpStep != null) HelpBadge(helpStep!),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showLine
                            ? Icons.bar_chart_rounded
                            : Icons.show_chart_rounded,
                        size: 12,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        showLine ? 'Barras' : 'Tendencia',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
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

Widget emptyChartWidget() => Center(
  child: Text(
    'Sin datos',
    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
  ),
);

class BarChartWidget extends StatefulWidget {
  final List<String> labels;

  /// Año a mostrar debajo del label cuando cambia (null = no mostrar)
  final List<String?> yearLabels;
  final List<double> values;

  /// Valores de churn (bajas) — barras rojas hacia abajo; misma longitud que values
  final List<double> churnValues;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;
  final void Function(int index)? onBarTap;
  final void Function(int index)? onChurnBarTap;

  const BarChartWidget({
    super.key,
    required this.labels,
    required this.yearLabels,
    required this.values,
    this.churnValues = const [],
    required this.color,
    this.integerValues = false,
    this.formatValue,
    this.onBarTap,
    this.onChurnBarTap,
  });

  @override
  State<BarChartWidget> createState() => _BarChartWidgetState();
}

class _BarChartWidgetState extends State<BarChartWidget> {
  int? _hoveredIndex;

  String _fmt(double v) {
    if (widget.formatValue != null) return widget.formatValue!(v);
    if (widget.integerValues) {
      return v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    }
    return v.toStringAsFixed(1);
  }

  int? _indexAt(Offset local, Size size) {
    if (widget.labels.isEmpty || size.width == 0) return null;
    final slotW = size.width / widget.labels.length;
    final i = (local.dx / slotW).floor();
    if (i < 0 || i >= widget.labels.length) return null;
    return i;
  }

  bool _isChurnZone(Offset local, Size size) {
    if (widget.churnValues.isEmpty) return false;
    const topPad = 4.0;
    const axisH = 13.0 + 12.0;
    final totalH = size.height - axisH - topPad;
    final maxPos = widget.values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxNeg = widget.churnValues.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxNeg <= 0) return false;
    final posRatio = maxPos <= 0 ? 0.0 : maxPos / (maxPos + maxNeg);
    final zeroY = topPad + totalH * posRatio;
    return local.dy > zeroY;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          cursor: (widget.onBarTap != null || widget.onChurnBarTap != null)
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (e) {
            final idx = _indexAt(e.localPosition, size);
            if (idx != _hoveredIndex) setState(() => _hoveredIndex = idx);
          },
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: GestureDetector(
            onTapDown: (e) {
              final idx = _indexAt(e.localPosition, size);
              if (idx != null) {
                final isChurn = _isChurnZone(e.localPosition, size);
                if (isChurn &&
                    widget.onChurnBarTap != null &&
                    idx < widget.churnValues.length &&
                    widget.churnValues[idx] > 0) {
                  widget.onChurnBarTap!(idx);
                } else if (widget.onBarTap != null) {
                  widget.onBarTap!(idx);
                } else {
                  setState(
                    () => _hoveredIndex = _hoveredIndex == idx ? null : idx,
                  );
                }
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  painter: _BarChartPainter(
                    labels: widget.labels,
                    yearLabels: widget.yearLabels,
                    values: widget.values,
                    churnValues: widget.churnValues,
                    color: widget.color,
                    integerValues: widget.integerValues,
                    formatValue: widget.formatValue,
                    hoveredIndex: _hoveredIndex,
                  ),
                  child: const SizedBox.expand(),
                ),
                if (_hoveredIndex != null)
                  BarTooltip(
                    index: _hoveredIndex!,
                    label: widget.labels[_hoveredIndex!],
                    yearLabel: widget.yearLabels[_hoveredIndex!],
                    valueText: _fmt(widget.values[_hoveredIndex!]),
                    churnText:
                        widget.churnValues.length > _hoveredIndex! &&
                            widget.churnValues[_hoveredIndex!] > 0
                        ? '-${_fmt(widget.churnValues[_hoveredIndex!])}'
                        : null,
                    color: widget.color,
                    totalSlots: widget.labels.length,
                    chartWidth: size.width,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BarTooltip extends StatelessWidget {
  final int index;
  final String label;
  final String? yearLabel;
  final String valueText;
  final String? churnText;
  final Color color;
  final int totalSlots;
  final double chartWidth;

  const BarTooltip({
    super.key,
    required this.index,
    required this.label,
    required this.yearLabel,
    required this.valueText,
    this.churnText,
    required this.color,
    required this.totalSlots,
    required this.chartWidth,
  });

  @override
  Widget build(BuildContext context) {
    const tooltipW = 92.0;
    final slotW = chartWidth / totalSlots;
    final cx = slotW * index + slotW / 2;
    final left = (cx - tooltipW / 2).clamp(0.0, chartWidth - tooltipW);
    // Reconstruct full label: e.g. "Q2 · 2024"
    final fullLabel = yearLabel != null ? '$label · $yearLabel' : label;

    return Positioned(
      left: left,
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: tooltipW,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fullLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha:0.65),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                valueText,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (churnText != null) ...[
                const SizedBox(height: 2),
                Text(
                  churnText!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFCA5A5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<String> labels;
  final List<String?> yearLabels;
  final List<double> values;
  final List<double> churnValues;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;
  final int? hoveredIndex;

  static const _churnColor = AppColors.error;

  const _BarChartPainter({
    required this.labels,
    required this.yearLabels,
    required this.values,
    this.churnValues = const [],
    required this.color,
    this.integerValues = false,
    this.formatValue,
    this.hoveredIndex,
  });

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
    double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || values.isEmpty) return;
    const quarterH = 13.0;
    const yearH = 12.0;
    const axisH = quarterH + yearH;
    const topPad = 4.0;
    final totalH = size.height - axisH - topPad;

    final maxPos = values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxNeg = churnValues.isEmpty
        ? 0.0
        : churnValues.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxPos <= 0 && maxNeg <= 0) return;

    // Zero line splits chart area proportionally
    final posRatio = maxNeg == 0 ? 1.0 : maxPos / (maxPos + maxNeg);
    final posH = totalH * posRatio; // height above zero
    final negH = totalH - posH; // height below zero
    final zeroY = topPad + posH;

    final n = labels.length;
    final slotW = size.width / n;
    final barW = slotW * 0.55;

    final quarterStyle = TextStyle(
      fontSize: 9,
      color: AppColors.textFaint,
      fontFamily: 'Inter',
    );
    final yearStyle = TextStyle(
      fontSize: 8,
      color: const Color(0xFFCBD5E1),
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
    );

    // Zero line (only when churn exists)
    if (maxNeg > 0) {
      canvas.drawLine(
        Offset(0, zeroY),
        Offset(size.width, zeroY),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
    }

    for (int i = 0; i < n; i++) {
      final hovered = i == hoveredIndex;
      final cx = slotW * i + slotW / 2;

      // Positive bar (up from zero)
      if (maxPos > 0) {
        final bh = (values[i] / maxPos) * posH;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, topPad, barW, posH),
            const Radius.circular(4),
          ),
          Paint()
            ..color = color.withValues(alpha:hovered ? 0.14 : 0.08)
            ..style = PaintingStyle.fill,
        );
        if (bh > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(cx - barW / 2, zeroY - bh, barW, bh),
              const Radius.circular(4),
            ),
            Paint()
              ..color = hovered ? color.withValues(alpha:0.85) : color
              ..style = PaintingStyle.fill,
          );
        }
      }

      // Negative / churn bar (down from zero)
      if (maxNeg > 0 && i < churnValues.length && churnValues[i] > 0) {
        final bh = (churnValues[i] / maxNeg) * negH;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, zeroY, barW, negH),
            const Radius.circular(4),
          ),
          Paint()
            ..color = _churnColor.withValues(alpha:hovered ? 0.14 : 0.07)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, zeroY, barW, bh),
            const Radius.circular(4),
          ),
          Paint()
            ..color = hovered
                ? _churnColor.withValues(alpha:0.85)
                : _churnColor
            ..style = PaintingStyle.fill,
        );
      }

      // Quarter label
      _drawCenteredText(
        canvas,
        labels[i],
        Offset(cx, size.height - axisH),
        quarterStyle,
        slotW,
      );

      // Year label (only on year change)
      if (i < yearLabels.length && yearLabels[i] != null) {
        _drawCenteredText(
          canvas,
          yearLabels[i]!,
          Offset(cx, size.height - yearH),
          yearStyle,
          slotW * 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.values != values ||
      old.churnValues != churnValues ||
      old.color != color ||
      old.labels != labels ||
      old.yearLabels != yearLabels ||
      old.hoveredIndex != hoveredIndex;
}

class LineChartWidget extends StatefulWidget {
  final List<String> labels;
  final List<String?> yearLabels;
  final List<double> values;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;

  const LineChartWidget({
    super.key,
    required this.labels,
    required this.yearLabels,
    required this.values,
    required this.color,
    this.integerValues = false,
    this.formatValue,
  });

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<LineChartWidget> {
  int? _hoveredIndex;

  String _fmt(double v) {
    if (widget.formatValue != null) return widget.formatValue!(v);
    if (widget.integerValues) {
      return v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    }
    return v.toStringAsFixed(1);
  }

  // Encuentra el índice del punto más cercano al X del mouse
  int? _indexAt(Offset local, Size size) {
    if (widget.values.isEmpty) return null;
    final n = widget.values.length;
    final stepX = n > 1 ? (size.width - 8) / (n - 1) : 0.0;
    double minDist = double.infinity;
    int? idx;
    for (int i = 0; i < n; i++) {
      final x = n > 1 ? 4.0 + i * stepX : size.width / 2;
      final d = (local.dx - x).abs();
      if (d < minDist) {
        minDist = d;
        idx = i;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onHover: (e) {
            final idx = _indexAt(e.localPosition, size);
            if (idx != _hoveredIndex) setState(() => _hoveredIndex = idx);
          },
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: GestureDetector(
            onTapDown: (e) {
              final idx = _indexAt(e.localPosition, size);
              setState(() => _hoveredIndex = _hoveredIndex == idx ? null : idx);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  painter: _LineChartPainter(
                    labels: widget.labels,
                    yearLabels: widget.yearLabels,
                    values: widget.values,
                    color: widget.color,
                    integerValues: widget.integerValues,
                    formatValue: widget.formatValue,
                    hoveredIndex: _hoveredIndex,
                  ),
                  child: const SizedBox.expand(),
                ),
                if (_hoveredIndex != null)
                  LineTooltip(
                    index: _hoveredIndex!,
                    label: widget.labels[_hoveredIndex!],
                    yearLabel: widget.yearLabels.length > _hoveredIndex!
                        ? widget.yearLabels[_hoveredIndex!]
                        : null,
                    valueText: _fmt(widget.values[_hoveredIndex!]),
                    color: widget.color,
                    totalPoints: widget.values.length,
                    chartWidth: size.width,
                    chartHeight: size.height,
                    values: widget.values,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class LineTooltip extends StatelessWidget {
  final int index;
  final String label;
  final String? yearLabel;
  final String valueText;
  final Color color;
  final int totalPoints;
  final double chartWidth;
  final double chartHeight;
  final List<double> values;

  const LineTooltip({
    super.key,
    required this.index,
    required this.label,
    required this.yearLabel,
    required this.valueText,
    required this.color,
    required this.totalPoints,
    required this.chartWidth,
    required this.chartHeight,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    const quarterH = 13.0;
    const yearH = 12.0;
    const axisH = quarterH + yearH;
    const topPad = 16.0;
    final chartH = chartHeight - axisH - topPad;
    final maxVal = values.fold<double>(0, (m, v) => v > m ? v : m);

    final stepX = totalPoints > 1 ? (chartWidth - 8) / (totalPoints - 1) : 0.0;
    final px = totalPoints > 1 ? 4.0 + index * stepX : chartWidth / 2;
    final py = maxVal > 0
        ? topPad + chartH * (1 - values[index] / maxVal)
        : topPad;

    const tooltipW = 96.0;
    const tooltipH = 52.0;
    final left = (px - tooltipW / 2).clamp(0.0, chartWidth - tooltipW);
    // Mostrar arriba del punto si hay espacio, abajo si no
    final top = (py - tooltipH - 10) < 0 ? py + 12 : py - tooltipH - 8;
    final fullLabel = yearLabel != null ? '$label · $yearLabel' : label;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: tooltipW,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fullLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha:0.65),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                valueText,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<String> labels;
  final List<String?> yearLabels;
  final List<double> values;
  final Color color;
  final bool integerValues;
  final String Function(double)? formatValue;
  final int? hoveredIndex;

  const _LineChartPainter({
    required this.labels,
    required this.yearLabels,
    required this.values,
    required this.color,
    this.integerValues = false,
    this.formatValue,
    this.hoveredIndex,
  });

  String _fmt(double v) {
    if (formatValue != null) return formatValue!(v);
    if (integerValues) {
      return v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    }
    return integerValues ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
    double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || values.isEmpty) return;
    const quarterH = 13.0;
    const yearH = 12.0;
    const axisH = quarterH + yearH;
    const topPad = 16.0;
    final chartH = size.height - axisH - topPad;
    final maxVal = values.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxVal <= 0) return;

    final n = values.length;
    final stepX = n > 1 ? (size.width - 8) / (n - 1) : 0.0;

    final points = List.generate(n, (i) {
      final x = n > 1 ? 4.0 + i * stepX : size.width / 2;
      final y = topPad + chartH * (1 - values[i] / maxVal);
      return Offset(x, y);
    });

    // Gradient fill
    final fillPath = Path()..moveTo(points.first.dx, topPad + chartH);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(points.last.dx, topPad + chartH)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha:0.18),
            color.withValues(alpha:0.01),
          ],
        ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH))
        ..style = PaintingStyle.fill,
    );

    // Smooth line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cp1 = Offset(
        (points[i - 1].dx + points[i].dx) / 2,
        points[i - 1].dy,
      );
      final cp2 = Offset((points[i - 1].dx + points[i].dx) / 2, points[i].dy);
      linePath.cubicTo(
        cp1.dx,
        cp1.dy,
        cp2.dx,
        cp2.dy,
        points[i].dx,
        points[i].dy,
      );
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Eje X: mostrar label solo cada Nth punto para no saturar
    // Siempre mostrar año cuando cambia; Q solo si hay espacio (n <= 8) o
    // si es el primer punto del año
    final quarterStyle = TextStyle(
      fontSize: 9,
      color: AppColors.textFaint,
      fontFamily: 'Inter',
    );
    final yearStyle = TextStyle(
      fontSize: 8,
      color: const Color(0xFFCBD5E1),
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
    );
    final valueStyle = TextStyle(
      fontSize: 9,
      color: color,
      fontWeight: FontWeight.w600,
      fontFamily: 'Inter',
    );

    // Umbral: mostrar Q label solo cuando hay espacio suficiente (slotX >= 18px)
    final showAllQ = stepX >= 18;

    for (int i = 0; i < n; i++) {
      final p = points[i];
      final isHovered = i == hoveredIndex;
      final isLast = i == n - 1;
      final isYearChange = i < yearLabels.length && yearLabels[i] != null;

      // Dot — más grande si está hovered
      final dotR = isHovered ? 4.5 : 2.5;
      canvas.drawCircle(
        p,
        dotR,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        p,
        dotR,
        Paint()
          ..color = isHovered ? color : color.withValues(alpha:0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHovered ? 2.5 : 1.5,
      );

      // Valor: solo en el último punto (o si está hovered, lo maneja el tooltip)
      if (isLast) {
        _drawCenteredText(
          canvas,
          _fmt(values[i]),
          Offset(p.dx, p.dy - 13),
          valueStyle,
          60,
        );
      }

      // Q label: solo si cabe o es cambio de año
      if (showAllQ || isYearChange) {
        _drawCenteredText(
          canvas,
          labels[i],
          Offset(p.dx, size.height - axisH),
          quarterStyle,
          stepX.clamp(14, 50),
        );
      }

      // Año: solo en cambio de año
      if (isYearChange) {
        _drawCenteredText(
          canvas,
          yearLabels[i]!,
          Offset(p.dx, size.height - yearH),
          yearStyle,
          60,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.color != color ||
      old.labels != labels ||
      old.yearLabels != yearLabels ||
      old.hoveredIndex != hoveredIndex;
}