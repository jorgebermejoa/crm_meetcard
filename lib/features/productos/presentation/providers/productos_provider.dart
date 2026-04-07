import 'package:flutter/material.dart';
import '../../../../models/proyecto.dart';

class ProductosProvider extends ChangeNotifier {
  Map<String, List<Proyecto>> _productosMap = {};
  List<String> _productosNombres = [];
  final Set<String> _selectedProductos = {};

  Map<String, List<Proyecto>> get productosMap => _productosMap;
  List<String> get productosNombres => _productosNombres;
  Set<String> get selectedProductos => _selectedProductos;

  void updateProyectos(List<Proyecto> proyectos) {
    final Map<String, List<Proyecto>> nuevoMapa = {};
    final Set<String> nombresUnicos = {};

    for (final p in proyectos) {
      if (p.productos.trim().isEmpty) continue;
      
      final parts = p.productos.split(',');
      for (var part in parts) {
        final prod = part.trim();
        if (prod.isEmpty) continue;
        
        nombresUnicos.add(prod);
        if (!nuevoMapa.containsKey(prod)) {
          nuevoMapa[prod] = [];
        }
        nuevoMapa[prod]!.add(p);
      }
    }

    _productosMap = nuevoMapa;
    _productosNombres = nombresUnicos.toList()..sort();

    // Remove any selected products that are no longer valid
    _selectedProductos.retainWhere((prod) => _productosNombres.contains(prod));

    // If nothing is selected and we have products, select the first one
    if (_selectedProductos.isEmpty && _productosNombres.isNotEmpty) {
      _selectedProductos.add(_productosNombres.first);
    }

    notifyListeners();
  }

  void toggleProducto(String producto) {
    if (_productosNombres.contains(producto)) {
      if (_selectedProductos.contains(producto)) {
        // Prevent deselecting the last one
        if (_selectedProductos.length > 1) {
          _selectedProductos.remove(producto);
        }
      } else {
        _selectedProductos.add(producto);
      }
      notifyListeners();
    }
  }

  List<Proyecto> get proyectosDeProductosSeleccionados {
    if (_selectedProductos.isEmpty) return [];
    final Set<String> projectIds = {};
    final List<Proyecto> combined = [];
    
    for (final prod in _selectedProductos) {
      final list = _productosMap[prod] ?? [];
      for (final p in list) {
        if (projectIds.add(p.id)) {
          combined.add(p);
        }
      }
    }
    return combined;
  }
}
