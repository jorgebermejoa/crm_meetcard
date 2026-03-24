import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../app_shell.dart';
import '../models/proyecto.dart';
import '../services/bigquery_service.dart';
import '../services/licitacion_api_service.dart';
import '../services/proyectos_service.dart';
import 'app_breadcrumbs.dart';

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';
const _primaryColor = Color(0xFF5B21B6);
const _bgColor = Color(0xFFF2F2F7);

// ── Datos CSV ─────────────────────────────────────────────────────────────
// Modalidad, Código, Productos, Estado, Comentario, Meses, ValorMensual

class _R {
  final String mod;       // 'Licitación Pública' | 'Convenio Marco'
  final String cod;       // Código Adquisición
  final String prod;      // productos
  final String est;       // estado CSV
  final String com;       // comentario/notas
  final int meses;        // plazo de duración en meses
  final int? vm;          // valor mensual (null si vacío en CSV)
  const _R(this.mod, this.cod, this.prod, this.est, this.com, this.meses, this.vm);

  bool get isLP => mod == 'Licitación Pública';
  String? get idLicitacion => isLP ? cod : null;
  String? get urlConvenio => isLP
      ? null
      : 'https://conveniomarco2.mercadopublico.cl/software3/quote_public/requestquote/view/id/$cod/';
}

