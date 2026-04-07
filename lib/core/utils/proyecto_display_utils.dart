import '../../features/proyectos/data/proyectos_constants.dart';
import '../../models/proyecto.dart';

class ProyectoDisplayUtils {
  /// Strips "|" suffix and "Unidad de compra:" prefix from institution name.
  static String cleanInst(String raw) {
    var s = raw.split('|').first.trim();
    if (s.toLowerCase().startsWith('unidad de compra:')) {
      s = s.substring('unidad de compra:'.length).trim();
    }
    return s;
  }

  /// Strips the "CM: " prefix that Firestore stores in idCotizacion.
  static String cleanCmId(String id) =>
      id.startsWith('CM: ') ? id.substring(4) : id;

  /// Extracts the convenio marco ID from its URL (e.g. ".../id/5802363-3205ZEZE").
  static String? cmIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'/id/([^/\?#]+)').firstMatch(url);
    return match?.group(1);
  }

  /// Returns the best display ID for a project (licitación ID, clean CM id, or CM from URL).
  static String? projectDisplayId(Proyecto p) {
    if (p.idLicitacion?.isNotEmpty == true) return p.idLicitacion;
    if (p.idCotizacion?.isNotEmpty == true) return cleanCmId(p.idCotizacion!);
    return cmIdFromUrl(p.urlConvenioMarco);
  }

  static String formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  static String fmtDateShort(DateTime? dt) {
    if (dt == null) return '—';
    return "${kMonthAbbr[dt.month - 1]} '${dt.year.toString().substring(2)}";
  }

  /// DD/MM HH:mm h — used in Gantt postulación / ruta for exact times.
  static String fmtDt(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}h';
  }

  static String fmt(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }
}