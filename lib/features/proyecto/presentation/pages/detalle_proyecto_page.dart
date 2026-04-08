import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../../domain/repositories/proyecto_repository.dart';
import '../../../../core/utils/responsive_helper.dart';
import '../../../../core/utils/string_utils.dart';
import '../../../../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../providers/detalle_proyecto_provider.dart';
import '../widgets/header_section.dart';
import '../widgets/cadena_timeline.dart';
import '../widgets/detalle_tabs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/shared/dev_tooltip.dart';
import '../../../../widgets/proyecto_form_dialog.dart';
import '../../../../models/proyecto.dart';

class DetalleProyectoPage extends StatefulWidget {
  /// ID del proyecto (siempre disponible desde la URL).
  final String proyectoId;

  /// Entidad pasada via `extra` en la navegación — evita un fetch en el caso
  /// normal (navegación interna). Null cuando se llega por URL directa / refresh.
  final ProyectoEntity? proyectoFromExtra;
  final String? initialTabName;

  /// Repositorio inyectado desde main.dart (no disponible en context en ese momento).
  final ProyectoRepository repository;

  const DetalleProyectoPage({
    super.key,
    required this.proyectoId,
    required this.repository,
    this.proyectoFromExtra,
    this.initialTabName,
  });

  @override
  State<DetalleProyectoPage> createState() => _DetalleProyectoPageState();
}

class _DetalleProyectoPageState extends State<DetalleProyectoPage> {
  ProyectoEntity? _proyecto;
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.proyectoFromExtra != null) {
      _proyecto = widget.proyectoFromExtra;
      // Actualizar URL canónica si llegamos sin modalidad en la ruta
      WidgetsBinding.instance.addPostFrameCallback((_) => _replaceCanonicalUrl());
    } else {
      _fetchProyecto();
    }
  }

  /// Devuelve el contract ID canónico para la URL (licitacion / CM / fallback firestoreId).
  String _contractId(ProyectoEntity p) => contractIdForUrl(
    p.id,
    idLicitacion: p.idLicitacion,
    idCotizacion: p.idCotizacion,
    urlConvenioMarco: p.urlConvenioMarco,
  );

  /// Navega (replace) a la URL canónica /:modalidad/:contractId
  void _replaceCanonicalUrl() {
    if (!mounted) return;
    final p = _proyecto;
    if (p == null) return;
    final slug = modalidadSlug(p.modalidadCompra);
    final cid  = _contractId(p);
    final canonical = '/proyectos/$slug/$cid';
    final current = GoRouterState.of(context).uri.path;
    if (current != canonical) {
      context.replace(canonical, extra: {
        'proyecto': p,
        if (widget.initialTabName != null) 'tab': widget.initialTabName,
      });
    }
  }

  Future<void> _fetchProyecto() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      // El :id de la URL es el contract ID — buscar primero por ese campo.
      // Si no hay match (proyecto sin licitacion/CM id), intentar como Firestore doc ID.
      ProyectoEntity? p = await widget.repository.getProyectoByContractId(widget.proyectoId);
      p ??= await widget.repository.getProyecto(widget.proyectoId);
      if (!mounted) return;
      setState(() { _proyecto = p; _loading = false; });
      _replaceCanonicalUrl();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadError = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        appBar: AppBar(
          title: const Text('Detalle de Proyecto'),
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        appBar: AppBar(
          title: const Text('Detalle de Proyecto'),
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _fetchProyecto, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final proyecto = _proyecto!;
    final proyectosProvider = context.read<ProyectosProvider>();

    return ChangeNotifierProvider(
      key: ValueKey(proyecto.id),
      create: (ctx) {
        final provider = DetalleProyectoProvider(
          repository: ctx.read<ProyectoRepository>(),
          proyecto: proyecto,
          initialTabName: widget.initialTabName,
        );
        provider.onMutated = () => proyectosProvider.cargar(forceRefresh: true);
        return provider..init();
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        appBar: AppBar(
          title: const Text('Detalle de Proyecto'),
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar proyecto',
                onPressed: () {
                  // Convertir ProyectoEntity a Proyecto
                  final proyectoEditar = Proyecto(
                    id: proyecto.id,
                    institucion: proyecto.institucion,
                    modalidadCompra: proyecto.modalidadCompra,
                    productos: proyecto.productos,
                    valorMensual: proyecto.valorMensualEfectivo,
                    idLicitacion: proyecto.idLicitacion,
                    idCotizacion: proyecto.idCotizacion,
                    urlConvenioMarco: proyecto.urlConvenioMarco,
                    notas: proyecto.notas,
                    fechaInicio: proyecto.fechaInicio,
                    fechaTermino: proyecto.fechaTermino,
                  );
                  
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => ProyectoFormDialog(
                      isEditing: true,
                      proyecto: proyectoEditar,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        body: const _DetalleProyectoBody(),
      ),
    );
  }
}

class _DetalleProyectoBody extends StatefulWidget {
  const _DetalleProyectoBody();

  @override
  State<_DetalleProyectoBody> createState() => _DetalleProyectoBodyState();
}

class _DetalleProyectoBodyState extends State<_DetalleProyectoBody> {
  String? _lastShownError;

  void _onProviderChange() {
    final provider = context.read<DetalleProyectoProvider>();
    final error = provider.errorMessage;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            ),
          ),
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<DetalleProyectoProvider>()
      ..removeListener(_onProviderChange)
      ..addListener(_onProviderChange);
  }

  @override
  void dispose() {
    context.read<DetalleProyectoProvider>().removeListener(_onProviderChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final hPad = ResponsiveHelper.getHorizontalPadding(context);

    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        alignment: Alignment.topCenter,
        padding: EdgeInsets.symmetric(
          horizontal: hPad,
          vertical: isMobile ? 16 : 32,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DevTooltip(
              filePath: 'lib/features/proyecto/presentation/widgets/header_section.dart',
              description: 'Encabezado del proyecto — estado, institución, acciones',
              child: HeaderSection(),
            ),
            SizedBox(height: 32),
            DevTooltip(
              filePath: 'lib/features/proyecto/presentation/widgets/cadena_timeline.dart',
              description: 'Línea de tiempo de encadenamiento y sugerencias',
              child: CadenaTimeline(),
            ),
            SizedBox(height: 32),
            DevTooltip(
              filePath: 'lib/features/proyecto/presentation/widgets/detalle_tabs.dart',
              description: 'Tabs del detalle del proyecto',
              child: DetalleTabs(),
            ),
          ],
        ),
      ),
    );
  }
}
