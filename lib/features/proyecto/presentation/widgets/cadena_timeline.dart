import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../providers/detalle_proyecto_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/proyecto_display_utils.dart';
import '../../../../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../../../../models/proyecto.dart';
import '../../../../services/upload_service.dart';
import 'package:web/web.dart' as web;
import 'sugerencias_cadena_section.dart';
import '../../../../widgets/shared/dev_tooltip.dart';
import '../../../../core/utils/string_utils.dart';

/// Public helper so other widgets (e.g. TabDocumentos) can open the edit sheet.
Future<void> showAumentoEditSheet(
  BuildContext context,
  DetalleProyectoProvider provider,
  AumentoEntity aumento,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AgregarAumentoSheet(provider: provider, existing: aumento),
  );
}

class CadenaTimeline extends StatelessWidget {
  const CadenaTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DetalleProyectoProvider>();

    if (provider.cadenaLoading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final cadena = provider.cadena;
    final sucesores = provider.sucesores;
    final anyAumentos = [...cadena, ...sucesores].any((p) => p.aumentos.isNotEmpty);
    final hasChain = cadena.length > 1 || sucesores.isNotEmpty || anyAumentos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasChain)
          DevTooltip(
            filePath: 'lib/features/proyecto/presentation/widgets/cadena_timeline.dart',
            description: 'Línea de tiempo de la cadena de proyectos (_CadenaCard)',
            child: _CadenaCard(cadena: cadena, sucesores: sucesores, provider: provider),
          ),
        Row(
          children: [
            _EncadenarButton(provider: provider),
            _AgregarAumentoButton(provider: provider),
          ],
        ),
        DevTooltip(
          filePath: 'lib/features/proyecto/presentation/widgets/sugerencias_cadena_section.dart',
          description: 'Sección de sugerencias de encadenamiento (SugerenciasCadenaSection)',
          child: SugerenciasCadenaSection(proyectoId: provider.proyecto.id),
        ),
      ],
    );
  }
}

// ── Chain card ────────────────────────────────────────────────────────────────

class _CadenaCard extends StatelessWidget {
  final List<ProyectoEntity> cadena;
  final List<ProyectoEntity> sucesores;
  final DetalleProyectoProvider provider;

  const _CadenaCard({
    required this.cadena,
    required this.sucesores,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    // Unified chain: all projects (cadena + sucesores) sorted newest → oldest
    final sucesorIds = sucesores.map((s) => s.id).toSet();
    final allProjects = <ProyectoEntity>{...cadena, ...sucesores}.toList()
      ..sort((a, b) => (b.fechaInicio ?? b.fechaCreacion ?? DateTime(0))
          .compareTo(a.fechaInicio ?? a.fechaCreacion ?? DateTime(0)));

    // Count: (other projects in chain) + (current project's aumentos)
    final totalAumentos = provider.proyecto.aumentos.length;
    final totalRenovaciones = (allProjects.length - 1) + totalAumentos;
    final renovLabel = '$totalRenovaciones renovación${totalRenovaciones != 1 ? 'es' : ''}';

    // Build flat list of nodes (aumentos BEFORE their project, newest→oldest)
    final nodes = <Widget>[];
    for (int i = 0; i < allProjects.length; i++) {
      final p = allProjects[i];
      final isSucesor = sucesorIds.contains(p.id);
      final projectAumentos = [...p.aumentos]
        ..sort((a, b) => b.fechaTermino.compareTo(a.fechaTermino));
      // Project node has a line below if there are more projects after it
      final hasMoreBelow = i < allProjects.length - 1;

      // Inject aumentos BEFORE the project node — they represent newer dates
      // than the project's original fechaTermino, so appear above in timeline
      for (final aumento in projectAumentos) {
        nodes.add(_AumentoNodo(
          aumento: aumento,
          projectId: p.id,
          showLine: true, // always connects down to project node below
          provider: provider,
          isCurrentProject: p.id == provider.proyecto.id,
        ));
      }

      if (isSucesor) {
        nodes.add(_SucesorNodo(
          key: ValueKey(p.id),
          proyecto: p,
          proyectoActual: provider.proyecto,
          showLine: hasMoreBelow,
          isLast: !hasMoreBelow,
          onRemove: () => _confirmRemoveSucesor(context, p, provider),
        ));
      } else {
        nodes.add(_AncestorNodo(
          proyecto: p,
          proyectoActual: provider.proyecto,
          showLine: hasMoreBelow,
          isLast: !hasMoreBelow,
        ));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LÍNEA DE TIEMPO',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                renovLabel,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...nodes,
        ],
      ),
    );
  }

