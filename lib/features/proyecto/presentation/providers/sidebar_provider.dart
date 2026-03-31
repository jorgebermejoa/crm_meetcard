import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider to manage the state of the collapsible sidebar with persistence.
class SidebarProvider extends ChangeNotifier {
  bool _isExpanded = true;
  static const String _key = 'sidebar_expanded';

  SidebarProvider() {
    _loadState();
  }

  bool get isExpanded => _isExpanded;
  
  /// Returns the appropriate width for the sidebar based on its state.
  double get sidebarWidth => _isExpanded ? 250.0 : 60.0;

  /// Loads the persisted state from SharedPreferences.
  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isExpanded = prefs.getBool(_key) ?? true;
    } catch (e) {
      debugPrint('SharedPreferences load error (incognito mode?): $e');
      _isExpanded = true; // Fallback to expanded sidebar
    }
    notifyListeners();
  }

  /// Toggles the sidebar state and persists the change.
  Future<void> toggleSidebar() async {
    _isExpanded = !_isExpanded;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, _isExpanded);
    } catch (e) {
      debugPrint('SharedPreferences save error (incognito mode?): $e');
    }
  }

  /// Programmatically expands the sidebar.
  void expandSidebar() {
    if (!_isExpanded) {
      toggleSidebar();
    }
  }

  /// Programmatically collapses the sidebar.
  void collapseSidebar() {
    if (_isExpanded) {
      toggleSidebar();
    }
  }
}
