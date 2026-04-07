import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/proyecto_display_utils.dart';
import '../../features/proyectos/data/proyectos_constants.dart';
import '../../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../filter_sheets.dart';

/// Shared filter section list used in both the bottom-sheet (ProyectosTab)
/// and the sidebar (ProyectosView).
///
/// Returns a flat list of widgets suitable for use inside a [ListView] or
/// [Column].
List<Widget> buildFilterContentList(
  BuildContext ctx,
  ProyectosProvider provider,
  void Function(VoidCallback) applyAndRefresh,
) {
  final allProducts = provider.config.productos.map((p) => p.abreviatura).toList()..sort();
  final modalidades = provider.config.modalidades;
  final estados = provider.config.estados.map((e) => e.nombre).toList();

  Widget title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget chip(String item, bool isSelected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            item,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      );

  Widget chips(List<String> items, String? sel, void Function(String?) onChanged) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in items)
            chip(item, sel == item, () => applyAndRefresh(() => onChanged(sel == item ? null : item))),
        ],
      );

  Widget multiChips(List<String> items, Set<String> sel, void Function(Set<String>) onChanged) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in items)
            chip(item, sel.contains(item), () => applyAndRefresh(() {
                  final s = {...sel};
                  if (s.contains(item)) {
                    s.remove(item);
                  } else {
                    s.add(item);
                  }
                  onChanged(s);
                })),
        ],
      );

  Widget instSelector() => GestureDetector(
        onTap: () async {
          final instituciones = provider.proyectos
              .map((p) => ProyectoDisplayUtils.cleanInst(p.institucion))
              .toSet()
              .toList()
            ..sort();
          final sel = await showDialog<String>(
            context: ctx,
            builder: (_) => FilterSearchDialog(
              hint: 'Institución',
              value: provider.filterInstitucion,
              items: instituciones,
              displayLabel: (s) => s,
            ),
          );
          if (sel == '\x00') {
            applyAndRefresh(() => provider.setSingleFilter(institucion: ''));
          } else if (sel != null) {
            applyAndRefresh(() => provider.setSingleFilter(institucion: sel));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: provider.filterInstitucion != null
                ? kPrimaryColor.withValues(alpha: 0.06)
                : AppColors.surfaceAlt,
            border: Border.all(
              color: provider.filterInstitucion != null
                  ? kPrimaryColor.withValues(alpha: 0.3)
                  : Colors.grey.shade200,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  provider.filterInstitucion != null
                      ? provider.filterInstitucion!.split('|').first.trim()
                      : 'Seleccionar…',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: provider.filterInstitucion != null
                        ? AppColors.textPrimary
                        : Colors.grey.shade400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                provider.filterInstitucion != null ? Icons.close : Icons.search,
                size: 14,
                color: provider.filterInstitucion != null ? kPrimaryColor : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      );

  return [
    title('Institución'),
    instSelector(),
    const SizedBox(height: 20),
    title('Productos'),
    multiChips(allProducts, provider.filterProductos, (v) => provider.setFilter(productos: v)),
    const SizedBox(height: 20),
    title('Contratación'),
    chips(modalidades, provider.filterModalidad, (v) => provider.setSingleFilter(modalidad: v)),
    const SizedBox(height: 20),
    title('Estado'),
    chips(estados, provider.filterEstado, (v) => provider.setSingleFilter(estado: v)),
    const SizedBox(height: 20),
    title('Reclamos'),
    chips(const ['Pendiente', 'Respondido'], provider.filterReclamo,
        (v) => provider.setSingleFilter(reclamo: v)),
    const SizedBox(height: 20),
    title('Vencimiento'),
    chips(const ['30 días', '3 meses', '6 meses', '12 meses'], provider.filterVencer,
        (v) => provider.setSingleFilter(vencer: v)),
    const SizedBox(height: 20),
    title('Encadenamiento'),
    chips(
      const ['Encadenados', 'Sin encadenar'],
      provider.filterEncadenado == null
          ? null
          : (provider.filterEncadenado! ? 'Encadenados' : 'Sin encadenar'),
      (v) => provider.setFilter(encadenado: v == null ? null : v == 'Encadenados'),
    ),
    const SizedBox(height: 20),
    title('Sugerencias'),
    chips(
      const ['Con sugerencia'],
      provider.filterSugerencia ? 'Con sugerencia' : null,
      (v) => provider.setFilter(sugerencia: v != null),
    ),
  ];
}
