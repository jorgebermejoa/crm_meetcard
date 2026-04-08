const admin = require("firebase-admin");
const axios = require("axios");
const cheerio = require("cheerio");
const { generarSugerenciasEncadenamiento, triggerSugerenciasEncadenamiento, reconciliarFlagsSugerencias, onNuevoProyecto } = require('./sugerencias_encadenamiento');
exports.generarSugerenciasEncadenamiento = generarSugerenciasEncadenamiento;
exports.triggerSugerenciasEncadenamiento = triggerSugerenciasEncadenamiento;
exports.reconciliarFlagsSugerencias = reconciliarFlagsSugerencias;
exports.onNuevoProyecto = onNuevoProyecto;
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

// --- IMPORTACIÓN PARA VERTEX AI (lazy init para evitar fallos de módulo en cold start) ---
const { SearchServiceClient, DocumentServiceClient } = require('@google-cloud/discoveryengine');
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const { BigQuery } = require('@google-cloud/bigquery');
const bigquery = new BigQuery({ projectId: 'licitaciones-prod' });
const XLSX = require('xlsx');
let _discoveryClient = null;
let _docClient = null;
function getDiscoveryClient() {
  if (!_discoveryClient) _discoveryClient = new SearchServiceClient();
  return _discoveryClient;
}
function getDocClient() {
  if (!_docClient) _docClient = new DocumentServiceClient();
  return _docClient;
}

const DE_PARENT = 'projects/licitaciones-prod/locations/global/collections/default_collection/dataStores/datos-licitaciones_1772758314411/branches/0';

// Indexa un lote de documentos en Discovery Engine (máx 100 por request)
async function indexarEnDiscoveryEngine(documentos) {
  if (!documentos.length) return;
  const DE_BATCH = 100;
  for (let i = 0; i < documentos.length; i += DE_BATCH) {
    const lote = documentos.slice(i, i + DE_BATCH);
    try {
      const [operation] = await getDocClient().importDocuments({
        parent: DE_PARENT,
        inlineSource: {
          documents: lote.map(({ id, data }) => ({
            id,
            // _firestoreId embebido para recuperarlo desde structData en búsqueda
            jsonData: JSON.stringify({ ...data, _firestoreId: id }),
          })),
        },
        reconciliationMode: 'INCREMENTAL',
      });
      logger.info(`DE import iniciado: ${lote.length} docs (lote ${Math.floor(i / DE_BATCH) + 1})`, operation.name);
    } catch (e) {
      logger.error('Error indexando en Discovery Engine:', e.message);
    }
  }
}

// Inicializar Firebase
admin.initializeApp();

// ── API Call Logger ────────────────────────────────────────────────────────────
// Escribe una entrada en `api_logs`; no bloquea — los errores se ignoran.
async function _logApiCall(db, { funcion, tipo, id, estado, statusCode, ms }) {
  try {
    await db.collection('api_logs').add({
      funcion,
      tipo,
      id: id ?? null,
      estado,
      statusCode: statusCode ?? null,
      ms: ms ?? null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.warn('_logApiCall error:', e.message);
  }
}

// Constantes
const BATCH_SIZE = 1000;
const BATCH_SIZE_DETAILS = 200;
const API_TIMEOUT = 10000;
const CONCURRENT_LIMIT = 15;
const BASE_URL = "https://api.mercadopublico.cl/APISOCDS/OCDS";
// Ticket Mercado Público — se sobreescribe por env var en producción si está configurada
const OC_TICKET = process.env.MP_TICKET || 'EE36DCF4-F727-4EED-9026-20EF36A6DD54';

// --- FUNCIONES AUXILIARES ---

function extractCodigoExterno(ocid) {
  if (!ocid) return null;
  const parts = ocid.split('-');
  return parts.length >= 3 ? parts.slice(2).join('-') : ocid;
}

function safeStringToTimestamp(dateString) {
  if (!dateString || typeof dateString !== 'string') return null;
  try {
    const dateObj = new Date(dateString);
    if (isNaN(dateObj.getTime())) return null;
    return admin.firestore.Timestamp.fromDate(dateObj);
  } catch (e) { return null; }
}

function convertDatesToTimestamps(data) {
  if (data === null || typeof data !== 'object') {
    if (typeof data === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(data)) {
      const ts = safeStringToTimestamp(data);
      return ts !== null ? ts : data;
    }
    return data;
  }
  if (Array.isArray(data)) return data.map(item => convertDatesToTimestamps(item));

  const newData = {};
  for (const key in data) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      const value = data[key];
      if ((key.toLowerCase().endsWith('date')) && typeof value === 'string') {
        const ts = safeStringToTimestamp(value);
        newData[key] = ts !== null ? ts : value;
      } else if (typeof value === 'object') {
        newData[key] = convertDatesToTimestamps(value);
      } else {
        newData[key] = value;
      }
    }
  }
  return newData;
}

async function processMonth(db, year, month) {
  let offset = 0;
  let hasMore = true;
  let totalAgregados = 0;
  while (hasMore) {
    const url = `${BASE_URL}/listaOCDSAgnoMes/${year}/${month}/${offset}/${BATCH_SIZE}`;
    const response = await axios.get(url, { timeout: API_TIMEOUT }).catch((e) => {
      logger.warn(`processMonth ${year}/${month} offset=${offset}: error API — ${e.message}`);
      return null;
    });
    const data = response?.data?.data || [];

    if (data.length === 0) {
      logger.info(`processMonth ${year}/${month}: sin más datos en offset ${offset}`);
      break;
    }

    const collectionRef = db.collection("licitaciones_activas");

    // Verificar existencia en paralelo — no resetear docs ya procesados
    const codigos = data
      .map(l => extractCodigoExterno(l.ocid))
      .filter(Boolean);
    const snaps = await Promise.all(codigos.map(c => collectionRef.doc(c).get()));

    const bulkWriter = db.bulkWriter();
    let nuevos = 0;
    for (let i = 0; i < codigos.length; i++) {
      if (snaps[i].exists) continue;   // ya existe, no sobreescribir
      const ocid = data[i]?.ocid || null;
      bulkWriter.set(collectionRef.doc(codigos[i]), {
        ocid,
        codigoExterno: codigos[i],
        procesado: false,
        error: false,
        fuente: 'ocds',
        fechaEncolado: admin.firestore.FieldValue.serverTimestamp(),
      });
      nuevos++;
    }
    await bulkWriter.close();
    totalAgregados += nuevos;
    hasMore = data.length === BATCH_SIZE;
    offset += BATCH_SIZE;
  }
  logger.info(`processMonth ${year}/${month}: ${totalAgregados} licitaciones encoladas`);
}

