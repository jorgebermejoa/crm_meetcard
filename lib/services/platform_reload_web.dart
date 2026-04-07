// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

@JS('window.location.reload')
external void _jsReload();

void reloadPage() => _jsReload();
