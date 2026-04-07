import '../entities/sugerencia_cadena_entity.dart';

abstract class SugerenciasCadenaRepository {
  /// Carga todas las sugerencias pendientes del proyecto.
  Future<List<SugerenciaCadenaEntity>> getSugerencias(String proyectoId);

  Future<void> aceptar(
    String proyectoId,
    String sugerenciaId, {
    String? idProyectoRelacionado,
    String tipo,
  });

  Future<void> rechazar(String proyectoId, String sugerenciaId);

  Future<void> revocar(
    String proyectoId,
    String sugerenciaId, {
    String? idProyectoRelacionado,
    String tipo,
  });
}
