import 'package:flutter/material.dart';

// ── Color helpers ─────────────────────────────────────────────────────────────

/// Convierte un string hex (ej. "10B981") a Color. Soporta 6 u 8 chars.
Color hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  if (h.length == 8) return Color(int.parse(h, radix: 16));
  return const Color(0xFF64748B);
}

/// Convierte Color a hex string de 6 chars (sin alpha).
String colorToHex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

// ── Estado ────────────────────────────────────────────────────────────────────

class EstadoItem {
  String nombre;
  String color; // 6-char hex, ej. "10B981"

  EstadoItem({required this.nombre, this.color = '64748B'});

  factory EstadoItem.fromJson(dynamic d) {
    if (d is String) return EstadoItem(nombre: d);
    final m = d as Map<String, dynamic>;
    return EstadoItem(
      nombre: m['nombre'] as String? ?? '',
      color: m['color'] as String? ?? '64748B',
    );
  }

  Map<String, dynamic> toJson() => {'nombre': nombre, 'color': color};

  Color get colorValue => hexToColor(color);
  Color get bgColor => colorValue.withValues(alpha: 0.15);
  Color get fgColor => colorValue;
}

// ── Producto ──────────────────────────────────────────────────────────────────

class ProductoItem {
  String nombre;
  String abreviatura;
  String color;  // 6-char hex, ej. "4F46E5"
  String icono;  // clave del mapa _iconMap, ej. "devices"

  ProductoItem({
    required this.nombre,
    required this.abreviatura,
    this.color = '4F46E5',
    this.icono = 'label',
  });

  factory ProductoItem.fromJson(Map<String, dynamic> d) => ProductoItem(
        nombre: d['nombre'] as String? ?? '',
        abreviatura: d['abreviatura'] as String? ?? '',
        color: d['color'] as String? ?? '4F46E5',
        icono: d['icono'] as String? ?? 'label',
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'abreviatura': abreviatura,
        'color': color,
        'icono': icono,
      };

  Color get colorValue => hexToColor(color);
  Color get bgColor => colorValue.withValues(alpha: 0.13);
  Color get fgColor => colorValue;
}

// ── Paleta de colores compartida ──────────────────────────────────────────────

const kColorPaleta = [
  '10B981', // emerald
  '3B82F6', // blue
  '8B5CF6', // purple
  'F59E0B', // amber
  'EF4444', // red
  'F43F5E', // rose
  '14B8A6', // teal
  'F97316', // orange
  '6366F1', // indigo
  '64748B', // slate
  '1E1B6B', // primary
  'EC4899', // pink
];

// ── Mapa de iconos para productos ─────────────────────────────────────────────

const kIconosProducto = <String, IconData>{
  'label': Icons.label_outline,
  'devices': Icons.devices_outlined,
  'people': Icons.people_outline,
  'public': Icons.public_outlined,
  'assessment': Icons.assessment_outlined,
  'security': Icons.security_outlined,
  'directions_car': Icons.directions_car_outlined,
  'business': Icons.business_outlined,
  'school': Icons.school_outlined,
  'health_and_safety': Icons.health_and_safety_outlined,
  'build': Icons.build_outlined,
  'park': Icons.park_outlined,
  'camera_alt': Icons.camera_alt_outlined,
  'wifi': Icons.wifi_outlined,
  'local_police': Icons.local_police_outlined,
  'home': Icons.home_outlined,
  'map': Icons.map_outlined,
  'star': Icons.star_outline,
  'phone_android': Icons.phone_android_outlined,
  'monitor': Icons.monitor_outlined,
  'card_membership': Icons.card_membership_outlined,
  'work': Icons.work_outline,
};

// ── ConfiguracionData ─────────────────────────────────────────────────────────

class ConfiguracionData {
  List<EstadoItem> estados;
  List<String> modalidades;
  List<ProductoItem> productos;
  List<String> tiposDocumento;

  ConfiguracionData({
    required this.estados,
    required this.modalidades,
    required this.productos,
    required this.tiposDocumento,
  });

  static ConfiguracionData defaults() => ConfiguracionData(
        estados: [
          EstadoItem(nombre: 'Vigente', color: '10B981'),
          EstadoItem(nombre: 'X Vencer', color: 'F59E0B'),
          EstadoItem(nombre: 'Finalizado', color: '64748B'),
          EstadoItem(nombre: 'Sin fecha', color: 'EF4444'),
        ],
        modalidades: ['Licitación Pública', 'Convenio Marco', 'Trato Directo', 'Otro'],
        productos: [],
        tiposDocumento: ['Contrato', 'Orden de Compra', 'Acta de Evaluación', 'Otro'],
      );

  factory ConfiguracionData.fromJson(Map<String, dynamic> d) => ConfiguracionData(
        estados: (d['estados'] as List? ?? [])
            .map((e) => EstadoItem.fromJson(e))
            .toList(),
        modalidades: List<String>.from(d['modalidades'] ?? []),
        productos: (d['productos'] as List? ?? [])
            .map((e) => ProductoItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        tiposDocumento: d['tiposDocumento'] != null
            ? List<String>.from(d['tiposDocumento'])
            : ['Contrato', 'Orden de Compra', 'Acta de Evaluación', 'Otro'],
      );

  Map<String, dynamic> toJson() => {
        'estados': estados.map((e) => e.toJson()).toList(),
        'modalidades': modalidades,
        'productos': productos.map((p) => p.toJson()).toList(),
        'tiposDocumento': tiposDocumento,
      };
}
