import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/utils/chain_utils.dart';
import '../core/utils/proyecto_display_utils.dart';
import '../features/proyectos/data/proyectos_constants.dart';
import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/configuracion.dart';
import '../models/proyecto.dart';
import 'filter_sheets.dart';
import 'shared/filter_content.dart';
import 'radar_tab.dart';
import 'shared/summary_widgets.dart';
import 'shared/dev_tooltip.dart';
import '../core/theme/app_colors.dart';

class ProyectosTab extends StatefulWidget {
  final bool isMobile;
  final bool hideFilterRow;
  final Future<void> Function() onOpenCreateDialog;
  final Future<void> Function(Proyecto, {String? tab}) onOpenEditDialog;
  final Future<void> Function(Proyecto) onShowEstadoPicker;

  const ProyectosTab({
    super.key,
    required this.isMobile,
    this.hideFilterRow = false,
    required this.onOpenCreateDialog,
    required this.onOpenEditDialog,
    required this.onShowEstadoPicker,
  });

  @override
  State<ProyectosTab> createState() => _ProyectosTabState();
}

class _ProyectosTabState extends State<ProyectosTab> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProyectosProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryRow(provider, widget.isMobile),
        const SizedBox(height: 16),
        if (!widget.hideFilterRow) ...[
          _buildFilterRow(provider.proyectos, widget.isMobile),
          const SizedBox(height: 16),
        ],
        if (provider.filteredProyectos.isEmpty)
          _buildEmptyState()
        else if (widget.isMobile || MediaQuery.of(context).size.width < 800)
          _buildMobileCards(provider.pageItems)
        else
          _buildDesktopTable(provider.pageItems),
        if (provider.totalPages > 1) ...[
          const SizedBox(height: 16),
          _buildPagination(),
        ],
      ],
    );
  }

  Widget _buildSummaryRow(ProyectosProvider provider, bool isMobile) {
    final filtered = provider.filteredProyectos;
    final total = filtered.length;
    final estados = provider.config.estados;

    // Conteo por estado en la lista filtrada
    final counts = <String, int>{for (final e in estados) e.nombre: 0};
    for (final p in filtered) {
      if (counts.containsKey(p.estado)) counts[p.estado] = counts[p.estado]! + 1;
    }

    // Chip de Total + uno por cada estado en el orden de configuración
    final allChips = <Widget>[
      SummaryChip('Total $total', null, AppColors.textPrimary),
      for (final e in estados)
        SummaryChip('${e.nombre} ${counts[e.nombre] ?? 0}', e.colorValue, e.colorValue),
    ];

    // Siempre scroll horizontal para no truncar nombres de estado
    final items = <Widget>[];
    for (int i = 0; i < allChips.length; i++) {
      if (i > 0) items.add(const HorizontalDivider());
      items.add(allChips[i]);
    }
    final chipRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );

    final summaryCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: chipRow,
    );

    final newButton = SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: widget.onOpenCreateDialog,
        icon: const Icon(Icons.add, size: 18),
        label: Text(
          isMobile ? 'Nuevo' : 'Nuevo Proyecto',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
        ),
      ),
    );

    if (isMobile) return summaryCard;
    return Row(children: [Expanded(child: summaryCard), const SizedBox(width: 16), newButton]);
  }

  Widget _buildFilterRow(List<Proyecto> all, bool isMobile) {
    final provider = context.watch<ProyectosProvider>();
    final hasFilters = provider.hasActiveFilters;
    final activeCount = provider.activeFilterCount;

    final activeChips = <Widget>[
      if (provider.filterInstitucion != null)
        ActiveFilterChip(label: provider.filterInstitucion!.split('|').first.trim(), onRemove: () => provider.setFilter(institucion: null)),
      if (provider.filterProductos.isNotEmpty)
        ActiveFilterChip(label: provider.filterProductos.join(', '), onRemove: () => provider.setFilter(productos: {})),
      if (provider.filterModalidad != null)
        ActiveFilterChip(label: provider.filterModalidad!, onRemove: () => provider.setFilter(modalidad: null)),
      if (provider.filterEstado != null)
        ActiveFilterChip(label: provider.filterEstado!, onRemove: () => provider.setFilter(estado: null)),
      if (provider.filterReclamo != null)
        ActiveFilterChip(label: 'Reclamo: ${provider.filterReclamo}', onRemove: () => provider.setFilter(reclamo: null)),
      if (provider.filterVencer != null)
        ActiveFilterChip(label: 'Vencer: ${provider.filterVencer}', onRemove: () => provider.setFilter(vencer: null)),
      if (provider.filterEncadenado != null)
        ActiveFilterChip(
          label: provider.filterEncadenado! ? 'Encadenados' : 'Sin encadenar',
          onRemove: () => provider.setFilter(encadenado: null),
        ),
      if (provider.filterSugerencia)
        ActiveFilterChip(
          label: 'Con sugerencia',
          onRemove: () => provider.setFilter(sugerencia: false),
        ),
      if (provider.filterQuarterYear != null && provider.filterQuarterQ != null)
        ActiveFilterChip(
          label: provider.filterQuarterIsChurn
              ? 'Pérdidas Q${provider.filterQuarterQ} · ${provider.filterQuarterYear}'
              : 'Q${provider.filterQuarterQ} · ${provider.filterQuarterYear}',
          onRemove: () => provider.clearFilters(),
        ),
    ];

    final filterButton = GestureDetector(
      onTap: () => _showFiltersSheet(all),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: hasFilters ? kPrimaryColor.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(color: hasFilters ? kPrimaryColor : Colors.grey.shade200, width: hasFilters ? 1.5 : 1.0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 15, color: hasFilters ? kPrimaryColor : AppColors.textMuted),
            const SizedBox(width: 6),
            Text('Filtros', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: hasFilters ? kPrimaryColor : AppColors.textMuted)),
            if (activeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(10)),
                child: Text('$activeCount', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );

    return Row(
      children: [
        if (activeChips.isNotEmpty)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: activeChips.expand((c) => [c, const SizedBox(width: 6)]).toList()..removeLast()),
            ),
          )
        else
          const Spacer(),
        if (hasFilters) ...[
          GestureDetector(onTap: () => context.read<ProyectosProvider>().clearFilters(), child: Icon(Icons.close, size: 15, color: Colors.grey.shade400)),
          const SizedBox(width: 6),
        ],
        GestureDetector(
          onTap: () => _mostrarSortEstadoSheet(provider),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: provider.sortColumn == null ? kPrimaryColor.withValues(alpha: 0.08) : Colors.white,
              border: Border.all(color: provider.sortColumn == null ? kPrimaryColor : Colors.grey.shade200, width: provider.sortColumn == null ? 1.5 : 1.0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(provider.estadoSortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: provider.sortColumn == null ? kPrimaryColor : Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('Estado', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: provider.sortColumn == null ? kPrimaryColor : Colors.grey.shade500)),
              ],
            ),
          ),
        ),
        filterButton,
      ],
    );
  }

  void _mostrarSortEstadoSheet(ProyectosProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Ordenar por Estado', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Elige el orden de prioridad de los estados', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            const SizedBox(height: 20),
            _sortOpcion(label: 'Descendente', subtitle: 'En Evaluación → Vigente → X Vencer → Sin fecha → Finalizado', icon: Icons.arrow_downward_rounded, selected: !provider.estadoSortAsc, onTap: () => context.read<ProyectosProvider>().setEstadoSort(false)),
            const SizedBox(height: 10),
            _sortOpcion(label: 'Ascendente', subtitle: 'Finalizado → Sin Fecha → X Vencer → Vigente → En Evaluación', icon: Icons.arrow_upward_rounded, selected: provider.estadoSortAsc, onTap: () => context.read<ProyectosProvider>().setEstadoSort(true)),
          ],
        ),
      ),
    );
  }

  Widget _sortOpcion({required String label, required String subtitle, required IconData icon, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { onTap(); Navigator.pop(context); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? kPrimaryColor.withValues(alpha: 0.06) : Colors.white,
          border: Border.all(color: selected ? kPrimaryColor : Colors.grey.shade200, width: selected ? 1.5 : 1.0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: selected ? kPrimaryColor.withValues(alpha: 0.10) : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: selected ? kPrimaryColor : Colors.grey.shade400)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? kPrimaryColor : AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
            ])),
            if (selected) Icon(Icons.check_circle_rounded, size: 18, color: kPrimaryColor),
          ],
        ),
      ),
    );
  }

  void _showFiltersSheet(List<Proyecto> all) {
    final provider = context.read<ProyectosProvider>();
    final instSeen = <String>{};
    final instituciones = <String>[];
    for (final p in all) {
      final norm = ProyectoDisplayUtils.cleanInst(p.institucion).trim().toUpperCase();
      if (norm.isEmpty) continue;
      if (instSeen.add(norm)) instituciones.add(ProyectoDisplayUtils.cleanInst(p.institucion));
    }
    instituciones.sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void applyAndRefresh(VoidCallback fn) { fn(); setSheet(() {}); }
          final activeCount = provider.activeFilterCount;

          return DraggableScrollableSheet(
            initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.92, expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                  child: Column(children: [
                    Center(child: Container(width: 32, height: 3, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Row(children: [
                        Text('Filtros', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (activeCount > 0) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(10)), child: Text('$activeCount', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)))],
                      ])),
                      if (activeCount > 0) TextButton(onPressed: () => applyAndRefresh(() => provider.clearFilters()), child: Text('Limpiar', style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade400))),
                      IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx), color: Colors.grey.shade500),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ]),
                ),
                Expanded(child: ListView(controller: scrollCtrl, padding: const EdgeInsets.fromLTRB(24, 16, 24, 32), children: _buildFilterContent(ctx, applyAndRefresh))),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildFilterContent(BuildContext ctx, void Function(VoidCallback) applyAndRefresh) {
    final provider = context.watch<ProyectosProvider>();
    return buildFilterContentList(ctx, provider, applyAndRefresh);
  }

  Widget _buildEmptyState() => Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 64), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.folder_outlined, size: 56, color: Colors.grey.shade300),
    const SizedBox(height: 12),
    Text('No hay proyectos', style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
    const SizedBox(height: 4),
    Text('Crea el primer proyecto con el botón "Nuevo Proyecto"', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
  ])));

  /// Dado un listado de proyectos (page), elimina entradas que son
  /// miembros de una cadena ya representada por otro proyecto en la misma lista.
  /// Mantiene siempre el proyecto más reciente como representante del grupo.
  List<Proyecto> _deduplicateChains(List<Proyecto> items, List<Proyecto> all) {
    final itemIds = items.map((p) => p.id).toSet();
    final processed = <String>{};
    final result = <Proyecto>[];

    for (final p in items) {
      if (processed.contains(p.id)) continue;
      // BFS restringido solo a los proyectos que están en la página
      final chainIds = resolveChainIds(p.id, all);
      final chainInPage = items.where((x) => chainIds.contains(x.id)).toList();
      if (chainInPage.length <= 1) {
        // No hay duplicado en esta página — incluir tal cual
        processed.add(p.id);
        result.add(p);
      } else {
        // Varios miembros de la misma cadena en la página — elegir el head (más reciente)
        for (final id in chainInPage.map((x) => x.id)) processed.add(id);
        chainInPage.sort((a, b) => (b.fechaInicio ?? b.fechaCreacion ?? DateTime(0))
            .compareTo(a.fechaInicio ?? a.fechaCreacion ?? DateTime(0)));
        result.add(chainInPage.first);
      }
    }
    // Preservar el orden original para los no-deduplicados
    final resultIds = result.map((p) => p.id).toSet();
    return items.where((p) => resultIds.contains(p.id)).toList();
  }

  Widget _buildDesktopTable(List<Proyecto> items) {
    final provider = context.watch<ProyectosProvider>();
    final all = provider.proyectos;
    final deduped = _deduplicateChains(items, all);
    const cols = ['Institución', 'Productos', 'Valor Mensual', 'Fecha de Inicio', 'Fecha de Término'];
    final flexes = [5, 2, 2, 2, 2];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(children: cols.asMap().entries.map((e) {
            final colIdx = e.key;
            final isActive = provider.sortColumn == colIdx;
            final isCentered = colIdx >= 2;
            return Expanded(flex: flexes[colIdx], child: GestureDetector(onTap: () => provider.setSort(colIdx), child: Row(
              mainAxisAlignment: isCentered ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
              Flexible(child: Text(e.value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? kPrimaryColor : Colors.grey.shade500), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 3),
              Icon(isActive ? (provider.sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more, size: 13, color: isActive ? kPrimaryColor : Colors.grey.shade300),
            ])));
          }).toList()),
        ),
        ...deduped.asMap().entries.map((entry) => DevTooltip(
          filePath: 'lib/widgets/proyectos_tab.dart',
          description: 'Fila desktop de proyecto (_DesktopTableRow)',
          child: _DesktopTableRow(
            proyecto: entry.value,
            flexes: flexes,
            isLast: entry.key == deduped.length - 1,
            onOpenEditDialog: widget.onOpenEditDialog,
          ),
        )),
      ]),
    );
  }

  Widget _buildMobileCards(List<Proyecto> items) {
    if (items.isEmpty) return _buildEmptyState();
    final all = context.read<ProyectosProvider>().proyectos;
    final deduped = _deduplicateChains(items, all);
    return Column(children: deduped.map((p) => DevTooltip(
      filePath: 'lib/widgets/proyectos_tab.dart',
      description: 'Card mobile de proyecto (_MobileCard)',
      child: _MobileCard(
        proyecto: p,
        all: all,
        onOpenEditDialog: widget.onOpenEditDialog,
        onShowEstadoPicker: widget.onShowEstadoPicker,
      ),
    )).toList());
  }

  Widget _buildPagination() {
    final provider = context.watch<ProyectosProvider>();
    final totalPages = provider.totalPages;
    final totalItems = provider.filteredProyectos.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Página ${provider.currentPage + 1} de $totalPages  ($totalItems proyectos)', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(width: 16),
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: provider.currentPage > 0 ? () => context.read<ProyectosProvider>().setPage(provider.currentPage - 1) : null, color: kPrimaryColor),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: provider.currentPage < totalPages - 1 ? () => context.read<ProyectosProvider>().setPage(provider.currentPage + 1) : null, color: kPrimaryColor),
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _MobileCard extends StatefulWidget {
  final Proyecto proyecto;
  final List<Proyecto> all;
  final Future<void> Function(Proyecto, {String? tab}) onOpenEditDialog;
  final Future<void> Function(Proyecto) onShowEstadoPicker;

  const _MobileCard({
    required this.proyecto,
    required this.all,
    required this.onOpenEditDialog,
    required this.onShowEstadoPicker,
  });

  @override
  State<_MobileCard> createState() => _MobileCardState();
}

