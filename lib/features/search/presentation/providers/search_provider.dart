import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Unified Search model for the application.
class LicitacionUI {
  final String id;
  final String titulo;
  final String descripcion;
  final String fechaPublicacion;
  final String fechaCierre;
  final Map<String, dynamic> rawData;

  LicitacionUI(this.id, this.titulo, this.descripcion, this.fechaPublicacion, this.fechaCierre, {required this.rawData});

  bool get esVigente {
    try {
      final cierre = DateTime.parse(fechaCierre);
      return cierre.isAfter(DateTime.now());
    } catch (_) {
      return true; // Si no hay fecha o error, asumimos vigente
    }
  }
}

/// Provider to manage application-wide search operations and results.
class SearchProvider extends ChangeNotifier {
  List<LicitacionUI> _licitaciones = [];
  bool _isLoading = false;
  String? _error;
  LicitacionUI? _selectedLicitacion;
  bool _showClosed = false;

  // Getters
  List<LicitacionUI> get licitaciones => _licitaciones;
  bool get isLoading => _isLoading;
  String? get error => _error;
  LicitacionUI? get selectedLicitacion => _selectedLicitacion;
  bool get showClosed => _showClosed;

  List<LicitacionUI> get filteredLicitaciones {
    if (_showClosed) return _licitaciones;
    return _licitaciones.where((l) => l.esVigente).toList();
  }

  void toggleShowClosed() {
    _showClosed = !_showClosed;
    notifyListeners();
  }

  void selectLicitacion(LicitacionUI? lic) {
    _selectedLicitacion = lic;
    notifyListeners();
  }

  void clearSearch() {
    _licitaciones = [];
    _selectedLicitacion = null;
    _error = null;
    notifyListeners();
  }

  Future<void> performSearch(String query) async {
    if (query.isEmpty) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken() ?? '';
      final url = Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/buscarLicitacionesAI?q=${Uri.encodeComponent(query)}');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> data;
        if (decoded is List) {
          data = decoded;
        } else if (decoded is Map) {
          data = (decoded['resultados'] as List?) ?? [];
        } else {
          data = [];
        }

        _licitaciones = data.map((item) {
          final m = item as Map<String, dynamic>;
          return LicitacionUI(
            m['id']?.toString() ?? 'S/I',
            m['titulo']?.toString() ?? 'Sin título',
            m['descripcion']?.toString() ?? 'Sin descripción',
            m['fechaPublicacion']?.toString() ?? 'S/F',
            m['fechaCierre']?.toString() ?? 'S/F',
            rawData: m,
          );
        }).toList();
      } else {
        _error = "Error del servidor: ${response.statusCode}";
      }
    } catch (e) {
      _error = "Error de red: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
