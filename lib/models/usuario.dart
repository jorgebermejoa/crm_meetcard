class UserProfile {
  final String uid;
  final String email;
  final String nombre;
  final String rol; // 'admin' | 'usuario'
  final Map<String, Map<String, bool>> permisos;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.rol,
    required this.permisos,
  });

  bool get esAdmin => rol == 'admin';

  /// Returns true if user has a specific permission, or if user is admin.
  bool puede(String seccion, String accion) =>
      esAdmin || (permisos[seccion]?[accion] ?? true);

  static Map<String, Map<String, bool>> defaultPermisos() => {
        'inicio': {'ver': true},
        'proyectos': {
          'ver': true,
          'crear': true,
          'editar': true,
          'eliminar': true,
        },
        'configuracion': {'ver': true, 'editar': true},
      };

  factory UserProfile.fromJson(Map<String, dynamic> d, {required String uid}) {
    final raw = d['permisos'] as Map<String, dynamic>? ?? {};
    return UserProfile(
      uid: uid,
      email: d['email'] as String? ?? '',
      nombre: d['nombre'] as String? ?? '',
      rol: d['rol'] as String? ?? 'usuario',
      permisos: {
        for (final e in raw.entries)
          e.key: Map<String, bool>.from(
              (e.value as Map<Object?, Object?>?)?.map(
                    (k, v) => MapEntry(k.toString(), v as bool? ?? false),
                  ) ??
                  {}),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'nombre': nombre,
        'rol': rol,
        'permisos': permisos,
      };

  UserProfile copyWith({
    String? nombre,
    String? rol,
    Map<String, Map<String, bool>>? permisos,
  }) =>
      UserProfile(
        uid: uid,
        email: email,
        nombre: nombre ?? this.nombre,
        rol: rol ?? this.rol,
        permisos: permisos ?? this.permisos,
      );
}
