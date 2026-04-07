import '../../../../models/configuracion.dart';
import '../../../../models/proyecto.dart';
import '../../domain/repositories/proyectos_repository.dart';
import '../datasources/proyectos_remote_datasource.dart';

class ProyectosRepositoryImpl implements ProyectosRepository {
  final ProyectosRemoteDatasource remoteDatasource;

  ProyectosRepositoryImpl({required this.remoteDatasource});

  @override
  Future<List<Proyecto>> loadProyectos({bool forceRefresh = false}) {
    return remoteDatasource.loadProyectos(forceRefresh: forceRefresh);
  }

  @override
  Future<ConfiguracionData> loadConfig() {
    return remoteDatasource.loadConfig();
  }

  @override
  Future<List<Map<String, dynamic>>> loadRadarOportunidades({bool forceRefresh = false}) {
    return remoteDatasource.loadRadarOportunidades(forceRefresh: forceRefresh);
  }

  @override
  Future<void> sincronizarPostulacionDesdeOcds(List<Proyecto> proyectos) {
    return remoteDatasource.sincronizarPostulacionDesdeOcds(proyectos);
  }

  @override
  Future<void> updateProyectoEstadoManual(String projectId, String? estadoManual) {
    return remoteDatasource.updateProyectoEstadoManual(projectId, estadoManual);
  }
}