const _rows = [
  // ── Migración 2: En Evaluación ──────────────────────────────────────────
  _R('Licitación Pública','1048-12-LE26','EME','En Evaluación','Provisión de botón de pánico inalámbrico',12,750000),
  _R('Licitación Pública','2667-2-LR26','APP, TV, ATV','En Evaluación','',36,5161993),
  _R('Licitación Pública','2675-30-LE26','EME','En Evaluación','',12,1593669),
  _R('Licitación Pública','2793-23-LE26','WEB','En Evaluación','',3,5416667),
  _R('Licitación Pública','3880-7-LE26','EME','En Evaluación','Oferta Técnica evaluada con 0 puntos, se procede con reclamo',11,800000),
  _R('Licitación Pública','2560-107-LR25','EME','En Evaluación','',48,8218438),
  // ── Migración 1: Histórico ───────────────────────────────────────────────
  _R('Licitación Pública','2345-42-LR26','GDOC','Desestimada','',48,2256832),
  _R('Licitación Pública','3929-13-LE26','OTRO','Desestimada','No tenemos plataforma de encuestas con tantas funcionalidades',34,1529412),
  _R('Licitación Pública','4963-6-LE26','GDOC','Desestimada','',12,1000000),
  _R('Licitación Pública','3603-11-LE26','GDOC','Desestimada','No tenemos gestor documental desarrollado',36,1500000),
  _R('Licitación Pública','1057489-62-LP26','CHBOT','Desestimada','No tenemos chatbot',36,3611111),
  _R('Licitación Pública','3656-69-LE26','GDOC','Desestimada','No tenemos gestor documental desarrollado',24,1541667),
  _R('Licitación Pública','2693-2-LE26','GDOC','Desestimada','No tenemos gestor documental desarrollado',24,2500000),
  _R('Convenio Marco','5802363-7892HLQT','GDOC','Desestimada','No tenemos gestor documental desarrollado',36,1672898),
  _R('Licitación Pública','2423-14-LP26','GDOC','Desestimada','No tenemos gestor documental desarrollado',36,3000000),
  _R('Licitación Pública','4956-16-LP26','CHBOT','Desestimada','No tenemos chatbot',24,6250000),
  _R('Licitación Pública','2483-19-LP26','CHBOT','Desestimada','No tenemos chatbot',12,10000000),
  _R('Licitación Pública','642028-2-LE26','GDOC','Desestimada','No tenemos gestor documental desarrollado',24,2000000),
  _R('Licitación Pública','1082957-6-LE26','SUAC','Desestimada','Se solicitan exigencias específicas para elaborar una propuesta competitiva en paralelo con Huechuraba, San Bernardo y Paine',12,1416667),
  _R('Licitación Pública','622-5-LR26','SUAC','Desestimada','',48,11481886),
  _R('Convenio Marco','5802363-8578IRQX','EME','Desestimada','Pide integración con bomberos (10% de la evaluación) - Usuarios 5.000 - Registros de 300.000',9,973909),
  _R('Convenio Marco','5802363-2799OILF','GDOC','Desestimada','No tenemos gestor documental desarrollado',12,1935013),
  _R('Convenio Marco','5802363-1396QAED','APP, TV','Revocada','Bases incorrectas: no suma 100% la evaluación',12,3342554),
  _R('Convenio Marco','5802363-6126HPHQ','APP, TV','Revocada','No se puede postular por las HH de las BA',12,3342554),
  _R('Convenio Marco','5802363-2403TYES','EME','Desestimada','Requiere usuarios registrados',12,6225269),
  _R('Licitación Pública','2560-106-LP25','APP, TV','Revocada','Municipalidad indica que proyecto estará incluido en otra plataforma',24,8000000),
  _R('Licitación Pública','5482-134-LP25','APP, TV','Revocada','',36,2540277),
  _R('Licitación Pública','2770-213-LP25','EME','Desestimada','Integraciones con central telefónica, ISO 27001, ISO 22301, ISO9001, ISO 37001',24,11521875),
  _R('Licitación Pública','2585-133-LE25','EME','Desestimada','Certificaciones ISO 27001, ISO 22301, ISO9001, ISO 37001',12,3000000),
  _R('Convenio Marco','5802363-7693AUZP','AGENDA','Desestimada','No tenemos servicio de contactabilidad vía whatsapp con chatbot',12,691586),
  _R('Convenio Marco','5802363-9678TXWE','GDOC','Desestimada','No tenemos gestor documental desarrollado',36,1385950),
  _R('Convenio Marco','5802363-0195YBDM','EME','Desestimada','Requiere integración con Bomberos y base de usuarios preexistente de 300.000 registros',12,2688929),
  _R('Licitación Pública','1216088-20-LE25','TYA','Desestimada','App móvil + sistema campeonatos + geolocalización requeridos en 20 días hábiles; presupuesto máximo \$22.000.000 en 24 meses',24,916667),
  _R('Convenio Marco','5802363-1031CMTM','APP, TYA, TV, WEB','Revocada','Se revoca por no adjuntar documentos',36,4186701),
  _R('Licitación Pública','717503-16-LE25','PROY','Desestimada','',28,1214501),
  _R('Licitación Pública','5420-25-LE25','WEB','Desestimada','Criterios de evaluación ambiguos en licitación anterior',12,2666667),
  _R('Licitación Pública','2337-61-LP25','LIC','Desestimada','Presupuesto escaso',12,541667),
  _R('Licitación Pública','4280-51-LE25','GDOC','Desestimada','No tenemos gestor',12,1083333),
  _R('Licitación Pública','622-94-LR25','SUAC','Desestimada','Certificaciones y Estándares: A lo menos ISO 27001 y/o SOC 2 u otras no mencionadas, adicionalmente cumplir con GDPR',18,25862813),
  _R('Licitación Pública','2582-118-LE25','WEB','Desestimada','Requiere servidor',24,1333333),
  _R('Licitación Pública','3181-56-LE25','GDOC','Desestimada','No tenemos gestor',24,1666667),
  _R('Convenio Marco','5802363-8855OWEJ','SUAC','Desierta','Requisito de certificaciones en laravel',14,4752548),
  _R('Licitación Pública','3693-170-L125','GDOC','Competencia','Bajo presupuesto, solo soporte y mantención',6,1100000),
  _R('Licitación Pública','834259-53-LE25','GDOC','Desestimada','No tenemos gestor',24,791667),
  _R('Licitación Pública','2337-58-LP25','LIC','Revocada','Presupuesto escaso; revocada por problemas con los TTR',12,541667),
  _R('Licitación Pública','3594-26-LE25','GDOC','Competencia','No tenemos gestor',36,958333),
  _R('Convenio Marco','5802363-8315BPMA','GDOC','Competencia','No tenemos gestor',36,1458428),
  _R('Convenio Marco','5802363-7040ORXL','SUAC','Desierta','Entrega de Código fuente',6,10624459),
  _R('Licitación Pública','1437-14-LE25','GDOC, INET','Competencia','No tenemos gestor',18,1388889),
  _R('Licitación Pública','728-21-LE25','GDOC','Competencia','Adquisición',24,1125000),
  _R('Licitación Pública','1133353-28-LE25','GDOC','Desierta','No tenemos gestor',12,1333333),
  _R('Convenio Marco','5802363-4871UTKB','GDOC','Desestimada','',2,12629825),
  _R('Licitación Pública','586-60-LQ25','GDOC','Desestimada','No tenemos gestor',75,2666667),
  _R('Convenio Marco','5802363-5218CNSI','GDOC','Competencia','No tenemos gestor',24,2875244),
  _R('Convenio Marco','5802363-7757PVKX','WEB','Desestimada','Requiere cake para el framework',9,3363527),
  _R('Licitación Pública','3760-6-LE25','GDOC','Desestimada','',36,972222),
  _R('Licitación Pública','2699-33-LE25','GDOC','Competencia','',24,2573111),
  _R('Licitación Pública','2436-56-LE25','EME','Desestimada','Requiere funcionalidades adicionales',12,2700000),
  _R('Licitación Pública','1048-61-LE25','ATV','Desierta','Entidad señala que al cambiar el año presupuestario no fue agregado al respectivo presupuesto',1,17850499),
  _R('Licitación Pública','5420-13-LE25','INET, WEB','Desierta','',12,2666667),
  _R('Convenio Marco','5802363-0837DGTW','SUAC','Desierta','Desestimada por el comprador',24,2796790),
  _R('Licitación Pública','1057480-67-LE25','CHBOT, SUAC','Competencia','Precios presentados por otros oferentes muy por debajo del precio presentado por Meetcard',24,2833333),
  _R('Licitación Pública','1287766-9-L125','TYA','Desestimada','Presupuesto bajo \$7.000.000 y requiere módulo de torneos e integración con torniquetes y pasarela de pago',12,583333),
  _R('Licitación Pública','1658-277-LQ25','GDOC','Desestimada','Requiere demo de presentación posterior al envío de la propuesta',36,4497306),
  _R('Licitación Pública','5056-77-LP25','CHBOT','Desestimada','Reclamo por ilegalidad de criterio de evaluación; 13/08/2024 se acoge íntegramente el reclamo',24,4908750),
  _R('Licitación Pública','628-15-LE25','SUAC','Desestimada','Entrega del código fuente',12,5000000),
  _R('Licitación Pública','1082957-40-LE25','SUAC','Desierta','',12,1666667),
  _R('Licitación Pública','2402-42-LE25','GDOC','Competencia','Se descarta postulación por plazos de elaboración de propuesta',36,1300000),
  _R('Licitación Pública','2295-86-LP25','EME','Competencia','Se descarta por dispositivos externos (botones de pánico)',12,8333333),
  _R('Licitación Pública','3378-43-LP25','AGENDA','Desestimada','Exige al menos 1 experiencia comprobable',36,4000000),
  _R('Licitación Pública','4956-56-LE25','APP, TV, TYA, WEB, OTRO','Desierta','Presupuesto insuficiente y requerimiento de módulo financiero-contable',24,1257617),
  _R('Licitación Pública','2455-50-LE25','GDOC','Competencia','Requiere implementación en al menos 1 comuna',12,2590000),
  _R('Licitación Pública','3847-18-LE25','CORREOS, WEB','Revocada','Solicita visitas técnicas presenciales 1 vez por semana',20,1700000),
  _R('Licitación Pública','4055-25-LE25','GDOC','Competencia','',24,1250000),
  _R('Licitación Pública','1221016-24-LP25','GDOC','Competencia','',36,2500000),
  _R('Convenio Marco','5802363-9014SZDN','SUAC','Desestimada','',27,13870821),
  _R('Licitación Pública','584264-16-LP25','GDOC','Competencia','',36,3750000),
  _R('Licitación Pública','2359-11-LP25','WEB','Desestimada','',48,2300000),
  _R('Licitación Pública','761-22-L125','CHBOT','Desierta','Chatbot requiere desarrollo',12,538883),
  _R('Convenio Marco','5802363-0627USXG','SUAC','Desierta','',12,1284895),
  _R('Licitación Pública','1211839-46-LP25','EME','Desierta','',36,2916667),
  _R('Convenio Marco','5802363-1063GOVD','SUAC','Desestimada','Solicitan Dynamics 365',12,3565834),
  _R('Convenio Marco','5802363-5341DHAW','ATV','Desestimada','No responden preguntas realizadas; pedían software específico',12,3863750),
  _R('Licitación Pública','2667-24-LR25','GDOC','Competencia','No tenemos gestor documental',60,12616545),
  _R('Licitación Pública','1289422-13-LP25','TYA','Desestimada','Solicitan demo para el jueves 22/5',36,2270917),
  _R('Licitación Pública','2667-37-LE25','WEB','Desestimada','',12,1333333),
  _R('Convenio Marco','5802363-0840HNPI','WEB','Desestimada','',12,2121572),
  _R('Convenio Marco','5802363-2823XMAY','EME','Desestimada','Requiere más de 1,5 millones de usuarios registrados',24,1780958),
  _R('Convenio Marco','5802363-0984OEML','ATV','Desierta','No responden preguntas realizadas; pedían software específico',12,3867469),
  _R('Convenio Marco','5802363-6596HSGI','WEB','Desierta','',7,2079169),
  _R('Convenio Marco','5802363-2591UIQP','WEB','Desestimada','Requiere Wordpress y Laravel',18,2850896),
  _R('Licitación Pública','2793-86-LE25','WEB','Revocada','Se adjudica a Cybercenter pero la revocan luego del reclamo de JBA',24,1423000),
  _R('Licitación Pública','1260-21-LE25','WEB','Desestimada','Requiere Wordpress (BA página 2)',12,null),
  _R('Licitación Pública','3671-28-LE25','WEB','Desestimada','',12,700000),
  _R('Licitación Pública','1388961-29-LR25','EME','Desestimada','',24,21888000),
  _R('Licitación Pública','2582-31-LR25','ATV, EME','Revocada','',36,13916667),
  _R('Convenio Marco','5802363-7073TFCU','APP, TV','Finalizada','',8,4398526),
  _R('Convenio Marco','5802363-2904YQDR','SUAC','Desierta','',24,15604674),
  _R('Licitación Pública','1084140-1-LP25','ATV, GDOC','Competencia','No responden preguntas del foro',12,null),
  _R('Licitación Pública','537934-7-LQ25','WEB','Desestimada','No se aborda la postulación',36,null),
  _R('Licitación Pública','2793-62-LE25','WEB','Revocada','Requiere solo mantención; la municipalidad es propietaria del sitio web',24,1423000),
  _R('Convenio Marco','5802363-2281KDYB','EME','Desierta','Requería 300.000 usuarios registrados en la plataforma',12,3090589),
  _R('Licitación Pública','633-18-LR25','TYA','Desestimada','',24,23250000),
  _R('Licitación Pública','3756-8-LE25','ATV','Desestimada','Falta presupuesto para adicionales como pago de plan de datos',10,3200000),
  _R('Licitación Pública','1057432-12-LE25','CORREOS','Desierta','',24,2708333),
  _R('Licitación Pública','4314-15-LE25','WEB','Desestimada','Falta de presupuesto',36,233333),
  _R('Convenio Marco','5802363-0845XFMM','SUAC','Desierta','Faltan certificaciones',12,3565834),
  _R('Licitación Pública','2963-9-LE25','WEB','Desestimada','Wordpress, Datacenter en Chile',12,2000000),
  _R('Licitación Pública','2436-15-LE25','EME','Desierta','Funcionalidades incompatibles con Meetcard (punto 17 BT)',10,2618000),
  _R('Convenio Marco','5802363-4805YEXC','WEB','Desestimada','Solicitan Intranet, Tarjeta Vecino, Portal Ciudadano y entrega CF',36,1934537),
  _R('Convenio Marco','5802363-8290SEQK','APP, TV','Finalizada','',12,2423705),
  _R('Licitación Pública','3559-5-LE25','APP','Desestimada','Solicita Chats',18,1489042),
  _R('Convenio Marco','5802363-7436WJXA','APP, TYA, TV, WEB','Finalizada','',12,4316186),
  _R('Convenio Marco','5802363-9519ILKZ','APP, TV','Finalizada','',12,2386220),
  _R('Convenio Marco','5802363-9956FQXL','EME','Desestimada','SOSAFE',12,2596352),
  _R('Convenio Marco','5802363-3738YVBX','APP, TYA, TV, WEB','Revocada','Rechazada',12,4065947),
  _R('Convenio Marco','5802363-2852GVGQ','SUAC','Desestimada','Solo Laravel en framework',19,3583658),
  _R('Convenio Marco','5802363-3209MGGS','APP, TV','Revocada','Desestimada por Municipio',15,2385988),
  _R('Convenio Marco','5802363-4001FAOI','WEB','Desestimada','No responden preguntas del foro',12,647428),
  _R('Licitación Pública','2585-290-LE24','ATV','Revocada','Se revoca por cambio de administración',12,1666667),
  _R('Convenio Marco','5802363-4745BNBH','SUAC','Desestimada','',3,6316905),
  _R('Convenio Marco','5802363-3726XIUK','APP, TV','Revocada','No respondieron preguntas realizadas',12,3984172),
  _R('Convenio Marco','5802363-7941PKEY','TV','Finalizada','',12,3160776),
  _R('Convenio Marco','5802363-7211DDKO','PROY','Desestimada','Complejidad de hacer un mix de proyectos y atv',4,5209305),
  _R('Convenio Marco','5802363-7504JPOK','SUAC','Desestimada','Dificultades de integración con otros sistemas',5,3600000),
  _R('Licitación Pública','812799-50-LE24','FORM, OMIL','Finalizada','',12,1600000),
  _R('Licitación Pública','2392-60-LE24','WEB','Desestimada','DataCenter en territorio nacional',14,2757143),
  _R('Licitación Pública','4127-40-LP24','APP','Desestimada','Sin Observaciones',1,120000000),
  _R('Licitación Pública','612-28-LE24','WEB','Desierta','Exige certificación ISO 9001 empresa y Drupal',36,940707),
  _R('Licitación Pública','2767-10-LE24','WEB','Desestimada','',24,1666667),
  _R('Licitación Pública','3603-71-LE24','ATV','Desestimada','No cumple con función de videollamada',12,708333),
  _R('Licitación Pública','463-3-LE24','APP','Competencia','iAnalytic mejor oferta económica y equipo',6,8333333),
  _R('Licitación Pública','2719-24-LE24','APP, TV','Competencia','LIGUP: mejor oferta económica',9,1652222),
  _R('Licitación Pública','2432-13-LE24','PAT','Desestimada','Adquisición indefinida del producto',12,2500000),
  _R('Licitación Pública','4086-24-LE24','EME','Competencia','',12,541667),
  _R('Licitación Pública','2324-458-LQ23','PAT','Revocada','',39,3378462),
  _R('Licitación Pública','1051177-11-LP23','APP','Desierta','Averiguar',10,11000000),
  _R('Licitación Pública','2490-97-LR23','EME','Competencia','',72,13538991),
  _R('Licitación Pública','4629-74-LP23','SUAC','Finalizada','Presupuesto Referencial de 2355 UF',16,5437500),
  _R('Licitación Pública','1736-51-LE23','APP','Finalizada','',20,1200000),
  _R('Licitación Pública','2585-241-LE22','WEB','Finalizada','',24,2083333),
  _R('Licitación Pública','4459-3-LE23','EME','Competencia','',18,2771667),
  _R('Licitación Pública','5482-9-LQ22','APP, TV','Finalizada','',48,2500000),
  _R('Licitación Pública','2699-33-LQ21','ATV','Finalizada','',36,4000000),
  _R('Licitación Pública','2770-55-LQ20','WEB','Finalizada','',36,2800000),
  _R('Licitación Pública','2560-11-LR20','APP, TV','Finalizada','',60,7184589),
  _R('Licitación Pública','3504-21-L119','TV','Finalizada','',12,329167),
];

