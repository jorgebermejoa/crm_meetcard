import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// Colores
const Color kPrimaryColor = AppColors.primary;

// Paginación
const int kPageSize = 10;

// Cloud Functions Base URL
const String kCloudFunctionsBaseUrl = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

// Orden canónico de estado: Abierto primero, Finalizado/Sin fecha últimos
const Map<String, int> kEstadoOrder = {
  'Abierto': 0,
  'En Evaluación': 1,
  'Vigente': 2,
  'X Vencer': 3,
  'Finalizado': 4,
  'Sin fecha': 5,
};

// Abreviaturas de meses para el Gantt
const List<String> kMonthAbbr = [
  'Ene',
  'Feb',
  'Mar',
  'Abr',
  'May',
  'Jun',
  'Jul',
  'Ago',
  'Sep',
  'Oct',
  'Nov',
  'Dic',
];