class _MobileCardState extends State<_MobileCard> {
  bool _expanded = false;
  late List<Proyecto> _chainedProyectos;

  @override
  void initState() {
    super.initState();
    _chainedProyectos = _buildChainedProyectos();
  }

  @override
  void didUpdateWidget(_MobileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.proyecto != widget.proyecto || oldWidget.all != widget.all) {
      _chainedProyectos = _buildChainedProyectos();
    }
  }

  // Build full chain via bidirectional BFS, sorted newest → oldest, excluding p itself
  List<Proyecto> _buildChainedProyectos() {
    final p = widget.proyecto;
    final all = widget.all;
    final chainIds = resolveChainIds(p.id, all);
    final result = all
        .where((x) => chainIds.contains(x.id) && x.id != p.id)
        .toList();
    result.sort((a, b) => (b.fechaInicio ?? b.fechaCreacion ?? DateTime(0))
        .compareTo(a.fechaInicio ?? a.fechaCreacion ?? DateTime(0)));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proyecto;
    final cfgEstados = context.read<ProyectosProvider>().config.estados;
    final idLabel = ProyectoDisplayUtils.projectDisplayId(p);
    final chainedProyectos = _chainedProyectos;
    final hasChains = chainedProyectos.isNotEmpty;

    Widget cardContent = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            Expanded(child: ProjectStatusDisplay(proyecto: p, cfgEstados: cfgEstados, showLabel: true, onTap: (proj) => widget.onShowEstadoPicker(proj))),
            const SizedBox(width: 8),
            if (hasChains)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              if (idLabel != null) Text(idLabel, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400), overflow: TextOverflow.ellipsis),
              Text(p.modalidadCompra, style: GoogleFonts.inter(fontSize: 9, color: Colors.grey.shade300), overflow: TextOverflow.ellipsis),
            ]),
          ]),
        ),
        // Body
        InkWell(
          onTap: () => widget.onOpenEditDialog(p),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ProyectoDisplayUtils.cleanInst(p.institucion), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (p.productos.isNotEmpty) ...[const SizedBox(height: 4), Text(p.productos, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis)],
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (p.valorMensual != null) Text('\$ ${ProyectoDisplayUtils.fmt(p.valorMensual!.toInt())}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
                if (p.fechaTermino != null) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey.shade400), const SizedBox(width: 4), Text(ProyectoDisplayUtils.formatDate(p.fechaTermino), style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500))]),
              ]),
            ]),
          ),
        ),
        // Expanded chained rows (newest → oldest)
        if (hasChains && _expanded) ...[
          Divider(height: 1, color: Colors.grey.shade100),
          ...chainedProyectos.map((chainP) => InkWell(
            onTap: () => widget.onOpenEditDialog(chainP),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                const Icon(Icons.timeline, size: 13, color: Colors.grey),
                const SizedBox(width: 8),
                _EstadoDot(proyecto: chainP),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ProyectoDisplayUtils.cleanInst(chainP.institucion), style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                  Text([
                    if (ProyectoDisplayUtils.projectDisplayId(chainP) != null) ProyectoDisplayUtils.projectDisplayId(chainP)!,
                    if (chainP.fechaInicio != null && chainP.fechaTermino != null)
                      '${ProyectoDisplayUtils.formatDate(chainP.fechaInicio)} – ${ProyectoDisplayUtils.formatDate(chainP.fechaTermino)}',
                  ].join('  ·  '), style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400), overflow: TextOverflow.ellipsis),
                ])),
                if (chainP.valorMensual != null)
                  Text('\$ ${ProyectoDisplayUtils.fmt(chainP.valorMensual!.toInt())}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
          )),
          const SizedBox(height: 4),
        ],
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: cardContent,
    );
  }
}

