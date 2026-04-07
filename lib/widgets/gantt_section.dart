import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../features/proyectos/data/proyectos_constants.dart';
import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/proyecto.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/string_utils.dart';

class GanttSection extends StatelessWidget {
  final bool isMobile;
  const GanttSection({super.key, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProyectosProvider>();
    final isRuta = provider.ganttMode == 'ruta';
    final isPostulacion = provider.ganttMode == 'postulacion';

    bool hasDates(Proyecto p) {
      if (isPostulacion) {
        return p.fechaPublicacion != null &&
            p.fechaCierre != null &&
            p.fechaCierre!.isAfter(p.fechaPublicacion!);
      }
      if (isRuta) {
        return p.fechaInicioRuta != null &&
            p.fechaTerminoRuta != null &&
            p.fechaTerminoRuta!.isAfter(p.fechaInicioRuta!);
      }
      return p.fechaInicio != null &&
          p.fechaTermino != null &&
          p.fechaTermino!.isAfter(p.fechaInicio!);
    }

    // Pre-filter by estado before date check
    final byEstado = isPostulacion
        ? provider.proyectos
            .where((p) => p.estadoManual == 'En Evaluación')
            .toList()
        : provider.proyectos
            .where((p) => p.estado == EstadoProyecto.vigente)
            .toList();

    final withDates = byEstado.where(hasDates).toList()
      ..sort(
        (a, b) => _startOf(
          a,
          isRuta: isRuta,
          isPostulacion: isPostulacion,
        ).compareTo(_startOf(b, isRuta: isRuta, isPostulacion: isPostulacion)),
      );

    final String emptyMsg = isPostulacion
        ? 'Ningún proyecto en estado En Evaluación tiene fechas de publicación y cierre registradas.'
        : isRuta
            ? 'Ningún proyecto tiene fechas de ruta de implementación registradas.'
            : '';

    if (withDates.isEmpty && provider.ganttMode == 'contrato') {
      return const SizedBox();
    }
    if (withDates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ganttHeader(
            isMobile,
            autoStart: DateTime.now(),
            autoEnd: DateTime.now(),
            stepMonths: 1,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
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
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    emptyMsg,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    DateTime startOf2(Proyecto p) =>
        _startOf(p, isRuta: isRuta, isPostulacion: isPostulacion);
    // Bar ends at fechaCierre (cierre recepción ofertas); adjudicación is a separate milestone.
    DateTime endOf2(Proyecto p) =>
        _endOf(p, isRuta: isRuta, isPostulacion: isPostulacion);

    final dataStart = startOf2(withDates.first);
    // For postulación: extend the default window to include adjudicación dates and today
    DateTime dataEnd = withDates
        .map((p) => endOf2(p))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (isPostulacion) {
      final candidates = <DateTime>[dataEnd, DateTime.now()];
      for (final p in withDates) {
        if (p.fechaAdjudicacion != null) candidates.add(p.fechaAdjudicacion!);
        if (p.fechaAdjudicacionFin != null) candidates.add(p.fechaAdjudicacionFin!);
      }
      dataEnd = candidates.reduce((a, b) => a.isAfter(b) ? a : b);
    }
    // Add 2-week padding on each side for visual comfort
    final autoStart = dataStart.subtract(const Duration(days: 14));
    final autoEnd = dataEnd.add(const Duration(days: 14));
    final rangeStart = provider.ganttWindowStart ?? autoStart;
    final rangeEnd = provider.ganttWindowEnd ?? autoEnd;
    final totalDays =
        rangeEnd.difference(rangeStart).inDays.toDouble().clamp(1.0, 36500.0);
    final spanMonths = (totalDays / 30).round();

    // Adaptive step: yearly for long spans, quarterly, or monthly
    final int stepMonths;
    if (spanMonths > 24) {
      stepMonths = 12;
    } else if (spanMonths > 12) {
      stepMonths = 6;
    } else if (spanMonths > 6) {
      stepMonths = 3;
    } else {
      stepMonths = 1;
    }

    final labelW = isMobile ? 100.0 : 190.0;
    final dateW = (isPostulacion || isRuta) ? 78.0 : 58.0;
    const barH = 20.0;
    const rowH = 48.0;
    const headerH = 36.0;

    const monthNames = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];

    List<({double frac, String label, bool isMajor})> buildMarkers() {
      final markers = <({double frac, String label, bool isMajor})>[];
      // Snap to first tick: round up to nearest stepMonths boundary
      int startMonth = rangeStart.month;
      int startYear = rangeStart.year;
      // advance to next step boundary
      final rem = (startMonth - 1) % stepMonths;
      if (rem != 0) {
        startMonth += stepMonths - rem;
        if (startMonth > 12) {
          startMonth -= 12;
          startYear++;
        }
      }
      var cursor = DateTime(startYear, startMonth, 1);
      while (cursor.isBefore(rangeEnd) || cursor.isAtSameMomentAs(rangeEnd)) {
        final days = cursor.difference(rangeStart).inDays.toDouble();
        final frac = (days / totalDays).clamp(0.0, 1.0);
        final isMajor = cursor.month == 1 || stepMonths == 12;
        final yearStr = isMobile
            ? "'${(cursor.year % 100).toString().padLeft(2, '0')}"
            : cursor.year.toString();
        final label = stepMonths >= 12
            ? yearStr
            : isMajor
                ? '${monthNames[cursor.month - 1]}\n$yearStr'
                : monthNames[cursor.month - 1];
        markers.add((frac: frac, label: label, isMajor: isMajor));
        var nextMonth = cursor.month + stepMonths;
        var nextYear = cursor.year;
        while (nextMonth > 12) {
          nextMonth -= 12;
          nextYear++;
        }
        cursor = DateTime(nextYear, nextMonth, 1);
      }
      return markers;
    }

    // Day-level ticks for short spans (postulación / ruta)
    final bool useDayMarkers = (isPostulacion || isRuta) && totalDays <= 60;
    List<({double frac, String label, bool isMajor})> buildDayMarkers(
      int stepDays,
    ) {
      final result = <({double frac, String label, bool isMajor})>[];
      var cursor = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
      while (cursor.isBefore(rangeEnd)) {
        final days = cursor.difference(rangeStart).inDays.toDouble();
        final frac = (days / totalDays).clamp(0.0, 1.0);
        final isMajor = cursor.day == 1 || stepDays >= 7;
        final label =
            '${cursor.day.toString().padLeft(2, '0')}/${cursor.month.toString().padLeft(2, '0')}';
        result.add((frac: frac, label: label, isMajor: isMajor));
        cursor = cursor.add(Duration(days: stepDays));
      }
      return result;
    }

    // Compute adaptive step from chart width (called inside LayoutBuilder)
    int adaptiveStepDays(double chartW) {
      const minPixels = 34.0; // min px between ticks to avoid overlap
      final maxTicks = (chartW / minPixels).floor().clamp(2, 200);
      final raw = (totalDays / maxTicks).ceil();
      if (raw <= 1) return 1;
      if (raw <= 2) return 2;
      if (raw <= 3) return 3;
      if (raw <= 7) return 7;
      if (raw <= 14) return 14;
      return 30;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ganttHeader(
          isMobile,
          autoStart: autoStart,
          autoEnd: autoEnd,
          stepMonths: stepMonths,
        ),
        const SizedBox(height: 12),
        Container(
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final chartW =
                  (constraints.maxWidth - labelW - dateW - 16).clamp(
                40.0,
                10000.0,
              );
              final markers = useDayMarkers
                  ? buildDayMarkers(adaptiveStepDays(chartW))
                  : buildMarkers();

              // Today fraction
              final todayDays = DateTime.now()
                  .difference(rangeStart)
                  .inDays
                  .toDouble()
                  .clamp(0.0, totalDays);
              final todayFrac = todayDays / totalDays;

              Widget todayLine() {
                if (todayFrac <= 0 || todayFrac >= 1) return const SizedBox();
                return Positioned(
                  left: todayFrac * chartW,
                  top: 0,
                  bottom: 0,
                  width: 1.5,
                  child: Container(
                    color: AppColors.primary.withValues(alpha:0.55),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(width: labelW + 8),
                      SizedBox(
                        width: chartW,
                        height: headerH,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            // Tick lines
                            ...markers.map(
                              (m) => Positioned(
                                left: m.frac * chartW,
                                top: m.isMajor ? 0 : headerH * 0.4,
                                bottom: 0,
                                width: m.isMajor ? 1.5 : 1,
                                child: Container(
                                  color: m.isMajor
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade200,
                                ),
                              ),
                            ),
                            // Today tick in header
                            if (todayFrac > 0 && todayFrac < 1)
                              Positioned(
                                left: todayFrac * chartW,
                                top: 0,
                                bottom: 0,
                                width: 1.5,
                                child: Container(
                                  color: const Color(
                                    0xFF007AFF,
                                  ).withValues(alpha:0.55),
                                ),
                              ),
                            // Labels
                            ...markers.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final m = entry.value;
                              final left = (m.frac * chartW + 4).clamp(
                                0.0,
                                chartW - 38.0,
                              );
                              // Stagger odd day-marker labels lower to prevent overlap on mobile
                              final top =
                                  (useDayMarkers && idx.isOdd) ? 14.0 : 0.0;
                              return Positioned(
                                left: left,
                                top: top,
                                child: Text(
                                  m.label,
                                  style: GoogleFonts.inter(
                                    fontSize: m.isMajor ? 10 : 9,
                                    fontWeight: m.isMajor
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: m.isMajor
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade400,
                                    height: 1.3,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.surfaceSubtle,
                  ),
                  // Project rows
                  ...withDates.map((p) {
                    final startDays = startOf2(p)
                        .difference(rangeStart)
                        .inDays
                        .toDouble()
                        .clamp(0.0, totalDays);
                    final endDays = endOf2(p)
                        .difference(rangeStart)
                        .inDays
                        .toDouble()
                        .clamp(0.0, totalDays);
                    final leftFrac = startDays / totalDays;
                    final widthFrac =
                        ((endDays - startDays) / totalDays).clamp(
                      0.0,
                      1.0,
                    );

                    const barColor = AppColors.primary;

                    final instFull = p.institucion.split('|').first.trim();
                    final instDisplay = instFull
                        .replaceAll(
                          RegExp(
                            r'\bI(?:LUSTRE)?\b\.?\s+MUNICIPALIDAD\b',
                            caseSensitive: false,
                          ),
                          'I.M.',
                        )
                        .replaceAll(
                          RegExp(r'\bMUNICIPALIDAD\b', caseSensitive: false),
                          'Mpal.',
                        );

                    final isExpanded =
                        provider.ganttExpandedRows.contains(p.id);

                    // Milestone helpers for postulación
                    Widget milestoneRow() {
                      if (!isPostulacion || !isExpanded) {
                        return const SizedBox();
                      }
                      const milestoneH = 32.0;
                      final milestones =
                          <({DateTime date, String label, Color color})>[];
                      if (p.fechaConsultas != null) {
                        milestones.add((
                          date: p.fechaConsultas!,
                          label: 'Consultas',
                          color: AppColors.primaryMuted,
                        ));
                      }
                      if (p.fechaAdjudicacion != null) {
                        milestones.add((
                          date: p.fechaAdjudicacion!,
                          label: 'Adjudicación',
                          color: AppColors.warning,
                        ));
                      }
                      if (milestones.isEmpty) return const SizedBox();
                      return SizedBox(
                        height: milestoneH,
                        child: Row(
                          children: [
                            SizedBox(width: labelW + 8),
                            SizedBox(
                              width: chartW,
                              height: milestoneH,
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  ...markers.map(
                                    (m) => Positioned(
                                      left: m.frac * chartW,
                                      top: 0,
                                      bottom: 0,
                                      width: 1,
                                      child: Container(
                                        color: Colors.grey.shade100,
                                      ),
                                    ),
                                  ),
                                  todayLine(),
                                  ...milestones.map((ms) {
                                    final msDays = ms.date
                                        .difference(rangeStart)
                                        .inDays
                                        .toDouble()
                                        .clamp(0.0, totalDays);
                                    final msFrac = msDays / totalDays;
                                    final labelLeft = (msFrac * chartW - 24)
                                        .clamp(0.0, chartW - 56.0);
                                    return Stack(
                                      children: [
                                        Positioned(
                                          left: msFrac * chartW - 1,
                                          top: 0,
                                          bottom: 4,
                                          width: 2,
                                          child: Container(
                                            color: ms.color.withValues(alpha:
                                              0.7,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: labelLeft,
                                          top: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  ms.color.withValues(alpha:0.12),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              ms.label,
                                              style: GoogleFonts.inter(
                                                fontSize: 8,
                                                fontWeight: FontWeight.w600,
                                                color: ms.color,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Milestone bottom sheet helper (mobile expand)
                    void showMilestoneSheet(
                      String label,
                      DateTime? inicio,
                      DateTime? fin,
                      Color color,
                    ) {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Container(
                                    width: 32,
                                    height: 3,
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      label,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (inicio != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.play_circle_outline,
                                          size: 14,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Inicio  ',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                        Text(
                                          _fmtDt(inicio),
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppColors.gray700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (fin != null)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.stop_circle_outlined,
                                        size: 14,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Fin      ',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      Text(
                                        _fmtDt(fin),
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.gray700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    // Mobile-only: expanded detail row with tappable milestones
                    Widget mobileExpandedRow() {
                      if (!isMobile || !isPostulacion || !isExpanded) {
                        return const SizedBox();
                      }
                      final hasMilestones = p.fechaConsultas != null ||
                          p.fechaAdjudicacion != null;
                      if (!hasMilestones) return const SizedBox();

                      Widget chip(
                        String label,
                        DateTime? inicio,
                        DateTime? fin,
                        Color color,
                      ) {
                        if (inicio == null && fin == null) {
                          return const SizedBox();
                        }
                        final rangeText = (inicio != null && fin != null)
                            ? '${_fmtDt(inicio)} – ${_fmtDt(fin)}'
                            : _fmtDt(inicio ?? fin);
                        return GestureDetector(
                          onTap: () =>
                              showMilestoneSheet(label, inicio, fin, color),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$label: ',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                rangeText,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.only(
                          left: (isPostulacion ? 16.0 : 0) + labelW + 16,
                          bottom: 6,
                        ),
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            if (p.fechaConsultas != null ||
                                p.fechaConsultasInicio != null)
                              chip(
                                'Consultas',
                                p.fechaConsultasInicio,
                                p.fechaConsultas,
                                AppColors.primaryMuted,
                              ),
                            if (p.fechaAdjudicacion != null ||
                                p.fechaAdjudicacionFin != null)
                              chip(
                                'Adjudicación',
                                p.fechaAdjudicacion,
                                p.fechaAdjudicacionFin,
                                AppColors.warning,
                              ),
                          ],
                        ),
                      );
                    }

                    // Bar row (all sizes)
                    final barTooltip = isPostulacion
                        ? 'Publicación: ${_fmtDt(startOf2(p))}\nCierre recepción: ${_fmtDt(endOf2(p))}'
                        : isRuta
                            ? 'Inicio: ${_fmtDt(startOf2(p))}\nFin: ${_fmtDt(endOf2(p))}'
                            : 'Inicio: ${_formatDate(startOf2(p))}\nFin: ${_formatDate(endOf2(p))}';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: rowH,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Expand toggle (postulación only)
                              if (isPostulacion)
                                GestureDetector(
                                  onTap: () => context
                                      .read<ProyectosProvider>()
                                      .toggleGanttRow(p.id),
                                  child: SizedBox(
                                    width: 16,
                                    child: Icon(
                                      isExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              // Label column — tapping navigates to project
                              GestureDetector(
                                onTap: () {
                                  final entity = p.toEntity();
                                  final slug = modalidadSlug(p.modalidadCompra);
                                  final cid = contractIdForUrl(p.id, idLicitacion: p.idLicitacion, idCotizacion: p.idCotizacion, urlConvenioMarco: p.urlConvenioMarco);
                                  context.go('/proyectos/$slug/$cid', extra: entity);
                                },
                                child: Tooltip(
                                  message: instFull,
                                  preferBelow: true,
                                  child: SizedBox(
                                    width:
                                        isPostulacion ? labelW - 16 : labelW,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          instDisplay,
                                          style: GoogleFonts.inter(
                                            fontSize: isMobile ? 10 : 11,
                                            color: AppColors.gray700,
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          (isPostulacion || isRuta)
                                              ? _fmtDt(startOf2(p))
                                              : _fmtDateShort(startOf2(p)),
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            color: Colors.grey.shade400,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Chart area — tooltip shows exact date range
                              Tooltip(
                                message: barTooltip,
                                preferBelow: true,
                                child: SizedBox(
                                  width: chartW,
                                  height: rowH,
                                  child: Stack(
                                    clipBehavior: Clip.hardEdge,
                                    children: [
                                      // Track
                                      Positioned(
                                        top: (rowH - barH) / 2,
                                        height: barH,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Grid lines
                                      ...markers.map(
                                        (m) => Positioned(
                                          left: m.frac * chartW,
                                          top: 0,
                                          bottom: 0,
                                          width: m.isMajor ? 1.5 : 1,
                                          child: Container(
                                            color: m.isMajor
                                                ? Colors.grey.shade200
                                                : Colors.grey.shade100,
                                          ),
                                        ),
                                      ),
                                      // Today line
                                      todayLine(),
                                      // Bar
                                      Positioned(
                                        left: leftFrac * chartW,
                                        width: (widthFrac * chartW).clamp(
                                          4.0,
                                          chartW,
                                        ),
                                        top: (rowH - barH) / 2,
                                        height: barH,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: barColor,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Adjudicación dot (orange, always visible in postulación)
                                      if (isPostulacion && p.fechaAdjudicacion != null)
                                        () {
                                          final adjDays = p.fechaAdjudicacion!
                                              .difference(rangeStart)
                                              .inDays
                                              .toDouble()
                                              .clamp(0.0, totalDays);
                                          final adjFrac = adjDays / totalDays;
                                          const dotR = 5.0;
                                          return Positioned(
                                            left: adjFrac * chartW - dotR,
                                            top: (rowH / 2) - dotR,
                                            child: Container(
                                              width: dotR * 2,
                                              height: dotR * 2,
                                              decoration: BoxDecoration(
                                                color: AppColors.warning,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 1.5),
                                              ),
                                            ),
                                          );
                                        }(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // End date
                              SizedBox(
                                width: dateW,
                                child: Text(
                                  (isPostulacion || isRuta)
                                      ? _fmtDt(endOf2(p))
                                      : _fmtDateShort(endOf2(p)),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isMobile) milestoneRow(),
                        mobileExpandedRow(),
                      ],
                    );
                  }),
                  const SizedBox(height: 4),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.surfaceSubtle,
                  ),
                  const SizedBox(height: 8),
                  // Legend
                  if (isMobile)
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _legendItem(
                          AppColors.primary,
                          isPostulacion ? 'Publicación → Cierre' : 'Período',
                        ),
                        if (isPostulacion) ...[
                          _legendItem(
                            AppColors.primaryMuted,
                            'Consultas',
                            isLine: true,
                          ),
                          _legendItem(
                            AppColors.warning,
                            'Adjudicación',
                            isDot: true,
                          ),
                        ],
                        _legendItem(
                          AppColors.primary.withValues(alpha:0.55),
                          'Hoy',
                          isLine: true,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        SizedBox(
                            width: (isPostulacion ? 16 : 0) + labelW + 8),
                        _legendItem(
                          AppColors.primary,
                          isPostulacion ? 'Publicación → Cierre' : 'Período',
                        ),
                        if (isPostulacion) ...[
                          const SizedBox(width: 14),
                          _legendItem(
                            AppColors.primaryMuted,
                            'Consultas',
                            isLine: true,
                          ),
                          const SizedBox(width: 14),
                          _legendItem(
                            AppColors.warning,
                            'Adjudicación',
                            isDot: true,
                          ),
                        ],
                        const SizedBox(width: 14),
                        _legendItem(
                          AppColors.primary.withValues(alpha:0.55),
                          'Hoy',
                          isLine: true,
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Gantt header (mode toggle + nav) ─────────────────────────────────────

  Widget _ganttHeader(
    bool isMobile, {
    DateTime? autoStart,
    DateTime? autoEnd,
    int stepMonths = 3,
  }) {
    return Builder(builder: (context) {
      const activeColor = AppColors.primary;
      const inactiveColor = AppColors.textFaint;
      final tabs = [
        ('contrato', 'Contrato'),
        ('postulacion', 'En Evaluación'),
        ('ruta', 'Implementación'),
      ];
      final subtitles = {
        'contrato': '',
        'ruta': 'Implementación por proyecto',
        'postulacion': 'Publicación y cierre de ofertas por proyecto',
      };
      final provider = context.read<ProyectosProvider>();
      final hasWindow = provider.ganttWindowStart != null || provider.ganttWindowEnd != null;
      final ws = provider.ganttWindowStart ?? autoStart;
      final we = provider.ganttWindowEnd ?? autoEnd;

      void shiftWindow(int months) {
        if (ws == null || we == null) return;
        final newStart = DateTime(ws.year, ws.month + months, ws.day);
        final newEnd = DateTime(we.year, we.month + months, we.day);
        provider.setGanttWindow(newStart, newEnd);
      }

      void zoomWindow(int deltaMonths) {
        if (ws == null || we == null) return;
        final curMonths = we.difference(ws).inDays ~/ 30;
        final newMonths = (curMonths + deltaMonths).clamp(1, 120);
        final center = ws.add(Duration(days: we.difference(ws).inDays ~/ 2));
        final newStart = DateTime(center.year, center.month - newMonths ~/ 2, center.day);
        final newEnd = DateTime(center.year, center.month + (newMonths - newMonths ~/ 2), center.day);
        provider.setGanttWindow(newStart, newEnd);
      }

      Widget navBtn(IconData icon, VoidCallback? onTap, {String? tooltip}) {
        final btn = GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: onTap != null ? AppColors.surfaceSubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Icon(icon, size: 14, color: onTap != null ? AppColors.textSecondary : Colors.grey.shade300),
          ),
        );
        return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
      }

      final modeTabs = Container(
        decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: tabs.map((t) {
            final isActive = provider.ganttMode == t.$1;
            return GestureDetector(
              onTap: () => provider.setGanttMode(t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isActive
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
                      : [],
                ),
                child: Text(t.$2,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? activeColor : inactiveColor)),
              ),
            );
          }).toList(),
        ),
      );

      List<Widget> navButtons() => [
        navBtn(Icons.chevron_left, () => shiftWindow(-stepMonths), tooltip: 'Retroceder'),
        const SizedBox(width: 4),
        navBtn(Icons.chevron_right, () => shiftWindow(stepMonths), tooltip: 'Avanzar'),
        const SizedBox(width: 6),
        navBtn(Icons.remove, () => zoomWindow(stepMonths * 2), tooltip: 'Alejar'),
        const SizedBox(width: 4),
        navBtn(Icons.add, () => zoomWindow(-stepMonths * 2), tooltip: 'Acercar'),
        if (hasWindow) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => provider.resetGanttWindow(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.grey.shade200)),
              child: Text('Reset', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
            ),
          ),
        ],
        const SizedBox(width: 8),
      ];

      final titleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Línea de Tiempo',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if ((subtitles[provider.ganttMode] ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitles[provider.ganttMode]!,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ],
      );

      if (isMobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: titleWidget),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: navButtons()),
            ]),
            const SizedBox(height: 8),
            modeTabs,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: titleWidget),
          if (ws != null && we != null) ...navButtons(),
          modeTabs,
        ],
      );
    });
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  DateTime _startOf(Proyecto p, {required bool isRuta, required bool isPostulacion}) {
    if (isPostulacion) return p.fechaPublicacion!;
    if (isRuta) return p.fechaInicioRuta!;
    return p.fechaInicio!;
  }

  DateTime _endOf(Proyecto p, {required bool isRuta, required bool isPostulacion}) {
    if (isPostulacion) return p.fechaCierre!;
    if (isRuta) return p.fechaTerminoRuta!;
    return p.fechaTermino!;
  }

  String _fmtDt(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}h';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _fmtDateShort(DateTime? dt) {
    if (dt == null) return '—';
    return "${kMonthAbbr[dt.month - 1]} '${dt.year.toString().substring(2)}";
  }

  Widget _legendItem(Color color, String label, {bool isLine = false, bool isDot = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isLine
            ? Container(width: 2, height: 12, color: color, margin: const EdgeInsets.symmetric(horizontal: 3))
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(isDot ? 5 : 2),
                ),
              ),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }
}