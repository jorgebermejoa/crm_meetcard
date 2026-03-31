import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/core/utils/responsive_helper.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';

class TabLicitacion extends StatefulWidget {
  const TabLicitacion({super.key});

  @override
  State<TabLicitacion> createState() => _TabLicitacionState();
}

class _TabLicitacionState extends State<TabLicitacion> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<DetalleProyectoProvider>(context, listen: false);
      if (provider.externalApiData == null && !provider.cargandoExternalData) {
        provider.cargarOcds();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DetalleProyectoProvider>(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final proyecto = provider.proyecto;

    if (proyecto.idLicitacion?.isNotEmpty != true && proyecto.urlConvenioMarco?.isNotEmpty != true) {
      return _buildNoIdState(provider);
    }

    if (provider.cargandoExternalData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Use externalApiData as the fallback 
    if (provider.externalApiData == null) {
      return _buildErrorState(provider);
    }

    // Modalidad check for display
    final isCM = proyecto.urlConvenioMarco?.isNotEmpty == true || proyecto.modalidadCompra.contains('Convenio Marco');
    
    if (isCM) {
      return _buildConvenioMarcoSection(context, provider.externalApiData!, isMobile, provider);
    }

    return _buildMpApiSection(context, provider.externalApiData!, isMobile, provider);
  }

  Widget _buildNoIdState(DetalleProyectoProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Sin ID de licitación registrado',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Edita el proyecto y agrega el ID para cargar los datos (Mercado Público).',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.cargarOcds(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(DetalleProyectoProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red.shade200),
            const SizedBox(height: 16),
            Text(
              provider.errorMessage ?? 'No se pudieron cargar los datos',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => provider.cargarOcds(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMpApiSection(BuildContext context, Map<String, dynamic> data, bool isMobile, DetalleProyectoProvider provider) {
    // Try both Listado (old MP API) and releases (Modern OCDS API) structures
    final listado = (data['Listado'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (listado.isEmpty && releases.isEmpty) {
      return const Center(child: Text('Sin datos de API Mercado Público (OCDS)'));
    }

    final Map<String, dynamic> item;
    final Map<String, dynamic> comprador;
    final Map<String, dynamic> fechas;

    if (listado.isNotEmpty) {
      // Logic for old API format
      item = listado.first;
      comprador = item['Comprador'] as Map<String, dynamic>? ?? {};
      fechas = item['Fechas'] as Map<String, dynamic>? ?? {};
    } else {
      // Logic for OCDS format (releases[0])
      final release = releases.first;
      final tender = release['tender'] as Map<String, dynamic>? ?? {};
      final buyer = release['buyer'] as Map<String, dynamic>? ?? {};
      final parties = (release['parties'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      
      // Find procuringEntity in parties if missing in tender
      final entity = tender['procuringEntity'] as Map<String, dynamic>? ?? 
                    parties.firstWhere((p) => (p['roles'] as List?)?.contains('procuringEntity') ?? false, orElse: () => {});

      item = {
        'Nombre': tender['title']?.toString() ?? 'Sin título',
        'CodigoExterno': release['ocid']?.toString().split('-').last ?? tender['id']?.toString() ?? 'S/C',
        'Estado': tender['status']?.toString() ?? 'S/E',
        'Tipo': tender['procurementMethodDetails']?.toString() ?? tender['mainProcurementCategory']?.toString() ?? 'S/T',
        'MontoEstimado': tender['value']?['amount'],
        'Moneda': tender['value']?['currency'],
      };

      comprador = {
        'NombreOrganismo': entity['name']?.toString() ?? buyer['name']?.toString() ?? 'No disponible',
        'DireccionUnidad': entity['address']?['streetAddress']?.toString() ?? 'No disponible',
        'ComunaUnidad': entity['address']?['locality']?.toString() ?? 'No disponible',
        'RegionUnidad': entity['address']?['region']?.toString() ?? 'No disponible',
      };

      fechas = {
        'FechaPublicacion': tender['tenderPeriod']?['startDate'] ?? release['date'],
        'FechaInicio': tender['tenderPeriod']?['startDate'],
        'FechaCierre': tender['tenderPeriod']?['endDate'],
        'FechaEstimadaAdjudicacion': tender['awardPeriod']?['startDate'],
      };
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRefreshBar(provider),
          const SizedBox(height: 16),
          _buildSourceWarning(listado.isNotEmpty ? 'Datos de API Mercado Público (Legacy).' : 'Datos de API Mercado Público (OCDS).'),
          const SizedBox(height: 16),
          _buildInfoCard(context, 'Licitación', [
            ('Nombre', item['Nombre']?.toString()),
            ('Código', item['CodigoExterno']?.toString()),
            ('Estado', item['Estado']?.toString()),
            ('Tipo', item['Tipo']?.toString()),
            ('Monto estimado', item['MontoEstimado'] != null ? '${provider.fmt(item['MontoEstimado'])} ${item['Moneda'] ?? ''}' : null),
          ], provider),
          _buildInfoCard(context, 'Comprador', [
            ('Organismo', comprador['NombreOrganismo']?.toString()),
            ('Dirección', comprador['DireccionUnidad']?.toString()),
            ('Comuna', comprador['ComunaUnidad']?.toString()),
            ('Región', comprador['RegionUnidad']?.toString()),
          ], provider),
          _buildInfoCard(context, 'Fechas', [
            ('Publicación', provider.fmtDateStr(fechas['FechaPublicacion']?.toString())),
            ('Inicio', provider.fmtDateStr(fechas['FechaInicio']?.toString())),
            ('Cierre', provider.fmtDateStr(fechas['FechaCierre']?.toString())),
            ('Adjudicación (est.)', provider.fmtDateStr(fechas['FechaEstimadaAdjudicacion']?.toString())),
          ], provider),
        ],
      ),
    );
  }

  Widget _buildConvenioMarcoSection(BuildContext context, Map<String, dynamic> data, bool isMobile, DetalleProyectoProvider provider) {
    // Structure from obtainDetalleConvenioMarco scraper
    final nombre = data['nombre_convenio']?.toString();
    final organismo = data['organismo']?.toString();
    final idConvenio = data['id_convenio']?.toString();
    final vigencia = data['vigencia_hasta']?.toString();
    final campos = (data['campos'] as Map?)?.cast<String, dynamic>() ?? {};

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRefreshBar(provider),
          const SizedBox(height: 16),
          _buildSourceWarning('Datos extraídos de Ficha Convenio Marco.'),
          const SizedBox(height: 16),
          _buildInfoCard(context, 'Convenio Marco', [
            ('Nombre', nombre),
            ('ID Convenio', idConvenio),
            ('Vigencia hasta', vigencia),
            ('Organismo', organismo),
          ], provider),
          if (campos.isNotEmpty)
            _buildInfoCard(context, 'Campos Extraídos', 
              campos.entries.map((e) => (e.key, e.value?.toString())).toList(), 
              provider
            ),
        ],
      ),
    );
  }

  Widget _buildRefreshBar(DetalleProyectoProvider provider) {
    return Row(
      children: [
        Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(
          'Actualizado: ${provider.fmtDateStr(provider.externalDataLastFetch?.toIso8601String())}',
          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => provider.cargarOcds(forceRefresh: true),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
          child: Text(
            'Actualizar ahora',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, List<(String, String?)> rows, DetalleProyectoProvider provider) {
    final visible = rows.where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
          ),
          const Divider(height: 1),
          ...visible.map((r) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(r.$1, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                    ),
                    Expanded(
                      child: Text(r.$2!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF334155))),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
