import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/proyecto.dart';
import 'radar_tab.dart';
import '../core/theme/app_colors.dart';

class RadarView extends StatefulWidget {
  const RadarView({super.key});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> {
  @override
  void initState() {
    super.initState();
    // Asegurar que Radar está cargado
    final provider = context.read<ProyectosProvider>();
    provider.cargarRadar(forceRefresh: false);
  }

  static String _fmtMonto(double n) {
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  void _goToProyectosFiltered(
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
    // Navegar a Proyectos
    context.go('/proyectos');
  }

  void _goToChurnFiltered(int year, int quarter) {
    context.read<ProyectosProvider>().setQuarterFilter(year, quarter, isChurn: true);
    // Navegar a Proyectos
    context.go('/proyectos');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;
    final hPad = isMobile ? 20.0 : 32.0;

    return Container(
      color: AppColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobileLayout = constraints.maxWidth < 900;

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 32),
                  child: RadarTab(
                    isMobile: isMobileLayout,
                    onGoToQuarterFiltered: _goToProyectosFiltered,
                    onGoToChurnQuarterFiltered: _goToChurnFiltered,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
