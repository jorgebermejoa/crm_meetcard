import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../models/proyecto.dart';
import '../../../proyectos/presentation/providers/proyectos_provider.dart';
import '../providers/productos_provider.dart';
import '../../../../widgets/radar_tab.dart' show RadarKpiRow;
import '../../../../widgets/charts/facturacion_chart_card.dart';
import '../../../../widgets/charts/clientes_chart_card.dart';
import '../../../../widgets/shared/dev_tooltip.dart';

class ProductosPage extends StatefulWidget {
  const ProductosPage({super.key});

  @override
  State<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends State<ProductosPage> {
  final _productosProvider = ProductosProvider();

  @override
  void initState() {
    super.initState();
    // Iniciar carga en base al proveedor de proyectos principal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final proyectos = context.read<ProyectosProvider>().proyectos;
      _productosProvider.updateProyectos(proyectos);
    });
  }

  @override
  void dispose() {
    _productosProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Escuchar cambios en los proyectos
    final proyectos = context.watch<ProyectosProvider>().proyectos;
    if (_productosProvider.productosNombres.isEmpty && proyectos.isNotEmpty) {
      _productosProvider.updateProyectos(proyectos);
    }

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;
    final padding = isMobile ? 16.0 : 32.0;

    return ChangeNotifierProvider.value(
      value: _productosProvider,
      child: Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Desempeño por Producto',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: -0.5,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: AppColors.border, height: 1),
          ),
        ),
        body: Consumer<ProductosProvider>(
          builder: (context, provider, child) {
            if (provider.productosNombres.isEmpty) {
              return const Center(child: Text('No hay productos disponibles'));
            }

            final selectedSet = provider.selectedProductos;
            final proyectosFiltrados = provider.proyectosDeProductosSeleccionados;
            final dashboardTitle = selectedSet.length == 1 
                ? selectedSet.first 
                : '${selectedSet.length} Productos seleccionados';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selector de productos (Tabs simulados o scrollable row)
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: provider.productosNombres.map((prod) {
                        final isSelected = selectedSet.contains(prod);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(prod),
                            selected: isSelected,
                            onSelected: (v) => provider.toggleProducto(prod),
                            showCheckmark: false,
                            backgroundColor: const Color(0xFFF2F2F7), // Apple's systemGray6
                            selectedColor: const Color(0xFF1C1C1E), // Near black
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF1C1C1E) : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            labelStyle: GoogleFonts.inter(
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              fontSize: 13,
                              letterSpacing: -0.2,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                
                // Dashboard del producto seleccionado
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(padding),
                    child: DevTooltip(
                      filePath: 'lib/features/productos/presentation/pages/productos_page.dart',
                      description: 'Dashboard de producto: $dashboardTitle',
                      child: _ProductoDashboard(
                        productoName: dashboardTitle,
                        proyectos: proyectosFiltrados,
                        isMobile: isMobile,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductoDashboard extends StatelessWidget {
  final String productoName;
  final List<Proyecto> proyectos;
  final bool isMobile;

  const _ProductoDashboard({
    required this.productoName,
    required this.proyectos,
    required this.isMobile,
  });

  static String _fmtMonto(double n) {
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(0)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    // Calcular KPIs
    final enCurso = proyectos.where((p) => p.estadoManual == 'En Evaluación').length;
    final ganados = proyectos
        .where((p) =>
            p.estado == EstadoProyecto.vigente ||
            p.estado == EstadoProyecto.xVencer ||
            p.estado == EstadoProyecto.finalizado)
        .length;
    final total = ganados + enCurso;
    final winRate = total > 0 ? ganados / total * 100.0 : 0.0;
    final montoActivo = proyectos
        .where((p) =>
            p.estado == EstadoProyecto.vigente ||
            p.estado == EstadoProyecto.xVencer)
        .fold<double>(0, (sum, p) => sum + (p.valorMensual ?? 0));

    const h = 280.0;
    final fact = SizedBox(
      height: h,
      child: FacturacionChartCard(proyectos: proyectos),
    );
    final cli = SizedBox(
      height: h,
      child: ClientesChartCard(proyectos: proyectos),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPIs Row
        RadarKpiRow(
          ganados: ganados,
          perdidos: 0,
          enCurso: enCurso,
          winRate: winRate,
          montoGanado: montoActivo,
          fmtMonto: _fmtMonto,
          isMobile: isMobile,
        ),
        const SizedBox(height: 24),
        
        // Charts Row
        if (isMobile)
          Column(children: [fact, const SizedBox(height: 12), cli])
        else
          Row(children: [
            Expanded(child: fact),
            const SizedBox(width: 14),
            Expanded(child: cli),
          ]),
      ],
    );
  }
}
