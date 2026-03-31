import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/usuario.dart';

const _fnBase =
    'https://us-central1-licitaciones-prod.cloudfunctions.net';

class AuthService {
  static final instance = AuthService._();
  AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  UserProfile? _perfil;
  UserProfile? get perfil => _perfil;
  User? get currentUser => _auth.currentUser;

  final _perfilCtrl = StreamController<UserProfile?>.broadcast();
  Stream<UserProfile?> get perfilStream => _perfilCtrl.stream;

  /// Must be called once after Firebase.initializeApp().
  void init() {
    _auth.authStateChanges().listen(
      (user) async {
        try {
          if (user == null) {
            _perfil = null;
            _perfilCtrl.add(null);
          } else {
            await _cargarPerfil(user);
            _perfilCtrl.add(_perfil);
          }
        } catch (_) {
          _perfil = null;
          _perfilCtrl.add(null);
        }
      },
      onError: (e) {
        // Log error but don't crash. Non-fatal channel errors might trigger this.
        developer.log(
          'AuthService init stream error',
          name: 'auth_service',
          level: 900, // WARNING
          error: e,
        );
      },
    );
  }

  Future<void> _cargarPerfil(User user) async {
    try {
      final doc = await _db.collection('usuarios').doc(user.uid).get();
      if (doc.exists) {
        _perfil = UserProfile.fromJson(doc.data()!, uid: user.uid);
      } else {
        // Auto-create profile on first login for the bootstrap admin.
        final esAdmin = user.email == 'jorge.bermejo@meetcard.cl';
        _perfil = UserProfile(
          uid: user.uid,
          email: user.email!,
          nombre: user.displayName ?? user.email!.split('@').first,
          rol: esAdmin ? 'admin' : 'usuario',
          permisos: UserProfile.defaultPermisos(),
        );
        await _db.collection('usuarios').doc(user.uid).set({
          ..._perfil!.toJson(),
          'creadoEn': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      _perfil = null;
    }
  }

  /// Returns null on success, error string on failure.
  Future<String?> login(String email, String password) async {
    if (!email.trim().toLowerCase().endsWith('@meetcard.cl')) {
      return 'Solo se permiten correos @meetcard.cl';
    }
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      
      // Manually trigger profile load and notification in case authStateChanges fails
      if (cred.user != null) {
        await _cargarPerfil(cred.user!);
        _perfilCtrl.add(_perfil);
      }
      
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    } catch (e) {
      return 'Error al iniciar sesión: ${e.toString()}';
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _perfil = null;
    _perfilCtrl.add(null);
  }

  Future<String?> actualizarNombre(String nombre) async {
    try {
      final user = _auth.currentUser!;
      await Future.wait([
        user.updateDisplayName(nombre),
        _db.collection('usuarios').doc(user.uid).update({'nombre': nombre}),
      ]);
      _perfil = _perfil?.copyWith(nombre: nombre);
      _perfilCtrl.add(_perfil);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> cambiarPassword(
      String currentPassword, String newPassword) async {
    try {
      final user = _auth.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    }
  }

  // ── Admin: Cloud Function calls ──────────────────────────────────────────

  Future<String?> crearUsuario({
    required String email,
    required String nombre,
    required String password,
  }) async {
    try {
      final token = await _auth.currentUser!.getIdToken();
      final resp = await http.post(
        Uri.parse('$_fnBase/crearUsuario'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'email': email, 'nombre': nombre, 'password': password}),
      );
      if (resp.statusCode == 200) return null;
      final body = jsonDecode(resp.body);
      return body['error'] ?? 'Error al crear usuario';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> eliminarUsuario(String uid) async {
    try {
      final token = await _auth.currentUser!.getIdToken();
      final resp = await http.post(
        Uri.parse('$_fnBase/eliminarUsuario'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'uid': uid}),
      );
      if (resp.statusCode == 200) return null;
      final body = jsonDecode(resp.body);
      return body['error'] ?? 'Error al eliminar usuario';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Admin: Firestore user list ────────────────────────────────────────────

  Stream<List<UserProfile>> usuariosStream() {
    return _db.collection('usuarios').snapshots().map((snap) => snap.docs
        .map((d) => UserProfile.fromJson(d.data(), uid: d.id))
        .toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre)));
  }

  Future<String?> actualizarPermisos(
      String uid, Map<String, Map<String, bool>> permisos) async {
    try {
      await _db.collection('usuarios').doc(uid).update({'permisos': permisos});
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> actualizarRol(String uid, String rol) async {
    try {
      await _db.collection('usuarios').doc(uid).update({'rol': rol});
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  String _authError(String code) => switch (code) {
        'user-not-found' => 'No existe una cuenta con este correo',
        'wrong-password' ||
        'invalid-credential' =>
          'Correo o contraseña incorrectos',
        'invalid-email' => 'Correo inválido',
        'user-disabled' => 'Esta cuenta ha sido deshabilitada',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde',
        'weak-password' =>
          'La contraseña debe tener al menos 6 caracteres',
        'email-already-in-use' => 'Este correo ya está registrado',
        _ => 'Error de autenticación ($code)',
      };
}
