import 'package:flutter/material.dart';

// El modelo de datos se mantiene intacto
class LicitacionUI {
  final String id;
  final String titulo;
  final String descripcion;
  final String fechaCierre;

  LicitacionUI(this.id, this.titulo, this.descripcion, this.fechaCierre);
}

class LicitacionesTable extends StatelessWidget {
  final List<LicitacionUI> licitaciones;

  const LicitacionesTable({super.key, required this.licitaciones});

  @override
  Widget build(BuildContext context) {
    // El contenedor principal (Fondo gris claro)
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8), // Tono off-white/gris muy sutil
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Pestañas Superiores (Tabs visuales)
          Row(
            children: [
              _buildTab('Resumen', isActive: false),
              const SizedBox(width: 8),
              _buildTab('Licitaciones Activas', isActive: true),
              const SizedBox(width: 8),
              _buildTab('Historial General', isActive: false),
            ],
          ),
          
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 24),

          // 2. Encabezados de la lista
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('ID Licitación', style: _headerStyle())),
                Expanded(flex: 3, child: Text('Título', style: _headerStyle())),
                Expanded(flex: 4, child: Text('Descripción', style: _headerStyle())),
                Expanded(flex: 2, child: Text('Cierre', style: _headerStyle())),
              ],
            ),
          ),
          
          const SizedBox(height: 8),

          // 3. Filas de datos (Tarjetas blancas)
          Expanded(
            child: ListView.separated(
              itemCount: licitaciones.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final lic = licitaciones[index];
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    // Una sombra levísima para despegar la tarjeta del fondo
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Usamos 'flex' para distribuir el espacio proporcionalmente
                      Expanded(
                        flex: 2, 
                        child: Text(lic.id, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
                      ),
                      Expanded(
                        flex: 3, 
                        child: Text(lic.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          lic.descripcion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                      Expanded(
                        flex: 2, 
                        child: Text(lic.fechaCierre, style: TextStyle(color: Colors.grey.shade700)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Widget auxiliar para construir las pestañas estilo "píldora"
  Widget _buildTab(String text, {required bool isActive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE2E8F0) : Colors.transparent, // Gris claro si está activa
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          color: isActive ? Colors.black87 : Colors.grey.shade600,
        ),
      ),
    );
  }

  // Estilo estandarizado para los encabezados
  TextStyle _headerStyle() {
    return TextStyle(
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade600,
      fontSize: 14,
    );
  }
}