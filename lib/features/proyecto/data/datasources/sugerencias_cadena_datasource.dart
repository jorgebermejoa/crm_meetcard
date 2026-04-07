import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/sugerencia_cadena_entity.dart';
import '../models/sugerencia_cadena_model.dart';

class SugerenciasCadenaDatasource {
  final FirebaseFirestore _db;

  SugerenciasCadenaDatasource({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String proyectoId) =>
      _db.collection('proyectos').doc(proyectoId).collection('sugerencias_cadena');

  /// Retorna sugerencias con estado 'pendiente' o 'aceptada', ordenadas por score desc.
  /// Las 'aceptadas' se incluyen para permitir revocarlas desde la UI.
  Future<List<SugerenciaCadenaEntity>> getSugerencias(String proyectoId) async {
    final snap = await _col(proyectoId)
        .where('estado', whereIn: ['pendiente', 'aceptada'])
        .get();
    final list = snap.docs.map(SugerenciaCadenaModel.fromFirestore).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// Marca como aceptada y, si corresponde, encadena el proyecto relacionado.
  /// [tipo] determina la dirección del link:
  ///   'predecesor' → idProyectoRelacionado apunta al proyecto actual como sucesor
  ///   'sucesor'    → proyecto actual apunta a idProyectoRelacionado como sucesor
  Future<void> aceptar(
    String proyectoId,
    String sugerenciaId, {
    String? idProyectoRelacionado,
    String tipo = 'sucesor',
  }) async {
    final batch = _db.batch();

    // 1. Actualizar estado de la sugerencia
    batch.update(_col(proyectoId).doc(sugerenciaId), {'estado': 'aceptada'});

    // 2. Si ya existe como proyecto en el sistema, encadenar en la dirección correcta
    if (idProyectoRelacionado != null) {
      if (tipo == 'predecesor') {
        // El predecesor apunta hacia este proyecto (predecesor → actual)
        batch.update(
          _db.collection('proyectos').doc(idProyectoRelacionado),
          {
            'proyectoContinuacionIds': FieldValue.arrayUnion([proyectoId]),
          },
        );
        // Marcar el proyecto ACTUAL como encadenado por sugerencia
        batch.update(
          _db.collection('proyectos').doc(proyectoId),
          {'fromSugerencia': true},
        );
      } else {
        // Este proyecto apunta al sucesor (actual → sucesor)
        batch.update(
          _db.collection('proyectos').doc(proyectoId),
          {
            'proyectoContinuacionIds': FieldValue.arrayUnion([idProyectoRelacionado]),
          },
        );
        // Marcar el SUCESOR como encadenado por sugerencia
        batch.update(
          _db.collection('proyectos').doc(idProyectoRelacionado),
          {'fromSugerencia': true},
        );
      }
    }

    await batch.commit();
    // No actualizamos el flag al aceptar: pueden quedar otras pendientes
  }

  /// Marca como rechazada para que el cron no la vuelva a generar.
  Future<void> rechazar(String proyectoId, String sugerenciaId) async {
    await _col(proyectoId).doc(sugerenciaId).update({'estado': 'rechazada'});
    await _actualizarFlag(proyectoId);
  }

  /// Revoca una sugerencia aceptada: marca como 'revocada' y desencadena
  /// el proyecto relacionado si corresponde.
  Future<void> revocar(
    String proyectoId,
    String sugerenciaId, {
    String? idProyectoRelacionado,
    String tipo = 'sucesor',
  }) async {
    final batch = _db.batch();

    batch.update(_col(proyectoId).doc(sugerenciaId), {'estado': 'revocada'});

    if (idProyectoRelacionado != null) {
      if (tipo == 'predecesor') {
        batch.update(
          _db.collection('proyectos').doc(idProyectoRelacionado),
          {
            'proyectoContinuacionIds': FieldValue.arrayRemove([proyectoId]),
          },
        );
        batch.update(
          _db.collection('proyectos').doc(proyectoId),
          {'fromSugerencia': false},
        );
      } else {
        batch.update(
          _db.collection('proyectos').doc(proyectoId),
          {
            'proyectoContinuacionIds': FieldValue.arrayRemove([idProyectoRelacionado]),
          },
        );
        batch.update(
          _db.collection('proyectos').doc(idProyectoRelacionado),
          {'fromSugerencia': false},
        );
      }
    }

    await batch.commit();
    await _actualizarFlag(proyectoId);
  }

  /// Actualiza hasSugerenciasPendientes en el proyecto según si quedan pendientes.
  Future<void> _actualizarFlag(String proyectoId) async {
    final snap = await _col(proyectoId)
        .where('estado', isEqualTo: 'pendiente')
        .limit(1)
        .get();
    await _db
        .collection('proyectos')
        .doc(proyectoId)
        .update({'hasSugerenciasPendientes': snap.docs.isNotEmpty});
  }
}