class _DesktopTableRow extends StatefulWidget {
  final Proyecto proyecto;
  final List<int> flexes;
  final bool isLast;
  final Future<void> Function(Proyecto) onOpenEditDialog;

  const _DesktopTableRow({
    required this.proyecto,
    required this.flexes,
    required this.isLast,
    required this.onOpenEditDialog,
  });

  @override
  State<_DesktopTableRow> createState() => _DesktopTableRowState();
}

class _DesktopTableRowState extends State<_DesktopTableRow> {
  bool _expanded = false;

  Widget _reclamoBadge(Proyecto p) {
    final hasPendiente = p.reclamos.any((r) => r.estado == 'Pendiente');
    final color = hasPendiente ? AppColors.errorDark : AppColors.success;
    final bg = hasPendiente ? AppColors.errorSurface : AppColors.successSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(hasPendiente ? 'Reclamo pendiente' : 'Reclamo respondido', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _productosCell(String productos) {
    final abrevs = productos.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final cfgProductos = context.read<ProyectosProvider>().config.productos;
    return _ProductosChipsCell(abrevs: abrevs, cfgProductos: cfgProductos);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proyecto;
    final flexes = widget.flexes;
    
    final all = context.read<ProyectosProvider>().proyectos;

    // A project has a visible chain if anything points TO it OR it points to something
    final hasChains =
        all.any((x) => x.proyectoContinuacionIds.contains(p.id)) ||
        p.proyectoContinuacionIds.isNotEmpty;

    final isLastParent = widget.isLast && !_expanded;

    // Build full chain via bidirectional BFS (handles non-linear topologies)
    List<Proyecto> chainedProyectos = [];
    if (hasChains) {
      final chainIds = resolveChainIds(p.id, all);
      final result = all
          .where((x) => chainIds.contains(x.id) && x.id != p.id)
          .toList();
      result.sort((a, b) => (b.fechaInicio ?? b.fechaCreacion ?? DateTime(0))
          .compareTo(a.fechaInicio ?? a.fechaCreacion ?? DateTime(0)));
      chainedProyectos = result;
    }

    final rowContent = InkWell(
      onTap: () => widget.onOpenEditDialog(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: isLastParent ? null : Border(bottom: BorderSide(color: Colors.grey.shade50)), 
          borderRadius: isLastParent ? const BorderRadius.vertical(bottom: Radius.circular(12)) : null,
          color: _expanded ? Colors.grey.shade50.withValues(alpha: 0.3) : null,
        ),
        child: Row(children: [
          Expanded(flex: flexes[0], child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (hasChains)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              )
            else
              const SizedBox(width: 28),
            _EstadoDot(proyecto: p),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ProyectoDisplayUtils.cleanInst(p.institucion), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([if (ProyectoDisplayUtils.projectDisplayId(p) != null) ProyectoDisplayUtils.projectDisplayId(p)!, p.modalidadCompra].join(' · '), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400), overflow: TextOverflow.ellipsis),
              if (p.reclamos.isNotEmpty) ...[const SizedBox(height: 4), _reclamoBadge(p)],
            ])),
          ])),
          Expanded(flex: flexes[1], child: _productosCell(p.productos)),
          Expanded(flex: flexes[2], child: Text(p.valorMensual != null ? '\$ ${ProyectoDisplayUtils.fmt(p.valorMensual!.toInt())}' : '—', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
          Expanded(flex: flexes[3], child: Text(ProyectoDisplayUtils.formatDate(p.fechaInicio), textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600))),
          Expanded(flex: flexes[4], child: Text(ProyectoDisplayUtils.formatDate(p.fechaTermino), textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600))),
        ]),
      ),
    );

    if (!hasChains || !_expanded || chainedProyectos.isEmpty) {
      return rowContent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rowContent,
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50.withValues(alpha: 0.5),
            border: widget.isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
            borderRadius: widget.isLast ? const BorderRadius.vertical(bottom: Radius.circular(12)) : null,
          ),
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: chainedProyectos.map((chainP) {
              return InkWell(
                onTap: () => widget.onOpenEditDialog(chainP),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Expanded(flex: flexes[0], child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      const SizedBox(width: 36),
                      const Icon(Icons.timeline, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      _EstadoDot(proyecto: chainP),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ProyectoDisplayUtils.cleanInst(chainP.institucion), style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text([if (ProyectoDisplayUtils.projectDisplayId(chainP) != null) ProyectoDisplayUtils.projectDisplayId(chainP)!, chainP.modalidadCompra].join(' · '), style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400), overflow: TextOverflow.ellipsis),
                      ])),
                    ])),
                    Expanded(flex: flexes[1], child: _productosCell(chainP.productos)),
                    Expanded(flex: flexes[2], child: Text(chainP.valorMensual != null ? '\$ ${ProyectoDisplayUtils.fmt(chainP.valorMensual!.toInt())}' : '—', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                    Expanded(flex: flexes[3], child: Text(ProyectoDisplayUtils.formatDate(chainP.fechaInicio), textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500))),
                    Expanded(flex: flexes[4], child: Text(ProyectoDisplayUtils.formatDate(chainP.fechaTermino), textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500))),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _EstadoDot extends StatelessWidget {
  final Proyecto proyecto;
  const _EstadoDot({required this.proyecto});

  @override
  Widget build(BuildContext context) {
    final cfgEstados = context.read<ProyectosProvider>().config.estados;
    final item = cfgEstados.firstWhere((e) => e.nombre == proyecto.estado, orElse: () => EstadoItem(nombre: proyecto.estado, color: '64748B'));
    return Tooltip(
      message: proyecto.estado,
      preferBelow: true,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]),
      textStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
      child: Container(width: 9, height: 9, decoration: BoxDecoration(color: item.colorValue, shape: BoxShape.circle)),
    );
  }
}

