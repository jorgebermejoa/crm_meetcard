import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile({required this.name, required this.bytes});
}

class UploadService {
  static final instance = UploadService._();
  UploadService._();

  /// Opens the native file picker. Returns the selected file, or null if cancelled.
  Future<PickedFile?> pickFile() {
    final completer = Completer<PickedFile?>();

    final input = web.HTMLInputElement();
    input.type = 'file';
    input.accept = '.pdf,.doc,.docx,.xls,.xlsx,.png,.jpg,.jpeg';
    input.style.display = 'none';
    web.document.body!.append(input);

    JSFunction? changeListener;
    changeListener = (web.Event _) {
      try {
        input.removeEventListener('change', changeListener!);
        final files = input.files;
        input.remove();
        if (files == null || files.length == 0) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final file = files.item(0)!;
        final name = file.name;
        final reader = web.FileReader();
        reader.onload = (web.Event _) {
          try {
            final result = reader.result;
            if (result == null) {
              if (!completer.isCompleted) completer.complete(null);
              return;
            }
            final bytes = (result as JSArrayBuffer).toDart.asUint8List();
            if (!completer.isCompleted) completer.complete(PickedFile(name: name, bytes: bytes));
          } catch (_) {
            if (!completer.isCompleted) completer.complete(null);
          }
        }.toJS;
        reader.onerror = (web.Event _) {
          if (!completer.isCompleted) completer.complete(null);
        }.toJS;
        reader.readAsArrayBuffer(file);
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      }
    }.toJS;

    input.addEventListener('change', changeListener);
    input.click();
    return completer.future;
  }

  /// Uploads [bytes] to Firebase Storage at [storagePath]/[timestamp]_[filename].
  /// Returns the public download URL.
  Future<String> upload({
    required Uint8List bytes,
    required String filename,
    required String storagePath,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref('$storagePath/${ts}_$filename');
    await ref.putData(bytes, SettableMetadata(contentType: _contentType(filename)));
    return ref.getDownloadURL();
  }

  String _contentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
  }
}