// ── Resultado de migración por fila ───────────────────────────────────────

enum _Status { ok, skip, warn, error, running }

class _MigResult {
  final _R row;
  _Status status;
  String msg;
  String? proyectoId;
  _MigResult(this.row) : status = _Status.running, msg = 'Procesando…';
}

// ── Vista ─────────────────────────────────────────────────────────────────

class MigracionView extends StatefulWidget {
  const MigracionView({super.key});

  @override
  State<MigracionView> createState() => _MigracionViewState();
}

class _MigracionViewState extends State<MigracionView> {
  bool _running = false;
  final List<_MigResult> _log = [];
  Set<String> _existingLPs = {};
  Set<String> _existingCMs = {};
  Map<String, dynamic>? _bqResult;
  bool _bqLoading = false;
  // Log de correcciones BQ: { tipo, id, msg, ok }
  final List<Map<String, dynamic>> _bqFixLog = [];
  bool _bqFixRunning = false;
  // Duplicados: lista de grupos { idLicitacion, proyectos: [...] }
  List<Map<String, dynamic>>? _duplicados;
  bool _dupLoading = false;
  bool _dupRunning = false;
  final List<Map<String, dynamic>> _dupLog = [];

  int get _lpCount => _rows.where((r) => r.isLP).length;
  int get _cmCount => _rows.where((r) => !r.isLP).length;

