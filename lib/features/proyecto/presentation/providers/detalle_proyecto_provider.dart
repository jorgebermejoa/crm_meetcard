import 'package:flutter/material.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../../domain/repositories/proyecto_repository.dart';

class DetalleProyectoProvider with ChangeNotifier {
  final ProyectoRepository _repository;
  
  ProyectoEntity _proyecto;
  ProyectoEntity get proyecto => _proyecto;

  String activeTab = 'Detalle';
  bool isLoading = false;
  String? errorMessage;

  // Analisis BQ State
  bool analisisCargando = false;
  String? analisisError;
  List<Map<String, dynamic>> competidores = [];
  List<Map<String, dynamic>> ganadorOcs = [];
  List<Map<String, dynamic>> predicciones = [];
  String? nombreGanador;
  String? rutGanador;
  String? permanenciaGanador;
  String? rutOrganismo;
  List<Map<String, dynamic>> historialGanador = [];

  // External API state (MP / OCDS / CM)
  bool cargandoExternalData = false;
  Map<String, dynamic>? externalApiData;
  DateTime? externalDataLastFetch;

  // Forum state
  bool cargandoForo = false;
  DateTime? foroFechaCache;
  List<Map<String, dynamic>> foroEnquiries = [];
  String? foroResumen;
  bool cargandoResumen = false;
  String foroQuery = '';

  List<Map<String, dynamic>> get filteredForo {
    if (foroQuery.isEmpty) return foroEnquiries;
    return foroEnquiries.where((e) {
      final text = (e['subject'] ?? '') + (e['question'] ?? '') + (e['answer'] ?? '');
      return text.toLowerCase().contains(foroQuery.toLowerCase());
    }).toList();
  }

  DetalleProyectoProvider({
    required ProyectoRepository repository,
    required ProyectoEntity proyecto,
    String? initialTabName,
  }) : _repository = repository, _proyecto = proyecto {
    if (initialTabName != null) activeTab = initialTabName;
  }

  void init() {
    // Initial data fetching if needed
    cargarAnalisisBq();
  }

  void setActiveTab(String tab) {
    activeTab = tab;
    notifyListeners();
  }

  // --- Field Updates ---
  Future<void> editField(String field, dynamic value, String label) async {
    try {
      await _repository.updateProyectoField(
        id: _proyecto.id,
        fieldName: field,
        value: value,
        historyData: {
          'fecha': DateTime.now().toIso8601String(),
          'accion': 'Editó $label',
          'valor': value.toString(),
        },
      );
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  // --- Document Management ---
  Future<void> addDocument(DocumentoEntity doc) async {
    try {
      await _repository.addDocumento(_proyecto.id, doc);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteDocument(int index) async {
    try {
      await _repository.deleteDocumento(_proyecto.id, index);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  // --- Certificate Management ---
  Future<void> addCertificado(CertificadoEntity cert) async {
    try {
      await _repository.addCertificado(_proyecto.id, cert);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteCertificado(String certId) async {
    try {
      await _repository.deleteCertificado(_proyecto.id, certId);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  // --- Reclamo Management ---
  Future<void> addReclamo(ReclamoEntity reclamo) async {
    try {
      await _repository.addReclamo(_proyecto.id, reclamo);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateReclamo(ReclamoEntity reclamo) async {
    try {
      await _repository.updateReclamo(_proyecto.id, reclamo);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteReclamo(String reclamoId) async {
    try {
      await _repository.deleteReclamo(_proyecto.id, reclamoId);
      _proyecto = await _repository.getProyecto(_proyecto.id);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  // --- BigQuery Analysis ---
  Future<void> cargarAnalisisBq({bool forceRefresh = false}) async {
    if (analisisCargando) return;
    analisisCargando = true;
    analisisError = null;
    notifyListeners();

    try {
      final res = await _repository.getAnalisisBq(_proyecto.id);
      competidores = List<Map<String, dynamic>>.from(res['competidores'] ?? []);
      ganadorOcs = List<Map<String, dynamic>>.from(res['ganador_ocs'] ?? []);
      predicciones = List<Map<String, dynamic>>.from(res['predicciones'] ?? []);
      nombreGanador = res['nombre_ganador'];
      rutGanador = res['rut_ganador'];
      permanenciaGanador = res['permanencia_ganador'];
      rutOrganismo = res['rut_organismo'];
      historialGanador = List<Map<String, dynamic>>.from(res['historial_ganador'] ?? []);
    } catch (e) {
      analisisError = e.toString();
    } finally {
      analisisCargando = false;
      notifyListeners();
    }
  }

  // --- Forum Handlers ---
  Future<void> cargarForo({bool forceRefresh = false}) async {
    if (cargandoForo) return;
    cargandoForo = true;
    notifyListeners();
    try {
      if (_proyecto.idLicitacion != null) {
        foroEnquiries = await _repository.getForoData(_proyecto.idLicitacion!, forceRefresh: forceRefresh);
        foroFechaCache = DateTime.now(); // Simplified
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      cargandoForo = false;
      notifyListeners();
    }
  }

  Future<void> generarResumenForo() async {
    if (cargandoResumen || foroEnquiries.isEmpty) return;
    cargandoResumen = true;
    notifyListeners();
    try {
      if (_proyecto.idLicitacion != null) {
        foroResumen = await _repository.generateForoSummary(_proyecto.idLicitacion!, foroEnquiries);
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      cargandoResumen = false;
      notifyListeners();
    }
  }

  // --- External Data Handlers (MP / OCDS / CM) ---
  Future<void> cargarOcds({bool forceRefresh = false}) async {
    if (cargandoExternalData) return;
    cargandoExternalData = true;
    notifyListeners();
    try {
      if (_proyecto.idLicitacion?.isNotEmpty == true || _proyecto.urlConvenioMarco?.isNotEmpty == true) {
        externalApiData = await _repository.getExternalApiData(
          _proyecto.id, 
          idLicitacion: _proyecto.idLicitacion, 
          urlConvenioMarco: _proyecto.urlConvenioMarco,
          forceRefresh: forceRefresh,
        );
        externalDataLastFetch = DateTime.now();
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      cargandoExternalData = false;
      notifyListeners();
    }
  }

  // --- Utilities ---
  String fmt(dynamic value) {
    if (value == null) return '—';
    if (value is num) return value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return value.toString();
  }

  String cleanName(String? name) {
    if (name == null) return '—';
    return name.replaceAll(RegExp(r'^\d+\s*-\s*'), '').trim();
  }

  // --- Timeline Helpers ---
  List<ProyectoEntity> get cadena => []; // Placeholder for complex logic
  List<ProyectoEntity> get sucesores => []; // Placeholder for complex logic

  // --- Forum Helpers ---
  void setForoQuery(String query) {
    foroQuery = query;
    notifyListeners();
  }

  String fmtDateStr(String? date) {
    if (date == null) return '—';
    try {
      final dt = DateTime.parse(date);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return date;
    }
  }
}
