import 'package:flutter/foundation.dart';
import '../../../domain/entities/proyecto_entity.dart';
import '../../../domain/repositories/proyecto_repository.dart';

/// Estado y carga de análisis BigQuery.
mixin ProyectoAnalisisMixin on ChangeNotifier {
  ProyectoRepository get repository;
  ProyectoEntity get proyecto;

  bool analisisCargando = false;
  String? analisisError;
  List<Map<String, dynamic>> competidores = [];
  List<Map<String, dynamic>> ganadorOcs = [];
  List<Map<String, dynamic>> predicciones = [];
  String? nombreGanador;
  String? rutGanador;
  String? permanenciaGanador;
  String? rutOrganismo;
  List<Map<String, dynamic>> historialGanador = [];

  Future<void> cargarAnalisisBq({bool forceRefresh = false}) async {
    if (analisisCargando) return;
    analisisCargando = true;
    analisisError = null;
    notifyListeners();

    try {
      final res = await repository.getAnalisisBq(proyecto.id);
      competidores = List<Map<String, dynamic>>.from(res['competidores'] ?? []);
      ganadorOcs = List<Map<String, dynamic>>.from(res['ganador_ocs'] ?? []);
      predicciones = List<Map<String, dynamic>>.from(res['predicciones'] ?? []);
      nombreGanador = res['nombre_ganador'];
      rutGanador = res['rut_ganador'];
      permanenciaGanador = res['permanencia_ganador'];
      rutOrganismo = res['rut_organismo'];
      historialGanador = List<Map<String, dynamic>>.from(res['historial_ganador'] ?? []);
    } catch (e) {
      analisisError = e.toString();
    } finally {
      analisisCargando = false;
      notifyListeners();
    }
  }
}