  Future<void> _confirmRemoveSucesor(
    BuildContext context,
    ProyectoEntity sucesor,
    DetalleProyectoProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Desvincular sucesor',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          '¿Desvincular "${ProyectoDisplayUtils.cleanInst(sucesor.institucion)}" de la cadena?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: Text('Desvincular',
                style: GoogleFonts.inter(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.removeSucesorCadena(sucesor.id);
    }
  }
}

// ── Ancestor node (navigable, fixed) ─────────────────────────────────────────

class _AncestorNodo extends StatelessWidget {
  final ProyectoEntity proyecto;
  final ProyectoEntity proyectoActual;
  final bool showLine;
  final bool isLast;

  const _AncestorNodo({
    required this.proyecto,
    required this.proyectoActual,
    required this.showLine,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final esAqui = proyecto.id == proyectoActual.id;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineDot(isActive: esAqui, showLine: showLine),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: GestureDetector(
                onTap: esAqui
                    ? null
                    : () {
                        final slug = modalidadSlug(proyecto.modalidadCompra);
                        final cid = contractIdForUrl(proyecto.id, idLicitacion: proyecto.idLicitacion, idCotizacion: proyecto.idCotizacion, urlConvenioMarco: proyecto.urlConvenioMarco);
                        context.push(
                          '/proyectos/$slug/$cid',
                          extra: {'proyecto': proyecto, 'tab': 'Detalle'},
                        );
                      },
                child: _NodoContent(
                  proyecto: proyecto,
                  esAqui: esAqui,
                  showChevron: !esAqui,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sucesores reorderable section ─────────────────────────────────────────────

class _SucesorNodo extends StatelessWidget {
  final ProyectoEntity proyecto;
  final ProyectoEntity proyectoActual;
  final bool showLine;
  final bool isLast;
  final VoidCallback onRemove;

  const _SucesorNodo({
    super.key,
    required this.proyecto,
    required this.proyectoActual,
    required this.showLine,
    required this.isLast,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineDot(isActive: false, showLine: showLine),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final slug = modalidadSlug(proyecto.modalidadCompra);
                        final cid = contractIdForUrl(proyecto.id, idLicitacion: proyecto.idLicitacion, idCotizacion: proyecto.idCotizacion, urlConvenioMarco: proyecto.urlConvenioMarco);
                        context.push(
                          '/proyectos/$slug/$cid',
                          extra: {'proyecto': proyecto, 'tab': 'Detalle'},
                        );
                      },
                      child: _NodoContent(
                        proyecto: proyecto,
                        esAqui: false,
                        showChevron: true,
                      ),
                    ),
                  ),
                  // Remove button
                  Tooltip(
                    message: 'Desvincular',
                    child: InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.link_off_rounded,
                            size: 15, color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(Icons.drag_handle_rounded,
                        size: 18, color: Colors.grey.shade300),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _TimelineDot extends StatelessWidget {
  final bool isActive;
  final bool showLine;

  const _TimelineDot({required this.isActive, required this.showLine});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      child: Column(
        children: [
          Container(
            width: isActive ? 12 : 8,
            height: isActive ? 12 : 8,
            margin: EdgeInsets.only(top: isActive ? 4 : 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.primary : Colors.grey.shade300,
              border: isActive
                  ? Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2), width: 3)
                  : null,
            ),
          ),
          if (showLine)
            Expanded(
              child: Container(width: 1.5, color: Colors.grey.shade200),
            ),
        ],
      ),
    );
  }
}

class _NodoContent extends StatelessWidget {
  final ProyectoEntity proyecto;
  final bool esAqui;
  final bool showChevron;

  const _NodoContent({
    required this.proyecto,
    required this.esAqui,
    required this.showChevron,
  });

  @override
  Widget build(BuildContext context) {
    final contractId = _contractId(proyecto);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ProyectoDisplayUtils.cleanInst(proyecto.institucion),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: esAqui ? FontWeight.w700 : FontWeight.w500,
                  color:
                      esAqui ? AppColors.textPrimary : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatDateRange(proyecto),
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.grey.shade400),
              ),
              if (contractId != null) ...[
                const SizedBox(height: 2),
                Text(
                  contractId,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: esAqui
                        ? AppColors.primary.withValues(alpha: 0.7)
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (proyecto.fromSugerencia) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 9, color: Color(0xFF6366F1)),
                      const SizedBox(width: 3),
                      Text(
                        'Proyecto sugerido',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showChevron)
          Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
      ],
    );
  }

