import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/proyectos/data/proyectos_constants.dart';
import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/proyecto.dart';
import 'filter_sheets.dart';
import 'shared/filter_content.dart';
import 'documentacion_tab.dart';
import 'export_utils.dart';
import 'proyecto_form_dialog.dart';
import 'shared/skeleton_loader.dart';
import 'radar_tab.dart';
import 'resumen_tab.dart';
import 'proyectos_tab.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/string_utils.dart';
import 'shared/dev_tooltip.dart';

class ProyectosView extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;

  const ProyectosView({super.key, this.onOpenMenu, this.onBack});

  @override
  State<ProyectosView> createState() => _ProyectosViewState();
}

class _ProyectosViewState extends State<ProyectosView>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Use post-frame callback to access provider safely in initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<ProyectosProvider>();
        provider.cargar();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openCreateDialog() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ProyectoFormDialog(isEditing: false),
    );
    if (result != null) {
      if (!mounted) return;
      context.read<ProyectosProvider>().cargar(forceRefresh: true);
    }
  }

  Future<void> _openEditDialog(Proyecto proyecto, {String? tab}) async {
    final entity = proyecto.toEntity();
    final extra = tab != null ? {'proyecto': entity, 'tab': tab} : {'proyecto': entity};
    final slug = modalidadSlug(proyecto.modalidadCompra);
    final cid = contractIdForUrl(proyecto.id, idLicitacion: proyecto.idLicitacion, idCotizacion: proyecto.idCotizacion, urlConvenioMarco: proyecto.urlConvenioMarco);
    context.go('/proyectos/$slug/$cid', extra: extra);
  }

  List<Proyecto> _getSortedFilteredProyectos(ProyectosProvider provider) {
    final list = provider.filteredProyectos;
    final sorted = [...list];
    // This is a simplified sort that should ideally be in the provider
    // or a shared location. For now, it mirrors the provider's logic.
    sorted.sort((a, b) => (a.fechaCreacion ?? DateTime(0))
        .compareTo(b.fechaCreacion ?? DateTime(0)));
    return sorted;
  }

  void _showExportMenu(BuildContext context) {
    final provider = context.read<ProyectosProvider>();
    final filtered = _getSortedFilteredProyectos(provider);
    final hasFilters = _hasActiveFilters(provider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Exportar proyectos',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${filtered.length} proyecto${filtered.length != 1 ? 's' : ''}${hasFilters ? ' (con filtros aplicados)' : ''}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            _exportOption(
              Icons.table_chart_outlined,
              'Exportar a Excel (CSV)',
              'Abrir en Excel o Google Sheets',
              () {
                Navigator.pop(context);                exportCSV(filtered);
              },
            ),
            const SizedBox(height: 8),
            _exportOption(
              Icons.print_outlined,
              'Imprimir / PDF',
              'Genera una tabla HTML lista para imprimir o guardar como PDF',
              () {
                Navigator.pop(context);                exportPDF(context, filtered);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _hasActiveFilters(ProyectosProvider provider) => provider.hasActiveFilters;

  Widget _exportOption(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: AppColors.surfaceAlt,
      leading: Container(
        padding: const EdgeInsets.all(8), //
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
      ),
      onTap: onTap,
    );
  }

  // ── KPI ROW ───────────────────────────────────────────────────────────────────

  void _goToProyectosFiltered(String? estado) {
    context.read<ProyectosProvider>().setSingleFilter(estado: estado);
    context.read<ProyectosProvider>().setPage(0);
    _tabController.animateTo(1);
  }

  void _goToReclamosFiltered(String reclamo) {
    context.read<ProyectosProvider>().setSingleFilter(reclamo: reclamo);
    context.read<ProyectosProvider>().setPage(0);
    _tabController.animateTo(1);
  }

  void _goToVencerFiltered(int dias) {
    final provider = context.read<ProyectosProvider>();
    final label = switch (dias) {
      30 => '30 días',
      90 => '3 meses',
      180 => '6 meses',
      _ => '12 meses',
    };
    provider.setSingleFilter(vencer: label);
    provider.setPage(0);
    _tabController.animateTo(1);
  }

  void _goToQuarterFiltered(
    int year,
    int quarter, {
    bool onlyWithOC = false,
    bool onlyIngresos = false,
  }) {
    context.read<ProyectosProvider>().setQuarterFilter(
          year,
          quarter,
          onlyWithOC: onlyWithOC,
          onlyIngresos: onlyIngresos,
        );
    _tabController.animateTo(1);
  }

  void _goToChurnQuarterFiltered(int year, int quarter) {
    context.read<ProyectosProvider>().setQuarterFilter(year, quarter, isChurn: true);
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProyectosProvider>();

    return Container(
      color: AppColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 900;
          final isWidescreen = constraints.maxWidth >= 1100;
          final hPad = isMobile ? 20.0 : 32.0;

          if (provider.cargando) {
            final skeletonBody = _buildSkeletonDashboard(hPad, isMobile, isWidescreen);
            return SingleChildScrollView(
              child: isWidescreen
                  ? skeletonBody
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: skeletonBody,
                      ),
                    ),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Error al cargar proyectos',
                    style: GoogleFonts.inter(color: Colors.red.shade600),
                  ), // Consider adding provider.error.toString() here for more detail
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => provider.cargar(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text('Reintentar', style: GoogleFonts.inter()),
                  ),
                ],
              ),
            );
          }

          // Layout Principal
          final content = Padding(
            padding: EdgeInsets.fromLTRB(hPad, isMobile ? 16 : 24, hPad, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tab bar â€” Apple style matching HomeView
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    tabAlignment: TabAlignment.fill,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                    labelColor: kPrimaryColor,
                    unselectedLabelColor: Colors.grey.shade400,
                    indicatorColor: kPrimaryColor,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Resumen'),
                      Tab(text: 'Proyectos'),
                      Tab(text: 'Documentación'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Tab content inline
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (_, __) {
                    final idx = _tabController.index;
                    if (idx == 0) {
                      return DevTooltip(
                        filePath: 'lib/widgets/resumen_tab.dart',
                        description: 'Dashboard — KPIs, gráficos y resumen de cartera',
                        child: ResumenTab(
                          isMobile: isMobile,
                          onGoToProyectosFiltrados: _goToProyectosFiltered,
                          onGoToReclamosFiltrados: _goToReclamosFiltered,
                          onGoToVencerFiltrados: _goToVencerFiltered,
                          onShowExport: () => _showExportMenu(context),
                        ),
                      );
                    }
                    if (idx == 2) {
                      return DevTooltip(
                        filePath: 'lib/widgets/documentacion_tab.dart',
                        description: 'Tab de documentación de proyectos',
                        child: DocumentacionTab(isMobile: isMobile, onOpenEditDialog: _openEditDialog),
                      );
                    }

                    // El Tab de Proyectos es el único que recibe el Split Layout en Widescreen
                    if (isWidescreen) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 280, child: _buildFilterSidebar()),
                          const SizedBox(width: 32),
                          Expanded(
                            child: DevTooltip(
                              filePath: 'lib/widgets/proyectos_tab.dart',
                              description: 'Tabla/lista de proyectos con filtros y paginación',
                              child: ProyectosTab(
                                isMobile: false,
                                hideFilterRow: true,
                                onOpenCreateDialog: _openCreateDialog,
                                onOpenEditDialog: _openEditDialog,
                                onShowEstadoPicker: _showEstadoPicker,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return DevTooltip(
                      filePath: 'lib/widgets/proyectos_tab.dart',
                      description: 'Tabla/lista de proyectos con filtros y paginación',
                      child: ProyectosTab(isMobile: isMobile, onOpenCreateDialog: _openCreateDialog, onOpenEditDialog: _openEditDialog, onShowEstadoPicker: _showEstadoPicker),
                    );
                  },
                ),
              ],
            ),
          );

          final scrollView = SingleChildScrollView(
            child: isWidescreen
                ? content
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: content,
                    ),
                  ),
          );

          if (isWidescreen) return scrollView;

          return RefreshIndicator(
            onRefresh: () => provider.cargar(forceRefresh: true),
            color: kPrimaryColor,
            child: scrollView,
          );
        },
      ),
    );
  }


  Future<void> _showEstadoPicker(Proyecto proyecto) async {
    final nuevoEstado = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EstadoPickerSheet(
        proyecto: proyecto, 
        cfgEstados: context.read<ProyectosProvider>().config.estados,
      ),
    );
    if (nuevoEstado == null) return;
    if (!mounted) return;
    final valor = nuevoEstado.isEmpty ? null : nuevoEstado;
    await context.read<ProyectosProvider>().updateProyectoEstadoManual(proyecto.id, valor);
  }


  Widget _buildFilterSidebar() {
    final provider = context.watch<ProyectosProvider>();
    final activeCount = provider.activeFilterCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Text(
                  'Filtros',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textApple,
                    letterSpacing: -0.5,
                  ),
                ),
                if (activeCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
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
                const Spacer(),
                if (activeCount > 0)
                  GestureDetector( //
                    onTap: () => provider.clearFilters(),
                    child: Text(
                      'Limpiar',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // We use a Column inside a single child view, or shrinkWrap the list
          ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20), //
            children: _buildFilterContentList(context, (fn) => setState(fn)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilterContentList(
    BuildContext ctx,
    void Function(VoidCallback) applyAndRefresh,
  ) {
    final provider = context.watch<ProyectosProvider>();
    return buildFilterContentList(ctx, provider, applyAndRefresh);
  }





}

// â”€â”€ Reclamos Carousel Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€ Skeleton loading â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€


Widget _buildSkeletonDashboard(double hPad, bool isMobile, bool isWidescreen) {
  const hGap = SizedBox(width: 14);
  const vGap12 = SizedBox(height: 12);
  const vGap20 = SizedBox(height: 20);

  // ── Primitives ──────────────────────────────────────────────────────────────

  Widget skCard({required double height, List<Widget> children = const []}) =>
      Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  // KPI card: label + big number + bottom bar
  Widget kpiCard() => skCard(
        height: isMobile ? 90 : 110,
        children: [
          SkeletonBox(width: 56, height: 9, radius: 4),
          const SizedBox(height: 10),
          SkeletonBox(width: 100, height: 26, radius: 6),
          const Spacer(),
          SkeletonBox(height: 7, radius: 4),
        ],
      );

  // ── KPI ROW ─────────────────────────────────────────────────────────────────

  Widget kpiRow() {
    if (isMobile) {
      // 2 × 2 grid
      return Column(
        children: [
          Row(children: [
            Expanded(child: kpiCard()),
            hGap,
            Expanded(child: kpiCard()),
          ]),
          vGap12,
          Row(children: [
            Expanded(child: kpiCard()),
            hGap,
            Expanded(child: kpiCard()),
          ]),
        ],
      );
    }
    // Desktop / tablet: 4 in a row
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: kpiCard()),
          hGap,
          Expanded(child: kpiCard()),
          hGap,
          Expanded(child: kpiCard()),
          hGap,
          Expanded(child: kpiCard()),
        ],
      ),
    );
  }

  // ── SUMMARY CHIP ROW ────────────────────────────────────────────────────────

  Widget summaryRow() => Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: SkeletonBox(height: 11, radius: 5)),
            Container(width: 1, height: 20, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 12)),
            Expanded(child: SkeletonBox(height: 11, radius: 5)),
            Container(width: 1, height: 20, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 12)),
            Expanded(child: SkeletonBox(height: 11, radius: 5)),
          ],
        ),
      );

  // ── CHARTS ──────────────────────────────────────────────────────────────────

  Widget chartsRow() {
    final h = isMobile ? 160.0 : 200.0;
    Widget chart() => skCard(
          height: h,
          children: [
            Row(children: [
              SkeletonBox(width: 70, height: 10, radius: 4),
              const Spacer(),
              SkeletonBox(width: 40, height: 10, radius: 4),
            ]),
            const SizedBox(height: 12),
            Expanded(child: SkeletonBox(height: double.infinity, radius: 8)),
          ],
        );
    if (isMobile) {
      return Column(children: [chart(), vGap12, chart()]);
    }
    return SizedBox(
      height: h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: chart()), hGap, Expanded(child: chart())],
      ),
    );
  }

  // ── GANTT SECTION ───────────────────────────────────────────────────────────

  Widget ganttHeader() => Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SkeletonBox(width: 80, height: 10, radius: 4),
            const Spacer(),
            SkeletonBox(width: 28, height: 28, radius: 8),
            const SizedBox(width: 8),
            SkeletonBox(width: 28, height: 28, radius: 8),
          ],
        ),
      );

  // Gantt timeline bar: left label + color bar at variable offset
  Widget ganttRow(double barStart, double barWidth, Color barColor) => Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Left label area
            SizedBox(
              width: isMobile ? 80 : 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SkeletonBox(width: isMobile ? 60 : 120, height: 10, radius: 4),
                  const SizedBox(height: 5),
                  SkeletonBox(width: isMobile ? 40 : 80, height: 7, radius: 3),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Timeline track
            Expanded(
              child: LayoutBuilder(
                builder: (_, bc) {
                  final total = bc.maxWidth;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(height: 8, decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(4))),
                      Positioned(
                        left: total * barStart,
                        child: Container(
                          width: total * barWidth,
                          height: 16,
                          decoration: BoxDecoration(
                            color: barColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );

  final ganttColors = [
    AppColors.success,
    AppColors.warning,
    AppColors.indigo,
    AppColors.success,
    AppColors.warning,
  ];
  final barStarts  = [0.05, 0.20, 0.40, 0.10, 0.30];
  final barWidths  = [0.30, 0.25, 0.35, 0.40, 0.20];

  Widget ganttRows() => Column(
        children: [
          for (int i = 0; i < 5; i++)
            ganttRow(barStarts[i], barWidths[i], ganttColors[i]),
        ],
      );

  // ── ASSEMBLE ────────────────────────────────────────────────────────────────

  return Padding(
    padding: EdgeInsets.fromLTRB(hPad, isMobile ? 80 : 24, hPad, 48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1 · Tab bar
        Container(
          height: 44,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(children: [
            Expanded(child: SkeletonBox(height: 30, radius: 8)),
            hGap,
            Expanded(child: SkeletonBox(height: 30, radius: 8)),
            hGap,
            Expanded(child: SkeletonBox(height: 30, radius: 8)),
            hGap,
            Expanded(child: SkeletonBox(height: 30, radius: 8)),
          ]),
        ),
        vGap20,
        // 2 · KPI cards
        kpiRow(),
        vGap12,
        // 3 · Summary chips row
        summaryRow(),
        vGap20,
        // 4 · Charts
        chartsRow(),
        vGap20,
        // 5 · Gantt header + rows
        ganttHeader(),
        const SizedBox(height: 10),
        ganttRows(),
      ],
    ),
  );
}
