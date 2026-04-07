import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/sugerencia_cadena_entity.dart';

class SugerenciaCadenaModel extends SugerenciaCadenaEntity {
  const SugerenciaCadenaModel({
    required super.id,
    required super.tipo,
    required super.idLicitacion,
    required super.titulo,
    required super.institucion,
    super.fechaPublicacion,
    super.fechaCierre,
    super.monto,
    super.modalidadCompra,
    super.idProyectoRelacionado,
    super.score,
    super.estado,
    super.fechaSugerencia,
  });

  factory SugerenciaCadenaModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SugerenciaCadenaModel(
      id: doc.id,
      tipo: d['tipo']?.toString() ?? 'sucesor',
      idLicitacion: d['idLicitacion']?.toString() ?? '',
      titulo: d['titulo']?.toString() ?? 'Sin título',
      institucion: d['institucion']?.toString() ?? '',
      fechaPublicacion: _toDateTime(d['fechaPublicacion']),
      fechaCierre: _toDateTime(d['fechaCierre']),
      monto: (d['monto'] as num?)?.toDouble(),
      modalidadCompra: d['modalidadCompra']?.toString(),
      idProyectoRelacionado: d['idProyectoRelacionado']?.toString(),
      score: (d['score'] as num?)?.toDouble() ?? 0.0,
      estado: d['estado']?.toString() ?? 'pendiente',
      fechaSugerencia: _toDateTime(d['fechaSugerencia']),
    );
  }

  static DateTime? _toDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) {
      final d = DateTime.tryParse(raw);
      return d;
    }
    return null;
  }
}
