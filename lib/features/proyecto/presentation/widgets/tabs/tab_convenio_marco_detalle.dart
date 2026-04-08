import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../../providers/detalle_proyecto_provider.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../widgets/shared/skeleton_loader.dart';

class TabConvenioMarcoDetalle extends StatefulWidget {
  const TabConvenioMarcoDetalle({super.key});

  @override
  State<TabConvenioMarcoDetalle> createState() =>
      _TabConvenioMarcoDetalleState();
}

class _TabConvenioMarcoDetalleState extends State<TabConvenioMarcoDetalle>
    with SingleTickerProviderStateMixin {
  static const _cf =
      'https://us-central1-licitaciones-prod.cloudfunctions.net';
  static const _primary = AppColors.primary;

  late TabController _tabController;
  bool _cargandoDetalles = false;
  Map<String, dynamic>? _detalles;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Intentar cargar del Provider cache de forma síncrona antes del primer build
    try {
      final provider = context.read<DetalleProyectoProvider>();
      final detallesEnCache = provider.obtenerConvenioMarcoDetalles();
      if (detallesEnCache != null && detallesEnCache.isNotEmpty) {
        _detalles = detallesEnCache;
        _cargandoDetalles = false;
        debugPrint('[TabConvenioMarco] Cache provisto en initState, sin parpadeo');
      }
    } catch (e) {
      debugPrint('[TabConvenioMarco] No se pudo leer Provider en initState: $e');
    }
    
    _cargarDetalles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDetalles() async {
    final provider = context.read<DetalleProyectoProvider>();
    final proyectoId = provider.proyecto.id ?? '';
    final url = provider.proyecto.urlConvenioMarco ?? '';
    
    if (url.isEmpty || proyectoId.isEmpty) {
      debugPrint('[TabConvenioMarco] URL o proyectoId vacío');
      return;
    }

    // Si ya tenemos datos en el estado local (cargado desde Provider en initState), 
    // solo verificar que las fechas estén actualizadas
    if (_detalles != null && _detalles!.isNotEmpty) {
      debugPrint('[TabConvenioMarco] Datos ya disponibles, solo actualizando fechas');
      _actualizarFechasDelProyecto(_detalles!);
      return;
    }

    setState(() => _cargandoDetalles = true);
    try {
      // Paso 1: Buscar en Firestore
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('convenio_marco_detalles').doc(proyectoId);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final storedData = docSnapshot.data() as Map<String, dynamic>;
        final timestamp = storedData['timestamp'] as Timestamp?;
        
        // Verificar si el cache es reciente (menos de 24 horas)
        if (timestamp != null) {
          final storedTime = timestamp.toDate();
          final edad = DateTime.now().difference(storedTime);
          
          if (edad.inHours < 24) {
            debugPrint('[TabConvenioMarco] Datos encontrados en Firestore (${edad.inMinutes} min)');
            final detalles = Map<String, dynamic>.from(storedData);
            detalles.remove('timestamp');
            if (mounted) setState(() => _detalles = detalles);
            provider.guardarConvenioMarcoDetalles(detalles);
            _actualizarFechasDelProyecto(detalles);
            if (mounted) setState(() => _cargandoDetalles = false);
            return;
          }
        }
      }

      // Paso 2: Si no existe en Firestore o es viejo, hacer fetch HTTP
      debugPrint('[TabConvenioMarco] Fetching desde Cloud Function');
      final uri = Uri.parse(
        '$_cf/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(url)}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      
      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        
        // Paso 3: Guardar en Firestore
        data['timestamp'] = FieldValue.serverTimestamp();
        await docRef.set(data, SetOptions(merge: true));
        debugPrint('[TabConvenioMarco] Detalles guardados en Firestore');
        
        data.remove('timestamp');
        setState(() => _detalles = data);
        provider.guardarConvenioMarcoDetalles(data);
        _actualizarFechasDelProyecto(data);
      } else {
        debugPrint('[TabConvenioMarco] Error HTTP ${resp.statusCode}: ${resp.body}');
        if (mounted) {
          setState(() => _detalles = {'error': 'HTTP ${resp.statusCode}'});
        }
      }
    } on TimeoutException catch (e) {
      debugPrint('[TabConvenioMarco] Timeout: $e');
      if (mounted) {
        setState(() => _detalles = {'error': 'Timeout al cargar datos'});
      }
    } catch (e) {
      debugPrint('[TabConvenioMarco] Error: $e');
      if (mounted) {
        setState(() => _detalles = {'error': e.toString()});
      }
    } finally {
      if (mounted) setState(() => _cargandoDetalles = false);
    }
  }

  void _actualizarFechasDelProyecto(Map<String, dynamic> detalles) {
    try {
      if (!mounted) return;
      
      final campos = (detalles['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (campos.isEmpty) {
        debugPrint('[TabConvenioMarco] Sin campos para extraer fechas');
        return;
      }

      final fechas = _extraerFechas(campos);

      // Buscar fechas de publicación y cierre
      DateTime? fechaPublicacion;
      DateTime? fechaCierre;

      // Publicación: buscar "Publicación" o "Inicio Publicación"
      final pubStr = fechas['Publicación'];
      if (pubStr != null && pubStr.isNotEmpty) {
        fechaPublicacion = _parseFecha(pubStr);
        debugPrint('[TabConvenioMarco] Fecha Publicación parseada: $fechaPublicacion de "$pubStr"');
      }

      // Cierre: buscar "Cierre de Publicación" o "Fin Publicación"
      final cierreStr = fechas['Cierre de Publicación'];
      if (cierreStr != null && cierreStr.isNotEmpty) {
        fechaCierre = _parseFecha(cierreStr);
        debugPrint('[TabConvenioMarco] Fecha Cierre parseada: $fechaCierre de "$cierreStr"');
      }

      // Si se encontraron fechas, actualizar el provider
      if ((fechaPublicacion != null || fechaCierre != null) && mounted) {
        try {
          final provider = context.read<DetalleProyectoProvider>();
          provider.actualizarFechasConvenioMarco(fechaPublicacion, fechaCierre);
          debugPrint('[TabConvenioMarco] Fechas actualizado en el proyecto');
        } catch (e) {
          debugPrint('[TabConvenioMarco] Error al leer provider: $e');
        }
      }
    } catch (e) {
      debugPrint('[TabConvenioMarco] Error al actualizar fechas: $e');
    }
  }

  DateTime? _parseFecha(String fechaStr) {
    if (fechaStr.isEmpty) return null;

    try {
      final cleaned = fechaStr.trim();

      // Formato dd/MM/yyyy (con o sin hora)
      if (cleaned.contains('/')) {
        final datePart = cleaned.split(' ')[0];
        final parts = datePart.split('/');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]) ?? 0;
          final month = int.tryParse(parts[1]) ?? 0;
          final year = int.tryParse(parts[2]) ?? 0;
          if (day > 0 && month > 0 && year > 0) {
            return DateTime(year, month, day);
          }
        }
      }

      // Formato con guiones - detectar si es DD-MM-YYYY o YYYY-MM-DD
      if (cleaned.contains('-')) {
        final datePart = cleaned.split(' ')[0];
        final parts = datePart.split('-');
        if (parts.length == 3) {
          final p0 = int.tryParse(parts[0]) ?? 0;
          final p1 = int.tryParse(parts[1]) ?? 0;
          final p2 = int.tryParse(parts[2]) ?? 0;

          int day, month, year;

          // Detectar el formato basándose en los valores
          if (p2 > 999) {
            // DD-MM-YYYY (el año es parts[2])
            day = p0;
            month = p1;
            year = p2;
          } else if (p0 > 999) {
            // YYYY-MM-DD (el año es parts[0])
            year = p0;
            month = p1;
            day = p2;
          } else {
            // No se puede determinar, no parsear
            debugPrint('[TabConvenioMarco] Formato de fecha confuso: $cleaned');
            return null;
          }

          if (day > 0 && month > 0 && year > 0 && month <= 12 && day <= 31) {
            return DateTime(year, month, day);
          }
        }
      }

      // Intenta DateTime.parse como último recurso
      return DateTime.tryParse(cleaned);
    } catch (e) {
      debugPrint('[TabConvenioMarco] Error parseando fecha "$fechaStr": $e');
      return null;
    }
  }

  void _abrirEnMercadoPublico() {
    final provider = context.read<DetalleProyectoProvider>();
    final url = provider.proyecto.urlConvenioMarco;
    if (url != null && url.isNotEmpty) {
      web.window.open(url, '_blank');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si aún está cargando, mostrar skeleton
    if (_cargandoDetalles || _detalles == null) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 12),
              SizedBox(height: 10),
              SkeletonBox(width: 150, height: 14),
            ],
          ),
        ),
      );
    }

    // Determinar cuál contenido mostrar basado en el tab seleccionado
    final isCalendarioTab = _tabController.index == 1;
    final mainContent = isCalendarioTab
        ? _panelCalendario()
        : _panelInformacion();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 24),
          // TabBar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w400),
              labelColor: _primary,
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: _primary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Información'),
                Tab(text: 'Calendario'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Contenido del tab - usa AnimatedBuilder para actualizar solo este widget
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return _tabController.index == 1
                  ? _panelCalendario()
                  : _panelInformacion();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final titulo = _detalles?['titulo'] ?? _detalles?['id'] ?? 'Convenio Marco';
    final comprador = _detalles?['comprador'] ?? 'Institución';
    final estado = _detalles?['estado'] ?? 'Desconocido';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comprador,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _estadoColor(estado).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _estadoColor(estado),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _abrirEnMercadoPublico,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.open_in_new, size: 12, color: _primary),
                  const SizedBox(width: 4),
                  Text('Abrir en Mercado Público',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _estadoColor(String estado) {
    final lower = estado.toLowerCase();
    if (lower.contains('finalizada') || lower.contains('adjudicada')) {
      return AppColors.success;
    } else if (lower.contains('revocada') || lower.contains('desierta')) {
      return Colors.orange;
    } else if (lower.contains('desestimada')) {
      return Colors.red;
    } else if (lower.contains('evaluación') || lower.contains('abierta')) {
      return _primary;
    }
    return Colors.grey;
  }

  Widget _panelInformacion() {
    // Si aún está cargando
    if (_cargandoDetalles) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 12),
              SizedBox(height: 10),
              SkeletonBox(width: 150, height: 14),
            ],
          ),
        ),
      );
    }

    // Si no hay detalles después de cargar, mostrar error
    if (_detalles == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'No se pudieron cargar los detalles',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final campos =
        (_detalles?['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (campos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Sin información disponible',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    // Mostrar en 2 columnas
    final columnasSize = (campos.length / 2).ceil();
    final column1 = campos.sublist(0, columnasSize);
    final column2 = campos.sublist(columnasSize);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: column1.map((c) => _campoCarta(c)).toList(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: column2.map((c) => _campoCarta(c)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoCarta(Map<String, dynamic> campo) {
    final label = campo['label']?.toString() ?? 'Campo';
    final valor = campo['valor']?.toString() ?? '';

    if (valor.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 0.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              valor,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelCalendario() {
    if (_cargandoDetalles && _detalles == null) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 12),
              SizedBox(height: 10),
              SkeletonBox(width: 150, height: 14),
            ],
          ),
        ),
      );
    }

    final campos =
        (_detalles?['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final fechas = _extraerFechas(campos);

    if (fechas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Sin fechas disponibles',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final fechasList = fechas.entries.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: fechasList.asMap().entries.map(
          (e) {
            final isLast = e.key == fechasList.length - 1;
            return _timelineItem(e.value, isLast);
          },
        ).toList(),
      ),
    );
  }

  Map<String, String> _extraerFechas(List<Map<String, dynamic>> campos) {
    final fechas = <String, String>{};
    for (final c in campos) {
      final label = c['label']?.toString().toLowerCase() ?? '';
      final valor = c['valor']?.toString() ?? '';
      if (valor.isEmpty) continue;

      if (label.contains('inicio') && label.contains('publicac')) {
        fechas['Publicación'] = valor;
      } else if (label.contains('fin') && label.contains('publicac')) {
        fechas['Cierre de Publicación'] = valor;
      } else if (label.contains('inicio') && label.contains('evaluaci')) {
        fechas['Inicio Evaluación'] = valor;
      } else if (label.contains('fin') && label.contains('evaluaci')) {
        fechas['Fin Evaluación'] = valor;
      } else if (label.contains('plazo') && label.contains('evaluaci')) {
        fechas['Plazo Evaluación'] = valor;
      } else if (label.contains('plazo') && label.contains('publicaci')) {
        fechas['Plazo Publicación'] = valor;
      } else if (label.contains('vigencia') && label.contains('contratos')) {
        fechas['Vigencia Contrato'] = valor;
      } else if (label.contains('vigencia') && label.contains('cotizaci')) {
        fechas['Vigencia Cotización'] = valor;
      } else if (label.contains('plazo') && label.contains('preguntas')) {
        fechas['Plazo Preguntas'] = valor;
      }
    }
    return fechas;
  }

  Widget _timelineItem(MapEntry<String, String> item, bool isLast) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: _primary.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.key,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textPrimary,
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
}
