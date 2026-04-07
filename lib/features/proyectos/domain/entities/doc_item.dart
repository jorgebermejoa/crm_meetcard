import 'package:flutter/material.dart';
import '../../../../models/proyecto.dart';

class DocItem {
  final String tipoDoc;
  final Proyecto proyecto;
  final String descripcion;
  final DateTime? fecha;
  final String? labelFecha;
  final DateTime? fechaSecundaria;
  final String? labelFechaSecundaria;
  final List<String> urls;
  final Color color;
  final String? tabTarget;

  const DocItem(
      {required this.tipoDoc,
      required this.proyecto,
      required this.descripcion,
      this.fecha,
      this.labelFecha,
      this.fechaSecundaria,
      this.labelFechaSecundaria,
      required this.urls,
      required this.color,
      this.tabTarget});
}