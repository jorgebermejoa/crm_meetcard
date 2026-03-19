import 'package:flutter/material.dart';

/// Global key for the root shell Scaffold.
/// Any widget can call [openAppDrawer] to open the navigation drawer,
/// regardless of where it sits in the widget tree.
final GlobalKey<ScaffoldState> appShellKey = GlobalKey<ScaffoldState>();

void openAppDrawer() => appShellKey.currentState?.openDrawer();
