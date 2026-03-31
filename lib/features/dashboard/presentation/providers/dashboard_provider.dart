import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/resumen_service.dart';

/// Provider to manage Dashboard (Home) statistics and ingesta operations.
/// Extracted from HomeView for better modularity and testability.
class DashboardProvider extends ChangeNotifier {
  Map<String, dynamic>? _stats;
  bool _isLoadingResumen = true;
  String? _errorResumen;
  bool _isTriggeringIngesta = false;

  // Firestore real-time listeners
  StreamSubscription<DocumentSnapshot>? _ingestaSub;
  StreamSubscription<DocumentSnapshot>? _procesamientoSub;

  DashboardProvider() {
    init();
  }

  // Getters
  Map<String, dynamic>? get stats => _stats;
  bool get isLoadingResumen => _isLoadingResumen;
  String? get errorResumen => _errorResumen;
  bool get isTriggeringIngesta => _isTriggeringIngesta;

  void init() {
    loadResumen();
    _subscribeStatsRealTime();
  }

  @override
  void dispose() {
    _ingestaSub?.cancel();
    _procesamientoSub?.cancel();
    super.dispose();
  }

  void _subscribeStatsRealTime() {
    final db = FirebaseFirestore.instance;
    
    _ingestaSub = db.collection('_stats').doc('ingesta').snapshots().listen((snap) {
      if (!snap.exists || _stats == null) return;
      final d = snap.data()!;
      _updateStatsSubset('ingesta', d);
    });

    _procesamientoSub = db.collection('_stats').doc('procesamiento').snapshots().listen((snap) {
      if (!snap.exists || _stats == null) return;
      final d = snap.data()!;
      _updateStatsSubset('procesamiento', d);
    });
  }

  void _updateStatsSubset(String key, Map<String, dynamic> data) {
    final ts = (data['fecha'] as Timestamp?)?.toDate();
    final fechaStr = ts == null ? null : _formatDate(ts);
    
    _stats = {
      ..._stats!,
      key: {
        ...data,
        'fecha': fechaStr,
      },
    };
    notifyListeners();
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d-$m-$y, $h:$min';
  }

  Future<void> loadResumen({bool forceRefresh = false}) async {
    _isLoadingResumen = true;
    _errorResumen = null;
    notifyListeners();

    try {
      _stats = await ResumenService.instance.load(forceRefresh: forceRefresh);
      _isLoadingResumen = false;
    } catch (e) {
      _errorResumen = e.toString();
      _isLoadingResumen = false;
    }
    notifyListeners();
  }

  Future<void> triggerIngesta() async {
    if (_isTriggeringIngesta) return;
    _isTriggeringIngesta = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken() ?? '';
      final resp = await http.get(
        Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/dispararIngestaOCDS'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 560));

      if (resp.statusCode == 200) {
        await loadResumen(forceRefresh: true);
      }
    } catch (e) {
      _errorResumen = "Error al disparar ingesta: $e";
    } finally {
      _isTriggeringIngesta = false;
      notifyListeners();
    }
  }
}