  String? _contractId(ProyectoEntity p) {
    if (p.idLicitacion?.isNotEmpty == true) return p.idLicitacion;
    if (p.idCotizacion?.isNotEmpty == true) return p.idCotizacion;
    if (p.urlConvenioMarco?.isNotEmpty == true) {
      // Show only last segment of CM URL as identifier
      final uri = Uri.tryParse(p.urlConvenioMarco!);
      if (uri != null) {
        final seg = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
        if (seg != null) return 'CM: $seg';
      }
      return 'Convenio Marco';
    }
    return null;
  }

  String _formatDateRange(ProyectoEntity p) {
    if (p.fechaInicio == null && p.fechaTermino == null) return 'Sin fechas';
    final start = p.fechaInicio != null ? p.fechaInicio!.year.toString() : '?';
    final end =
        p.fechaTermino != null ? p.fechaTermino!.year.toString() : 'Actual';
    return '$start – $end';
  }
}

// ── Aumento node ─────────────────────────────────────────────────────────────

class _AumentoNodo extends StatelessWidget {
  final AumentoEntity aumento;
  final String projectId;
  final bool showLine;
  final DetalleProyectoProvider provider;
  final bool isCurrentProject;

  const _AumentoNodo({
    required this.aumento,
    required this.projectId,
    required this.showLine,
    required this.provider,
    this.isCurrentProject = false,
  });

  static const _colorPlazo = Color(0xFFF59E0B); // amber
  static const _colorContrato = Color(0xFF8B5CF6); // violet
  static const _colorGrey = Color(0xFF94A3B8); // slate-400

  Color get _activeColor =>
      aumento.tipo == 'aumento_contrato' ? _colorContrato : _colorPlazo;

  Color get _color => isCurrentProject ? _activeColor : _colorGrey;

