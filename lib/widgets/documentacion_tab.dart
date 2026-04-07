import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../features/proyectos/data/proyectos_constants.dart';
import '../features/proyectos/domain/entities/doc_item.dart';
import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../core/utils/proyecto_display_utils.dart';
import '../models/proyecto.dart';
import 'filter_sheets.dart';
import 'shared/summary_widgets.dart';
import '../core/theme/app_colors.dart';

class DocumentacionTab extends StatefulWidget {
  final bool isMobile;
  final Future<void> Function(Proyecto, {String? tab}) onOpenEditDialog;

  const DocumentacionTab({
    super.key,
    required this.isMobile,
    required this.onOpenEditDialog,
  });

  @override
  State<DocumentacionTab> createState() => _DocumentacionTabState();
}

class _DocumentacionTabState extends State<DocumentacionTab> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProyectosProvider>();

    final allItems = provider.docItems;
    final pageItems = provider.docPageItems;
    final totalPages = provider.docTotalPages;
    final hasFilters = provider.hasActiveDocFilters;

    final activeCount = [
          provider.docFilterInstitucion,
          provider.docFilterModalidad,
          provider.docFilterEstado,
        ].where((v) => v != null).length +
        (provider.docFilterProductos.isNotEmpty ? 1 : 0) +
        (provider.docFilterTipos.isNotEmpty ? 1 : 0);

    final allTipos = allItems.map((i) => i.tipoDoc).toSet().toList()..sort();

    final docFilterButton = GestureDetector(
      onTap: () => _showDocFiltersSheet(context, allTipos),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hasFilters
              ? kPrimaryColor.withValues(alpha: 0.08)
              : Colors.white,
          border: Border.all(
            color: hasFilters ? kPrimaryColor : Colors.grey.shade200,
            width: hasFilters ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 15,
              color: hasFilters ? kPrimaryColor : Colors.grey.shade500,
            ),
            if (activeCount > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    Widget docFilterRow() => Row(
      children: [
        if (hasFilters)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (provider.docFilterInstitucion != null)
                    ActiveFilterChip(
                      label: provider.docFilterInstitucion!
                          .split('|')
                          .first
                          .trim(),
                      onRemove: () => provider.setDocFilter(
                        institucion: '',
                      ),
                    ),
                  if (provider.docFilterProductos.isNotEmpty)
                    ActiveFilterChip(
                      label: provider.docFilterProductos.join(', '),
                      onRemove: () =>
                          provider.setDocFilter(productos: {}),
                    ),
                  if (provider.docFilterModalidad != null)
                    ActiveFilterChip(
                      label: provider.docFilterModalidad!,
                      onRemove: () =>
                          provider.setDocFilter(modalidad: ''),
                    ),
                  if (provider.docFilterEstado != null)
                    ActiveFilterChip(
                      label: provider.docFilterEstado!,
                      onRemove: () =>
                          provider.setDocFilter(estado: ''),
                    ),
                  if (provider.docFilterTipos.isNotEmpty)
                    ActiveFilterChip(
                      label: provider.docFilterTipos.join(', '),
                      onRemove: () =>
                          provider.setDocFilter(tipos: {}),
                    ),
                ]
                    .expand((c) => [c, const SizedBox(width: 6)])
                    .toList()
                  ..removeLast(),
              ),
            ),
          )
        else
          const Spacer(),
        if (hasFilters) ...[
          GestureDetector(
            onTap: () => provider.clearDocFilters(),
            child: Icon(Icons.close, size: 15, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
        ],
        GestureDetector(
          onTap: () => provider.setDocSort(!provider.docSortAscending),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              provider.docSortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 15,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        docFilterButton,
      ],
    );

    Widget docPagination() {
      if (totalPages <= 1) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: provider.docCurrentPage > 0
                  ? () => provider.setDocPage(provider.docCurrentPage - 1)
                  : null,
              color: kPrimaryColor,
            ),
            Text(
              '${provider.docCurrentPage + 1} / $totalPages',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: provider.docCurrentPage < totalPages - 1
                  ? () => provider.setDocPage(provider.docCurrentPage + 1)
                  : null,
              color: kPrimaryColor,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary chip row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          child: Row(
            children: [
              Expanded(
                child: SummaryChip(
                  'Total ${allItems.length}',
                  null,
                  AppColors.textPrimary,
                ),
              ),
              const HorizontalDivider(),
              Expanded(
                child: SummaryChip(
                  'Certificados ${allItems.where((i) => i.tipoDoc == 'Certificado').length}',
                  AppColors.primaryMuted,
                  AppColors.primaryMuted,
                ),
              ),
              const HorizontalDivider(),
              Expanded(
                child: SummaryChip(
                  'Reclamos ${allItems.where((i) => i.tipoDoc.startsWith('Reclamo')).length}',
                  AppColors.error,
                  AppColors.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        docFilterRow(),
        const SizedBox(height: 16),
        if (pageItems.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 56,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sin documentos',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: pageItems
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildDocCard(item),
                  ),
                )
                .toList(),
          ),
        docPagination(),
      ],
    );
  }

  Widget _buildDocCard(DocItem item) {
    final p = item.proyecto;
    final idLabel = p.idLicitacion?.isNotEmpty == true
        ? p.idLicitacion
        : p.idCotizacion?.isNotEmpty == true
            ? p.idCotizacion
            : p.idsOrdenesCompra.isNotEmpty
                ? p.idsOrdenesCompra.first
                : null;

    return GestureDetector(
      onTap: () => widget.onOpenEditDialog(p, tab: item.tabTarget),
      child: Container(
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
            // Header strip
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.tipoDoc,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: item.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (idLabel != null)
                        Text(
                          idLabel,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey.shade400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        p.modalidadCompra,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: Colors.grey.shade300,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.descripcion,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ProyectoDisplayUtils.cleanInst(p.institucion),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (p.productos.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.productos,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (item.fecha != null || item.fechaSecundaria != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (item.fecha != null && item.labelFecha != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 11,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${item.labelFecha}: ${ProyectoDisplayUtils.formatDate(item.fecha)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        if (item.fechaSecundaria != null &&
                            item.labelFechaSecundaria != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 11,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${item.labelFechaSecundaria}: ${ProyectoDisplayUtils.formatDate(item.fechaSecundaria)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  if (item.urls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.urls.asMap().entries.map((e) {
                        final idx = e.key;
                        final url = e.value;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => web.window.open(url, '_blank'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimaryColor.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      kPrimaryColor.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.open_in_new,
                                    size: 12,
                                    color: kPrimaryColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.urls.length > 1
                                        ? 'Ficha ${idx + 1}'
                                        : 'Ver ficha',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: kPrimaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocFiltersSheet(BuildContext context, List<String> tipoOptions) {
    final provider = context.read<ProyectosProvider>();
    final modalidades = provider.config.modalidades;
    final estados = provider.config.estados.map((e) => e.nombre).toList();
    final allProducts =
        provider.config.productos.map((p) => p.abreviatura).toList()..sort();

    final instSeen = <String>{};
    final instituciones = <String>[];
    for (final p in provider.proyectos) {
      final clean = ProyectoDisplayUtils.cleanInst(p.institucion);
      final norm = clean.trim().toUpperCase();
      if (norm.isEmpty) continue;
      if (instSeen.add(norm)) instituciones.add(clean);
    }
    instituciones.sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void applyAndRefresh(VoidCallback fn) {
            fn();
            setSheet(() {});
          }

          Widget sectionTitle(String t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              t,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          );

          Widget chipGroup(
            List<String> items,
            String? selected,
            void Function(String?) onTap,
          ) {
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in items)
                  GestureDetector(
                    onTap: () {
                      applyAndRefresh(
                        () => onTap(selected == item ? null : item),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected == item
                            ? kPrimaryColor
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selected == item
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }

          Widget multiChipGroup(
            List<String> items,
            Set<String> selected,
            void Function(Set<String>) onChanged,
          ) {
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in items)
                  GestureDetector(
                    onTap: () {
                      final next = Set<String>.from(selected);
                      if (next.contains(item)) {
                        next.remove(item);
                      } else {
                        next.add(item);
                      }
                      applyAndRefresh(() => onChanged(next));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected.contains(item)
                            ? kPrimaryColor
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selected.contains(item)
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }

          final activeCount = [
                provider.docFilterInstitucion,
                provider.docFilterModalidad,
                provider.docFilterEstado,
              ].where((v) => v != null).length +
              (provider.docFilterProductos.isNotEmpty ? 1 : 0) +
              (provider.docFilterTipos.isNotEmpty ? 1 : 0);

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 32,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  'Filtros documentos',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (activeCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kPrimaryColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$activeCount',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (activeCount > 0)
                            TextButton(
                              onPressed: () {
                                applyAndRefresh(
                                    () => provider.clearDocFilters());
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                              child: Text(
                                'Limpiar',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.red.shade400,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    children: [
                      sectionTitle('Tipo de documento'),
                      multiChipGroup(
                        tipoOptions,
                        provider.docFilterTipos,
                        (v) => provider.setDocFilter(tipos: v),
                      ),
                      const SizedBox(height: 20),
                      sectionTitle('Institución'),
                      GestureDetector(
                        onTap: () async {
                          final sel = await showDialog<String>(
                            context: ctx,
                            builder: (_) => FilterSearchDialog(
                              hint: 'Institución',
                              value: provider.docFilterInstitucion,
                              items: instituciones,
                              displayLabel: (s) => s,
                            ),
                          );
                          if (sel == '\x00') {
                            applyAndRefresh(() => provider.setDocFilter(
                                  institucion: '',
                                ));
                          } else if (sel != null) {
                            applyAndRefresh(() => provider.setDocFilter(
                                  institucion: sel,
                                ));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: provider.docFilterInstitucion != null
                                ? kPrimaryColor.withValues(alpha: 0.06)
                                : AppColors.surfaceAlt,
                            border: Border.all(
                              color: provider.docFilterInstitucion != null
                                  ? kPrimaryColor.withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  provider.docFilterInstitucion != null
                                      ? provider.docFilterInstitucion!
                                          .split('|')
                                          .first
                                          .trim()
                                      : 'Seleccionar institución…',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color:
                                        provider.docFilterInstitucion != null
                                            ? AppColors.textPrimary
                                            : Colors.grey.shade400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                provider.docFilterInstitucion != null
                                    ? Icons.close
                                    : Icons.search,
                                size: 16,
                                color: provider.docFilterInstitucion != null
                                    ? kPrimaryColor
                                    : Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      sectionTitle('Productos'),
                      multiChipGroup(
                        allProducts,
                        provider.docFilterProductos,
                        (v) => provider.setDocFilter(productos: v),
                      ),
                      const SizedBox(height: 20),
                      sectionTitle('Contratación'),
                      chipGroup(
                        modalidades,
                        provider.docFilterModalidad,
                        (v) => provider.setDocFilter(modalidad: v ?? ''),
                      ),
                      const SizedBox(height: 20),
                      sectionTitle('Estado del proyecto'),
                      chipGroup(
                        estados,
                        provider.docFilterEstado,
                        (v) => provider.setDocFilter(estado: v ?? ''),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
