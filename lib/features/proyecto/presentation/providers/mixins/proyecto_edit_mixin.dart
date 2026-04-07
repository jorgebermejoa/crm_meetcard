import 'package:flutter/foundation.dart';
import '../../../domain/entities/proyecto_entity.dart';
import '../../../domain/repositories/proyecto_repository.dart';

/// Métodos de edición de campos, documentos, certificados y reclamos.
mixin ProyectoEditMixin on ChangeNotifier {
  ProyectoRepository get repository;
  ProyectoEntity get proyecto;
  set proyectoInternal(ProyectoEntity value);
  String? get errorMessage;
  set errorMessage(String? value);

  /// Callback invocado tras cada mutación exitosa.
  /// Se usa para invalidar cachés del proveedor padre (ej. ProyectosProvider).
  VoidCallback? onMutated;

  void _notifyMutation() {
    onMutated?.call();
    notifyListeners();
  }

  /// Runs [operation], then reloads the project and notifies listeners.
  /// On error, stores the message and notifies listeners.
  Future<void> _mutate(Future<void> Function() operation) async {
    try {
      await operation();
      proyectoInternal = await repository.getProyecto(proyecto.id);
      _notifyMutation();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> editField(String field, dynamic value, String label) => _mutate(() =>
      repository.updateProyectoField(
        id: proyecto.id,
        fieldName: field,
        value: value,
        historyData: {
          'fecha': DateTime.now().toIso8601String(),
          'accion': 'Editó $label',
          'valor': value.toString(),
        },
      ));

  Future<void> addDocument(DocumentoEntity doc) =>
      _mutate(() => repository.addDocumento(proyecto.id, doc));

  Future<void> deleteDocument(int index) =>
      _mutate(() => repository.deleteDocumento(proyecto.id, index));

  Future<void> addCertificado(CertificadoEntity cert) =>
      _mutate(() => repository.addCertificado(proyecto.id, cert));

  Future<void> deleteCertificado(String certId) =>
      _mutate(() => repository.deleteCertificado(proyecto.id, certId));

  Future<void> addReclamo(ReclamoEntity reclamo) =>
      _mutate(() => repository.addReclamo(proyecto.id, reclamo));

  Future<void> updateReclamo(ReclamoEntity reclamo) =>
      _mutate(() => repository.updateReclamo(proyecto.id, reclamo));

  Future<void> deleteReclamo(String reclamoId) =>
      _mutate(() => repository.deleteReclamo(proyecto.id, reclamoId));
}
