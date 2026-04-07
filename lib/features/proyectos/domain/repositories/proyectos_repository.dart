import '../../../../models/configuracion.dart';
import '../../../../models/proyecto.dart';

abstract class ProyectosRepository {
  Future<List<Proyecto>> loadProyectos({bool forceRefresh = false});
  Future<ConfiguracionData> loadConfig();
  Future<List<Map<String, dynamic>>> loadRadarOportunidades({bool forceRefresh = false});
  Future<void> sincronizarPostulacionDesdeOcds(List<Proyecto> proyectos);
  Future<void> updateProyectoEstadoManual(String projectId, String? estadoManual);
}