// --- CLOUD FUNCTION 1: Ingesta Masiva ---
exports.obtenerLicitacionesOCDS = onSchedule({
  schedule: "0 2 * * *",
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (event) => {
  const db = admin.firestore();
  const now = new Date();
  const months = [
    { year: now.getFullYear(), month: String(now.getMonth() + 1).padStart(2, '0') },
    { year: now.getFullYear(), month: String(now.getMonth()).padStart(2, '0') }
  ];

  logger.info(`obtenerLicitacionesOCDS iniciado — meses: ${months.map(m => `${m.year}/${m.month}`).join(', ')}`);
  for (const { year, month } of months) {
    await processMonth(db, year, month);
  }
  logger.info('obtenerLicitacionesOCDS completado');
});

// --- CLOUD FUNCTION 2: Procesar Detalle (GUARDA TODO EL OCDS + CAMPO DE BÚSQUEDA) ---
exports.procesarLotesDeLicitaciones = onSchedule({
  schedule: "every 2 minutes",
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "512MiB",
}, async (event) => {
  const db = admin.firestore();
  const snapshot = await db.collection("licitaciones_activas")
    .where("procesado", "==", false)
    .limit(BATCH_SIZE_DETAILS)
    .get();

  if (snapshot.empty) return;

  const bulkWriter = db.bulkWriter();
  const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
  const docsParaIndexar = [];

  for (let i = 0; i < snapshot.docs.length; i += CONCURRENT_LIMIT) {
    const chunk = snapshot.docs.slice(i, i + CONCURRENT_LIMIT);

    const apiPromises = chunk.map(doc => {
      const codigoExterno = doc.id;
      return axios.get(`${BASE_URL}/tender/${codigoExterno}`, { validateStatus: s => s < 500 })
        .then(res => ({ codigoExterno, success: true, status: res.status, data: res.data }))
        .catch(() => ({ codigoExterno, success: false }));
    });

    const results = await Promise.allSettled(apiPromises);

    let erroresApi = 0;
    let erroresParse = 0;
    for (const result of results) {
      if (result.status !== 'fulfilled' || !result.value.success) {
        // Fallo de red o timeout — el doc queda en cola para reintento
        const codigo = result.value?.codigoExterno ?? '(desconocido)';
        logger.warn(`procesarLotes: fallo de red en ${codigo}`);
        erroresApi++;
        continue;
      }
      const { codigoExterno, status, data } = result.value;
      const activaRef = db.collection("licitaciones_activas").doc(codigoExterno);

      if (status === 404) {
        logger.warn(`procesarLotes: OCDS 404 para ${codigoExterno} — marcando error`);
        bulkWriter.update(activaRef, { procesado: true, error: true, errorTipo: 'ocds_404' });
        erroresParse++;
        continue;
      }

      if (status >= 400) {
        logger.warn(`procesarLotes: OCDS HTTP ${status} para ${codigoExterno} — reintentará`);
        erroresApi++;
        continue;
      }

      try {
        const releases = data?.releases;
        if (!releases || !Array.isArray(releases) || releases.length === 0) {
          logger.warn(`procesarLotes: releases vacío para ${codigoExterno}`);
          bulkWriter.update(activaRef, { procesado: true, error: true, errorTipo: 'releases_vacio' });
          erroresParse++;
          continue;
        }
        const release = releases[0];
        const releaseData = convertDatesToTimestamps(release);

        const descripcionesItems = (releaseData.tender?.items || [])
          .map(item => item?.description).filter(Boolean).join(" ");

        const textoBusqueda = `
          ${releaseData.tender?.title || ''}
          ${releaseData.tender?.description || ''}
          ${descripcionesItems}
        `.replace(/\s+/g, ' ').trim();

        const ocdsRef = db.collection("licitaciones_ocds").doc(codigoExterno);

        // Calcular prefijos UNSPSC únicos para consultas por categoría
        const unspscPrefixes = [...new Set(
          (releaseData.tender?.items || [])
            .map(item => String(item?.classification?.id || ''))
            .filter(code => code.length >= 2)
            .map(code => code.slice(0, 2))
        )];

        bulkWriter.set(ocdsRef, {
          ...releaseData,
          texto_busqueda: textoBusqueda,
          _unspsc_prefixes: unspscPrefixes,
          fechaProceso: serverTimestamp
        }, { merge: true });

        bulkWriter.update(activaRef, { procesado: true, error: false });

        // Acumular para indexar en Discovery Engine
        docsParaIndexar.push({ id: codigoExterno, data: { ...release, texto_busqueda: textoBusqueda } });

      } catch (e) {
        logger.error(`procesarLotes: error de parse en ${codigoExterno} — ${e.message}`);
        bulkWriter.update(activaRef, { procesado: true, error: true, errorTipo: 'parse_exception' });
        erroresParse++;
      }
    }
  }
  await bulkWriter.close();

  // Registrar estado del procesamiento
  const procesados = docsParaIndexar.length;
  const totalErrores = snapshot.docs.length - procesados;
  await db.collection('_stats').doc('procesamiento').set({
    estado: totalErrores === 0 ? 'ok' : 'ok_con_errores',
    fecha: admin.firestore.FieldValue.serverTimestamp(),
    procesadas: procesados,
    erroresApi,
    erroresParse,
    error: totalErrores > 0 ? `${totalErrores} con error (${erroresApi} API, ${erroresParse} parse)` : null,
  });

  // Indexar el lote procesado en Discovery Engine
  await indexarEnDiscoveryEngine(docsParaIndexar);
});

// --- CLOUD FUNCTION 3: Re-indexar backlog de Firestore → Discovery Engine ---
exports.reindexarLicitaciones = onRequest({
  cors: false,
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (req, res) => {
  const db = admin.firestore();
  const LOTE = 200;
  let cursor = null;
  let total = 0;

  try {
    while (true) {
      let query = db.collection("licitaciones_ocds").orderBy('__name__').limit(LOTE);
      if (cursor) query = query.startAfter(cursor);

      const snap = await query.get();
      if (snap.empty) break;

      const lote = snap.docs.map(doc => ({
        id: doc.id,
        data: doc.data(),
      }));

      await indexarEnDiscoveryEngine(lote);
      total += lote.length;
      cursor = snap.docs[snap.docs.length - 1];

      if (snap.docs.length < LOTE) break;
    }

    res.json({ ok: true, total });
  } catch (e) {
    logger.error('Error en reindexar:', e);
    res.status(500).json({ error: e.message });
  }
});

// Tokeniza una query eliminando stopwords y acentos para el filtro léxico
function tokenizarQuery(query) {
  const stopwords = new Set([
    'de', 'la', 'el', 'en', 'y', 'a', 'que', 'por', 'con', 'del', 'al', 'los', 'las',
    'un', 'una', 'para', 'es', 'se', 'no', 'como', 'más', 'este', 'esta', 'pero', 'sus',
    'le', 'ya', 'o', 'fue', 'ha', 'me', 'si', 'sin', 'sobre', 'entre', 'cuando', 'muy',
    'hasta', 'todo', 'ser', 'hay', 'su', 'les', 'lo', 'también', 'ni', 'e', 'u', 'ante',
    'bajo', 'tras', 'según', 'durante', 'mediante', 'cada', 'otras', 'otros', 'dicho',
  ]);
  return query.toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .split(/\s+/)
    .filter(t => t.length > 2 && !stopwords.has(t));
}

// --- CLOUD FUNCTION 4: Búsqueda ---
// Discovery Engine → candidatos semánticos | filtro léxico | Firestore → datos completos
exports.buscarLicitacionesAI = onRequest({
  cors: true,
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "512MiB"
}, async (req, res) => {
  if (!await _verifyToken(req, res)) return;
  const query = req.query.q;
  if (!query) return res.status(400).send("Falta el parámetro 'q'");

  try {
    const db = admin.firestore();

    // 1. Obtener candidatos semánticos desde Discovery Engine
    const servingConfig = getDiscoveryClient().projectLocationCollectionDataStoreServingConfigPath(
      'licitaciones-prod', 'global', 'default_collection',
      'datos-licitaciones_1772758314411', 'default_search'
    );
    const [deResults] = await getDiscoveryClient().search({
      servingConfig,
      query,
      pageSize: 25,
    });

    const ids = deResults
      .map(r => {
        const fields = r.document?.structData?.fields;
        if (fields?._firestoreId?.stringValue) return fields._firestoreId.stringValue;
        const ocid = fields?.ocid?.stringValue;
        if (ocid) return extractCodigoExterno(ocid);
        return null;
      })
      .filter(Boolean);

    if (!ids.length) return res.status(200).json({ resultados: [] });

    // 2. Leer documentos completos desde Firestore en paralelo
    const snapshots = await Promise.all(
      ids.map(id => db.collection('licitaciones_ocds').doc(id).get())
    );

    // 3. Formatear resultados (sin filtro léxico — Discovery Engine es semántico)
    const toMs = (n) => n > 1e13 ? Math.round(n / 1000) : n > 1e10 ? n : n * 1000;

    const formatDate = (raw) => {
      if (!raw) return "S/F";
      try {
        let ms;
        if (raw && typeof raw === 'object' && (raw.seconds !== undefined || raw._seconds !== undefined)) {
          ms = (raw.seconds ?? raw._seconds) * 1000;
        } else if (typeof raw === 'number') {
          ms = toMs(raw);
        } else if (typeof raw === 'string') {
          ms = /^\d+$/.test(raw) ? toMs(parseInt(raw)) : new Date(raw).getTime();
        } else {
          return "S/F";
        }
        const d = new Date(ms);
        if (isNaN(d.getTime())) return "S/F";
        return d.toLocaleDateString('es-CL', {
          day: '2-digit', month: '2-digit', year: 'numeric',
          timeZone: 'America/Santiago',
        });
      } catch (e) { return "S/F"; }
    };

    const resultados = snapshots
      .filter(snap => snap.exists)
      .map(snap => {
        const data = snap.data();
        const id = snap.id;

        let tender = data.tender;
        if (Array.isArray(tender)) tender = tender[0];

        const compradorParty = (data.parties || []).find(p =>
          Array.isArray(p.roles) && (p.roles.includes('buyer') || p.roles.includes('procuringEntity'))
        );
        const comprador = data.buyer?.name ||
          tender?.procuringEntity?.name ||
          compradorParty?.name ||
          "No disponible";

        return {
          id,
          titulo: tender?.title?.trim() || "Sin título",
          descripcion: tender?.description || "Sin descripción",
          fechaPublicacion: formatDate(tender?.tenderPeriod?.startDate || data.date),
          fechaCierre: formatDate(tender?.tenderPeriod?.endDate || tender?.awardPeriod?.startDate),
          monto: tender?.value?.amount
            ? new Intl.NumberFormat('es-CL').format(tender.value.amount) : 'S/M',
          comprador,
          rawData: {
            id,
            tender,
            parties: data.parties,
            buyer: data.buyer,
            date: data.date,
          },
        };
      });

    res.status(200).json({ resultados });
  } catch (error) {
    logger.error("Error en búsqueda:", error);
    res.status(500).send("Error interno de búsqueda");
  }
});

// Mapa de prefijos UNSPSC a nombres de categoría en español
const UNSPSC_CATEGORIAS = {
  '10': 'Agricultura y Ganadería', '11': 'Fibras y Textiles', '12': 'Minerales',
  '13': 'Combustibles', '14': 'Materias Primas', '15': 'Componentes',
  '20': 'Maquinaria Industrial', '21': 'Equipos Industriales', '22': 'Equipos de Construcción',
  '23': 'Herramientas Industriales', '24': 'Materiales de Producción', '25': 'Vehículos',
  '26': 'Componentes Electrónicos', '27': 'Herramientas', '30': 'Materiales de Construcción',
  '31': 'Manufactura', '39': 'Electricidad e Iluminación', '40': 'Distribución',
  '41': 'Laboratorio y Científico', '42': 'Equipos Médicos', '43': 'Tecnología de la Información',
  '44': 'Oficina y Papelería', '45': 'Artes y Artesanía', '46': 'Defensa y Seguridad',
  '47': 'Aseo e Higiene', '48': 'Deportes y Recreación', '49': 'Alimentos Elaborados',
  '50': 'Alimentos y Bebidas', '51': 'Farmacia y Droguería', '52': 'Retail',
  '53': 'Textiles y Vestuario', '54': 'Papel y Cartón', '55': 'Publicaciones',
  '56': 'Mobiliario y Equipamiento', '60': 'Instrumentos', '70': 'Servicios Agrícolas',
  '71': 'Servicios Industriales', '72': 'Construcción y Obras', '73': 'Manufactura y Proceso',
  '75': 'Servicios de Terrenos', '76': 'Servicios de Limpieza', '77': 'Medio Ambiente',
  '78': 'Transporte y Logística', '79': 'Turismo y Hotelería', '80': 'Gestión y Consultoría',
  '81': 'Servicios de TI y Consultoría', '82': 'Edición e Imprenta', '83': 'Servicios de Construcción',
  '84': 'Finanzas y Seguros', '85': 'Salud', '86': 'Educación y Capacitación',
  '87': 'Servicios Jurídicos', '88': 'Servicios Sociales', '90': 'Servicios Comunitarios',
  '91': 'Servicios Políticos', '92': 'Defensa Nacional', '93': 'Servicios Gubernamentales',
  '95': 'Terrenos y Edificios',
};

// --- CLOUD FUNCTION 5: Resumen estadístico (stats rápidas + categorías cacheadas) ---
exports.obtenerResumen = onRequest({
  cors: true,
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (req, res) => {
  const db = admin.firestore();
  try {
    const ahora = new Date();
    const offsetMs = 3 * 60 * 60 * 1000; // Chile UTC-3 aprox
    // Inicio de mes en Chile
    const inicioMesUTC = new Date(Date.UTC(ahora.getUTCFullYear(), ahora.getUTCMonth(), 1) + offsetMs);
    // Hace 14 días (para métrica "recientes" — el feed OCDS de Mercado Público llega con ~9 días de retraso)
    const hace7diasUTC = new Date(Date.UTC(ahora.getUTCFullYear(), ahora.getUTCMonth(), ahora.getUTCDate() - 14) + offsetMs);

    // Usar el campo 'date' del release OCDS (fecha real de publicación en Mercado Público)
    const [totalSnap, recientesSnap, mesSnap, statsDoc, ingestaDoc, procesamientoDoc] = await Promise.all([
      db.collection('licitaciones_ocds').count().get(),
      db.collection('licitaciones_ocds')
        .where('date', '>=', admin.firestore.Timestamp.fromDate(hace7diasUTC))
        .count().get(),
      db.collection('licitaciones_ocds')
        .where('date', '>=', admin.firestore.Timestamp.fromDate(inicioMesUTC))
        .count().get(),
      db.collection('_stats').doc('resumen').get(),
      db.collection('_stats').doc('ingesta').get(),
      db.collection('_stats').doc('procesamiento').get(),
    ]);

    const cache = statsDoc.exists ? statsDoc.data() : null;
    const _fmtChile = (date) => date.toLocaleDateString('es-CL', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
      timeZone: 'America/Santiago',
    });
    const ultimaActualizacion = _fmtChile(new Date());

    const _fmtTs = (ts) => ts?.toDate?.() ? _fmtChile(ts.toDate()) : null;

    const ingesta = ingestaDoc.exists ? ingestaDoc.data() : null;
    const procesamiento = procesamientoDoc.exists ? procesamientoDoc.data() : null;

    res.status(200).json({
      total: totalSnap.data().count,
      recientes: recientesSnap.data().count,
      esteMes: mesSnap.data().count,
      ti: cache?.ti || 0,
      tiBase: cache?.tiBase || 0,   // total del período 90d usado para calcular %
      categorias: cache?.categorias || [],
      ultimaActualizacion,
      ingesta: ingesta ? {
        estado: ingesta.estado,
        fecha: _fmtTs(ingesta.fecha),
        encoladas: ingesta.encoladas ?? null,
        error: ingesta.error ?? null,
      } : null,
      procesamiento: procesamiento ? {
        estado: procesamiento.estado,
        fecha: _fmtTs(procesamiento.fecha),
        procesadas: procesamiento.procesadas ?? null,
        error: procesamiento.error ?? null,
      } : null,
    });
  } catch (error) {
    logger.error("Error en obtenerResumen:", error);
    res.status(500).send("Error obteniendo estadísticas");
  }
});

// --- Lógica compartida: calcula categorías/TI de los últimos 90 días y guarda en caché ---
async function _ejecutarCalculoEstadisticas(db) {
  const ahora = new Date();
  const hace90dias = new Date(ahora.getTime() - 90 * 24 * 60 * 60 * 1000);

  const categoriaCounts = {};
  let tiCount = 0;
  let cursor = null;
  let totalProcesados = 0;

  while (true) {
    let q = db.collection('licitaciones_ocds')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(hace90dias))
      .select('tender', 'date')
      .orderBy('date')
      .limit(500);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const data = doc.data();
      let tender = data.tender;
      if (Array.isArray(tender)) tender = tender[0];
      const items = tender?.items || [];
      const prefixesVistas = new Set();

      for (const item of items) {
        const code = String(item?.classification?.id || '');
        if (code.length >= 2) {
          const prefix = code.slice(0, 2);
          if (!prefixesVistas.has(prefix)) {
            prefixesVistas.add(prefix);
            categoriaCounts[prefix] = (categoriaCounts[prefix] || 0) + 1;
            if (prefix === '43' || prefix === '81') tiCount++;
          }
        }
      }
      totalProcesados++;
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < 500) break;
  }

  const categorias = Object.entries(categoriaCounts)
    .map(([prefix, cantidad]) => ({
      nombre: UNSPSC_CATEGORIAS[prefix] || `Categoría ${prefix}`,
      cantidad,
      prefix,
      esTI: prefix === '43' || prefix === '81',
    }))
    .filter(c => c.esTI)   // solo categorías TI
    .sort((a, b) => b.cantidad - a.cantidad);

  await db.collection('_stats').doc('resumen').set({
    ti: tiCount,
    categorias,
    tiBase: totalProcesados,
    ultimaActualizacion: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { totalProcesados, tiCount, categorias };
}

// --- CLOUD FUNCTION 6: Cálculo de categorías del mes actual (HTTP, manual) ---
exports.calcularEstadisticas = onRequest({
  cors: false,
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (req, res) => {
  const db = admin.firestore();
  try {
    const result = await _ejecutarCalculoEstadisticas(db);
    res.json({ ok: true, ...result });
  } catch (error) {
    logger.error("Error calculando estadísticas:", error);
    res.status(500).json({ error: error.message });
  }
});

// --- CLOUD FUNCTION 6b: Cálculo automático diario (6am UTC = 3am Chile) ---
exports.calcularEstadisticasDiario = onSchedule({
  schedule: "0 6 * * *",
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async () => {
  const db = admin.firestore();
  try {
    await _ejecutarCalculoEstadisticas(db);
    logger.info("Estadísticas mensuales recalculadas correctamente.");
  } catch (error) {
    logger.error("Error en calcularEstadisticasDiario:", error);
  }
});

// --- CLOUD FUNCTION 7: Migración — agrega _unspsc_prefixes a cada doc de Firestore ---
exports.migrarCamposCategoria = onRequest({
  cors: false,
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (req, res) => {
  const db = admin.firestore();
  const bulkWriter = db.bulkWriter();
  let cursor = null;
  let total = 0;

  try {
    while (true) {
      let q = db.collection('licitaciones_ocds').select('tender').orderBy('__name__').limit(500);
      if (cursor) q = q.startAfter(cursor);

      const snap = await q.get();
      if (snap.empty) break;

      for (const doc of snap.docs) {
        const data = doc.data();
        let tender = data.tender;
        if (Array.isArray(tender)) tender = tender[0];
        const items = tender?.items || [];
        const prefixes = [...new Set(
          items
            .map(item => String(item?.classification?.id || ''))
            .filter(code => code.length >= 2)
            .map(code => code.slice(0, 2))
        )];
        if (prefixes.length > 0) {
          bulkWriter.update(doc.ref, { _unspsc_prefixes: prefixes });
          total++;
        }
      }

      cursor = snap.docs[snap.docs.length - 1];
      if (snap.docs.length < 500) break;
    }

    await bulkWriter.close();
    res.json({ ok: true, total });
  } catch (error) {
    logger.error("Error en migración:", error);
    res.status(500).json({ error: error.message });
  }
});

// --- CLOUD FUNCTION 8: Licitaciones por categoría UNSPSC (browse, no búsqueda semántica) ---
exports.obtenerLicitacionesPorCategoria = onRequest({
  cors: true,
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "512MiB",
}, async (req, res) => {
  const prefixParam = req.query.prefix;
  const limite = Math.min(parseInt(req.query.limit) || 20, 50);
  const cursorId = req.query.cursor;

  if (!prefixParam) return res.status(400).send("Falta el parámetro 'prefix'");
  // Soporta prefix=43 o prefix=43,81
  const prefixes = prefixParam.split(',').map(p => p.trim()).filter(Boolean);

  const db = admin.firestore();
  const toMs = (n) => n > 1e13 ? Math.round(n / 1000) : n > 1e10 ? n : n * 1000;
  const formatDate = (raw) => {
    if (!raw) return "S/F";
    try {
      let ms;
      if (raw && typeof raw === 'object' && (raw.seconds !== undefined || raw._seconds !== undefined)) {
        ms = (raw.seconds ?? raw._seconds) * 1000;
      } else if (typeof raw === 'number') {
        ms = toMs(raw);
      } else if (typeof raw === 'string') {
        ms = /^\d+$/.test(raw) ? toMs(parseInt(raw)) : new Date(raw).getTime();
      } else return "S/F";
      const d = new Date(ms);
      if (isNaN(d.getTime())) return "S/F";
      return d.toLocaleDateString('es-CL', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'America/Santiago' });
    } catch (e) { return "S/F"; }
  };

  try {
    const whereOp = prefixes.length === 1 ? 'array-contains' : 'array-contains-any';
    let q = db.collection('licitaciones_ocds')
      .where('_unspsc_prefixes', whereOp, prefixes.length === 1 ? prefixes[0] : prefixes)
      .limit(limite);

    if (cursorId) {
      const cursorDoc = await db.collection('licitaciones_ocds').doc(cursorId).get();
      if (cursorDoc.exists) q = q.startAfter(cursorDoc);
    }

    const snap = await q.get();

    const resultados = snap.docs.map(doc => {
      const data = doc.data();
      const id = doc.id;
      let tender = data.tender;
      if (Array.isArray(tender)) tender = tender[0];
      const compradorParty = (data.parties || []).find(p =>
        Array.isArray(p.roles) && (p.roles.includes('buyer') || p.roles.includes('procuringEntity'))
      );
      return {
        id,
        titulo: tender?.title?.trim() || "Sin título",
        descripcion: tender?.description || "Sin descripción",
        fechaPublicacion: formatDate(tender?.tenderPeriod?.startDate || data.date),
        fechaCierre: formatDate(tender?.tenderPeriod?.endDate || tender?.awardPeriod?.startDate),
        monto: tender?.value?.amount
          ? new Intl.NumberFormat('es-CL').format(tender.value.amount) : 'S/M',
        comprador: data.buyer?.name || tender?.procuringEntity?.name || compradorParty?.name || "No disponible",
        rawData: data,
      };
    });

    const nextCursor = snap.docs.length === limite ? snap.docs[snap.docs.length - 1].id : null;
    res.status(200).json({ resultados, nextCursor });
  } catch (error) {
    logger.error("Error en obtenerLicitacionesPorCategoria:", error);
    res.status(500).send("Error obteniendo licitaciones por categoría");
  }
});

// --- CLOUD FUNCTION 9: Buscar licitación por ID (OCDS) ---
exports.buscarLicitacionPorId = onRequest({
  cors: true,
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (req, res) => {
  const id = req.query.id;
  if (!id) return res.status(400).json({ error: "Falta el parámetro 'id'" });

  const db = admin.firestore();
  const t0 = Date.now();
  try {
    const type = req.query.type === 'award' ? 'award' : 'tender';
    const url = `${BASE_URL}/${type}/${id}`;
    const response = await axios.get(url, { timeout: API_TIMEOUT });
    _logApiCall(db, { funcion: 'buscarLicitacionPorId', tipo: 'licitacion', id, estado: 'ok', statusCode: 200, ms: Date.now() - t0 });
    res.status(200).json(response.data);
  } catch (error) {
    if (error.response) {
      const status = error.response.status;
      logger.error(`Error buscando licitación ${id}: status ${status}`);
      _logApiCall(db, { funcion: 'buscarLicitacionPorId', tipo: 'licitacion', id, estado: 'error', statusCode: status, ms: Date.now() - t0 });
      // Si la OCDS aún no publicó esta licitación, intentar fallback con API tradicional
      if (status === 404) {
        try {
          const configSnap = await db.collection('config').doc('mercado_publico').get();
          const ticket = (configSnap.exists ? configSnap.data().ticket : null) ?? OC_TICKET;
          const fallbackUrl = `https://api.mercadopublico.cl/servicios/v1/publico/licitaciones.json?codigo=${encodeURIComponent(id)}&ticket=${ticket}`;
          const fallbackResp = await axios.get(fallbackUrl, { timeout: API_TIMEOUT });
          const listado = fallbackResp.data?.Listado ?? [];
          if (listado.length) {
            _logApiCall(db, { funcion: 'buscarLicitacionPorId', tipo: 'licitacion_fallback', id, estado: 'ok', statusCode: 200, ms: Date.now() - t0 });
            return res.status(200).json({ _source: 'licitaciones_api', releases: [{ tender: listado[0] }], _raw: listado[0] });
          }
        } catch (fallbackErr) {
          logger.warn(`Fallback licitaciones.json también falló para ${id}:`, fallbackErr.message);
        }
        // Registrar para reintento nocturno
        db.collection('licitaciones_pendientes').doc(id).set({
          id,
          intentos: admin.firestore.FieldValue.increment(1),
          ultimoIntento: admin.firestore.FieldValue.serverTimestamp(),
          creadoEn: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }).catch(e => logger.warn('licitaciones_pendientes write error:', e.message));
      }
      res.status(status).json({ error: `Error ${status} al consultar la API` });
    } else {
      logger.error(`Error buscando licitación ${id}:`, error.message);
      _logApiCall(db, { funcion: 'buscarLicitacionPorId', tipo: 'licitacion', id, estado: 'error', statusCode: 500, ms: Date.now() - t0 });
      res.status(500).json({ error: "Error interno al consultar la licitación" });
    }
  }
});

// --- CLOUD FUNCTION 10: Buscar Orden de Compra por ID ---
const OC_BASE_URL = 'https://api.mercadopublico.cl/servicios/v1/publico/ordenesdecompra.json';

exports.buscarOrdenCompra = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 30,
  memory: '512MiB',
}, async (req, res) => {
  const id = req.query.id;
  if (!id) return res.status(400).json({ error: "Falta el parámetro 'id'" });

  const db = admin.firestore();
  const t0 = Date.now();
  try {
    const configSnap = await db.collection('config').doc('mercado_publico').get();
    const ticket = (configSnap.exists ? configSnap.data().ticket : null) ?? OC_TICKET;
    logger.info(`buscarOrdenCompra: id=${id} ticket_source=${configSnap.exists ? 'firestore' : 'fallback'}`);
    const url = `${OC_BASE_URL}?codigo=${encodeURIComponent(id)}&ticket=${ticket}`;
    const response = await axios.get(url, { timeout: 20000 });
    const data = response.data;

    // La API devuelve { Listado: [...], Cantidad: N }
    const listado = data?.Listado ?? [];
    if (!listado.length) {
      _logApiCall(db, { funcion: 'buscarOrdenCompra', tipo: 'oc', id, estado: 'not_found', statusCode: 404, ms: Date.now() - t0 });
      return res.status(404).json({ error: 'No se encontró la orden de compra' });
    }
    _logApiCall(db, { funcion: 'buscarOrdenCompra', tipo: 'oc', id, estado: 'ok', statusCode: 200, ms: Date.now() - t0 });
    const oc = listado[0];
    // Log estructura de ítems para diagnosticar campo de moneda
    const items = oc?.Items?.Listado ?? [];
    const item0 = items[0] ?? {};
    logger.info(`OC ${id} → Total=${oc.Total} Moneda="${oc.Moneda}" TipoMonedaOC="${oc.TipoMonedaOC}" Items.count=${items.length} item0.keys=${Object.keys(item0).join(',')} item0.Moneda="${item0.Moneda}" item0.MonedaOC="${item0.MonedaOC}"`);
    // Inyectar _moneda desde TipoMoneda (campo real de la API de MP) o ítems
    const normalizarMoneda = (v) => {
      if (!v) return null;
      const u = v.toString().toUpperCase();
      if (u === 'CLF' || u === 'UF' || u.includes('FOMENTO')) return 'UF';
      if (u === 'USD' || u.includes('DOLAR') || u.includes('DÓLAR')) return 'USD';
      if (u === 'PESO' || u === 'CLP' || u.includes('PESO CHILENO')) return 'CLP';
      if (v === '2') return 'UF';
      return null;
    };
    oc._moneda = normalizarMoneda(oc.TipoMoneda)
      ?? normalizarMoneda(oc.TipoMonedaOC)
      ?? normalizarMoneda(oc.Moneda)
      ?? normalizarMoneda(item0.Moneda)
      ?? '';
    logger.info(`OC ${id} → TipoMoneda="${oc.TipoMoneda}" _moneda="${oc._moneda || 'ninguna'}"`);

    // Si la moneda es UF, obtener valor UF del día y calcular CLP equivalente
    if (oc._moneda === 'UF' && oc.Total != null) {
      try {
        const now = new Date();
        const yyyy = now.getFullYear();
        const mm = String(now.getMonth() + 1).padStart(2, '0');
        const dd = String(now.getDate()).padStart(2, '0');
        const ufResp = await axios.get(
          `https://mindicador.cl/api/uf/${dd}-${mm}-${yyyy}`,
          { timeout: 5000 }
        );
        const ufValor = ufResp.data?.serie?.[0]?.valor ?? null;
        if (ufValor) {
          oc._ufValor = ufValor;
          oc._totalCLP = Math.round(parseFloat(oc.Total) * ufValor);
        }
      } catch (ufErr) {
        logger.warn(`No se pudo obtener valor UF: ${ufErr.message}`);
      }
    }

    return res.json(oc); // Devolver el primer (único) resultado
  } catch (error) {
    if (error.response) {
      logger.error(`Error buscando OC ${id}: status ${error.response.status}`);
      _logApiCall(db, { funcion: 'buscarOrdenCompra', tipo: 'oc', id, estado: 'error', statusCode: error.response.status, ms: Date.now() - t0 });
      return res.status(error.response.status).json({ error: `Error ${error.response.status}` });
    }
    logger.error(`Error buscando OC ${id}:`, error.message);
    _logApiCall(db, { funcion: 'buscarOrdenCompra', tipo: 'oc', id, estado: 'error', statusCode: 500, ms: Date.now() - t0 });
    return res.status(500).json({ error: error.message });
  }
});

// --- CLOUD FUNCTION 11: Obtener detalle Convenio Marco ---
exports.obtenerDetalleConvenioMarco = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 30,
  memory: '256MiB',
}, async (req, res) => {
  const url = req.query.url;
  if (!url) return res.status(400).json({ error: "Falta el parámetro 'url'" });

  // Extract ID from URL path segment /id/{id}/
  const match = url.match(/\/id\/([^\/\?#]+)/);
  const id = match ? match[1] : 'Desconocido';
  const db = admin.firestore();
  const t0 = Date.now();

  try {
    const response = await axios.get(url, {
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'es-CL,es;q=0.9,en;q=0.8',
      },
    });

    const $ = cheerio.load(response.data);

    const data = {
      id,
      url,
      titulo: '',
      comprador: '',
      convenioMarco: '',
      estado: '',
      campos: [],
    };

    // ── Etiquetas conocidas de páginas CM de Mercado Público ────────────────
    // Ordenadas de mayor a menor longitud para que el regex priorice correctamente
    const KNOWN_LABELS = [
      'Plazo máximo disponible para la ejecución de los servicios',
      'Justificación de selección de proveedor',
      'Requerimiento mínimo de la oferta',
      'Alcance de la contratación',
      'Objetivo de la contratación',
      'Código comité TIC (Si tiene)',
      'Plazo para realizar preguntas',
      'Vigencia de la cotización',
      'Nombre de la cotización',
      'Inicio de publicación',
      'Fin de publicación',
      'Inicio de evaluación',
      'Fin de evaluación',
      'Plazo de publicación',
      'Plazo de evaluación',
      'Vigencia del contrato',
      'ID Orden de Compra',
      'Correo electrónico',
      'Unidad de compra',
      'Presupuesto máximo',
      'Criterios de desempate',
      'Nombre del servicio',
      'Ficha servicio',
      'Beneficiario',
      'Organismo',
      'Modalidad',
      'Estado',
      'Monto',
    ];

    // Mapa label → campo de datos
    const FIELD_MAP = {
      'organismo': 'comprador',
      'unidad de compra': 'comprador',
      'nombre de la cotización': 'titulo',
      'nombre de la cotizacion': 'titulo',
      'nombre del servicio': 'titulo',
      'estado': 'estado',
    };

    function asignar(label, valor) {
      const lLower = label.toLowerCase().trim();
      for (const [key, campo] of Object.entries(FIELD_MAP)) {
        if (lLower.includes(key) && !data[campo]) {
          data[campo] = valor;
          break;
        }
      }
    }

    const seenLabels = new Set();
    function agregarCampo(labelRaw, valorRaw) {
      const label = labelRaw.replace(/^[\s:]+|[\s:]+$/g, '').replace(/\s+/g, ' ');
      const valor = valorRaw.replace(/^[\s:]+/, '').replace(/\s+/g, ' ').trim();
      if (!label || !valor || label.length > 130 || valor.length > 500) return;
      // Solo el primer valor por etiqueta (evita duplicados del mismo campo)
      const labelKey = label.toLowerCase();
      if (seenLabels.has(labelKey)) return;
      seenLabels.add(labelKey);
      data.campos.push({ label, valor });
      asignar(label, valor);
    }

    // ── Eliminar scripts/styles del DOM antes de extraer texto ───────────────
    $('script, style, noscript, iframe').remove();
    const bodyText = $('body').text();

    // ── Extracción por posiciones de etiquetas conocidas ─────────────────────
    // Construir regex con todas las etiquetas (ya ordenadas por longitud desc)
    const escaped = KNOWN_LABELS.map(l => l.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    const labelRe = new RegExp(escaped.join('|'), 'gi');
    const hits = [...bodyText.matchAll(labelRe)];

    for (let i = 0; i < hits.length; i++) {
      const label = hits[i][0];
      const afterStart = hits[i].index + label.length;
      // El valor termina donde empieza la siguiente etiqueta (o 400 chars después)
      const afterEnd = i + 1 < hits.length
        ? hits[i + 1].index
        : afterStart + 400;
      const rawVal = bodyText.slice(afterStart, afterEnd);
      // Limpiar: quitar colon inicial, tomar primer contenido no vacío
      const valor = rawVal
        .replace(/^[\s:]+/, '')
        .split('\n')
        .map(l => l.trim())
        .filter(l => l.length > 0)[0] || '';
      if (valor) agregarCampo(label, valor);
    }

    // ── Título desde h1/h2 si no se obtuvo ──────────────────────────────────
    if (!data.titulo) {
      $('h1, h2').each((_, el) => {
        const t = $(el).text().trim().replace(/\s+/g, ' ');
        if (t.length > 5 && t.length < 300 && !data.titulo) data.titulo = t;
      });
    }
    if (!data.titulo) {
      data.titulo = $('title').text().trim().replace(/\s+/g, ' ');
    }

    _logApiCall(db, { funcion: 'obtenerDetalleConvenioMarco', tipo: 'convenio', id, estado: 'ok', statusCode: 200, ms: Date.now() - t0 });
    return res.json(data);
  } catch (error) {
    if (error.response) {
      logger.error(`Error obteniendo CM ${url}: status ${error.response.status}`);
      _logApiCall(db, { funcion: 'obtenerDetalleConvenioMarco', tipo: 'convenio', id, estado: 'error', statusCode: error.response.status, ms: Date.now() - t0 });
      return res.json({ id, url, titulo: '', comprador: '', convenioMarco: '', estado: '', campos: [], fetchError: `Error ${error.response.status}` });
    }
    logger.error(`Error obteniendo CM ${url}:`, error.message);
    _logApiCall(db, { funcion: 'obtenerDetalleConvenioMarco', tipo: 'convenio', id, estado: 'error', statusCode: 500, ms: Date.now() - t0 });
    return res.json({ id, url, titulo: '', comprador: '', convenioMarco: '', estado: '', campos: [], fetchError: error.message });
  }
});

// PROYECTOS CRUD

exports.obtenerProyectos = onRequest({ cors: true, region: 'us-central1', minInstances: 1 }, async (req, res) => {
  logger.info('obtenerProyectos: function started.'); // Add log at function start
  try {
    const db = admin.firestore(); // Use admin.firestore() once
    const snapshot = await db
      .collection('proyectos')
      .orderBy('fechaCreacion', 'desc')
      .limit(500) // Limita la carga inicial a 500 para evitar timeouts
      .get();
    const toIso = (v) => v?.toDate?.()?.toISOString() ?? null;
    const proyectos = snapshot.docs.map(doc => {
      const d = doc.data();
      return {
        id: doc.id,
        ...d,
        fechaCreacion: toIso(d.fechaCreacion),
        fechaInicio: toIso(d.fechaInicio),
        fechaTermino: toIso(d.fechaTermino),
        fechaInicioRuta: toIso(d.fechaInicioRuta),
        fechaTerminoRuta: toIso(d.fechaTerminoRuta),
        fechaPublicacion: toIso(d.fechaPublicacion),
        fechaCierre: toIso(d.fechaCierre),
        fechaConsultasInicio: toIso(d.fechaConsultasInicio),
        fechaConsultas: toIso(d.fechaConsultas),
        fechaAdjudicacion: toIso(d.fechaAdjudicacion),
        fechaAdjudicacionFin: toIso(d.fechaAdjudicacionFin),
      };
    });
    logger.info(`obtenerProyectos: found ${proyectos.length} projects.`); // Log count
    return res.json(proyectos);
  } catch (e) {
    logger.error('obtenerProyectos: error fetching projects:', e.message, { stack: e.stack }); // Log error details
    return res.status(500).json({ error: e.message });
  }
});

exports.crearProyecto = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!await _verifyToken(req, res)) return;
  try {
    const { institucion, productos, modalidadCompra, valorMensual, fechaInicio, fechaTermino, idLicitacion, documentoUrl, notas } = req.body;
    const data = {
      institucion: institucion || '',
      productos: productos || '',
      modalidadCompra: modalidadCompra || '',
      completado: false,
      fechaCreacion: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (valorMensual != null) data.valorMensual = Number(valorMensual);
    if (fechaInicio) data.fechaInicio = new Date(fechaInicio);
    if (fechaTermino) data.fechaTermino = new Date(fechaTermino);
    if (idLicitacion) data.idLicitacion = idLicitacion;
    if (req.body.idCotizacion) data.idCotizacion = req.body.idCotizacion;
    if (req.body.urlConvenioMarco) data.urlConvenioMarco = req.body.urlConvenioMarco;
    if (documentoUrl) data.documentoUrl = documentoUrl;
    if (req.body.documentos) data.documentos = req.body.documentos;
    if (notas) data.notas = notas;
    if (req.body.idsOrdenesCompra) data.idsOrdenesCompra = req.body.idsOrdenesCompra;
    else if (req.body.idOrdenCompra) data.idsOrdenesCompra = [req.body.idOrdenCompra];
    const ref = await admin.firestore().collection('proyectos').add(data);
    return res.json({ id: ref.id });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.actualizarProyecto = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!await _verifyToken(req, res)) return;
  try {
    const { id, institucion, productos, modalidadCompra, valorMensual, fechaInicio, fechaTermino, idLicitacion, documentoUrl, notas, completado, _campoEditado, _valorAnterior, _valorNuevo } = req.body;

    if (!id) return res.status(400).json({ error: 'Missing id' });

    logger.info(`actualizarProyecto START: id=${id}`);

    const data = {};
    if (institucion !== undefined) data.institucion = institucion;
    if (productos !== undefined) data.productos = productos;
    if (modalidadCompra !== undefined) data.modalidadCompra = modalidadCompra;
    if (valorMensual !== undefined) data.valorMensual = valorMensual != null ? Number(valorMensual) : null;
    if (fechaInicio !== undefined) data.fechaInicio = fechaInicio ? new Date(fechaInicio) : null;
    if (fechaTermino !== undefined) data.fechaTermino = fechaTermino ? new Date(fechaTermino) : null;
    if (idLicitacion !== undefined) data.idLicitacion = idLicitacion;
    if (req.body.idCotizacion !== undefined) data.idCotizacion = req.body.idCotizacion;
    if (req.body.urlConvenioMarco !== undefined) data.urlConvenioMarco = req.body.urlConvenioMarco;
    if (req.body.idsOrdenesCompra !== undefined) data.idsOrdenesCompra = req.body.idsOrdenesCompra;
    if (documentoUrl !== undefined) data.documentoUrl = documentoUrl;
    if (req.body.documentos !== undefined) data.documentos = req.body.documentos;
    if (notas !== undefined) data.notas = notas;
    if (completado !== undefined) data.completado = completado;
    if (req.body.estadoManual !== undefined) data.estadoManual = req.body.estadoManual;
    if (req.body.certificados !== undefined) data.certificados = req.body.certificados;
    if (req.body.reclamos !== undefined) data.reclamos = req.body.reclamos;
    if (req.body.fechaInicioRuta !== undefined) data.fechaInicioRuta = req.body.fechaInicioRuta ? new Date(req.body.fechaInicioRuta) : null;
    if (req.body.fechaTerminoRuta !== undefined) data.fechaTerminoRuta = req.body.fechaTerminoRuta ? new Date(req.body.fechaTerminoRuta) : null;
    if (req.body.fechaPublicacion !== undefined) data.fechaPublicacion = req.body.fechaPublicacion ? new Date(req.body.fechaPublicacion) : null;
    if (req.body.fechaCierre !== undefined) data.fechaCierre = req.body.fechaCierre ? new Date(req.body.fechaCierre) : null;
    if (req.body.fechaConsultasInicio !== undefined) data.fechaConsultasInicio = req.body.fechaConsultasInicio ? new Date(req.body.fechaConsultasInicio) : null;
    if (req.body.fechaConsultas !== undefined) data.fechaConsultas = req.body.fechaConsultas ? new Date(req.body.fechaConsultas) : null;
    if (req.body.fechaAdjudicacion !== undefined) data.fechaAdjudicacion = req.body.fechaAdjudicacion ? new Date(req.body.fechaAdjudicacion) : null;
    if (req.body.fechaAdjudicacionFin !== undefined) data.fechaAdjudicacionFin = req.body.fechaAdjudicacionFin ? new Date(req.body.fechaAdjudicacionFin) : null;
    if (req.body.origenFechas !== undefined) data.origenFechas = req.body.origenFechas ?? null;
    if (req.body.urlFicha !== undefined) data.urlFicha = req.body.urlFicha ?? null;

    // Encadenamiento multi-sucesor
    // add and remove are independent — both can be applied in the same request
    if (req.body.addProyectoContinuacionId) {
      data.proyectoContinuacionIds = admin.firestore.FieldValue.arrayUnion(req.body.addProyectoContinuacionId);
    }
    if (req.body.removeProyectoContinuacionId) {
      // If add was also specified Firestore will apply both atomically (arrayUnion then arrayRemove
      // are separate field transforms, so we can't do both on the same field in one update).
      // When both are present, apply remove by overwriting the add operation.
      data.proyectoContinuacionIds = admin.firestore.FieldValue.arrayRemove(req.body.removeProyectoContinuacionId);
    }
    if (!req.body.addProyectoContinuacionId && !req.body.removeProyectoContinuacionId) {
      if (req.body.clearProyectoContinuacionIds === true) {
        data.proyectoContinuacionIds = [];
      } else if (req.body.proyectoContinuacionId !== undefined) {
        const pid = req.body.proyectoContinuacionId;
        data.proyectoContinuacionIds = pid ? admin.firestore.FieldValue.arrayUnion(pid) : [];
      }
    }

    logger.info(`actualizarProyecto DATOS: campos=${Object.keys(data).join(', ')}`);

    const db = admin.firestore();
    const batch = db.batch();

    batch.update(db.collection('proyectos').doc(id), data);

    // Registrar en historial si se indica el campo editado
    if (_campoEditado) {
      const histRef = db.collection('proyectos').doc(id).collection('historial').doc();
      batch.set(histRef, {
        campo: _campoEditado,
        valorAnterior: _valorAnterior ?? null,
        valorNuevo: _valorNuevo ?? null,
        fecha: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    logger.info(`actualizarProyecto COMMIT: iniciando batch.commit()`);
    await batch.commit();
    logger.info(`actualizarProyecto SUCCESS: id=${id}`);
    return res.json({ ok: true });

  } catch (e) {
    logger.error(`actualizarProyecto EXCEPTION: ${e.message}`);
    console.error('actualizarProyecto FULL ERROR:', e);
    return res.status(500).json({ error: e.message, stack: e.stack });
  }
});

exports.eliminarProyecto = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!await _verifyToken(req, res)) return;
  const db = admin.firestore();
  try {
    const { id } = req.body;
    if (!id) return res.status(400).json({ error: 'id requerido' });
    await db.collection('proyectos').doc(id).delete();
    logger.info(`eliminarProyecto: id=${id}`);
    return res.json({ ok: true });
  } catch (e) {
    logger.error(`eliminarProyecto error: ${e.message}`);
    return res.status(500).json({ error: e.message });
  }
});

// --- FUNCIONES CORREGIDAS PARA TIPOS DE DOCUMENTO (COMO ARRAY) ---

// 1. Obtener la lista de strings desde el documento principal
exports.obtenerTiposDocumento = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  try {
    const doc = await admin.firestore().collection('configuracion').doc('opciones').get();
    if (!doc.exists) return res.json([]);

    // Retornamos el array 'tiposDocumento' o una lista vacía si no existe
    const tipos = doc.data().tiposDocumento || [];
    return res.json(tipos);
  } catch (e) {
    logger.error("Error en obtenerTiposDocumento:", e);
    return res.status(500).json({ error: e.message });
  }
});