  Future<void> _loadExisting() async {
    final all = await ProyectosService.instance.load(forceRefresh: true);
    _existingLPs = all
        .where((p) => p.idLicitacion != null)
        .map((p) => p.idLicitacion!)
        .toSet();
    _existingCMs = all
        .where((p) => p.urlConvenioMarco != null)
        .map((p) => p.urlConvenioMarco!)
        .toSet();
  }

  bool _isDuplicate(_R r) {
    if (r.isLP) return _existingLPs.contains(r.cod);
    return _existingCMs.any((u) => u.contains(r.cod));
  }

  Future<void> _migrateOne(_MigResult res) async {
    final r = res.row;
    if (_isDuplicate(r)) {
      res.status = _Status.skip;
      res.msg = 'Ya existe en la base de datos';
      return;
    }

    // ── 1. Buscar institución, fechas y datos externos ──
    String institucion = r.cod;
    Map<String, dynamic>? externalData;
    String? cacheKey;
    DateTime? fechaInicio;
    DateTime? fechaTermino;

    try {
      if (r.isLP) {
        // OCDS → fallback MP API
        final info = await LicitacionApiService.instance.fetchLP(r.cod);
        if (info.institucion.isNotEmpty && info.institucion != r.cod) {
          institucion = info.institucion;
        }
        fechaInicio = info.fechaAdjudicacion;
        externalData = info.data;
        cacheKey = info.cacheKey;

        // Calcular fechaTermino = fechaInicio + meses
        if (fechaInicio != null) {
          fechaTermino = LicitacionApiService.addMonths(fechaInicio, r.meses);
        }
      } else {
        // Convenio Marco
        final url = r.urlConvenio!;
        final resp = await http
            .get(Uri.parse(
                '$_cfBase/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(url)}'))
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) {
          externalData = json.decode(resp.body) as Map<String, dynamic>;
          cacheKey = 'convenio';
          final comprador = externalData['comprador']?.toString() ?? '';
          if (comprador.isNotEmpty) {
            institucion = comprador.split('|').first.trim();
          }

          // Buscar "fin de evaluación" en campos (prioridad) → fallback última fecha
          final campos =
              (externalData['campos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          DateTime? finEvaluacion;
          DateTime? lastDate;
          for (final c in campos) {
            final label = (c['label'] ?? c['nombre'] ?? '').toString().toLowerCase();
            final d = LicitacionApiService.parseDate(c['valor']?.toString());
            if (d == null) continue;
            if (label.contains('fin') && label.contains('evaluaci')) finEvaluacion = d;
            if (lastDate == null || d.isAfter(lastDate)) lastDate = d;
          }
          // Campos de primer nivel
          for (final key in ['fechaVencimiento', 'vencimiento']) {
            final d = LicitacionApiService.parseDate(externalData[key]?.toString());
            if (d != null && (lastDate == null || d.isAfter(lastDate))) lastDate = d;
          }

          final baseDate = finEvaluacion ?? lastDate;
          if (baseDate != null) {
            fechaInicio = baseDate;
            fechaTermino = LicitacionApiService.addMonths(baseDate, r.meses);
          }

        }
      }
    } catch (_) {
      // institución y fechas quedan como fallback; editar luego
    }

    // ── 3. Crear proyecto ──
    final body = <String, dynamic>{
      'institucion': institucion,
      'productos': r.prod,
      'modalidadCompra': r.mod,
      'completado': false,
      'estadoManual': r.est,
    };
    if (r.idLicitacion != null) body['idLicitacion'] = r.idLicitacion;
    if (r.urlConvenio != null) body['urlConvenioMarco'] = r.urlConvenio;
    if (r.com.isNotEmpty) body['notas'] = r.com;
    if (r.vm != null) body['valorMensual'] = r.vm;
    if (fechaInicio != null) body['fechaInicio'] = fechaInicio.toIso8601String();
    if (fechaTermino != null) body['fechaTermino'] = fechaTermino.toIso8601String();

    final createResp = await http
        .post(Uri.parse('$_cfBase/crearProyecto'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body))
        .timeout(const Duration(seconds: 20));

    if (createResp.statusCode != 200) {
      res.status = _Status.error;
      res.msg = 'HTTP ${createResp.statusCode}: ${createResp.body}';
      return;
    }

    // Intentar obtener el ID del proyecto creado
    String? proyectoId;
    try {
      final decoded = json.decode(createResp.body);
      proyectoId = decoded['id']?.toString();
    } catch (_) {}

    if (proyectoId == null) {
      try {
        final all = await ProyectosService.instance.load(forceRefresh: true);
        final match = r.isLP
            ? all.firstWhere((p) => p.idLicitacion == r.cod,
                orElse: () => throw Exception())
            : all.firstWhere(
                (p) => p.urlConvenioMarco?.contains(r.cod) == true,
                orElse: () => throw Exception());
        proyectoId = match.id;
      } catch (_) {}
    }

    // ── 4. Actualizar campos que crearProyecto no persiste ──
    if (proyectoId != null) {
      final updates = <String, dynamic>{'id': proyectoId};
      if (r.est.isNotEmpty) updates['estadoManual'] = r.est;
      if (updates.length > 1) {
        await http
            .post(Uri.parse('$_cfBase/actualizarProyecto'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(updates))
            .timeout(const Duration(seconds: 10));
      }
    }

    // ── 5. Cachear datos externos (fire & forget) ──
    if (proyectoId != null && externalData != null && cacheKey != null) {
      http
          .post(Uri.parse('$_cfBase/guardarCacheExterno'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'proyectoId': proyectoId,
                'tipo': cacheKey,
                'data': externalData,
              }))
          .ignore();
    }

    res.status = _Status.ok;
    res.proyectoId = proyectoId;
    final fechaStr = fechaTermino != null
        ? ' · hasta ${fechaTermino.day.toString().padLeft(2, '0')}/${fechaTermino.month.toString().padLeft(2, '0')}/${fechaTermino.year}'
        : '';
    res.msg = 'Creado · $institucion$fechaStr${proyectoId != null ? ' · $proyectoId' : ''}';
  }

  Future<void> _run(List<_R> toProcess) async {
    if (_running) return;
    await _loadExisting();

    final results = toProcess.map(_MigResult.new).toList();
    setState(() {
      _running = true;
      _log.insertAll(0, results);
    });

    for (final res in results) {
      final wasDuplicate = _isDuplicate(res.row);
      try {
        await _migrateOne(res);
      } catch (e) {
        res.status = _Status.error;
        res.msg = e.toString();
      }
      if (mounted) setState(() {});
      // Pausa entre filas que hacen llamadas a API para no saturar el servicio
      if (!wasDuplicate && mounted) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    ProyectosService.instance.invalidate();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _runTest() async {
    final lp = _rows.firstWhere((r) => r.isLP);
    final cm = _rows.firstWhere((r) => !r.isLP);
    await _run([lp, cm]);
  }

  Future<void> _runAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Migrar todos',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text(
            'Se procesarán ${_rows.length} filas del CSV. Las duplicadas se omitirán automáticamente.\n\n¿Continuar?',
            style: GoogleFonts.inter()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: GoogleFonts.inter())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: _primaryColor),
              child: Text('Migrar',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm == true) await _run(_rows);
  }

