import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'global_search_bar.dart';
import 'licitaciones_table.dart';
import 'detalle_licitacion.dart';

class BusquedaView extends StatefulWidget {
  final VoidCallback? onOpenMenu;

  const BusquedaView({super.key, this.onOpenMenu});

  @override
  State<BusquedaView> createState() => _BusquedaViewState();
}

class _BusquedaViewState extends State<BusquedaView> {
  // Estado para la tabla de resultados
  List<LicitacionUI> _licitaciones = [];
  bool _cargando = false;

  // Estado para el sidebar
  Map<String, dynamic>? _licitacionSeleccionada;

  Future<void> _ejecutarBusqueda(String query) async {
    if (query.isEmpty) return;

    setState(() => _cargando = true);

    try {
      final url = Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/buscarLicitacionesAI?q=${Uri.encodeComponent(query)}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> data;
        if (decoded is List) {
          data = decoded;
        } else if (decoded is Map) {
          data = (decoded['resultados'] as List?) ?? [];
        } else {
          data = [];
        }

        if (mounted) {
          setState(() {
            _licitaciones = data.map((item) {
              final mapItem = item as Map<String, dynamic>;
              return LicitacionUI(
                mapItem['id']?.toString() ?? 'S/I',
                mapItem['titulo']?.toString() ?? 'Sin título',
                mapItem['descripcion']?.toString() ?? 'Sin descripción',
                mapItem['fechaPublicacion']?.toString() ?? 'S/F',
                mapItem['fechaCierre']?.toString() ?? 'S/F',
                rawData: mapItem,
              );
            }).toList();
          });
        }
      } else {
        debugPrint("Error del servidor: ${response.statusCode} — ${response.body}");
      }
    } catch (e, stack) {
      debugPrint("Error de búsqueda: $e\n$stack");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _limpiarBusqueda() {
    setState(() {
      _licitaciones = [];
      _licitacionSeleccionada = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < 700;
          final double padding = isMobile ? 20 : 64;

          // En móvil: el sidebar ocupa toda la pantalla cuando está abierto
          if (isMobile && _licitacionSeleccionada != null) {
            return DetalleLicitacionSidebar(
              rawData: _licitacionSeleccionada!,
              onClose: () => setState(() => _licitacionSeleccionada = null),
            );
          }

          final bool showHeader = constraints.maxHeight > 340;
          final double vGap = constraints.maxHeight < 500 ? 12 : (isMobile ? 20 : 32);

          final searchPanel = SelectionArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: isMobile ? 20 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.onOpenMenu != null) ...[
                          IconButton(
                            onPressed: widget.onOpenMenu,
                            icon: const Icon(Icons.menu),
                            tooltip: 'Menú',
                            color: Colors.grey.shade700,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Inteligencia de Licitaciones',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 22 : 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Búsqueda semántica impulsada por Vertex AI',
                                style: GoogleFonts.inter(fontSize: isMobile ? 13 : 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: vGap),
                  ],
                  GlobalSearchBar(
                    onSearch: _ejecutarBusqueda,
                    onClear: _limpiarBusqueda,
                  ),
                  SizedBox(height: vGap),
                  Expanded(
                    child: _cargando
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                  child: LicitacionesTable(
                                    licitaciones: _licitaciones,
                                    onSelected: (lic) {
                                      setState(() => _licitacionSeleccionada = lic);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );

          // Desktop: buscador + sidebar en fila
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: _licitacionSeleccionada == null ? 1 : 2,
                child: searchPanel,
              ),
              if (_licitacionSeleccionada != null)
                DetalleLicitacionSidebar(
                  rawData: _licitacionSeleccionada!,
                  onClose: () => setState(() => _licitacionSeleccionada = null),
                ),
            ],
          );
        },
      ),
    );
  }
}