// 2. Obtener toda la configuración (estados, modalidades, productos, etc.)
exports.obtenerConfiguracion = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  try {
    const doc = await admin.firestore().collection('configuracion').doc('opciones').get();
    if (!doc.exists) {
      // Retornamos una estructura por defecto similar a ConfiguracionData.defaults()
      return res.json({
        estados: [
          { nombre: 'Vigente', color: '10B981' },
          { nombre: 'X Vencer', color: 'F59E0B' },
          { nombre: 'Finalizado', color: '64748B' },
          { nombre: 'Sin fecha', color: 'EF4444' },
        ],
        modalidades: ['Licitación Pública', 'Convenio Marco', 'Trato Directo', 'Otro'],
        productos: [],
        tiposDocumento: ['Contrato', 'Orden de Compra', 'Acta de Evaluación', 'Otro'],
      });
    }
    return res.json(doc.data());
  } catch (e) {
    logger.error("Error en obtenerConfiguracion:", e);
    return res.status(500).json({ error: e.message });
  }
});

// 3. Guardar toda la configuración
exports.guardarConfiguracion = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const data = req.body;
    await admin.firestore().collection('configuracion').doc('opciones').set(data, { merge: true });
    return res.json({ ok: true });
  } catch (e) {
    logger.error("Error en guardarConfiguracion:", e);
    return res.status(500).json({ error: e.message });
  }
});