  /// Elimina los proyectos de prueba (1 LP + 1 CM) si existen.
  Future<void> _deleteTestProjects() async {
    if (_running) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar prueba',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text(
            'Se eliminarán los proyectos de prueba:\n• ${_rows.firstWhere((r) => r.isLP).cod}\n• ${_rows.firstWhere((r) => !r.isLP).cod}\n\n¿Continuar?',
            style: GoogleFonts.inter()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: GoogleFonts.inter())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Eliminar',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _running = true);
    final testLP = _rows.firstWhere((r) => r.isLP);
    final testCM = _rows.firstWhere((r) => !r.isLP);

    try {
      final all = await ProyectosService.instance.load(forceRefresh: true);
      var deleted = 0;
      for (final r in [testLP, testCM]) {
        final match = r.isLP
            ? all.where((p) => p.idLicitacion == r.cod).firstOrNull
            : all.where((p) => p.urlConvenioMarco?.contains(r.cod) == true).firstOrNull;
        if (match == null) continue;
        final resp = await http.post(
          Uri.parse('$_cfBase/eliminarProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': match.id}),
        );
        if (resp.statusCode == 200) deleted++;
      }
      ProyectosService.instance.invalidate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$deleted proyecto(s) de prueba eliminado(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ── Análisis BigQuery ──────────────────────────────────────────────────

  Future<void> _runAnalisisBQ() async {
    if (_bqLoading || _running) return;
    setState(() { _bqLoading = true; _bqResult = null; });
    try {
      final result = await BigQueryService.instance.analizarMesesPublicadoOC();
      if (mounted) setState(() => _bqResult = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _bqLoading = false);
    }
  }

  // ── Correcciones BQ ────────────────────────────────────────────────────

  /// Agrega la OC de BQ a idsOrdenesCompra de cada proyecto en ocFaltante.
  Future<void> _registrarOCsFaltantes(List<Map<String, dynamic>> items) async {
    if (_bqFixRunning) return;
    setState(() { _bqFixRunning = true; _bqFixLog.clear(); });
    for (final row in items) {
      final proyectoId = row['proyectoId']?.toString() ?? '';
      final ocBQ       = row['id_oc_bq']?.toString() ?? '';
      if (proyectoId.isEmpty || ocBQ.isEmpty) continue;
      final currentOCs = List<String>.from(row['oc_en_app'] as List? ?? []);
      if (!currentOCs.map((o) => o.toUpperCase()).contains(ocBQ.toUpperCase())) {
        currentOCs.add(ocBQ);
      }
      try {
        final resp = await http.post(
          Uri.parse('$_cfBase/actualizarProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': proyectoId, 'idsOrdenesCompra': currentOCs}),
        ).timeout(const Duration(seconds: 15));
        final ok = resp.statusCode == 200;
        setState(() => _bqFixLog.add({
          'tipo': 'oc', 'id': row['id_licitacion'], 'oc': ocBQ,
          'msg': ok ? 'OC registrada → $proyectoId' : 'Error ${resp.statusCode}',
          'ok': ok,
        }));
      } catch (e) {
        setState(() => _bqFixLog.add({
          'tipo': 'oc', 'id': row['id_licitacion'], 'oc': ocBQ,
          'msg': 'Error: $e', 'ok': false,
        }));
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    ProyectosService.instance.invalidate();
    if (mounted) setState(() => _bqFixRunning = false);
  }

  /// Crea proyectos para las licitaciones de BQ no presentes en la app.
  /// Usa OCDS → MP API (mismo fallback que migración CSV).
  Future<void> _crearProyectosFaltantes(List<Map<String, dynamic>> items) async {
    if (_bqFixRunning) return;
    setState(() { _bqFixRunning = true; _bqFixLog.clear(); });
    for (final row in items) {
      final idLicit = row['id_licitacion']?.toString() ?? '';
      final idOC    = row['id_oc_bq']?.toString() ?? '';
      if (idLicit.isEmpty) continue;
      try {
        // 1. Obtener datos via OCDS → MP API
        final info = await LicitacionApiService.instance.fetchLP(idLicit);

        // 2. Fechas: intentar contractPeriod del OCDS, fallback a fecha_envio_oc de BQ
        DateTime? fechaInicio;
        DateTime? fechaTermino;

        if (info.ocdsData != null) {
          final releases = (info.ocdsData!['releases'] as List?)
              ?.cast<Map<String, dynamic>>() ?? [];
          if (releases.isNotEmpty) {
            final last = releases.last;
            final contracts = (last['contracts'] as List?)
                ?.cast<Map<String, dynamic>>() ?? [];
            if (contracts.isNotEmpty) {
              final period = contracts.first['period'] as Map<String, dynamic>?;
              fechaInicio  = LicitacionApiService.parseDate(period?['startDate']?.toString());
              fechaTermino = LicitacionApiService.parseDate(period?['endDate']?.toString());
            }
            // Fallback a awardPeriod si no hay contrato
            if (fechaInicio == null) {
              final tender = last['tender'] as Map<String, dynamic>? ?? {};
              fechaInicio = LicitacionApiService.parseDate(
                  tender['awardPeriod']?['startDate']?.toString());
            }
          }
        }
        // Último fallback: fecha_envio_oc de BQ (DD/MM/YYYY)
        fechaInicio ??= LicitacionApiService.parseDate(row['fecha_envio_oc']?.toString());

        // 3. Crear proyecto
        final body = <String, dynamic>{
          'institucion':   info.institucion.isNotEmpty ? info.institucion : idLicit,
          'productos':     '',
          'modalidadCompra': 'Licitación Pública',
          'completado':    false,
          'idLicitacion':  idLicit,
          if (idOC.isNotEmpty) 'idsOrdenesCompra': [idOC],
          if (fechaInicio  != null) 'fechaInicio':  fechaInicio.toIso8601String(),
          if (fechaTermino != null) 'fechaTermino': fechaTermino.toIso8601String(),
        };

        final createResp = await http.post(
          Uri.parse('$_cfBase/crearProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(body),
        ).timeout(const Duration(seconds: 20));

        String? proyectoId;
        try { proyectoId = json.decode(createResp.body)['id']?.toString(); } catch (_) {}

        // 4. Guardar caché externo (fire & forget)
        if (proyectoId != null && info.data != null) {
          http.post(
            Uri.parse('$_cfBase/guardarCacheExterno'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'proyectoId': proyectoId, 'tipo': info.cacheKey, 'data': info.data}),
          ).ignore();
        }

        final ok = createResp.statusCode == 200;
        setState(() => _bqFixLog.add({
          'tipo': 'crear', 'id': idLicit, 'oc': idOC,
          'msg': ok
              ? 'Creado · ${info.institucion} · fuente: ${info.source}${proyectoId != null ? ' · $proyectoId' : ''}'
              : 'Error ${createResp.statusCode}: ${createResp.body}',
          'ok': ok,
        }));
      } catch (e) {
        setState(() => _bqFixLog.add({
          'tipo': 'crear', 'id': idLicit, 'oc': idOC,
          'msg': 'Error: $e', 'ok': false,
        }));
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    ProyectosService.instance.invalidate();
    if (mounted) setState(() => _bqFixRunning = false);
  }

  // ── Duplicados ─────────────────────────────────────────────────────────

  Future<void> _detectarDuplicados() async {
    if (_dupLoading) return;
    setState(() { _dupLoading = true; _duplicados = null; _dupLog.clear(); });
    try {
      final all = await ProyectosService.instance.load(forceRefresh: true);
      // Agrupar por idLicitacion normalizado
      final grupos = <String, List<Map<String, dynamic>>>{};
      for (final p in all) {
        final key = (p.idLicitacion ?? '').trim().toUpperCase();
        if (key.isEmpty) continue;
        grupos.putIfAbsent(key, () => []).add({
          'id':               p.id,
          'idLicitacion':     p.idLicitacion,
          'institucion':      p.institucion,
          'idsOrdenesCompra': p.idsOrdenesCompra,
          'fechaCreacion':    p.fechaCreacion?.toIso8601String(),
          'fechaInicio':      p.fechaInicio?.toIso8601String(),
          'fechaTermino':     p.fechaTermino?.toIso8601String(),
          'notas':            p.notas,
          'estadoManual':     p.estadoManual,
          'valorMensual':     p.valorMensual,
        });
      }
      final duplicados = grupos.entries
          .where((e) => e.value.length > 1)
          .map((e) => {'idLicitacion': e.key, 'proyectos': e.value})
          .toList()
          ..sort((a, b) => (a['idLicitacion'] as String)
              .compareTo(b['idLicitacion'] as String));
      setState(() => _duplicados = duplicados);
    } finally {
      if (mounted) setState(() => _dupLoading = false);
    }
  }

  Future<void> _unificarTodos() async {
    final grupos = _duplicados;
    if (grupos == null || grupos.isEmpty || _dupRunning) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unificar duplicados',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text(
          'Se unificarán ${grupos.length} grupos de proyectos duplicados.\n'
          'Las órdenes de compra se consolidarán en el proyecto con más datos '
          'y los duplicados serán eliminados.\n\n¿Continuar?',
          style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: GoogleFonts.inter())),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _primaryColor),
            child: Text('Unificar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _dupRunning = true; _dupLog.clear(); });

    for (final grupo in grupos) {
      final idLicit   = grupo['idLicitacion'] as String;
      final proyectos = List<Map<String, dynamic>>.from(grupo['proyectos'] as List);

      // Elegir proyecto a conservar: mayor cantidad de OCs; empate → más antiguo
      proyectos.sort((a, b) {
        final aOCs = (a['idsOrdenesCompra'] as List?)?.length ?? 0;
        final bOCs = (b['idsOrdenesCompra'] as List?)?.length ?? 0;
        if (bOCs != aOCs) return bOCs.compareTo(aOCs);
        final aDate = a['fechaCreacion'] as String? ?? '';
        final bDate = b['fechaCreacion'] as String? ?? '';
        return aDate.compareTo(bDate); // más antiguo primero
      });

      final kept = proyectos.first;
      final dups  = proyectos.skip(1).toList();

      // Unión de todas las OCs (sin duplicados, case-insensitive)
      final allOCs = <String>{};
      for (final p in proyectos) {
        for (final oc in (p['idsOrdenesCompra'] as List?)?.cast<String>() ?? []) {
          allOCs.add(oc.trim());
        }
      }

      // Tomar el mejor valor disponible de cada campo entre todos los duplicados
      String? bestNotas      = kept['notas'] as String?;
      double? bestValor      = (kept['valorMensual'] as num?)?.toDouble();
      String? bestEstado     = kept['estadoManual'] as String?;
      String? bestInicio     = kept['fechaInicio'] as String?;
      String? bestTermino    = kept['fechaTermino'] as String?;
      for (final p in dups) {
        bestNotas   ??= p['notas']        as String?;
        bestValor   ??= (p['valorMensual'] as num?)?.toDouble();
        bestEstado  ??= p['estadoManual'] as String?;
        bestInicio  ??= p['fechaInicio']  as String?;
        bestTermino ??= p['fechaTermino'] as String?;
      }

      try {
        // Actualizar el proyecto conservado
        final updateBody = <String, dynamic>{
          'id':               kept['id'],
          'idsOrdenesCompra': allOCs.toList(),
          if (bestNotas   != null) 'notas':        bestNotas,
          if (bestValor   != null) 'valorMensual':  bestValor,
          if (bestEstado  != null) 'estadoManual':  bestEstado,
          if (bestInicio  != null) 'fechaInicio':   bestInicio,
          if (bestTermino != null) 'fechaTermino':  bestTermino,
        };
        final updResp = await http.post(
          Uri.parse('$_cfBase/actualizarProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updateBody),
        ).timeout(const Duration(seconds: 15));

        if (updResp.statusCode != 200) throw Exception('actualizarProyecto: ${updResp.statusCode}');

        // Eliminar duplicados
        for (final dup in dups) {
          await http.post(
            Uri.parse('$_cfBase/eliminarProyecto'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'id': dup['id']}),
          ).timeout(const Duration(seconds: 15));
          await Future.delayed(const Duration(milliseconds: 300));
        }

        setState(() => _dupLog.add({
          'ok': true,
          'msg': '$idLicit  ·  conservado: ${kept['id']}  ·  OCs: ${allOCs.length}  ·  eliminados: ${dups.length}',
        }));
      } catch (e) {
        setState(() => _dupLog.add({'ok': false, 'msg': '$idLicit  ·  Error: $e'}));
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    ProyectosService.instance.invalidate();
    if (mounted) setState(() { _dupRunning = false; _duplicados = null; });
  }

  // ── Auditoría ──────────────────────────────────────────────────────────

  Future<void> _runAudit() async {
    if (_running) return;
    setState(() { _running = true; _log.clear(); });

    final all = await ProyectosService.instance.load(forceRefresh: true);

    final results = <_MigResult>[];
    for (final r in _rows) {
      final res = _MigResult(r);
      final Proyecto? p = r.isLP
          ? all.where((x) => x.idLicitacion == r.cod).firstOrNull
          : all.where((x) => x.urlConvenioMarco?.contains(r.cod) == true).firstOrNull;

      if (p == null) {
        res.status = _Status.error;
        res.msg = 'No encontrado en Firebase';
      } else {
        res.proyectoId = p.id;
        final issues = <String>[];

        if (p.institucion.isEmpty || p.institucion == r.cod) {
          issues.add('sin institución');
        }
        if (p.fechaInicio == null) issues.add('sin fechaInicio');
        if (p.fechaTermino == null) issues.add('sin fechaTermino');
        if (r.est.isNotEmpty &&
            (p.estadoManual == null ||
                p.estadoManual!.toLowerCase() != r.est.toLowerCase())) {
          issues.add('estado: esperado "${r.est}" / actual "${p.estadoManual ?? 'null'}"');
        }
        if (r.vm != null && p.valorMensual == null) issues.add('sin valorMensual');

        if (issues.isEmpty) {
          res.status = _Status.ok;
          String fmt(DateTime? d) => d == null
              ? '?'
              : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
          res.msg = '${p.institucion}  ·  ${fmt(p.fechaInicio)} → ${fmt(p.fechaTermino)}';
        } else {
          res.status = _Status.warn;
          res.msg = issues.join('  ·  ');
        }
      }
      results.add(res);
    }

    setState(() {
      _log
        ..clear()
        ..addAll(results);
      _running = false;
    });
  }

  // ── Duplicados ─────────────────────────────────────────────────────────

  Widget _buildDuplicados(List<Map<String, dynamic>> grupos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Proyectos duplicados',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
            const SizedBox(height: 2),
            Text(grupos.isEmpty
                ? 'No se encontraron duplicados'
                : '${grupos.length} licitaciones con más de un proyecto',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
          ])),
          if (grupos.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _dupRunning ? null : _unificarTodos,
              icon: const Icon(Icons.merge, size: 18),
              label: Text('Unificar todos (${grupos.length})',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ]),
        if (_dupRunning) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_dupLog.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._dupLog.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: (e['ok'] as bool) ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(
                (e['ok'] as bool) ? Icons.check_circle : Icons.error_outline,
                size: 14,
                color: (e['ok'] as bool) ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(e['msg'] as String,
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)))),
            ]),
          )),
        ],
        if (grupos.isEmpty && _dupLog.isEmpty)
          const SizedBox(height: 8),
        if (grupos.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...grupos.map((grupo) {
            final idLicit   = grupo['idLicitacion'] as String;
            final proyectos = (grupo['proyectos'] as List).cast<Map<String, dynamic>>();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(idLicit,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                        color: const Color(0xFF7C3AED))),
                const SizedBox(height: 6),
                ...proyectos.map((p) {
                  final ocs = (p['idsOrdenesCompra'] as List?)?.cast<String>() ?? [];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('• ', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      Expanded(child: Text(
                        '${p['id']}  ·  ${p['institucion'] ?? '—'}'
                        '${ocs.isNotEmpty ? '  ·  OCs: ${ocs.join(', ')}' : '  ·  sin OC'}',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF374151)),
                      )),
                    ]),
                  );
                }),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  // ── Resultado análisis BigQuery ────────────────────────────────────────

  Widget _buildBQResult(Map<String, dynamic> r) {
    final totalBQ      = r['totalBQ'] as int? ?? 0;
    final totalEnApp   = r['totalEnApp'] as int? ?? 0;
    final totalFuera   = r['totalFueraDeApp'] as int? ?? 0;
    final totalOCFalt  = r['totalConOCFaltante'] as int? ?? 0;
    final enApp        = (r['enApp']  as List?)?.cast<Map<String, dynamic>>() ?? [];
    final fueraDeApp   = (r['fueraDeApp'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ocFaltante   = (r['ocFaltante'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    Widget kpi(String label, int value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          Text(label,   style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    );

    Widget section(String title, Color color, List<Map<String, dynamic>> rows, List<Widget> Function(Map<String, dynamic>) rowBuilder) {
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(height: 8),
        ...rows.map((row) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rowBuilder(row)),
        )),
      ]);
    }

    String? ocList(Map<String, dynamic> row) {
      final ocs = row['oc_en_app'];
      if (ocs is List && ocs.isNotEmpty) return ocs.join(', ');
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Análisis OC vs Proyectos (BigQuery)',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
        const SizedBox(height: 4),
        Text('Tabla: sistema_compras.meses_publicado_ordendecompra',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
        const SizedBox(height: 14),
        Row(children: [
          kpi('Total en BQ',       totalBQ,     const Color(0xFF1E293B)),
          const SizedBox(width: 8),
          kpi('En la app',         totalEnApp,  const Color(0xFF16A34A)),
          const SizedBox(width: 8),
          kpi('Fuera de la app',   totalFuera,  const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          kpi('OC no registrada',  totalOCFalt, const Color(0xFFD97706)),
        ]),

        // Proyectos en app con OC no registrada
        section('OC de BQ no registrada en el proyecto', const Color(0xFFD97706), ocFaltante, (row) => [
          Text('${row['id_licitacion']}  ·  ${row['institucion'] ?? ''}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('OC BQ: ${row['id_oc_bq']}  ·  En app: ${ocList(row) ?? 'ninguna'}',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
          if (row['fecha_envio_oc'] != null)
            Text('Envío OC: ${row['fecha_envio_oc']}  ·  ${row['meses_totales']} meses desde publicación',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
        ]),

        // Licitaciones sin proyecto en la app
        section('Licitaciones sin proyecto en la app', const Color(0xFFDC2626), fueraDeApp, (row) => [
          Text(row['id_licitacion'] ?? '', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('OC: ${row['id_oc_bq']}  ·  Publicación: ${row['fecha_publicacion'] ?? '-'}  ·  Envío OC: ${row['fecha_envio_oc'] ?? '-'}',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
          Text('${row['meses_totales']} meses entre publicación y OC',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
        ]),

        // Botones de corrección
        if (ocFaltante.isNotEmpty || fueraDeApp.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text('Correcciones', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (ocFaltante.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _bqFixRunning ? null : () => _registrarOCsFaltantes(ocFaltante),
                icon: const Icon(Icons.add_link, size: 18),
                label: Text('Registrar OCs faltantes (${ocFaltante.length})',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            if (fueraDeApp.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _bqFixRunning ? null : () => _crearProyectosFaltantes(fueraDeApp),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text('Crear proyectos faltantes (${fueraDeApp.length})',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ]),
          if (_bqFixRunning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_bqFixLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._bqFixLog.map((entry) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (entry['ok'] as bool)
                    ? const Color(0xFFF0FDF4)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(
                  (entry['ok'] as bool) ? Icons.check_circle : Icons.error_outline,
                  size: 14,
                  color: (entry['ok'] as bool) ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${entry['tipo'] == 'oc' ? 'OC' : 'Nuevo'}  ·  ${entry['id']}  ·  ${entry['msg']}',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)),
                )),
              ]),
            )),
          ],
        ],

        // Proyectos en app (colapsado por defecto si son muchos)
        if (enApp.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('En la app ($totalEnApp proyectos)',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A))),
          const SizedBox(height: 8),
          ...enApp.map((row) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(row['oc_bq_registrada'] == true ? Icons.check_circle : Icons.warning_amber,
                  size: 14,
                  color: row['oc_bq_registrada'] == true ? const Color(0xFF16A34A) : const Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${row['id_licitacion']}  ·  ${row['institucion'] ?? ''}  ·  OC BQ: ${row['id_oc_bq']}',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)),
                ),
              ),
            ]),
          )),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: buildBreadcrumbAppBar(
        context: context,
        onOpenMenu: openAppDrawer,
        crumbs: [
          BreadcrumbItem('Admin'),
          BreadcrumbItem('Migración CSV'),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildActions(),
              if (_duplicados != null) ...[
                const SizedBox(height: 24),
                _buildDuplicados(_duplicados!),
              ],
              if (_bqResult != null) ...[
                const SizedBox(height: 24),
                _buildBQResult(_bqResult!),
              ],
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildLog(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Migración de datos CSV',
            style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B))),
        const SizedBox(height: 4),
        Text(
          'Importa proyectos históricos desde la planilla de seguimiento.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 16),
        Row(children: [
          _stat('Total filas', '${_rows.length}', const Color(0xFF1E293B)),
          const SizedBox(width: 12),
          _stat('Licitaciones Públicas', '$_lpCount', const Color(0xFF2563EB)),
          const SizedBox(width: 12),
          _stat('Convenios Marco', '$_cmCount', const Color(0xFF7C3AED)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Por cada fila: (1) busca institución y fecha en OCDS/Convenio Marco, '
                '(2) calcula fechaTermino = fechaInicio + meses del CSV, '
                '(3) crea el proyecto con valor mensual, (4) guarda el caché externo. '
                'Las filas con el mismo código ya existente se omiten.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF92400E)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Acciones',
            style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B))),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ElevatedButton.icon(
            onPressed: _running ? null : _runTest,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text('Probar (1 LP + 1 CM)',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _running ? null : _runAll,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: Text('Migrar todos (${_rows.length})',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _running ? null : _runAudit,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text('Auditar migración',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F766E),
              side: const BorderSide(color: Color(0xFF0F766E)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _running ? null : _deleteTestProjects,
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            label: Text('Eliminar prueba',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500, color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const Divider(height: 1),
          OutlinedButton.icon(
            onPressed: (_running || _dupLoading) ? null : _detectarDuplicados,
            icon: _dupLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.merge_outlined, size: 18),
            label: Text('Detectar duplicados',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7C3AED),
              side: const BorderSide(color: Color(0xFF7C3AED)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: (_running || _bqLoading) ? null : _runAnalisisBQ,
            icon: _bqLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.analytics_outlined, size: 18),
            label: Text('Analizar OC vs Proyectos (BQ)',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0369A1),
              side: const BorderSide(color: Color(0xFF0369A1)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        if (_running) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ]),
    );
  }

  Widget _buildLog() {
    final ok    = _log.where((r) => r.status == _Status.ok).length;
    final warn  = _log.where((r) => r.status == _Status.warn).length;
    final err   = _log.where((r) => r.status == _Status.error).length;
    final skip  = _log.where((r) => r.status == _Status.skip).length;
    final hasAuditSummary = ok + warn + err > 0 && skip == 0 ||
        _log.any((r) => r.status == _Status.warn || r.status == _Status.error);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              Expanded(
                child: Text('Log',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B))),
              ),
              if (hasAuditSummary) ...[
                _chip('$ok OK', const Color(0xFF16A34A)),
                const SizedBox(width: 6),
                if (warn > 0) ...[
                  _chip('$warn avisos', const Color(0xFFD97706)),
                  const SizedBox(width: 6),
                ],
                if (err > 0)
                  _chip('$err faltantes', const Color(0xFFDC2626)),
              ],
            ]),
          ),
          const Divider(height: 1),
          ..._log.map((res) => _buildLogRow(res)),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color)),
      );

  Widget _buildLogRow(_MigResult res) {
    final (color, icon) = switch (res.status) {
      _Status.ok      => (const Color(0xFF16A34A), Icons.check_circle_outline),
      _Status.skip    => (const Color(0xFFD97706), Icons.skip_next_outlined),
      _Status.warn    => (const Color(0xFFD97706), Icons.warning_amber_outlined),
      _Status.error   => (const Color(0xFFDC2626), Icons.error_outline),
      _Status.running => (const Color(0xFF2563EB), Icons.hourglass_top_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        color: color.withValues(alpha: 0.03),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        SizedBox(
          width: 180,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(res.row.cod,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B)),
                overflow: TextOverflow.ellipsis),
            Text('${res.row.mod.contains('Convenio') ? 'CM' : 'LP'}  ·  ${res.row.meses}m',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(res.msg,
              style: GoogleFonts.inter(fontSize: 12, color: color),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
