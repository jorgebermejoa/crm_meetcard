import '../../domain/entities/proyecto_entity.dart';
import '../../domain/repositories/proyecto_repository.dart';
import '../datasources/proyecto_remote_datasource.dart';
import '../models/proyecto_model.dart';

class ProyectoRepositoryImpl implements ProyectoRepository {
  final ProyectoRemoteDataSource remoteDataSource;

  ProyectoRepositoryImpl({required this.remoteDataSource});

  @override
  Future<ProyectoEntity> getProyecto(String id) async {
    return await remoteDataSource.getProyecto(id);
  }

  @override
  Future<List<ProyectoEntity>> getProyectos() async {
    return await remoteDataSource.getProyectos();
  }

  @override
  Future<void> updateProyectoField({
    required String id,
    required String fieldName,
    required dynamic value,
    required Map<String, dynamic> historyData,
  }) async {
    final Map<String, dynamic> updateData = {
      fieldName: value,
      'historial': [historyData], // Simplified for example, normally it's FieldValue.arrayUnion
    };
    await remoteDataSource.updateProyecto(id, updateData);
  }

  @override
  Future<void> addDocumento(String id, DocumentoEntity documento) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final List<DocumentoModel> docs = (proyecto.documentos).map((d) => d as DocumentoModel).toList();
    docs.add(DocumentoModel(tipo: documento.tipo, url: documento.url, nombre: documento.nombre));
    await remoteDataSource.updateProyecto(id, {
      'documentos': docs.map((d) => d.toJson()).toList(),
    });
  }

  @override
  Future<void> deleteDocumento(String id, int index) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final List<DocumentoModel> docs = (proyecto.documentos).map((d) => d as DocumentoModel).toList();
    docs.removeAt(index);
    await remoteDataSource.updateProyecto(id, {
      'documentos': docs.map((d) => d.toJson()).toList(),
    });
  }

  @override
  Future<void> addCertificado(String id, CertificadoEntity certificado) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final List<CertificadoModel> certs = (proyecto.certificados).map((c) => c as CertificadoModel).toList();
    certs.add(CertificadoModel(
      id: certificado.id,
      descripcion: certificado.descripcion,
      fechaEmision: certificado.fechaEmision,
      url: certificado.url,
    ));
    await remoteDataSource.updateProyecto(id, {
      'certificados': certs.map((c) => c.toJson()).toList(),
    });
  }

  @override
  Future<void> deleteCertificado(String id, String certificadoId) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final newList = (proyecto.certificados as List<CertificadoModel>).where((c) => c.id != certificadoId).toList();
    await remoteDataSource.updateProyecto(id, {
      'certificados': newList.map((c) => c.toJson()).toList(),
    });
  }

  @override
  Future<void> addReclamo(String id, ReclamoEntity reclamo) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final List<ReclamoModel> reclamos = (proyecto.reclamos as List<ReclamoModel>).toList();
    reclamos.add(ReclamoModel(
      id: reclamo.id,
      descripcion: reclamo.descripcion,
      fechaReclamo: reclamo.fechaReclamo,
      estado: reclamo.estado,
      documentos: reclamo.documentos.map((d) => d as DocumentoModel).toList(),
    ));
    await remoteDataSource.updateProyecto(id, {
      'reclamos': reclamos.map((r) => r.toJson()).toList(),
    });
  }

  @override
  Future<void> updateReclamo(String id, ReclamoEntity reclamo) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final newList = (proyecto.reclamos as List<ReclamoModel>).map((r) => r.id == reclamo.id ? (reclamo as ReclamoModel) : r).toList();
    await remoteDataSource.updateProyecto(id, {
      'reclamos': newList.map((r) => r.toJson()).toList(),
    });
  }

  @override
  Future<void> deleteReclamo(String id, String reclamoId) async {
    final proyecto = await remoteDataSource.getProyecto(id);
    final newList = (proyecto.reclamos as List<ReclamoModel>).where((r) => r.id != reclamoId).toList();
    await remoteDataSource.updateProyecto(id, {
      'reclamos': newList.map((r) => r.toJson()).toList(),
    });
  }

  @override
  Future<Map<String, dynamic>> getExternalApiData(String id, {String? idLicitacion, String? urlConvenioMarco, bool forceRefresh = false}) async {
    return await remoteDataSource.getExternalApiData(id, idLicitacion: idLicitacion, urlConvenioMarco: urlConvenioMarco, forceRefresh: forceRefresh);
  }

  @override
  Future<List<Map<String, dynamic>>> getForoData(String idLicitacion, {bool forceRefresh = false}) async {
    return await remoteDataSource.getForoData(idLicitacion, forceRefresh: forceRefresh);
  }

  @override
  Future<String> generateForoSummary(String idLicitacion, List<Map<String, dynamic>> enquiries) async {
    return await remoteDataSource.generateForoSummary(idLicitacion, enquiries);
  }

  @override
  Future<Map<String, dynamic>> getAnalisisBq(String proyectoId) async {
    return await remoteDataSource.getAnalisisBq(proyectoId);
  }
}