// 4. Agregar un nuevo texto a la lista (arrayUnion) de tipos de documento
exports.guardarTipoDocumento = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { nombre } = req.body;
    if (!nombre) return res.status(400).json({ error: 'Missing nombre' });

    const docRef = admin.firestore().collection('configuracion').doc('opciones');

    // Agrega el string al array solo si no existe ya
    await docRef.update({
      tiposDocumento: admin.firestore.FieldValue.arrayUnion(nombre)
    });

    return res.json({ ok: true, nombre });
  } catch (e) {
    logger.error("Error en guardarTipoDocumento:", e);
    return res.status(500).json({ error: e.message });
  }
});

// 3. Quitar un texto de la lista (arrayRemove)
exports.eliminarTipoDocumento = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { nombre } = req.body;
    if (!nombre) return res.status(400).json({ error: 'Missing nombre' });

    const docRef = admin.firestore().collection('configuracion').doc('opciones');

    // Elimina el string exacto de la lista
    await docRef.update({
      tiposDocumento: admin.firestore.FieldValue.arrayRemove(nombre)
    });

    return res.json({ ok: true });
  } catch (e) {
    logger.error("Error en eliminarTipoDocumento:", e);
    return res.status(500).json({ error: e.message });
  }
});

exports.contarUsoModalidades = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  try {
    const snap = await admin.firestore().collection('proyectos').get();
    const conteo = {};
    snap.docs.forEach(doc => {
      const m = doc.data().modalidadCompra;
      if (m) conteo[m] = (conteo[m] || 0) + 1;
    });
    return res.json(conteo);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.obtenerCacheExterno = onRequest({
  cors: ['https://licitaciones-prod.web.app', 'https://licitaciones-prod.firebaseapp.com', 'http://localhost:5000', 'http://localhost:8080', 'http://localhost:3000'],
  region: 'us-central1'
}, async (req, res) => {
  try {
    const { proyectoId, tipo } = req.query;
    if (!proyectoId || !tipo) return res.status(400).json({ error: 'Missing proyectoId or tipo' });
    const doc = await admin.firestore()
      .collection('proyectos').doc(proyectoId)
      .collection('cache').doc(tipo).get();
    if (!doc.exists) return res.json(null);
    const d = doc.data();
    return res.json({
      data: d.data,
      fetchedAt: d.fetchedAt ? d.fetchedAt.toDate().toISOString() : null,
    });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.guardarCacheExterno = onRequest({
  cors: ['https://licitaciones-prod.web.app', 'https://licitaciones-prod.firebaseapp.com', 'http://localhost:5000', 'http://localhost:8080', 'http://localhost:3000'],
  region: 'us-central1'
}, async (req, res) => {
  // En v2 con cors: list, el preflight se maneja automáticamente.
  // Solo validamos el método para la lógica de negocio.
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { proyectoId, tipo, data } = req.body;
    if (!proyectoId || !tipo || !data) return res.status(400).json({ error: 'Missing fields' });
    await admin.firestore()
      .collection('proyectos').doc(proyectoId)
      .collection('cache').doc(tipo).set({
        data,
        fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// ── Auth: crear usuario (solo admins) ─────────────────────────────────────────

exports.crearUsuario = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Verify Firebase ID token
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) return res.status(401).json({ error: 'Sin autorización' });
  const idToken = authHeader.split('Bearer ')[1];
  let caller;
  try {
    caller = await admin.auth().verifyIdToken(idToken);
  } catch (_) {
    return res.status(401).json({ error: 'Token inválido' });
  }

  // Check caller is admin in Firestore
  const callerDoc = await admin.firestore().collection('usuarios').doc(caller.uid).get();
  if (!callerDoc.exists || callerDoc.data().rol !== 'admin') {
    return res.status(403).json({ error: 'Solo los administradores pueden crear usuarios' });
  }

  const { email, nombre, password } = req.body;
  if (!email || !nombre || !password) return res.status(400).json({ error: 'Faltan campos' });
  if (!email.endsWith('@meetcard.cl')) return res.status(400).json({ error: 'Solo se permiten correos @meetcard.cl' });

  try {
    const user = await admin.auth().createUser({ email, password, displayName: nombre });
    await admin.firestore().collection('usuarios').doc(user.uid).set({
      email,
      nombre,
      rol: 'usuario',
      permisos: {
        inicio: { ver: true },
        proyectos: { ver: true, crear: true, editar: true, eliminar: true },
        configuracion: { ver: true, editar: true },
      },
      creadoEn: admin.firestore.FieldValue.serverTimestamp(),
      creadoPor: caller.uid,
    });
    return res.json({ uid: user.uid });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
});

// ── Auth: eliminar usuario (solo admins) ──────────────────────────────────────

exports.eliminarUsuario = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) return res.status(401).json({ error: 'Sin autorización' });
  const idToken = authHeader.split('Bearer ')[1];
  let caller;
  try {
    caller = await admin.auth().verifyIdToken(idToken);
  } catch (_) {
    return res.status(401).json({ error: 'Token inválido' });
  }

  const callerDoc = await admin.firestore().collection('usuarios').doc(caller.uid).get();
  if (!callerDoc.exists || callerDoc.data().rol !== 'admin') {
    return res.status(403).json({ error: 'Solo los administradores pueden eliminar usuarios' });
  }

  const { uid } = req.body;
  if (!uid) return res.status(400).json({ error: 'Falta uid' });
  if (uid === caller.uid) return res.status(400).json({ error: 'No puedes eliminarte a ti mismo' });

  try {
    await admin.auth().deleteUser(uid);
    await admin.firestore().collection('usuarios').doc(uid).delete();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
});

// --- BigQuery proxy ---
// POST body: { query: string, params?: any[] }
// Requiere autenticación Firebase (header Authorization: Bearer <idToken>)
exports.queryBigQuery = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  // Verificar token Firebase
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token requerido' });
  }
  try {
    await admin.auth().verifyIdToken(auth.slice(7));
  } catch (_) {
    return res.status(401).json({ error: 'Token inválido' });
  }

  const { query, params } = req.body;
  if (!query || typeof query !== 'string') {
    return res.status(400).json({ error: 'Campo "query" requerido' });
  }

  try {
    const [rows] = await bigquery.query({
      query,
      params: params || [],
      useLegacySql: false,
    });
    return res.json(rows);
  } catch (e) {
    logger.error('queryBigQuery error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- Análisis meses_publicado_ordendecompra vs proyectos ---
// Cruza licitaciones-prod.sistema_compras.meses_publicado_ordendecompra con proyectos Firestore
// GET /analizarMesesPublicadoOC
exports.analizarMesesPublicadoOC = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 300,
  memory: '512MiB',
}, async (req, res) => {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Token requerido' });
  try { await admin.auth().verifyIdToken(auth.slice(7)); }
  catch (_) { return res.status(401).json({ error: 'Token inválido' }); }

  try {
    // 1. Obtener todos los registros de BigQuery
    const [bqRows] = await bigquery.query({
      query: `SELECT id_licitacion, id_oc, fecha_publicacion, fecha_envio_oc, dias_totales, meses_totales
              FROM \`licitaciones-prod.sistema_compras.meses_publicado_ordendecompra\`
              ORDER BY id_licitacion`,
      useLegacySql: false,
    });
    logger.info(`meses_publicado_ordendecompra: ${bqRows.length} filas en BQ`);

    // 2. Cargar proyectos desde Firestore
    const snap = await admin.firestore().collection('proyectos').get();
    const proyectos = snap.docs.map(d => ({ firestoreId: d.id, ...d.data() }));

    // Índices rápidos por idLicitacion (normalizado)
    const proyectoPorLicit = {};
    for (const p of proyectos) {
      if (p.idLicitacion) {
        proyectoPorLicit[p.idLicitacion.trim().toUpperCase()] = p;
      }
    }

    // 3. Cruzar
    const enApp = [];
    const fueraDeApp = [];

    for (const row of bqRows) {
      const licitKey = (row.id_licitacion ?? '').trim().toUpperCase();
      const ocBQ = (row.id_oc ?? '').trim();
      const proyecto = proyectoPorLicit[licitKey];

      if (proyecto) {
        const ocsEnApp = Array.isArray(proyecto.idsOrdenesCompra) ? proyecto.idsOrdenesCompra : [];
        const ocRegistrada = ocsEnApp.map(o => o.trim().toUpperCase());
        const ocBQKey = ocBQ.toUpperCase();
        enApp.push({
          id_licitacion: row.id_licitacion,
          id_oc_bq: ocBQ,
          fecha_publicacion: row.fecha_publicacion,
          fecha_envio_oc: row.fecha_envio_oc,
          dias_totales: row.dias_totales,
          meses_totales: row.meses_totales,
          proyectoId: proyecto.firestoreId,
          institucion: proyecto.institucion ?? null,
          oc_en_app: ocsEnApp,
          oc_bq_registrada: ocRegistrada.includes(ocBQKey),
        });
      } else {
        fueraDeApp.push({
          id_licitacion: row.id_licitacion,
          id_oc_bq: ocBQ,
          fecha_publicacion: row.fecha_publicacion,
          fecha_envio_oc: row.fecha_envio_oc,
          dias_totales: row.dias_totales,
          meses_totales: row.meses_totales,
        });
      }
    }

    const ocFaltante = enApp.filter(r => !r.oc_bq_registrada);

    return res.json({
      totalBQ: bqRows.length,
      totalEnApp: enApp.length,
      totalFueraDeApp: fueraDeApp.length,
      totalConOCFaltante: ocFaltante.length,
      enApp,
      fueraDeApp,
      ocFaltante,   // Proyectos presentes pero con OC de BQ no registrada en la app
    });
  } catch (e) {
    logger.error('analizarMesesPublicadoOC error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- Análisis de clientes nuevos Meetcard ---
// Cruza clientes_nuevos_meetcard (BQ) con proyectos (Firestore) vía MP API
// GET /analizarClientesMeetcard
// Requiere Authorization: Bearer <idToken>
exports.analizarClientesMeetcard = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
}, async (req, res) => {
  // Autenticación
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token requerido' });
  }
  try {
    await admin.auth().verifyIdToken(auth.slice(7));
  } catch (_) {
    return res.status(401).json({ error: 'Token inválido' });
  }

  try {
    // 1. Obtener todos los id_oc_inicial desde BigQuery
    const [bqRows] = await bigquery.query({
      query: 'SELECT id_oc_inicial, nombre_institucion, nombre_proveedor FROM `licitaciones-prod.sistema_compras.clientes_nuevos_meetcard`',
      useLegacySql: false,
    });
    logger.info(`Meetcard: ${bqRows.length} OCs en BigQuery`);

    // 2. Obtener todos los proyectos de Firestore
    const snap = await admin.firestore().collection('proyectos').get();
    const proyectos = snap.docs.map(d => ({ id: d.id, ...d.data() }));

    // Construir índices para búsqueda rápida
    const ocEnProyecto = new Set();      // id_oc en minúsculas
    const licitEnProyecto = new Set();   // idLicitacion en minúsculas
    const proyectoPorOC = {};            // ocId -> proyectoId
    const proyectoPorLicit = {};         // licitId -> proyectoId

    for (const p of proyectos) {
      const ocs = Array.isArray(p.idsOrdenesCompra) ? p.idsOrdenesCompra : [];
      for (const oc of ocs) {
        const key = oc.trim().toLowerCase();
        ocEnProyecto.add(key);
        proyectoPorOC[key] = p.id;
      }
      if (p.idLicitacion) {
        const key = p.idLicitacion.trim().toLowerCase();
        licitEnProyecto.add(key);
        proyectoPorLicit[key] = p.id;
      }
    }

    // 3. Para cada OC de BQ, determinar si está en la app
    const presentes = [];
    const ausentes = [];

    // Limitar concurrencia a 10 llamadas simultáneas a la API
    const CONCURRENCY = 10;
    for (let i = 0; i < bqRows.length; i += CONCURRENCY) {
      const lote = bqRows.slice(i, i + CONCURRENCY);
      await Promise.all(lote.map(async (row) => {
        const ocId = row.id_oc_inicial?.toString().trim() ?? '';
        if (!ocId) return;

        const ocKey = ocId.toLowerCase();

        // Verificar por OC directamente
        if (ocEnProyecto.has(ocKey)) {
          presentes.push({
            id_oc_inicial: ocId,
            nombre_institucion: row.nombre_institucion,
            nombre_proveedor: row.nombre_proveedor,
            match: 'oc',
            proyectoId: proyectoPorOC[ocKey],
          });
          return;
        }

        // Si no está por OC, consultar la API para obtener CodigoLicitacion
        let codigoLicitacion = null;
        try {
          const url = `${OC_BASE_URL}?codigo=${encodeURIComponent(ocId)}&ticket=${OC_TICKET}`;
          const resp = await axios.get(url, { timeout: 15000 });
          const listado = resp.data?.Listado ?? [];
          if (listado.length > 0) {
            codigoLicitacion = listado[0]?.CodigoLicitacion?.trim() ?? null;
          }
        } catch (e) {
          logger.warn(`Error consultando OC ${ocId}: ${e.message}`);
        }

        const licitKey = codigoLicitacion?.toLowerCase() ?? null;


        if (licitKey && licitEnProyecto.has(licitKey)) {
          presentes.push({
            id_oc_inicial: ocId,
            nombre_institucion: row.nombre_institucion,
            nombre_proveedor: row.nombre_proveedor,
            match: 'licitacion',
            codigoLicitacion,
            proyectoId: proyectoPorLicit[licitKey],
          });
        } else {
          ausentes.push({
            id_oc_inicial: ocId,
            nombre_institucion: row.nombre_institucion,
            nombre_proveedor: row.nombre_proveedor,
            codigoLicitacion: codigoLicitacion ?? null,
          });
        }
      }));
    }

    return res.json({
      totalMeetcard: bqRows.length,
      totalPresentes: presentes.length,
      totalAusentes: ausentes.length,
      presentes,
      ausentes,
    });
  } catch (e) {
    logger.error('analizarClientesMeetcard error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// ── Helpers análisis ──────────────────────────────────────────────────────────

// Verifica token Firebase y retorna uid, o responde 401.
async function _verifyToken(req, res) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) { res.status(401).json({ error: 'Token requerido' }); return null; }
  try { const decodedToken = await admin.auth().verifyIdToken(auth.slice(7)); return decodedToken.uid; } catch (_) { res.status(401).json({ error: 'Token inválido' }); return null; }
}

// Lee caché Firestore. Retorna datos si vigente (ttlMs), null si expirado/inexistente.
async function _readCache(db, docId, ttlMs) {
  const snap = await db.collection('cache_bq').doc(docId).get();
  if (!snap.exists) return null;
  const d = snap.data();
  if (ttlMs && Date.now() - (d.fetchedAt?.toMillis?.() ?? 0) > ttlMs) return null;
  return d;
}

async function _writeCache(db, docId, data) {
  await db.collection('cache_bq').doc(docId).set({ ...data, fetchedAt: admin.firestore.FieldValue.serverTimestamp() });
}

const TTL_7D = 7 * 24 * 60 * 60 * 1000;

// --- CLOUD FUNCTION: Competidores por licitación ---
// Retorna todas las ofertas de Competencia_Ofertas para un id_licitacion.
// GET /obtenerCompetidoresLicitacion?idLicitacion=XXX
// Caché Firestore 7 días.
exports.obtenerCompetidoresLicitacion = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { idLicitacion } = req.query;
  if (!idLicitacion) return res.status(400).json({ error: 'idLicitacion requerido' });

  const db = admin.firestore();
  const cacheId = `competidores_${idLicitacion.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ rows: cached.rows, fromCache: true });

  try {
    const [rows] = await bigquery.query({
      query: `SELECT id_licitacion, titulo, id_oferta, nombre_competidor, rut_competidor, monto_ofertado, quien_oferta
              FROM \`licitaciones-prod.sistema_compras.Competencia_Ofertas\`
              WHERE id_licitacion = @idLicitacion
              ORDER BY monto_ofertado ASC`,
      params: { idLicitacion },
      useLegacySql: false,
    });
    await _writeCache(db, cacheId, { rows });
    return res.json({ rows, fromCache: false });
  } catch (e) {
    logger.error('obtenerCompetidoresLicitacion error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Ganador de licitación ---
// Retorna las OC adjudicadas para un CodigoLicitacion desde tab_gestion_universal.
// GET /obtenerGanadorLicitacion?idLicitacion=XXX
// Caché Firestore 7 días.
exports.obtenerGanadorLicitacion = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { idLicitacion } = req.query;
  if (!idLicitacion) return res.status(400).json({ error: 'idLicitacion requerido' });

  const db = admin.firestore();
  const cacheId = `ganador_${idLicitacion.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ rows: cached.rows, fromCache: true });

  try {
    const [rows] = await bigquery.query({
      query: `SELECT ID, NombreProveedor, rut_proveedor, CAST(monto_calculado_oc AS STRING) AS monto_calculado_oc,
                     RutUnidadCompra, OrganismoPublico, FechaEnvio, modalidad, Estado, CodigoLicitacion,
                     Moneda
              FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
              WHERE CodigoLicitacion = @idLicitacion
              LIMIT 20`,
      params: { idLicitacion },
      useLegacySql: false,
    });
    await _writeCache(db, cacheId, { rows });
    return res.json({ rows, fromCache: false });
  } catch (e) {
    logger.error('obtenerGanadorLicitacion error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Historial ganador con organismo ---
// Combina tab_gestion_universal (historial OC) y analisis_permanencia_proveedor.
// GET /obtenerHistorialGanador?rutProveedor=XXX&rutOrganismo=YYY
// Caché Firestore 7 días.
exports.obtenerHistorialGanador = onRequest({ cors: true, memory: '512MiB' }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { rutProveedor, rutOrganismo } = req.query;
  if (!rutProveedor) return res.status(400).json({ error: 'rutProveedor requerido' });

  const db = admin.firestore();
  const cacheId = `historial_v2_${rutProveedor.replace(/[^a-zA-Z0-9_-]/g, '_')}_${(rutOrganismo || '').replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ ocs: cached.ocs, permanencia: cached.permanencia, fromCache: true });

  try {
    // Query 1: últimas 30 OC del proveedor con este organismo
    const ocQuery = rutOrganismo
      ? `SELECT ID, CAST(monto_calculado_oc AS STRING) AS monto_calculado_oc, FechaEnvio, OrganismoPublico, RutUnidadCompra, Estado, CodigoLicitacion, modalidad
         FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
         WHERE rut_proveedor = @rutProveedor AND RutUnidadCompra = @rutOrganismo
         ORDER BY fecha_envio_limpia DESC LIMIT 30`
      : `SELECT ID, CAST(monto_calculado_oc AS STRING) AS monto_calculado_oc, FechaEnvio, OrganismoPublico, RutUnidadCompra, Estado, CodigoLicitacion, modalidad
         FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
         WHERE rut_proveedor = @rutProveedor
         ORDER BY fecha_envio_limpia DESC LIMIT 30`;

    const [ocs] = await bigquery.query({
      query: ocQuery,
      params: rutOrganismo ? { rutProveedor, rutOrganismo } : { rutProveedor },
      useLegacySql: false,
    });

    // Query 2: permanencia del proveedor filtrada por organismo cuando está disponible
    // (la tabla no tiene cliente_rut, usamos el nombre del organismo del primer OC)
    const nombreOrganismo = ocs.length > 0 ? (ocs[0].OrganismoPublico ?? null) : null;
    const permQuery = nombreOrganismo
      ? `SELECT cliente_nombre, categoria_nombre, proveedor_rut, proveedor_nombre,
                CAST(fecha_inicio_primera_compra AS STRING) AS fecha_inicio_primera_compra,
                CAST(fecha_ultima_compra AS STRING) AS fecha_ultima_compra,
                cantidad_oc_emitidas, permanencia_meses, permanencia_anios, promedio_dias_entre_compras
         FROM \`licitaciones-prod.ordenes_historicas.analisis_permanencia_proveedor\`
         WHERE proveedor_rut = @rutProveedor
           AND cliente_nombre LIKE @organismoLike
         ORDER BY permanencia_meses DESC LIMIT 5`
      : `SELECT cliente_nombre, categoria_nombre, proveedor_rut, proveedor_nombre,
                CAST(fecha_inicio_primera_compra AS STRING) AS fecha_inicio_primera_compra,
                CAST(fecha_ultima_compra AS STRING) AS fecha_ultima_compra,
                cantidad_oc_emitidas, permanencia_meses, permanencia_anios, promedio_dias_entre_compras
         FROM \`licitaciones-prod.ordenes_historicas.analisis_permanencia_proveedor\`
         WHERE proveedor_rut = @rutProveedor
         ORDER BY permanencia_meses DESC LIMIT 10`;

    const [perm] = await bigquery.query({
      query: permQuery,
      params: nombreOrganismo
        ? { rutProveedor, organismoLike: `%${nombreOrganismo.substring(0, 40).trim()}%` }
        : { rutProveedor },
      useLegacySql: false,
    });

    await _writeCache(db, cacheId, { ocs, permanencia: perm });
    return res.json({ ocs, permanencia: perm, fromCache: false });
  } catch (e) {
    logger.error('obtenerHistorialGanador error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Predicción próxima compra por organismo ---
// Retorna frecuencia_compra_prediccion_CATEGORIA filtrada por Cliente_RUT.
// GET /obtenerPrediccionOrganismo?rutOrganismo=XXX
// Caché Firestore 7 días.
exports.obtenerPrediccionOrganismo = onRequest({ cors: true, memory: '512MiB' }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { rutOrganismo } = req.query;
  if (!rutOrganismo) return res.status(400).json({ error: 'rutOrganismo requerido' });

  const db = admin.firestore();
  const cacheId = `prediccion_${rutOrganismo.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ rows: cached.rows, fromCache: true });

  try {
    const [rows] = await bigquery.query({
      query: `SELECT Cliente_RUT, Cliente_Nombre, Proveedor_RUT, Proveedor_Nombre,
                     codigoCategoria, Categoria_Nombre_Referencia,
                     Total_OCs_Adjudicadas, CAST(MontoTotal_CLP AS STRING) AS MontoTotal_CLP,
                     CAST(Primera_Compra AS STRING) AS Primera_Compra,
                     CAST(Ultima_Compra AS STRING) AS Ultima_Compra,
                     Promedio_Dias_Entre_Compras,
                     CAST(Proxima_Compra_Estimada AS STRING) AS Proxima_Compra_Estimada
              FROM \`licitaciones-prod.ordenes_historicas.frecuencia_compra_prediccion_CATEGORIA\`
              WHERE Cliente_RUT = @rutOrganismo
              ORDER BY Proxima_Compra_Estimada ASC
              LIMIT 50`,
      params: { rutOrganismo },
      useLegacySql: false,
    });
    await _writeCache(db, cacheId, { rows });
    return res.json({ rows, fromCache: false });
  } catch (e) {
    logger.error('obtenerPrediccionOrganismo error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Ficha de Organismo ---
// Retorna resumen del organismo + top proveedores desde tab_gestion_universal.
// GET /obtenerFichaOrganismo?rutOrganismo=XXX — Caché 7 días.
exports.obtenerFichaOrganismo = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { rutOrganismo } = req.query;
  if (!rutOrganismo) return res.status(400).json({ error: 'rutOrganismo requerido' });

  const db = admin.firestore();
  const cacheId = `ficha_org_v2_${rutOrganismo.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ resumen: cached.resumen, proveedores: cached.proveedores, fromCache: true });

  try {
    const [[resumenRows], [proveedores]] = await Promise.all([
      bigquery.query({
        query: `SELECT OrganismoPublico, RutUnidadCompra, Sector, RegionUnidadCompra, ActividadComprador,
                       COUNT(*) AS total_ocs,
                       SUM(monto_calculado_oc) AS gasto_total,
                       CAST(MIN(fecha_envio_limpia) AS STRING) AS primera_oc,
                       CAST(MAX(fecha_envio_limpia) AS STRING) AS ultima_oc
                FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
                WHERE RutUnidadCompra = @rutOrganismo
                GROUP BY OrganismoPublico, RutUnidadCompra, Sector, RegionUnidadCompra, ActividadComprador
                LIMIT 1`,
        params: { rutOrganismo }, useLegacySql: false,
      }),
      bigquery.query({
        query: `SELECT rut_proveedor, nombre_proveedor,
                       MAX(ActividadProveedor) AS actividad_proveedor,
                       COUNT(*) AS total_ocs,
                       SUM(monto_calculado_oc) AS monto_total,
                       CAST(MIN(fecha_envio_limpia) AS STRING) AS primera_oc,
                       CAST(MAX(fecha_envio_limpia) AS STRING) AS ultima_oc
                FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
                WHERE RutUnidadCompra = @rutOrganismo
                GROUP BY rut_proveedor, nombre_proveedor
                ORDER BY monto_total DESC
                LIMIT 50`,
        params: { rutOrganismo }, useLegacySql: false,
      }),
    ]);
    const resumen = resumenRows[0] ?? null;
    await _writeCache(db, cacheId, { resumen, proveedores });
    return res.json({ resumen, proveedores, fromCache: false });
  } catch (e) {
    logger.error('obtenerFichaOrganismo error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Ficha de Proveedor ---
// Retorna resumen del proveedor + top organismos + permanencia desde BQ.
// GET /obtenerFichaProveedor?rutProveedor=XXX — Caché 7 días.
exports.obtenerFichaProveedor = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { rutProveedor } = req.query;
  if (!rutProveedor) return res.status(400).json({ error: 'rutProveedor requerido' });

  const db = admin.firestore();
  const cacheId = `ficha_prov_${rutProveedor.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ resumen: cached.resumen, organismos: cached.organismos, permanencia: cached.permanencia, fromCache: true });

  try {
    const [[resumenRows], [organismos], [permanencia]] = await Promise.all([
      bigquery.query({
        query: `SELECT nombre_proveedor, rut_proveedor, ActividadProveedor, RegionProveedor,
                       COUNT(*) AS total_ocs,
                       SUM(monto_calculado_oc) AS monto_total,
                       CAST(MIN(fecha_envio_limpia) AS STRING) AS primera_oc,
                       CAST(MAX(fecha_envio_limpia) AS STRING) AS ultima_oc
                FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
                WHERE rut_proveedor = @rutProveedor
                GROUP BY nombre_proveedor, rut_proveedor, ActividadProveedor, RegionProveedor
                LIMIT 1`,
        params: { rutProveedor }, useLegacySql: false,
      }),
      bigquery.query({
        query: `SELECT RutUnidadCompra, OrganismoPublico,
                       COUNT(*) AS total_ocs,
                       SUM(monto_calculado_oc) AS monto_total,
                       CAST(MAX(fecha_envio_limpia) AS STRING) AS ultima_oc
                FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
                WHERE rut_proveedor = @rutProveedor
                GROUP BY RutUnidadCompra, OrganismoPublico
                ORDER BY monto_total DESC
                LIMIT 20`,
        params: { rutProveedor }, useLegacySql: false,
      }),
      bigquery.query({
        query: `SELECT cliente_nombre, categoria_nombre, cantidad_oc_emitidas,
                       permanencia_meses, permanencia_anios, promedio_dias_entre_compras,
                       CAST(fecha_inicio_primera_compra AS STRING) AS fecha_inicio_primera_compra,
                       CAST(fecha_ultima_compra AS STRING) AS fecha_ultima_compra
                FROM \`licitaciones-prod.ordenes_historicas.analisis_permanencia_proveedor\`
                WHERE proveedor_rut = @rutProveedor
                ORDER BY permanencia_meses DESC
                LIMIT 15`,
        params: { rutProveedor }, useLegacySql: false,
      }),
    ]);
    const resumen = resumenRows[0] ?? null;
    await _writeCache(db, cacheId, { resumen, organismos, permanencia });
    return res.json({ resumen, organismos, permanencia, fromCache: false });
  } catch (e) {
    logger.error('obtenerFichaProveedor error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Radar de Oportunidades ---
// Retorna todas las filas de sistema_compras."Radar de Oportunidades".
// Caché Firestore 24 h bajo /cache_bq/radar_oportunidades.
exports.obtenerRadarOportunidades = onRequest({ cors: true, memory: '512MiB', timeoutSeconds: 120 }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Token requerido' });
  try { await admin.auth().verifyIdToken(auth.slice(7)); } catch (_) { return res.status(401).json({ error: 'Token inválido' }); }

  const db = admin.firestore();
  const cacheRef = db.collection('cache_bq').doc('radar_oportunidades');
  try {
    const snap = await cacheRef.get();
    if (snap.exists) {
      const d = snap.data();
      const age = Date.now() - (d.fetchedAt?.toMillis?.() ?? 0);
      if (age < 24 * 60 * 60 * 1000) return res.json({ rows: d.rows, fromCache: true });
    }
  } catch (_) { /* cache read failure is non-fatal */ }

  try {
    const [rows] = await bigquery.query({
      query: `SELECT institucion, titulo, ganador_actual,
                     CAST(fecha_adjudicacion AS STRING) AS fecha_adjudicacion,
                     CAST(monto AS STRING) AS monto,
                     menciona_seguridad, alerta_comercial
              FROM \`licitaciones-prod.sistema_compras.Radar de Oportunidades\`
              ORDER BY fecha_adjudicacion DESC
              LIMIT 300`,
      useLegacySql: false,
    });
    // Save cache but don't fail the request if it exceeds Firestore doc limit
    try {
      await cacheRef.set({ rows, fetchedAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (cacheErr) {
      logger.warn('obtenerRadarOportunidades cache write failed:', cacheErr.message);
    }
    return res.json({ rows, fromCache: false });
  } catch (e) {
    logger.error('obtenerRadarOportunidades error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Rubros ONU ---
// Retorna toda la tabla analisis_mercado.rubros_onu (clasificador UNSPSC oficial).
// Caché Firestore permanente (sin TTL) bajo /cache_bq/rubros_onu.
exports.obtenerRubrosOnu = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Token requerido' });
  try { await admin.auth().verifyIdToken(auth.slice(7)); } catch (_) { return res.status(401).json({ error: 'Token inválido' }); }

  const db = admin.firestore();
  const cacheRef = db.collection('cache_bq').doc('rubros_onu');
  const snap = await cacheRef.get();
  if (snap.exists) return res.json({ rows: snap.data().rows, fromCache: true });

  try {
    const [rows] = await bigquery.query({
      query: 'SELECT Segmento, Familia, Clase, Producto_Nivel, Codigo_ONU, Nombre_Item, Codigo_Especifico FROM `licitaciones-prod.analisis_mercado.rubros_onu` ORDER BY Codigo_ONU',
      useLegacySql: false,
    });
    await cacheRef.set({ rows, fetchedAt: admin.firestore.FieldValue.serverTimestamp() });
    return res.json({ rows, fromCache: false });
  } catch (e) {
    logger.error('obtenerRubrosOnu error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Refresh nocturno de caché de proyectos ---
// Corre a las 5 AM UTC (2 AM Santiago) después de la ingesta de licitaciones.
// Para cada proyecto revisa si el caché de licitación/OC existe y está vigente;
// si no, lo re-fetcha directamente desde las APIs de Mercado Público.
const MP_API_LICIT_URL = 'https://api.mercadopublico.cl/servicios/v1/publico/licitaciones.json';
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 días
const CONCURRENCY = 5; // peticiones simultáneas máx. al API externo

async function _ejecutarRefrescarCache(db) {
  const now = new Date();
  const stats = { licitaciones: 0, oc: 0, omitidas: 0, errores: 0 };

  // ── Helpers ───────────────────────────────────────────────────────────────

  function isFresh(snap) {
    if (!snap.exists) return false;
    const fetchedAt = snap.data()?.fetchedAt?.toDate?.();
    return fetchedAt ? (now - fetchedAt) < CACHE_TTL_MS : false;
  }

  // Guarda en Firestore sin lanzar excepción
  async function saveCache(ref, data) {
    await ref.set({ data, fetchedAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  // Fetch OCDS (tender o award) con fallback a MP API REST
  async function refreshLicitacion(cacheRef, idLicitacion, modalidad) {
    const ocdsSnap = await cacheRef.doc('ocds').get();

    // Ya existe caché fresco con releases → skip
    if (isFresh(ocdsSnap) && (ocdsSnap.data()?.data?.releases ?? []).length > 0) {
      stats.omitidas++; return;
    }

    const useAward = modalidad === 'Convenio Marco' || modalidad === 'Trato Directo';
    const type = useAward ? 'award' : 'tender';

    // 1. Intentar OCDS
    try {
      const resp = await axios.get(
        `${BASE_URL}/${type}/${encodeURIComponent(idLicitacion)}`,
        { timeout: 20000 }
      );
      if (resp.status === 200 && resp.data) {
        await saveCache(cacheRef.doc('ocds'), resp.data);
        stats.licitaciones++;
        // Si releases vacío, también refrescar fallback MP API
        if ((resp.data?.releases ?? []).length === 0) {
          await refreshMpApi(cacheRef, idLicitacion);
        }
        return;
      }
    } catch (e) {
      if (e.response?.status === 404) { stats.omitidas++; return; }
      logger.warn(`refrescarCache OCDS ${idLicitacion}: ${e.message}`);
    }

    // 2. Fallback: MP API REST
    await refreshMpApi(cacheRef, idLicitacion);
    stats.errores++;
  }

  async function refreshMpApi(cacheRef, idLicitacion) {
    const snap = await cacheRef.doc('mp_api').get();
    if (isFresh(snap)) return;
    try {
      const resp = await axios.get(
        `${MP_API_LICIT_URL}?codigo=${encodeURIComponent(idLicitacion)}&ticket=${OC_TICKET}`,
        { timeout: 15000 }
      );
      if (resp.status === 200 && (resp.data?.Listado ?? []).length > 0) {
        await saveCache(cacheRef.doc('mp_api'), resp.data);
      }
    } catch (e) {
      logger.warn(`refrescarCache MP API ${idLicitacion}: ${e.message}`);
    }
  }

  async function refreshOc(cacheRef, ocId) {
    const cacheKey = `oc_${ocId}`;
    const snap = await cacheRef.doc(cacheKey).get();
    if (isFresh(snap)) { stats.omitidas++; return; }
    try {
      const resp = await axios.get(
        `${OC_BASE_URL}?codigo=${encodeURIComponent(ocId)}&ticket=${OC_TICKET}`,
        { timeout: 20000 }
      );
      const listado = resp.data?.Listado ?? [];
      if (listado.length > 0) {
        await saveCache(cacheRef.doc(cacheKey), listado[0]);
        stats.oc++;
      } else {
        stats.omitidas++;
      }
    } catch (e) {
      if (e.response?.status === 404) { stats.omitidas++; return; }
      logger.warn(`refrescarCache OC ${ocId}: ${e.message}`);
      stats.errores++;
    }
  }

  // ── Main ─────────────────────────────────────────────────────────────────

  const proySnap = await db.collection('proyectos').get();
  logger.info(`refrescarCacheExterno: ${proySnap.size} proyectos`);

  const tasks = [];
  for (const doc of proySnap.docs) {
    const p = doc.data();
    const cacheRef = db.collection('proyectos').doc(doc.id).collection('cache');

    if (p.idLicitacion) {
      tasks.push(() => refreshLicitacion(cacheRef, p.idLicitacion, p.modalidadCompra ?? ''));
    }
    if (Array.isArray(p.idsOrdenesCompra)) {
      for (const ocId of p.idsOrdenesCompra) {
        if (ocId) tasks.push(() => refreshOc(cacheRef, ocId));
      }
    }
  }

  logger.info(`refrescarCacheExterno: ${tasks.length} entradas a revisar`);

  // Ejecutar con concurrencia limitada para no saturar el API externo
  for (let i = 0; i < tasks.length; i += CONCURRENCY) {
    await Promise.allSettled(tasks.slice(i, i + CONCURRENCY).map(fn => fn()));
  }

  logger.info(
    `refrescarCacheExterno completado — licitaciones: ${stats.licitaciones}, ` +
    `OC: ${stats.oc}, omitidas: ${stats.omitidas}, errores: ${stats.errores}`
  );
  await _logApiCall(admin.firestore(), {
    funcion: 'refrescarCacheExterno',
    tipo: 'cache_refresh',
    id: `${proySnap.size} proyectos — ${stats.licitaciones} licit, ${stats.oc} OC, ${stats.omitidas} omitidas, ${stats.errores} errores`,
    estado: stats.errores === 0 ? 'ok' : 'error',
    statusCode: null,
    ms: null,
  });
  return stats;
}

exports.refrescarCacheExterno = onSchedule({
  schedule: '0 5 * * *',   // 5 AM UTC = 2 AM Santiago
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
}, async () => {
  const db = admin.firestore();
  try { await _ejecutarRefrescarCache(db); } catch (e) { logger.error('refrescarCacheExterno scheduled error:', e); }
});

exports.dispararRefrescarCache = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
}, async (req, res) => {
  const uid = await _verifyToken(req, res); if (!uid) return;
  const db = admin.firestore();
  try {
    const stats = await _ejecutarRefrescarCache(db);
    res.json({ ok: true, ...stats });
  } catch (e) {
    logger.error('dispararRefrescarCache error:', e);
    res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Ingesta manual bajo demanda ---
exports.dispararIngestaOCDS = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '1GiB',
}, async (req, res) => {
  if (!await _verifyToken(req, res)) return;
  const db = admin.firestore();
  const now = new Date();
  const months = [
    { year: now.getFullYear(), month: String(now.getMonth() + 1).padStart(2, '0') },
    { year: now.getFullYear(), month: String(now.getMonth()).padStart(2, '0') },
  ];
  const ingestaRef = db.collection('_stats').doc('ingesta');
  await ingestaRef.set({ estado: 'en_proceso', fecha: admin.firestore.FieldValue.serverTimestamp(), encoladas: null, error: null });
  try {
    let totalEncoladas = 0;
    for (const { year, month } of months) {
      const antes = await db.collection('licitaciones_activas').where('procesado', '==', false).count().get();
      await processMonth(db, year, month);
      const despues = await db.collection('licitaciones_activas').where('procesado', '==', false).count().get();
      totalEncoladas += Math.max(0, despues.data().count - antes.data().count);
    }
    // Recalcular categorías y stats de TI para que los cards reflejen los datos actuales
    await _ejecutarCalculoEstadisticas(db);
    await ingestaRef.set({ estado: 'ok', fecha: admin.firestore.FieldValue.serverTimestamp(), encoladas: totalEncoladas, error: null });
    res.json({ ok: true, mensaje: 'Ingesta y estadísticas actualizadas.', encoladas: totalEncoladas });
  } catch (e) {
    await ingestaRef.set({ estado: 'error', fecha: admin.firestore.FieldValue.serverTimestamp(), encoladas: null, error: e.message });
    res.status(500).json({ ok: false, error: e.message });
  }
});

// --- CLOUD FUNCTION: Historial de consultas a APIs externas ---
exports.obtenerHistorialApi = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 15,
  memory: '256MiB',
}, async (req, res) => {
  if (!await _verifyToken(req, res)) return;
  const db = admin.firestore();
  const limit = Math.min(parseInt(req.query.limit ?? '100'), 200);
  const snap = await db.collection('api_logs')
    .orderBy('timestamp', 'desc')
    .limit(limit)
    .get();
  const logs = snap.docs.map(d => {
    const data = d.data();
    return {
      funcion: data.funcion,
      tipo: data.tipo,
      id: data.id,
      estado: data.estado,
      statusCode: data.statusCode ?? null,
      ms: data.ms ?? null,
      timestamp: data.timestamp?.toDate?.()?.toISOString() ?? null,
    };
  });
  res.json({ logs });
});

// --- SCHEDULED: Renovar caché Radar de Oportunidades cada noche ---
// Corre a las 3 AM Santiago (6 AM UTC) para que esté listo al inicio del día laboral.
exports.renovarRadarOportunidades = onSchedule({
  schedule: '0 6 * * *',
  region: 'us-central1',
  timeoutSeconds: 180,
  memory: '512MiB',
}, async () => {
  const db = admin.firestore();
  const cacheRef = db.collection('cache_bq').doc('radar_oportunidades');
  try {
    const [rows] = await bigquery.query({
      query: `SELECT institucion, titulo, ganador_actual,
                     CAST(fecha_adjudicacion AS STRING) AS fecha_adjudicacion,
                     CAST(monto AS STRING) AS monto,
                     menciona_seguridad, alerta_comercial
              FROM \`licitaciones-prod.sistema_compras.Radar de Oportunidades\`
              ORDER BY fecha_adjudicacion DESC
              LIMIT 300`,
      useLegacySql: false,
    });
    await cacheRef.set({ rows, fetchedAt: admin.firestore.FieldValue.serverTimestamp() });
    logger.info(`renovarRadarOportunidades: ${rows.length} filas guardadas en caché.`);
  } catch (e) {
    logger.error('renovarRadarOportunidades error:', e.message);
  }
});

// --- SCHEDULED: Análisis nocturno de todos los proyectos (TTL 30 días) ---
// Corre cada noche a las 2 AM UTC (11 PM Santiago).
// Solo re-analiza proyectos cuyo análisis tiene más de 30 días o no existe.
// Procesa hasta 60 proyectos por ejecución para no superar el timeout.
const TTL_30D = 30 * 24 * 60 * 60 * 1000;

exports.analizarProyectosNocturno = onSchedule({
  schedule: '0 2 * * *',
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '1GiB',
}, async () => {
  const db = admin.firestore();
  const stats = { analizados: 0, omitidos: 0, errores: 0 };

  // 1. Obtener proyectos con idLicitacion
  const snap = await db.collection('proyectos').get();
  const proyectos = snap.docs
    .map(d => ({ id: d.id, idLicitacion: d.data().idLicitacion }))
    .filter(p => p.idLicitacion && p.idLicitacion.trim() !== '');

  logger.info(`analizarProyectosNocturno: ${proyectos.length} proyectos con licitación.`);

  // Función auxiliar: analiza un proyecto y guarda en Firestore
  async function analizarProyecto(idLicitacion) {
    // Competidores y ganador en paralelo
    const [compRows] = await bigquery.query({
      query: `SELECT rut_competidor, nombre_competidor, monto_ofertado, quien_oferta
              FROM \`licitaciones-prod.sistema_compras.Competencia_Ofertas\`
              WHERE id_licitacion = @idLicitacion`,
      params: { idLicitacion },
      useLegacySql: false,
    });

    const [ganRows] = await bigquery.query({
      query: `SELECT rut_proveedor, NombreProveedor, RutUnidadCompra, OrganismoPublico,
                     CAST(monto_calculado_oc AS STRING) AS monto_calculado_oc,
                     FechaEnvio, CodigoLicitacion
              FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
              WHERE CodigoLicitacion = @idLicitacion
              ORDER BY fecha_envio_limpia DESC LIMIT 10`,
      params: { idLicitacion },
      useLegacySql: false,
    });

    let historialOcs = [], permanencia = [], predicciones = [];
    let rutGanador = null, nombreGanador = null, rutOrganismo = null;

    let nombreOrganismo = null;
    if (ganRows.length > 0) {
      const p = ganRows[0];
      rutGanador = p.rut_proveedor ?? null;
      nombreGanador = p.NombreProveedor ?? null;
      rutOrganismo = p.RutUnidadCompra ?? null;
      nombreOrganismo = p.OrganismoPublico ?? null;
    }

    const subFutures = [];

    if (rutGanador) {
      subFutures.push(
        bigquery.query({
          query: `SELECT ID, CAST(monto_calculado_oc AS STRING) AS monto_calculado_oc,
                         FechaEnvio, OrganismoPublico, CodigoLicitacion
                  FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
                  WHERE rut_proveedor = @rutGanador
                    ${rutOrganismo ? 'AND RutUnidadCompra = @rutOrganismo' : ''}
                  ORDER BY fecha_envio_limpia DESC LIMIT 30`,
          params: rutOrganismo ? { rutGanador, rutOrganismo } : { rutGanador },
          useLegacySql: false,
        }).then(([r]) => { historialOcs = r; }),

        bigquery.query({
          query: `SELECT cliente_nombre, categoria_nombre, proveedor_rut, proveedor_nombre,
                         CAST(fecha_inicio_primera_compra AS STRING) AS fecha_inicio_primera_compra,
                         CAST(fecha_ultima_compra AS STRING) AS fecha_ultima_compra,
                         cantidad_oc_emitidas, permanencia_meses, permanencia_anios
                  FROM \`licitaciones-prod.ordenes_historicas.analisis_permanencia_proveedor\`
                  WHERE proveedor_rut = @rutGanador
                  ${nombreOrganismo ? 'AND cliente_nombre LIKE @organismoLike' : ''}
                  ORDER BY permanencia_meses DESC LIMIT 5`,
          params: nombreOrganismo
            ? { rutGanador, organismoLike: `%${nombreOrganismo.substring(0, 40).trim()}%` }
            : { rutGanador },
          useLegacySql: false,
        }).then(([r]) => { permanencia = r; })
      );
    }

    if (rutOrganismo) {
      subFutures.push(
        bigquery.query({
          query: `SELECT Cliente_RUT, Cliente_Nombre, Proveedor_RUT, Proveedor_Nombre,
                         codigoCategoria, Categoria_Nombre_Referencia,
                         Total_OCs_Adjudicadas, CAST(MontoTotal_CLP AS STRING) AS MontoTotal_CLP,
                         CAST(Primera_Compra AS STRING) AS Primera_Compra,
                         CAST(Ultima_Compra AS STRING) AS Ultima_Compra,
                         Promedio_Dias_Entre_Compras,
                         CAST(Proxima_Compra_Estimada AS STRING) AS Proxima_Compra_Estimada
                  FROM \`licitaciones-prod.ordenes_historicas.frecuencia_compra_prediccion_CATEGORIA\`
                  WHERE Cliente_RUT = @rutOrganismo
                  ORDER BY Proxima_Compra_Estimada ASC LIMIT 50`,
          params: { rutOrganismo },
          useLegacySql: false,
        }).then(([r]) => { predicciones = r; })
      );
    }

    if (subFutures.length > 0) await Promise.all(subFutures);

    const cacheDoc = db.collection('analisis_licitacion').doc(idLicitacion);
    const payload = {
      competidores: compRows,
      ganadorOcs: ganRows,
      historialGanador: historialOcs,
      permanencia,
      predicciones,
      rutGanador,
      nombreGanador,
      rutOrganismo,
      fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await cacheDoc.set(payload);

    // Snapshot de historial para análisis de tendencias
    await cacheDoc.collection('historial').add({
      fechaConsulta: admin.firestore.FieldValue.serverTimestamp(),
      totalCompetidores: compRows.length,
      rutGanador,
      nombreGanador,
      rutOrganismo,
      montoAdjudicado: ganRows[0]?.monto_calculado_oc ?? null,
      totalOcsHistorial: historialOcs.length,
      totalPredicciones: predicciones.length,
      competidoresSnapshot: compRows.map(c => ({
        rut: c.rut_competidor,
        nombre: c.nombre_competidor,
        monto: c.monto_ofertado?.toString() ?? null,
      })),
      fuente: 'nocturno',
    });
  }

  // 2. Procesar en lotes de 5 (paralelo moderado para no saturar BQ)
  const BATCH = 5;
  let procesados = 0;

  for (let i = 0; i < proyectos.length && procesados < 60; i += BATCH) {
    const lote = proyectos.slice(i, i + BATCH);
    await Promise.all(lote.map(async (p) => {
      if (procesados >= 60) return;
      try {
        // Verificar TTL 30 días
        const cacheSnap = await db.collection('analisis_licitacion').doc(p.idLicitacion).get();
        if (cacheSnap.exists) {
          const fetchedAt = cacheSnap.data()?.fetchedAt?.toDate?.();
          if (fetchedAt && (Date.now() - fetchedAt.getTime()) < TTL_30D) {
            stats.omitidos++;
            return;
          }
        }
        await analizarProyecto(p.idLicitacion);
        stats.analizados++;
        procesados++;
      } catch (e) {
        logger.warn(`analizarProyectosNocturno error en ${p.idLicitacion}:`, e.message);
        stats.errores++;
      }
    }));
    // Pausa breve entre lotes para no saturar BigQuery
    if (i + BATCH < proyectos.length) await new Promise(r => setTimeout(r, 2000));
  }

  logger.info(`analizarProyectosNocturno: analizados=${stats.analizados}, omitidos=${stats.omitidos}, errores=${stats.errores}`);
});

// ─── Helper compartido: encola licitaciones de la API nativa en licitaciones_activas ─────
async function encolarLicitacionesNativas(db, fecha, licitaciones) {
  if (!licitaciones.length) return 0;
  const collectionRef = db.collection('licitaciones_activas');

  // Filtrar códigos válidos
  const items = licitaciones
    .map(lic => ({ codigo: lic.CodigoExterno }))
    .filter(item => !!item.codigo);

  if (!items.length) return 0;

  // Verificar existencia en paralelo para evitar sobreescribir docs ya procesados
  let snaps;
  try {
    snaps = await Promise.all(items.map(item => collectionRef.doc(item.codigo).get()));
  } catch (e) {
    logger.error(`encolarLicitacionesNativas: error leyendo existentes — ${e.message}`);
    throw e;
  }

  const bulkWriter = db.bulkWriter();
  let encoladas = 0;
  for (let i = 0; i < items.length; i++) {
    if (snaps[i].exists) continue;   // ya está (procesado por OCDS u otra fuente)
    bulkWriter.set(collectionRef.doc(items[i].codigo), {
      codigoExterno: items[i].codigo,
      procesado: false,
      error: false,
      fuente: 'api_nativa',
      fechaPublicacion: fecha,
      fechaEncolado: admin.firestore.FieldValue.serverTimestamp(),
    });
    encoladas++;
  }
  await bulkWriter.close();
  return encoladas;
}

// --- SCHEDULED: Ingesta Diaria API Nativa (cubre lag OCDS 0-30 días) ---
// Corre a las 03:00 UTC ≈ 23:00-00:00 hora Chile según DST, para capturar
// todas las licitaciones publicadas durante el día que termina.
exports.ingestarLicitacionesNativas = onSchedule({
  schedule: '0 3 * * *',
  region: 'us-central1',
  timeoutSeconds: 300,
  memory: '512MiB',
}, async () => {
  const db = admin.firestore();

  // A las 03:00 UTC aún es el mismo día calendario en Chile → usamos fecha UTC actual
  const now = new Date();
  const dd = String(now.getUTCDate()).padStart(2, '0');
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  const yyyy = now.getUTCFullYear();
  const fecha = `${dd}${mm}${yyyy}`;   // formato DDMMYYYY requerido por la API

  logger.info(`ingestarLicitacionesNativas: consultando fecha ${fecha}`);

  let response;
  try {
    response = await axios.get(
      `${MP_API_LICIT_URL}?fecha=${fecha}&ticket=${OC_TICKET}`,
      { timeout: 30000 }
    );
  } catch (e) {
    logger.error(`ingestarLicitacionesNativas: error API — ${e.message}`);
    return;
  }

  const licitaciones = response.data?.Listado ?? [];
  logger.info(`ingestarLicitacionesNativas: ${licitaciones.length} licitaciones en ${fecha}`);

  const encoladas = await encolarLicitacionesNativas(db, fecha, licitaciones);

  await db.collection('_stats').doc('ingesta_nativa').set({
    fecha,
    encontradas: licitaciones.length,
    encoladas,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
  logger.info(`ingestarLicitacionesNativas: ${encoladas} nuevas encoladas`);
});

// --- HTTP: Backfill de los últimos 30 días (ejecución única para cubrir lag OCDS) ---
// Llamar con: POST /backfillLicitaciones15Dias  (no requiere body)
exports.backfillLicitaciones15Dias = onRequest({
  cors: false,
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '1GiB',
}, async (req, res) => {
  const db = admin.firestore();
  const resumen = [];

  for (let diasAtras = 1; diasAtras <= 30; diasAtras++) {
    const d = new Date();
    d.setUTCDate(d.getUTCDate() - diasAtras);
    const dd = String(d.getUTCDate()).padStart(2, '0');
    const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
    const yyyy = d.getUTCFullYear();
    const fecha = `${dd}${mm}${yyyy}`;

    try {
      const response = await axios.get(
        `${MP_API_LICIT_URL}?fecha=${fecha}&ticket=${OC_TICKET}`,
        { timeout: 30000 }
      );
      const licitaciones = response.data?.Listado ?? [];
      const encoladas = await encolarLicitacionesNativas(db, fecha, licitaciones);
      resumen.push({ fecha, encontradas: licitaciones.length, encoladas });
      logger.info(`backfill ${fecha}: ${licitaciones.length} encontradas, ${encoladas} encoladas`);
    } catch (e) {
      logger.warn(`backfill ${fecha}: error — ${e.message}`);
      resumen.push({ fecha, error: e.message });
    }
  }

  const totalEncoladas = resumen.reduce((s, r) => s + (r.encoladas ?? 0), 0);
  await db.collection('_stats').doc('backfill_nativa').set({
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    totalEncoladas,
    resumen,
  });

  res.json({ ok: true, totalEncoladas, resumen });
});

// --- CLOUD FUNCTION: Inteligencia de Licitación ---
// Combina ganador histórico, permanencia del proveedor y predicción próxima compra.
// GET /obtenerInteligenciaLicitacion?id=XXX&comprador_nombre=YYY
// Caché Firestore 7 días.
exports.obtenerInteligenciaLicitacion = onRequest({ cors: true, memory: '512MiB' }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  const { id, comprador_nombre } = req.query;
  if (!id) return res.status(400).json({ error: 'id requerido' });

  const db = admin.firestore();
  const cacheId = `intel_lic_${id.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
  const cached = await _readCache(db, cacheId, TTL_7D);
  if (cached) return res.json({ ...cached, fromCache: true });

  try {
    // 1. Buscar OCs adjudicadas para esta licitación (referencias + ganador)
    const [ocsRows] = await bigquery.query({
      query: `SELECT NombreProveedor, rut_proveedor, RutUnidadCompra,
                     CAST(monto_calculado_oc AS STRING) AS monto_calculado_oc,
                     FechaEnvio, CodigoLicitacion, Estado
              FROM \`licitaciones-prod.sistema_compras.tab_gestion_universal\`
              WHERE CodigoLicitacion = @id
              ORDER BY FechaEnvio DESC LIMIT 10`,
      params: { id },
      useLegacySql: false,
    });

    const ganador = ocsRows[0] ?? null;
    const rutProveedor = ganador?.rut_proveedor ?? null;
    const rutOrganismo = ganador?.RutUnidadCompra ?? null;

    // 2. Permanencia del ganador con este organismo (si existe)
    let permanenciaRow = null;
    if (rutProveedor && rutOrganismo) {
      const [permRows] = await bigquery.query({
        query: `SELECT proveedor_nombre, cliente_nombre, permanencia_anios, cantidad_oc_emitidas
                FROM \`licitaciones-prod.ordenes_historicas.analisis_permanencia_proveedor\`
                WHERE proveedor_rut = @rutProveedor AND cliente_nombre LIKE @compradorLike
                ORDER BY permanencia_meses DESC LIMIT 1`,
        params: {
          rutProveedor,
          compradorLike: comprador_nombre ? `%${comprador_nombre.substring(0, 30)}%` : '%',
        },
        useLegacySql: false,
      });
      permanenciaRow = permRows[0] ?? null;
    }

    // 3. Predicción próxima compra del organismo (primera categoría relevante)
    let prediccionRow = null;
    if (rutOrganismo) {
      const [predRows] = await bigquery.query({
        query: `SELECT Categoria_Nombre_Referencia,
                       CAST(Proxima_Compra_Estimada AS STRING) AS proxima
                FROM \`licitaciones-prod.ordenes_historicas.frecuencia_compra_prediccion_CATEGORIA\`
                WHERE Cliente_RUT = @rutOrganismo
                ORDER BY Proxima_Compra_Estimada ASC LIMIT 1`,
        params: { rutOrganismo },
        useLegacySql: false,
      });
      prediccionRow = predRows[0] ?? null;
    }

    // 4. Construir estrategia heurística
    const anios = permanenciaRow?.permanencia_anios ?? 0;
    const Nivel_Prioridad = anios > 3 ? 'Alta' : anios > 1 ? 'Media' : 'Baja';
    const Accion_Tactica = anios > 3
      ? 'Evaluar propuesta diferenciada para desplazar proveedor arraigado'
      : anios > 1
        ? 'Presentar oferta competitiva con énfasis en precio y plazo'
        : 'Participar activamente, organismo sin proveedor consolidado';
    const Argumento_Semantico = ganador
      ? `Proveedor histórico: ${ganador.NombreProveedor}. ` +
      (anios > 0 ? `Lleva ${anios.toFixed ? anios.toFixed(1) : anios} años con este organismo.` : '')
      : 'Sin historial de adjudicaciones registrado para esta licitación.';

    const estrategia = { Nivel_Prioridad, Accion_Tactica, Argumento_Semantico };
    const permanencia = permanenciaRow
      ? { proveedor_nombre: permanenciaRow.proveedor_nombre, anios: permanenciaRow.permanencia_anios }
      : ganador
        ? { proveedor_nombre: ganador.NombreProveedor, anios: 0 }
        : null;
    const prediccion = prediccionRow ?? null;
    const referencias = ocsRows.map(r => ({
      titulo: r.CodigoLicitacion,
      ganador: r.NombreProveedor,
      monto_adjudicado: r.monto_calculado_oc,
    }));

    const payload = { estrategia, permanencia, prediccion, referencias };
    await _writeCache(db, cacheId, payload);
    return res.json({ ...payload, fromCache: false });
  } catch (e) {
    logger.error('obtenerInteligenciaLicitacion error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Análisis de BigQuery para un Proyecto ---
// Mapea proyectoId -> análisis_licitacion (cache).
// GET /getAnalisisBq?proyectoId=XXX
exports.getAnalisisBq = onRequest({ cors: true, memory: '512MiB' }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).send('Method Not Allowed');
  if (!await _verifyToken(req, res)) return;
  const { proyectoId } = req.query;
  if (!proyectoId) return res.status(400).json({ error: 'proyectoId requerido' });

  const db = admin.firestore();
  try {
    const proySnap = await db.collection('proyectos').doc(proyectoId).get();
    if (!proySnap.exists) return res.status(404).json({ error: 'Proyecto no encontrado' });

    const p = proySnap.data();
    const idLicitacion = p.idLicitacion;
    if (!idLicitacion) {
      if (p.urlConvenioMarco) {
        return res.status(404).json({ error: 'Análisis no aplica para Convenio Marco', idLicitacion: null });
      }
      return res.status(400).json({ error: 'El proyecto no tiene idLicitacion' });
    }

    // Intentar leer de la caché consolidada (generada por el proceso nocturno o disparada)
    const cacheRef = db.collection('analisis_licitacion').doc(idLicitacion);
    const cacheSnap = await cacheRef.get();

    if (cacheSnap.exists) {
      const data = cacheSnap.data();
      // Retornar con el formato que espera el DetalleProyectoProvider
      return res.json({
        competidores: data.competidores ?? [],
        ganador_ocs: data.ganadorOcs ?? [],
        predicciones: data.predicciones ?? [],
        nombre_ganador: data.nombreGanador ?? null,
        rut_ganador: data.rutGanador ?? null,
        permanencia_ganador: Array.isArray(data.permanencia) && data.permanencia.length > 0 
          ? `${data.permanencia[0].permanencia_anios ?? 0} años` 
          : '—',
        rut_organismo: data.rutOrganismo ?? null,
        historial_ganador: data.historialGanador ?? [],
        fetchedAt: data.fetchedAt?.toDate?.()?.toISOString() ?? null,
      });
    }

    // Si no está en caché, podríamos activar el análisis manual, pero por ahora fallamos
    // para indicar que el proceso nocturno no lo ha capturado.
    return res.status(404).json({ 
      error: 'Análisis no disponible para esta licitación todavía.',
      idLicitacion 
    });

  } catch (e) {
    logger.error('getAnalisisBq error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Obtener el foro de Mercado Público y cachear ---
exports.fetchForoLicitacion = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 30,
  memory: '512MiB',
}, async (req, res) => {
  const uid = await _verifyToken(req, res);
  if (!uid) return;

  const { id } = req.query; // Código de licitación
  if (!id) return res.status(400).json({ error: 'ID de licitación requerido' });

  try {
    // Buscar OC_TICKET
    const configSnap = await admin.firestore().collection('config').doc('mercado_publico').get();
    const ticket = (configSnap.exists ? configSnap.data().ticket : null) ?? OC_TICKET;

    const url = `https://api.mercadopublico.cl/servicios/v1/publico/licitaciones/foro.json?codigo=${id}&ticket=${ticket}`;
    logger.info(`fetchForoLicitacion: GET ${url.replace(ticket, '***')}`);
    const resp = await axios.get(url, { timeout: 15000 });
    const data = resp.data;

    const raw = data?.Listado ?? [];
    // Normalizar campos MP → formato esperado por el cliente Dart
    const enquiries = raw.map(item => ({
      description: item.Pregunta ?? item.description ?? '',
      answer:      item.Respuesta ?? item.answer ?? '',
      date:        item.FechaPregunta ?? item.date ?? null,
      dateAnswered: item.FechaRespuesta ?? item.dateAnswered ?? null,
      participant: item.NombreParticipante ?? item.participant ?? '',
      number:      item.Numero ?? item.number ?? null,
    }));
    if (enquiries.length) {
      await admin.firestore().collection('licitaciones_foro').doc(id).set({
        enquiries,
        fetchedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    }
    logger.info(`fetchForoLicitacion: ${enquiries.length} enquiries para ${id}`);
    return res.json({ ok: true, count: enquiries.length, enquiries });
  } catch (e) {
    // 404 = esta licitación no tiene foro en MP (Trato Directo, Cotización, etc.) — no es un error
    if (e.response?.status === 404) {
      logger.info(`fetchForoLicitacion: sin foro para ${id} (404 MP)`);
      return res.json({ ok: true, count: 0, enquiries: [], sinForo: true });
    }
    logger.error('fetchForoLicitacion error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// --- CLOUD FUNCTION: Resumir foro de una licitación con Vertex AI Gemini ---
exports.generarResumenForo = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 120,
  memory: '512MiB',
}, async (req, res) => {
  const uid = await _verifyToken(req, res);
  if (!uid) return;

  const { proyectoId, licitacionId } = req.query;
  if (!proyectoId || !licitacionId) {
    return res.status(400).json({ error: 'Faltan parámetros proyectoId o licitacionId' });
  }

  const db = admin.firestore();
  const foroRef = db.collection('proyectos').doc(proyectoId).collection('foro').doc(licitacionId);
  const proyectoRef = db.collection('proyectos').doc(proyectoId);

  try {
    // 1. Verificar caché de resumen (válido 30 días, permanente si licitación cerrada)
    const foroSnap = await foroRef.get();
    if (!foroSnap.exists) {
      return res.status(404).json({ error: 'No hay foro cacheado para esta licitación. Carga el foro primero.' });
    }

    const foroData = foroSnap.data();
    const resumenExistente = foroData.resumen;
    const resumenFecha = foroData.resumenGeneradoAt;
    const cerrada = foroData.licitacionCerrada === true;

    if (resumenExistente && resumenFecha) {
      const diasDesde = (Date.now() - resumenFecha.toMillis()) / (1000 * 60 * 60 * 24);
      if (cerrada || diasDesde < 30) {
        return res.json({ resumen: resumenExistente, fromCache: true });
      }
    }

    // 2. Leer enquiries
    const enquiries = foroData.enquiries;
    if (!Array.isArray(enquiries) || enquiries.length === 0) {
      return res.status(400).json({ error: 'El foro no tiene preguntas registradas.' });
    }

    // 3. Leer nombre y descripción del proyecto
    const proyectoSnap = await proyectoRef.get();
    const proyectoData = proyectoSnap.exists ? proyectoSnap.data() : {};
    const nombreLicitacion = proyectoData.nombre ?? licitacionId;
    const descripcionLicitacion = proyectoData.descripcion ?? '';

    // 4. Construir prompt
    const foroTexto = enquiries.map((e, i) => {
      const p = e.description ?? '(sin texto)';
      const r = e.answer ?? '(sin respuesta)';
      return `[${i + 1}] Pregunta: ${p}\nRespuesta: ${r}`;
    }).join('\n\n');

    const prompt = `Eres un asistente experto en licitaciones públicas chilenas (Mercado Público).

Analiza el siguiente foro de preguntas y respuestas de una licitación y genera un resumen ejecutivo conciso, estructurado en:
1. **Puntos clave** (máx. 5 bullets): los temas más relevantes o recurrentes del foro
2. **Aclaraciones importantes**: cambios de plazos, requisitos modificados, aclaraciones técnicas relevantes
3. **Alertas**: si hay respuestas contradictorias, condiciones restrictivas o aspectos que un proveedor debe tener muy en cuenta

Licitación: ${nombreLicitacion}
${descripcionLicitacion ? `Descripción: ${descripcionLicitacion}\n` : ''}Total de preguntas: ${enquiries.length}

FORO:
${foroTexto}

Responde en español, con formato markdown limpio. Sé conciso y enfocado en lo que es útil para un proveedor.`;

    // 5. Llamar a Gemini 1.5 Flash vía Google AI Studio API
    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${GEMINI_API_KEY}`;
    const geminiResp = await axios.post(geminiUrl, {
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
    }, { timeout: 90000 });

    const resumen = geminiResp.data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

    if (!resumen) {
      return res.status(500).json({ error: 'Gemini no devolvió contenido.' });
    }

    // 6. Guardar en Firestore (best-effort)
    try {
      await foroRef.set({
        resumen,
        resumenGeneradoAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (saveErr) {
      logger.warn('No se pudo guardar resumen en Firestore:', saveErr.message);
    }

    return res.json({ resumen, fromCache: false });

  } catch (e) {
    const detail = e.response?.data ?? e.message;
    logger.error('resumirForo error:', JSON.stringify(detail));
    return res.status(500).json({ error: e.message, detail });
  }
});

// --- HELPER: Parsear archivo XLS del Foro de Mercado Público ---
function parseXLSForoMP(bufferOArchivo) {
  try {
    // Leer el archivo
    const workbook = XLSX.read(bufferOArchivo, { type: 'buffer' });
    const nombreHoja = workbook.SheetNames[0];
    if (!nombreHoja) throw new Error('Archivo XLS vacío');

    const worksheet = workbook.Sheets[nombreHoja];
    const range = XLSX.utils.decode_range(worksheet['!ref'] || 'A1');

    logger.info(`parseXLSForoMP: sheet="${nombreHoja}" range=${JSON.stringify(range)}`);

    // Obtener todas las filas
    const filas = [];
    for (let r = range.s.r; r <= range.e.r; r++) {
      const fila = [];
      for (let c = range.s.c; c <= range.e.c; c++) {
        const celda_ref = XLSX.utils.encode_col(c) + XLSX.utils.encode_row(r);
        const celda = worksheet[celda_ref];
        fila.push(celda ? celda.v : '');
      }
      filas.push(fila);
    }

    logger.info(`parseXLSForoMP: ${filas.length} filas totales`);

    // Debug: imprimir primeras 5 filas
    for (let i = 0; i < Math.min(5, filas.length); i++) {
      const preview = filas[i].slice(0, 6).map(c => (c || '').toString().substring(0, 20)).join(' | ');
      logger.info(`parseXLSForoMP row[${i}]: ${preview}`);
    }

    // ── ESTRATEGIA 1: BÚSQUEDA EXACTA ──
    let filaEncabezado = -1;
    let idxPregunta = -1, idxRespuesta = -1, idxFecha = -1;
    
    for (let i = 0; i < filas.length; i++) {
      const row = filas[i];
      const str = row.map(c => (c ? c.toString().toLowerCase().trim() : '')).join('|');
      
      if (str.includes('pregunta') && str.includes('respuesta')) {
        filaEncabezado = i;
        logger.info(`parseXLSForoMP: encabezado exacto en fila ${i}`);
        // Mapear índices
        for (let c = 0; c < row.length; c++) {
          const h = (row[c] ? row[c].toString().toLowerCase().trim() : '');
          if (h.includes('pregunta') && idxPregunta === -1) idxPregunta = c;
          if ((h.includes('respuesta') || h === 'answer') && idxRespuesta === -1) idxRespuesta = c;
          if ((h.includes('fecha') || h === 'date') && idxFecha === -1) idxFecha = c;
        }
        break;
      }
    }

    // ── ESTRATEGIA 2: HEURÍSTICA FLEXIBLE ──
    if (filaEncabezado === -1) {
      for (let i = 0; i < filas.length; i++) {
        const row = filas[i];
        const nonEmpty = row.filter(c => c && c.toString().trim().length > 0);
        
        if (nonEmpty.length >= 2) {
          filaEncabezado = i;
          idxPregunta = 0;
          idxRespuesta = 1;
          logger.info(`parseXLSForoMP: encabezado heurístico en fila ${i}, columnas ${idxPregunta}, ${idxRespuesta}`);
          break;
        }
      }
    }

    if (filaEncabezado === -1) {
      throw new Error(`No se encontró encabezado válido. Primeras 5 filas analizadas.`);
    }

    // Extraer preguntas
    const foro = [];
    let dataRowCount = 0;

    for (let i = filaEncabezado + 1; i < filas.length; i++) {
      const row = filas[i];
      if (!row || row.every(cell => !cell)) continue;

      const pregunta = (row[idxPregunta] ? row[idxPregunta].toString().trim() : '');
      const respuesta = (row[idxRespuesta] ? row[idxRespuesta].toString().trim() : '');

      // Incluir si hay pregunta O respuesta (o ambas)
      if (pregunta.length > 0 || respuesta.length > 0) {
        foro.push({
          description: pregunta.length > 0 ? pregunta : '(sin pregunta registrada)',
          answer: respuesta,
          date: row[idxFecha] ? row[idxFecha].toString().trim() : null,
          dateAnswered: respuesta.length > 0 ? new Date().toISOString() : null,
          participant: '',
          number: null,
        });
        dataRowCount++;
      }
    }

    logger.info(`parseXLSForoMP: ✅ success - ${dataRowCount} preguntas parseadas`);

    if (foro.length === 0) {
      throw new Error('No se encontraron preguntas en el archivo');
    }

    return foro;
  } catch (e) {
    logger.error(`parseXLSForoMP error: ${e.message}`, { stack: e.stack });
    throw new Error(`Error parseando XLS: ${e.message}`);
  }
}

// --- CLOUD FUNCTION: Procesar archivo XLS de Foro y guardar con resumen IA ---
exports.procesarForoXLS = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 180,
  memory: '1GiB',
}, async (req, res) => {
  const uid = await _verifyToken(req, res);
  if (!uid) return;

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Solo POST permitido' });
  }

  const { proyectoId, licitacionId, generarResumen = true } = req.query;
  if (!proyectoId || !licitacionId) {
    return res.status(400).json({ error: 'Faltan proyectoId o licitacionId' });
  }

  try {
    // 1. Obtener el archivo (espera body como buffer o base64)
    let buffer;
    if (typeof req.body === 'string') {
      buffer = Buffer.from(req.body, 'base64');
    } else if (Buffer.isBuffer(req.body)) {
      buffer = req.body;
    } else {
      return res.status(400).json({ error: 'Body debe ser buffer o base64' });
    }

    if (buffer.length === 0) {
      return res.status(400).json({ error: 'Archivo vacío' });
    }

    // 2. Parsear XLS
    logger.info(`procesarForoXLS: parseando archivo para ${licitacionId}`);
    const enquiries = parseXLSForoMP(buffer);

    if (!enquiries || enquiries.length === 0) {
      return res.status(400).json({ error: 'No se encontraron preguntas en el archivo' });
    }

    logger.info(`procesarForoXLS: ${enquiries.length} preguntas parseadas`);

    const db = admin.firestore();
    const foroRef = db.collection('proyectos').doc(proyectoId).collection('foro').doc(licitacionId);

    // 3. Guardar foro
    await foroRef.set({
      enquiries,
      fetchedMethod: 'xls_upload',
      uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
      fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // 4. Generar resumen con Gemini (si se solicita)
    let resumen = null;
    if (generarResumen === 'true' || generarResumen === true) {
      try {
        const proyectoSnap = await db.collection('proyectos').doc(proyectoId).get();
        const proyectoData = proyectoSnap.exists ? proyectoSnap.data() : {};
        const nombreLicitacion = proyectoData.nombre ?? licitacionId;
        const descripcionLicitacion = proyectoData.descripcion ?? '';

        // Construir prompt
        const foroTexto = enquiries.map((e, i) => {
          const p = e.description ?? '(sin texto)';
          const r = e.answer ?? '(sin respuesta)';
          return `[${i + 1}] Pregunta: ${p}\nRespuesta: ${r}`;
        }).join('\n\n');

        const prompt = `Eres un asistente experto en licitaciones públicas chilenas (Mercado Público).

Analiza el siguiente foro de preguntas y respuestas importado desde un archivo XLS y genera un resumen ejecutivo conciso, estructurado en:
1. **Puntos clave** (máx. 5 bullets): los temas más relevantes o recurrentes del foro
2. **Aclaraciones importantes**: cambios de plazos, requisitos modificados, aclaraciones técnicas relevantes
3. **Alertas**: si hay respuestas contradictorias, condiciones restrictivas o aspectos que un proveedor debe tener muy en cuenta

Licitación: ${nombreLicitacion}
${descripcionLicitacion ? `Descripción: ${descripcionLicitacion}\n` : ''}Total de preguntas: ${enquiries.length}

FORO:
${foroTexto}

Responde en español, con formato markdown limpio. Sé conciso y enfocado en lo que es útil para un proveedor.`;

        // Llamar Gemini
        const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${GEMINI_API_KEY}`;
        const geminiResp = await axios.post(geminiUrl, {
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
        }, { timeout: 120000 });

        resumen = geminiResp.data?.candidates?.[0]?.content?.parts?.[0]?.text ?? null;

        if (resumen) {
          // Guardar resumen
          await foroRef.set({
            resumen,
            resumenGeneradoAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          logger.info(`procesarForoXLS: resumen generado para ${licitacionId}`);
        }
      } catch (geminiErr) {
        logger.warn(`procesarForoXLS: error al generar resumen: ${geminiErr.message}`);
        // No fallar si Gemini falla, el foro está guardado de todas formas
      }
    }

    // 5. También guardar en licitaciones_foro para acceso global (caché)
    await db.collection('licitaciones_foro').doc(licitacionId).set({
      enquiries,
      fetchedMethod: 'xls_upload',
      uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
      fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    logger.info(`procesarForoXLS: completado para ${licitacionId}, ${enquiries.length} preguntas`);

    return res.json({
      ok: true,
      licitacionId,
      totalPreguntas: enquiries.length,
      respondidas: enquiries.filter(e => e.answer?.trim()).length,
      sinResponder: enquiries.filter(e => !e.answer?.trim()).length,
      resumenGenerado: !!resumen,
      resumen: resumen ? resumen.substring(0, 500) + '...' : null,
    });

  } catch (e) {
    logger.error('procesarForoXLS error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// ── Reintentar licitaciones pendientes (OCDS aún no publicadas) ────────────────
// Corre a las 4 AM UTC (~1 AM Santiago). Para cada ID en `licitaciones_pendientes`,
// intenta obtener la institución desde OCDS. Si la encuentra, actualiza todos los
// proyectos que tengan ese idLicitacion y elimina el pendiente.
// Después de 30 intentos fallidos (~1 mes) descarta el pendiente automáticamente.
exports.resolverLicitacionesPendientes = onSchedule({
  schedule: '0 4 * * *',
  timeZone: 'America/Santiago',
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '256MiB',
}, async () => {
  const db = admin.firestore();
  const snap = await db.collection('licitaciones_pendientes').get();
  if (snap.empty) { logger.info('resolverLicitacionesPendientes: sin pendientes'); return; }

  logger.info(`resolverLicitacionesPendientes: procesando ${snap.size} pendientes`);

  for (const doc of snap.docs) {
    const { id, intentos = 0 } = doc.data();

    // Descartar tras 30 intentos (~1 mes de reintentos diarios)
    if (intentos >= 30) {
      logger.warn(`resolverLicitacionesPendientes: descartando ${id} tras ${intentos} intentos`);
      await doc.ref.delete();
      continue;
    }

    try {
      const url = `${BASE_URL}/tender/${id}`;
      const resp = await axios.get(url, { timeout: API_TIMEOUT });
      const data = resp.data;

      // Extraer institución (buyer) igual que en el cliente Flutter
      let institucion = '';
      const releases = data.releases ?? (Array.isArray(data) ? data : [data]);
      for (const release of releases) {
        const parties = release.parties ?? [];
        const buyer = parties.find(p => Array.isArray(p.roles) && p.roles.includes('buyer'));
        if (buyer?.name) {
          institucion = buyer.name.split('|')[0].trim();
          break;
        }
      }

      if (!institucion) {
        // Aún sin datos — actualizar contador y continuar
        await doc.ref.set({ intentos: admin.firestore.FieldValue.increment(1), ultimoIntento: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        continue;
      }

      // Actualizar todos los proyectos con este idLicitacion
      const proySnap = await db.collection('proyectos').where('idLicitacion', '==', id).get();
      const batch = db.batch();
      for (const p of proySnap.docs) {
        batch.update(p.ref, { institucion });
      }
      batch.delete(doc.ref);
      await batch.commit();

      logger.info(`resolverLicitacionesPendientes: resuelta ${id} → "${institucion}" (${proySnap.size} proyectos actualizados)`);

    } catch (err) {
      if (err.response?.status === 404) {
        // Sigue sin estar en OCDS — incrementar contador
        await doc.ref.set({ intentos: admin.firestore.FieldValue.increment(1), ultimoIntento: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      } else {
        logger.error(`resolverLicitacionesPendientes: error en ${id}:`, err.message);
      }
    }
  }
});
