/// Entidad de dominio para una sugerencia de encadenamiento de proyecto.
///
/// Almacenada en /proyectos/{pid}/sugerencias_cadena/{sid}
class SugerenciaCadenaEntity {
  final String id;

  /// 'predecesor' | 'sucesor'
  final String tipo;

  final String idLicitacion;
  final String titulo;
  final String institucion;
  final DateTime? fechaPublicacion;
  final DateTime? fechaCierre;
  final double? monto;

  /// Modalidad de compra (ej. 'licitacion_publica', 'trato_directo', etc.)
  final String? modalidadCompra;

  /// ID del proyecto en el sistema si esta licitación ya fue agregada.
  final String? idProyectoRelacionado;

  /// Score de relevancia de Discovery Engine (0.0–1.0).
  final double score;

  /// 'pendiente' | 'aceptada' | 'rechazada' | 'revocada'
  final String estado;

  final DateTime? fechaSugerencia;

  const SugerenciaCadenaEntity({
    required this.id,
    required this.tipo,
    required this.idLicitacion,
    required this.titulo,
    required this.institucion,
    this.fechaPublicacion,
    this.fechaCierre,
    this.monto,
    this.modalidadCompra,
    this.idProyectoRelacionado,
    this.score = 0.0,
    this.estado = 'pendiente',
    this.fechaSugerencia,
  });

  bool get isPendiente => estado == 'pendiente';
  bool get isAceptada => estado == 'aceptada';
  bool get isRevocada => estado == 'revocada';
  bool get isPredecesor => tipo == 'predecesor';
  bool get isSucesor => tipo == 'sucesor';
}
