import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:myapp/features/proyecto/presentation/widgets/campo_editable.dart';

class TabProyecto extends StatelessWidget {
  const TabProyecto({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final proyecto = provider.proyecto;

        return Column(
          children: [
            // Basic Info Section
            _buildSection(context, 'DATOS BÁSICOS', [
              CampoEditable(
                label: 'INSTITUCIÓN',
                valor: proyecto.institucion,
                campoDb: 'institucion',
                onSave: (val) => provider.editField('institucion', val, 'Institución'),
              ),
              const Divider(height: 1, indent: 16),
              CampoEditable(
                label: 'PRODUCTOS / SERVICIOS',
                valor: proyecto.productos,
                campoDb: 'productos',
                maxLines: 3,
                onSave: (val) => provider.editField('productos', val, 'Productos'),
              ),
              const Divider(height: 1, indent: 16),
              CampoEditable(
                label: 'MODALIDAD',
                valor: proyecto.modalidadCompra,
                campoDb: 'modalidadCompra',
                onSave: (val) => provider.editField('modalidadCompra', val, 'Modalidad'),
              ),
            ]),
            const SizedBox(height: 20),

            // Financial & Dates Section
            _buildSection(context, 'VALORES Y FECHAS', [
              CampoEditable(
                label: 'VALOR MENSUAL',
                valor: proyecto.valorMensual != null ? '\$ ${provider.fmt(proyecto.valorMensual)}' : '—',
                campoDb: 'valorMensual',
                isNumeric: true,
                onSave: (val) => provider.editField('valorMensual', val, 'Valor mensual'),
              ),
              const Divider(height: 1, indent: 16),
              CampoEditable(
                label: 'FECHA INICIO',
                valor: provider.fmtDateStr(proyecto.fechaInicio?.toIso8601String()),
                campoDb: 'fechaInicio',
                isDate: true,
                onSave: (val) => provider.editField('fechaInicio', val, 'Fecha Inicio'),
              ),
              const Divider(height: 1, indent: 16),
              CampoEditable(
                label: 'FECHA TÉRMINO',
                valor: provider.fmtDateStr(proyecto.fechaTermino?.toIso8601String()),
                campoDb: 'fechaTermino',
                isDate: true,
                onSave: (val) => provider.editField('fechaTermino', val, 'Fecha Término'),
              ),
            ]),
            const SizedBox(height: 20),

            // Purchase Order Section
            _buildSection(context, 'ORDEN DE COMPRA', [
              CampoEditable(
                label: 'ID ORDEN DE COMPRA',
                valor: proyecto.idsOrdenesCompra.isNotEmpty ? proyecto.idsOrdenesCompra.join(', ') : '—',
                campoDb: 'idsOrdenesCompra',
                isList: true,
                onSave: (val) => provider.editField('idsOrdenesCompra', val, 'IDs Órdenes de Compra'),
              ),
              const Divider(height: 1, indent: 16),
              CampoEditable(
                label: 'MONTO TOTAL OC',
                valor: proyecto.montoTotalOC != null ? '\$ ${provider.fmt(proyecto.montoTotalOC)}' : '—',
                campoDb: 'montoTotalOC',
                isNumeric: true,
                onSave: (val) => provider.editField('montoTotalOC', val, 'Monto Total OC'),
              ),
            ]),
            const SizedBox(height: 48),
          ],
        );
      },
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
