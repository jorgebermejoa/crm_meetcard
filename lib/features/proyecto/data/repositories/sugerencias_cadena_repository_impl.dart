import '../../domain/entities/sugerencia_cadena_entity.dart';
import '../../domain/repositories/sugerencias_cadena_repository.dart';
import '../datasources/sugerencias_cadena_datasource.dart';

class SugerenciasCadenaRepositoryImpl implements SugerenciasCadenaRepository {
  final SugerenciasCadenaDatasource _datasource;

  SugerenciasCadenaRepositoryImpl({SugerenciasCadenaDatasource? datasource})
      : _datasource = datasource ?? SugerenciasCadenaDatasource();

  @override
  Future<List<SugerenciaCadenaEntity>> getSugerencias(String proyectoId) =>
      _datasource.getSugerencias(proyectoId);

  @override
  Future<void> aceptar(
    String proyectoId,
    String sugerenciaId, {
    String? idProyectoRelacionado,
    String tipo = 'sucesor',
  }) =>
      _datasource.aceptar(
        proyectoId,
        sugerenciaId,
        idProyectoRelacionado: idProyectoRelacionado,
        tipo: tipo,
      );

  @override
  Future<void> rechazar(String proyectoId, String sugerenciaId) =>
      _datasource.rechazar(proyectoId, sugerenciaId);

  @override
  Future<void> revocar(
    String proyectoId,
    String sugerenciaId, {
    String? idProyectoRelacionado,
    String tipo = 'sucesor',
  }) =>
      _datasource.revocar(
        proyectoId,
        sugerenciaId,
        idProyectoRelacionado: idProyectoRelacionado,
        tipo: tipo,
      );
}