class _ProductosChipsCell extends StatefulWidget {
  final List<String> abrevs;
  final List<ProductoItem> cfgProductos;
  const _ProductosChipsCell({required this.abrevs, required this.cfgProductos});

  @override
  State<_ProductosChipsCell> createState() => _ProductosChipsCellState();
}

class _ProductosChipsCellState extends State<_ProductosChipsCell> {
  final _scrollCtrl = ScrollController();
  bool _hasOverflow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    _scrollCtrl.addListener(_checkOverflow);
  }

  void _checkOverflow() {
    if (!_scrollCtrl.hasClients) return;
    final hasMore = _scrollCtrl.position.maxScrollExtent > 0 && _scrollCtrl.position.pixels < _scrollCtrl.position.maxScrollExtent - 1;
    if (hasMore != _hasOverflow) setState(() => _hasOverflow = hasMore);
  }

  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      SingleChildScrollView(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        child: Row(children: widget.abrevs.map((abv) {
          final cfg = widget.cfgProductos.where((p) => p.abreviatura == abv).firstOrNull;
          final bg = cfg != null ? cfg.bgColor : AppColors.background;
          final fg = cfg != null ? cfg.fgColor : AppColors.textMuted;
          return Padding(padding: const EdgeInsets.only(right: 4), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)), child: Text(abv, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: fg))));
        }).toList()),
      ),
      if (_hasOverflow)
        Positioned(right: 0, top: 0, bottom: 0, child: IgnorePointer(child: Container(width: 28, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.85)]))))),
    ]);
  }
}
