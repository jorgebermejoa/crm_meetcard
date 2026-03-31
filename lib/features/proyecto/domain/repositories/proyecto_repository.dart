import '../entities/proyecto_entity.dart';

/// Abstract interface for Project repository.
/// 
/// Defines the contract for data operations without specifying the data source.
abstract class ProyectoRepository {
  /// Fetch a project by its unique ID.
  Future<ProyectoEntity> getProyecto(String id);

  /// Fetch all projects.
  Future<List<ProyectoEntity>> getProyectos();

  /// Update a specific field of a project.
  Future<void> updateProyectoField({
    required String id,
    required String fieldName,
    required dynamic value,
    required Map<String, dynamic> historyData,
  });

  /// Add a new document to a project.
  Future<void> addDocumento(String id, DocumentoEntity documento);

  /// Delete a document from a project.
  Future<void> deleteDocumento(String id, int index);

  /// Add a new certificate to a project.
  Future<void> addCertificado(String id, CertificadoEntity certificado);

  /// Delete a certificate from a project.
  Future<void> deleteCertificado(String id, String certificadoId);

  /// Add a new complaint (reclamo) to a project.
  Future<void> addReclamo(String id, ReclamoEntity reclamo);

  /// Update an existing complaint.
  Future<void> updateReclamo(String id, ReclamoEntity reclamo);

  /// Delete a complaint.
  Future<void> deleteReclamo(String id, String reclamoId);

  /// Fetch external OCDS data for a project.
  Future<Map<String, dynamic>> getExternalApiData(String id, {String? idLicitacion, String? urlConvenioMarco, bool forceRefresh = false});

  /// Fetch forum data for a project.
  Future<List<Map<String, dynamic>>> getForoData(String idLicitacion, {bool forceRefresh = false});

  /// Generate forum summary using AI.
  Future<String> generateForoSummary(String idLicitacion, List<Map<String, dynamic>> enquiries);

  /// Fetch BigQuery analysis data.
  Future<Map<String, dynamic>> getAnalisisBq(String proyectoId);
}
