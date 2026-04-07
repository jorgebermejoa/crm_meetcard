import 'package:flutter/foundation.dart';
import '../../../domain/entities/proyecto_entity.dart';
import '../../../domain/repositories/proyecto_repository.dart';

/// Estado y carga de datos externos: OCDS, Convenio Marco, Órdenes de Compra.
mixin ProyectoExternalDataMixin on ChangeNotifier {
  ProyectoRepository get repository;
  ProyectoEntity get proyecto;
  String? get errorMessage;
  set errorMessage(String? value);

  bool cargandoExternalData = false;
  Map<String, dynamic>? externalApiData;
  DateTime? externalDataLastFetch;

  Map<String, bool> ordenesCompraLoading = {};
  Map<String, Map<String, dynamic>> ordenesData = {};
  Map<String, String> ordenesError = {};

  Future<void> cargarOcds({bool forceRefresh = false}) async {
    if (cargandoExternalData) return;
    cargandoExternalData = true;
    notifyListeners();
    try {
      if (proyecto.idLicitacion?.isNotEmpty == true || proyecto.urlConvenioMarco?.isNotEmpty == true) {
        externalApiData = await repository.getExternalApiData(
          proyecto.id,
          idLicitacion: proyecto.idLicitacion,
          urlConvenioMarco: proyecto.urlConvenioMarco,
          forceRefresh: forceRefresh,
        );
        externalDataLastFetch = DateTime.now();
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      cargandoExternalData = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> cargarOrdenCompra(String idOC, {bool forceRefresh = false}) async {
    if (ordenesCompraLoading[idOC] == true) return null;
    ordenesCompraLoading[idOC] = true;
    notifyListeners();
    try {
      final data = await repository.getOrdenCompra(idOC, proyectoId: proyecto.id, forceRefresh: forceRefresh);
      ordenesData[idOC] = data;
      ordenesError.remove(idOC);
      notifyListeners();
      return data;
    } catch (e) {
      ordenesError[idOC] = e.toString();
      errorMessage = e.toString();
      notifyListeners();
      return null;
    } finally {
      ordenesCompraLoading[idOC] = false;
      notifyListeners();
    }
  }
}
