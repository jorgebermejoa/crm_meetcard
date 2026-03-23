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
  '5B21B6', // primary
  'EC4899', // pink
  '06B6D4', // cyan
  '84CC16', // lime
  'A3E635', // yellow-green
  'FBBF24', // yellow
  'FB923C', // orange-400
  'E11D48', // rose-600
  'BE185D', // pink-700
  '7C3AED', // violet
  '4338CA', // indigo-700
  '1D4ED8', // blue-700
  '0369A1', // sky-700
  '0F766E', // teal-700
  '15803D', // green-700
  '92400E', // amber-800
  '7F1D1D', // red-900
  '374151', // gray-700
  '111827', // gray-900
  'FFFFFF', // white
];

// ── Mapa de iconos para productos ─────────────────────────────────────────────

const kIconosProducto = <String, IconData>{
  // General
  'label':             Icons.label_outline,
  'star':              Icons.star_outline,
  'work':              Icons.work_outline,
  'business':          Icons.business_outlined,
  'store':             Icons.store_outlined,
  'inventory':         Icons.inventory_2_outlined,
  'receipt':           Icons.receipt_long_outlined,
  'payments':          Icons.payments_outlined,
  'account_balance':   Icons.account_balance_outlined,
  'savings':           Icons.savings_outlined,
  // Tecnología
  'devices':           Icons.devices_outlined,
  'monitor':           Icons.monitor_outlined,
  'phone_android':     Icons.phone_android_outlined,
  'tablet':            Icons.tablet_outlined,
  'computer':          Icons.computer_outlined,
  'wifi':              Icons.wifi_outlined,
  'cloud':             Icons.cloud_outlined,
  'storage':           Icons.storage_outlined,
  'code':              Icons.code_outlined,
  'terminal':          Icons.terminal_outlined,
  'api':               Icons.api_outlined,
  'smart_toy':         Icons.smart_toy_outlined,
  'data_usage':        Icons.data_usage_outlined,
  'analytics':         Icons.analytics_outlined,
  'assessment':        Icons.assessment_outlined,
  // Personas / Organización
  'people':            Icons.people_outline,
  'person':            Icons.person_outline,
  'groups':            Icons.groups_outlined,
  'school':            Icons.school_outlined,
  'card_membership':   Icons.card_membership_outlined,
  'badge':             Icons.badge_outlined,
  'assignment_ind':    Icons.assignment_ind_outlined,
  // Seguridad / Legal
  'security':          Icons.security_outlined,
  'local_police':      Icons.local_police_outlined,
  'gavel':             Icons.gavel_outlined,
  'policy':            Icons.policy_outlined,
  'verified':          Icons.verified_outlined,
  'lock':              Icons.lock_outline,
  // Salud / Bienestar
  'health_and_safety': Icons.health_and_safety_outlined,
  'local_hospital':    Icons.local_hospital_outlined,
  'emergency':         Icons.emergency_outlined,
  'medication':        Icons.medication_outlined,
  // Transporte / Movilidad
  'directions_car':    Icons.directions_car_outlined,
  'local_shipping':    Icons.local_shipping_outlined,
  'flight':            Icons.flight_outlined,
  'directions_bus':    Icons.directions_bus_outlined,
  'train':             Icons.train_outlined,
  // Infraestructura / Territorio
  'home':              Icons.home_outlined,
  'map':               Icons.map_outlined,
  'public':            Icons.public_outlined,
  'location_city':     Icons.location_city_outlined,
  'park':              Icons.park_outlined,
  'terrain':           Icons.terrain_outlined,
  'water':             Icons.water_outlined,
  'electrical_services': Icons.electrical_services_outlined,
  'build':             Icons.build_outlined,
  'construction':      Icons.construction_outlined,
  // Comunicación / Multimedia
  'camera_alt':        Icons.camera_alt_outlined,
  'photo_library':     Icons.photo_library_outlined,
  'videocam':          Icons.videocam_outlined,
  'mic':               Icons.mic_outlined,
  'campaign':          Icons.campaign_outlined,
  'chat':              Icons.chat_outlined,
  'email':             Icons.email_outlined,
  'notifications':     Icons.notifications_outlined,
  // Documentos / Gestión
  'folder':            Icons.folder_outlined,
  'description':       Icons.description_outlined,
  'assignment':        Icons.assignment_outlined,
  'fact_check':        Icons.fact_check_outlined,
  'edit_document':     Icons.edit_document,
  'print':             Icons.print_outlined,
  'archive':           Icons.archive_outlined,
  // Otros
  'settings':          Icons.settings_outlined,
  'tune':              Icons.tune_outlined,
  'support':           Icons.support_outlined,
  'volunteer_activism': Icons.volunteer_activism_outlined,
  'sports':            Icons.sports_outlined,
  'music_note':        Icons.music_note_outlined,
  'restaurant':        Icons.restaurant_outlined,
  'local_fire_department': Icons.local_fire_department_outlined,
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
