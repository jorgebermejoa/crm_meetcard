import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/detalle_proyecto_provider.dart';
import 'tabs/tab_proyecto.dart';
import 'tabs/tab_licitacion.dart';
import 'tabs/tab_foro.dart';
import 'tabs/tab_oc.dart';
import 'tabs/tab_analisis_bq.dart';
import 'tabs/tab_certificados.dart';
import 'tabs/tab_reclamos.dart';
import 'tabs/tab_documentos.dart';

class DetalleTabs extends StatefulWidget {
  const DetalleTabs({super.key});

  @override
  State<DetalleTabs> createState() => _DetalleTabsState();
}

class _DetalleTabsState extends State<DetalleTabs> with TickerProviderStateMixin {
  TabController? _tabController;
  int _lastTabCount = 0;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _updateTabController(int count) {
    if (_lastTabCount != count) {
      _tabController?.dispose();
      _tabController = TabController(length: count, vsync: this);
      _lastTabCount = count;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final proyecto = provider.proyecto;
        final licitacionId = proyecto.idLicitacion;

        // Definimos las pestañas dinámicamente
        final List<Tab> tabs = [
          const Tab(text: 'Proyecto'),
        ];
        final List<Widget> contents = [
          const TabProyecto(),
        ];

        if (licitacionId != null && licitacionId.isNotEmpty) {
          tabs.add(const Tab(text: 'Licitación'));
          contents.add(const TabLicitacion());
          
          tabs.add(const Tab(text: 'Foro'));
          contents.add(const TabForo());

          tabs.add(const Tab(text: 'OC'));
          contents.add(const TabOC());
          
          tabs.add(const Tab(text: 'Análisis BQ'));
          contents.add(const TabAnalisisBq());
        }

        tabs.add(const Tab(text: 'Certificados'));
        contents.add(const TabCertificados());

        tabs.add(const Tab(text: 'Reclamos'));
        contents.add(const TabReclamos());

        tabs.add(const Tab(text: 'Documentos'));
        contents.add(const TabDocumentos());

        // Aseguramos que el controlador esté sincronizado
        _updateTabController(tabs.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFF007AFF),
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: const Color(0xFF007AFF),
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              tabs: tabs,
            ),
            const SizedBox(height: 24),
            // Usamos un Switch o IndexedStack para el contenido de las pestañas
            // para evitar problemas con el TabBarView dentro de un ListView
            AnimatedBuilder(
              animation: _tabController!,
              builder: (context, child) {
                final index = _tabController!.index;
                if (index >= contents.length) return const SizedBox.shrink();
                return contents[index];
              },
            ),
          ],
        );
      },
    );
  }
}