  @override
  Widget build(BuildContext context) {
    final textColor = isCurrentProject ? AppColors.textPrimary : AppColors.textMuted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AumentoDot(color: _color, showLine: showLine),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Badge row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                aumento.badgeLabel.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // New end date
                        Text(
                          'Hasta ${_fmtDate(aumento.fechaTermino)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        if (aumento.valorMensual != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '\$ ${_fmt(aumento.valorMensual)}/mes',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isCurrentProject ? _colorContrato : _colorGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (aumento.descripcion?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            aumento.descripcion!,
                            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (aumento.documentos.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: aumento.documentos.map((doc) {
                              final label = doc.nombre?.isNotEmpty == true
                                  ? doc.nombre!
                                  : 'Documento';
                              return GestureDetector(
                                onTap: () {
                                  if (doc.url.isNotEmpty) _openUrl(doc.url);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AppColors.border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.attach_file_rounded,
                                          size: 11,
                                          color: AppColors.textMuted),
                                      const SizedBox(width: 4),
                                      Text(
                                        label,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Edit: only for current project
                  if (isCurrentProject)
                    Tooltip(
                      message: 'Editar aumento',
                      child: InkWell(
                        onTap: () => _showEditSheet(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.edit_outlined,
                              size: 15, color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                  // Delete: always shown so accidental augmentos can be removed from any project
                  Tooltip(
                    message: 'Eliminar aumento',
                    child: InkWell(
                      onTap: () => _confirmDelete(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 15, color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openUrl(String url) {
    try {
      // ignore: avoid_web_libraries_in_flutter
      final uri = Uri.parse(url);
      if (uri.hasScheme) {
        // Web: open in new tab
        // ignore: undefined_prefixed_name
        web.window.open(url, '_blank');
      }
    } catch (_) {}
  }

  Future<void> _showEditSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgregarAumentoSheet(
        provider: provider,
        existing: aumento,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Eliminar aumento',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          '¿Eliminar el "${aumento.badgeLabel}" al ${_fmtDate(aumento.fechaTermino)}?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: Text('Eliminar',
                style: GoogleFonts.inter(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await provider.deleteAumentoFromChain(projectId, aumento.id);
    }
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  String _fmt(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }
}

class _AumentoDot extends StatelessWidget {
  final Color color;
  final bool showLine;
  const _AumentoDot({required this.color, required this.showLine});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      child: Column(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: color.withValues(alpha: 0.25), width: 2),
            ),
          ),
          if (showLine)
            Expanded(
              child: Container(
                width: 1.5,
                color: color.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Encadenar button ──────────────────────────────────────────────────────────

class _EncadenarButton extends StatelessWidget {
  final DetalleProyectoProvider provider;

  const _EncadenarButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showEncadenarSheet(context),
      icon: const Icon(Icons.add_link_rounded, size: 16),
      label: Text(
        'Encadenar proyecto',
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Future<void> _showEncadenarSheet(BuildContext context) async {
    final proyectosProvider = context.read<ProyectosProvider>();
    final allProyectos = proyectosProvider.proyectos;

    final linked = {
      provider.proyecto.id,
      ...provider.proyecto.proyectoContinuacionIds,
    };
    final candidates =
        allProyectos.where((p) => !linked.contains(p.id)).toList();

    if (!context.mounted) return;

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EncadenarSheet(candidates: candidates),
    );

    if (selectedId != null) {
      await provider.addSucesorCadena(selectedId);
    }
  }
}

// ── Picker sheet ──────────────────────────────────────────────────────────────

class _EncadenarSheet extends StatefulWidget {
  final List<Proyecto> candidates;

  const _EncadenarSheet({required this.candidates});

  @override
  State<_EncadenarSheet> createState() => _EncadenarSheetState();
}

class _EncadenarSheetState extends State<_EncadenarSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.candidates
        .where((p) =>
            _query.isEmpty ||
            p.institucion.toLowerCase().contains(_query.toLowerCase()) ||
            (p.idLicitacion?.contains(_query) ?? false) ||
            (p.idCotizacion?.contains(_query) ?? false))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Encadenar proyecto sucesor',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Buscar institución o ID…',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 14, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Sin resultados',
                        style: GoogleFonts.inter(
                            fontSize: 14, color: Colors.grey.shade400),
                      ),
                    )
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final contractId = p.idLicitacion ?? p.idCotizacion;
                        return InkWell(
                          onTap: () => Navigator.pop(context, p.id),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ProyectoDisplayUtils.cleanInst(
                                            p.institucion),
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (contractId != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          contractId,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 18,
                                    color: Colors.grey.shade300),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}

// ── Agregar Aumento button ────────────────────────────────────────────────────

class _AgregarAumentoButton extends StatelessWidget {
  final DetalleProyectoProvider provider;
  const _AgregarAumentoButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showAumentoSheet(context),
      icon: const Icon(Icons.expand_circle_down_outlined, size: 16),
      label: Text(
        'Agregar aumento',
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFF59E0B),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Future<void> _showAumentoSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgregarAumentoSheet(provider: provider),
    );
  }
}

// ── Agregar Aumento sheet ─────────────────────────────────────────────────────

class _AgregarAumentoSheet extends StatefulWidget {
  final DetalleProyectoProvider provider;
  final AumentoEntity? existing; // non-null → edit mode

  const _AgregarAumentoSheet({required this.provider, this.existing});

  @override
  State<_AgregarAumentoSheet> createState() => _AgregarAumentoSheetState();
}

class _AgregarAumentoSheetState extends State<_AgregarAumentoSheet> {
  late String _tipo;
  DateTime? _fechaTermino;
  double? _valorMensual;
  late TextEditingController _valorCtrl;
  late TextEditingController _descCtrl;
  String? _docUrl;
  String? _docNombre;
  bool _guardando = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tipo = e?.tipo ?? 'aumento_plazo';
    _fechaTermino = e?.fechaTermino;
    _valorMensual = e?.valorMensual;
    _valorCtrl = TextEditingController(
        text: e?.valorMensual != null ? e!.valorMensual!.toStringAsFixed(0) : '');
    _descCtrl = TextEditingController(text: e?.descripcion ?? '');
    if (e != null && e.documentos.isNotEmpty) {
      _docUrl = e.documentos.first.url;
      _docNombre = e.documentos.first.nombre ?? e.documentos.first.tipo;
    }
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  static const _colorPlazo = Color(0xFFF59E0B);
  static const _colorContrato = Color(0xFF8B5CF6);

  Color get _color => _tipo == 'aumento_contrato' ? _colorContrato : _colorPlazo;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 24),
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isEditing ? 'Editar aumento' : 'Agregar aumento',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Tipo selector
            _sectionLabel('Tipo de aumento'),
            const SizedBox(height: 8),
            Row(
              children: [
                _TipoChip(
                  label: 'Aumento de Plazo',
                  selected: _tipo == 'aumento_plazo',
                  color: _colorPlazo,
                  onTap: () => setState(() => _tipo = 'aumento_plazo'),
                ),
                const SizedBox(width: 10),
                _TipoChip(
                  label: 'Aumento de Contrato',
                  selected: _tipo == 'aumento_contrato',
                  color: _colorContrato,
                  onTap: () => setState(() => _tipo = 'aumento_contrato'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Nueva fecha de término
            _sectionLabel('Nueva fecha de término'),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: widget.provider.proyecto.fechaTerminoEfectiva
                          ?.add(const Duration(days: 1)) ??
                      DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2040),
                  helpText: 'Seleccionar nueva fecha de término',
                );
                if (picked != null) setState(() => _fechaTermino = picked);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: _fechaTermino != null
                      ? _color.withValues(alpha: 0.05)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _fechaTermino != null ? _color.withValues(alpha: 0.3) : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 16,
                        color: _fechaTermino != null ? _color : Colors.grey.shade400),
                    const SizedBox(width: 10),
                    Text(
                      _fechaTermino != null
                          ? '${_fechaTermino!.day}/${_fechaTermino!.month}/${_fechaTermino!.year}'
                          : 'Seleccionar fecha…',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: _fechaTermino != null
                            ? AppColors.textPrimary
                            : Colors.grey.shade400,
                        fontWeight: _fechaTermino != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Nuevo valor mensual (solo para aumento_contrato)
            if (_tipo == 'aumento_contrato') ...[
              _sectionLabel('Nuevo valor mensual (CLP)'),
              const SizedBox(height: 8),
              TextField(
                controller: _valorCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ej: 7500000',
                  hintStyle:
                      GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400),
                  prefixText: '\$ ',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                onChanged: (v) {
                  _valorMensual = double.tryParse(v.replaceAll('.', '').replaceAll(',', '.'));
                },
              ),
              const SizedBox(height: 20),
            ],

            // Descripción opcional
            _sectionLabel('Descripción (opcional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ej: Extensión por decreto N° 1234…',
                hintStyle:
                    GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Documento de respaldo
            _sectionLabel('Documento de respaldo (opcional)'),
            const SizedBox(height: 8),
            if (_docUrl == null)
              _UploadDocRow(
                onUploaded: (url, nombre) =>
                    setState(() { _docUrl = url; _docNombre = nombre; }),
              )
            else
              _AttachedDoc(
                nombre: _docNombre ?? 'Documento',
                onRemove: () => setState(() { _docUrl = null; _docNombre = null; }),
              ),
            const SizedBox(height: 28),

            // Guardar
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _fechaTermino == null || _guardando ? null : _guardar,
                style: FilledButton.styleFrom(
                  backgroundColor: _color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _guardando
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isEditing ? 'Guardar cambios' : 'Guardar aumento',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
          letterSpacing: 0.3,
        ),
      );

  Future<void> _guardar() async {
    if (_fechaTermino == null) return;
    setState(() => _guardando = true);
    final docs = _docUrl != null
        ? [DocumentoEntity(tipo: 'Respaldo', url: _docUrl!, nombre: _docNombre)]
        : <DocumentoEntity>[];
    final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    if (_isEditing) {
      await widget.provider.updateAumentoItem(
        aumentoId: widget.existing!.id,
        tipo: _tipo,
        fechaTermino: _fechaTermino!,
        valorMensual: _tipo == 'aumento_contrato' ? _valorMensual : null,
        documentos: docs,
        descripcion: desc,
        fechaRegistro: widget.existing!.fechaRegistro,
      );
    } else {
      await widget.provider.addAumento(
        tipo: _tipo,
        fechaTermino: _fechaTermino!,
        valorMensual: _tipo == 'aumento_contrato' ? _valorMensual : null,
        documentos: docs,
        descripcion: desc,
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _TipoChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.4) : Colors.grey.shade200,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? color : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadDocRow extends StatefulWidget {
  final void Function(String url, String nombre) onUploaded;
  const _UploadDocRow({required this.onUploaded});

  @override
  State<_UploadDocRow> createState() => _UploadDocRowState();
}

class _UploadDocRowState extends State<_UploadDocRow> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _uploading ? null : _pickAndUpload,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.grey.shade200, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Icon(_uploading ? Icons.hourglass_empty : Icons.attach_file_rounded,
                size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 10),
            Text(
              _uploading ? 'Subiendo…' : 'Adjuntar documento…',
              style: GoogleFonts.inter(
                  fontSize: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _uploading = true);
    try {
      final file = await UploadService.instance.pickFile();
      if (file == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }
      final url = await UploadService.instance.upload(
        bytes: file.bytes,
        filename: file.name,
        storagePath: 'proyectos/aumentos',
      );
      widget.onUploaded(url, file.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir documento: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

class _AttachedDoc extends StatelessWidget {
  final String nombre;
  final VoidCallback onRemove;
  const _AttachedDoc({required this.nombre, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 16, color: Colors.green.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nombre,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 16, color: Colors.green.shade400),
          ),
        ],
      ),
    );
  }
}
