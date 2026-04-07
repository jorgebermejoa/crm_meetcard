import 'package:flutter/foundation.dart';
import '../../domain/entities/sugerencia_cadena_entity.dart';
import '../../domain/repositories/sugerencias_cadena_repository.dart';
import '../../data/repositories/sugerencias_cadena_repository_impl.dart';

class SugerenciasCadenaProvider extends ChangeNotifier {
  final String proyectoId;
  final SugerenciasCadenaRepository _repo;

  SugerenciasCadenaProvider({
    required this.proyectoId,
    SugerenciasCadenaRepository? repo,
  }) : _repo = repo ?? SugerenciasCadenaRepositoryImpl();

  List<SugerenciaCadenaEntity> sugerencias = [];
  bool isLoading = false;
  String? error;

  Future<void> cargar() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      sugerencias = await _repo.getSugerencias(proyectoId);
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> aceptar(SugerenciaCadenaEntity s) async {
    try {
      await _repo.aceptar(
        proyectoId,
        s.id,
        idProyectoRelacionado: s.idProyectoRelacionado,
        tipo: s.tipo,
      );
      await cargar(); // recarga para reflejar estado real
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> rechazar(SugerenciaCadenaEntity s) async {
    try {
      await _repo.rechazar(proyectoId, s.id);
      await cargar();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> revocar(SugerenciaCadenaEntity s) async {
    try {
      await _repo.revocar(
        proyectoId,
        s.id,
        idProyectoRelacionado: s.idProyectoRelacionado,
        tipo: s.tipo,
      );
      await cargar();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }
}
