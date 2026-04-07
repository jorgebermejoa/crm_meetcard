import 'package:flutter/foundation.dart';
import '../../../domain/entities/proyecto_entity.dart';
import '../../../domain/repositories/proyecto_repository.dart';

/// CRUD operations for contract extensions (aumentos de plazo / contrato).
mixin ProyectoAumentosMixin on ChangeNotifier {
  ProyectoRepository get repository;
  ProyectoEntity get proyecto;
  set proyectoInternal(ProyectoEntity value);
  String? get errorMessage;
  set errorMessage(String? value);
  VoidCallback? get onMutated;

  void _notifyMutation() {
    onMutated?.call();
    notifyListeners();
  }

  Future<void> addAumento({
    required String tipo,
    required DateTime fechaTermino,
    double? valorMensual,
    List<DocumentoEntity> documentos = const [],
    String? descripcion,
  }) async {
    try {
      final aumento = AumentoEntity(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tipo: tipo,
        fechaTermino: fechaTermino,
        valorMensual: valorMensual,
        documentos: documentos,
        fechaRegistro: DateTime.now(),
        descripcion: descripcion,
      );
      await repository.addAumento(proyecto.id, aumento);
      proyectoInternal = await repository.getProyecto(proyecto.id);
      _notifyMutation();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateAumentoItem({
    required String aumentoId,
    required String tipo,
    required DateTime fechaTermino,
    double? valorMensual,
    List<DocumentoEntity> documentos = const [],
    String? descripcion,
    required DateTime fechaRegistro,
  }) async {
    try {
      final aumento = AumentoEntity(
        id: aumentoId,
        tipo: tipo,
        fechaTermino: fechaTermino,
        valorMensual: valorMensual,
        documentos: documentos,
        fechaRegistro: fechaRegistro,
        descripcion: descripcion,
      );
      await repository.updateAumento(proyecto.id, aumento);
      proyectoInternal = await repository.getProyecto(proyecto.id);
      _notifyMutation();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteAumento(String aumentoId) async {
    try {
      await repository.deleteAumento(proyecto.id, aumentoId);
      proyectoInternal = await repository.getProyecto(proyecto.id);
      _notifyMutation();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }
}
