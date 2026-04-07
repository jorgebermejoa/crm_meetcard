import 'dart:io';

void main() {
  const parseDateFunc = '''
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  try {
    return (value as dynamic).toDate();
  } catch (_) {
    try {
      return DateTime.parse(value.toString());
    } catch (_) {}
  }
  return null;
}

''';

  for (final path in ['lib/models/proyecto.dart', 'lib/features/proyecto/data/models/proyecto_model.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();
    
    if (!content.contains('DateTime? _parseDate')) {
      final importEnd = content.lastIndexOf(RegExp(r"^import .*;$", multiLine: true));
      if (importEnd != -1) {
        final insertIndex = content.indexOf('\n', importEnd) + 1;
        content = content.substring(0, insertIndex) + '\n' + parseDateFunc + content.substring(insertIndex);
      } else {
        content = parseDateFunc + content;
      }
    }
    
    // single line
    content = content.replaceAllMapped(
      RegExp(r"d\['([^']+)'\] != null \? DateTime\.tryParse\(d\['[^']+'\]\) : null"),
      (m) => "_parseDate(d['${m.group(1)}'])"
    );
    
    // multi line
    content = content.replaceAllMapped(
      RegExp(r"d\['([^']+)'\] != null\s*\n\s*\? DateTime\.tryParse\(d\['[^']+'\]\)\s*\n\s*: null"),
      (m) => "_parseDate(d['${m.group(1)}'])"
    );

    file.writeAsStringSync(content);
    print('Updated \$path');
  }
}
