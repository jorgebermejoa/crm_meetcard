import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../../domain/repositories/proyecto_repository.dart';
import '../../../../core/utils/responsive_helper.dart';
import '../providers/detalle_proyecto_provider.dart';
import '../widgets/header_section.dart';
import '../widgets/cadena_timeline.dart';
import '../widgets/detalle_tabs.dart';

class DetalleProyectoPage extends StatelessWidget {
  final ProyectoEntity proyecto;
  final String? initialTabName;

  const DetalleProyectoPage({super.key, required this.proyecto, this.initialTabName});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => DetalleProyectoProvider(
        repository: context.read<ProyectoRepository>(),
        proyecto: proyecto,
        initialTabName: initialTabName,
      )..init(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Detalle de Proyecto'),
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
        ),
        body: const _DetalleProyectoBody(),
      ),
    );
  }
}

class _DetalleProyectoBody extends StatelessWidget {
  const _DetalleProyectoBody();

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final hPad = ResponsiveHelper.getHorizontalPadding(context);

    // Using MediaQuery for full width minus constraints
    return SingleChildScrollView(
      child: Container(
        width: double.infinity, // Consume todo el ancho disponible
        alignment: Alignment.topCenter,
        padding: EdgeInsets.symmetric(
          horizontal: hPad,
          vertical: isMobile ? 16 : 32,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeaderSection(),
            SizedBox(height: 32),
            CadenaTimeline(),
            SizedBox(height: 32),
            DetalleTabs(),
          ],
        ),
      ),
    );
  }
}
