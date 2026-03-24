const admin = require("firebase-admin");
const axios = require("axios");
const cheerio = require("cheerio");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

// --- IMPORTACIÓN PARA VERTEX AI (lazy init para evitar fallos de módulo en cold start) ---
const { SearchServiceClient, DocumentServiceClient } = require('@google-cloud/discoveryengine');
const { BigQuery } = require('@google-cloud/bigquery');
const bigquery = new BigQuery({ projectId: 'licitaciones-prod' });
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

// Indexa un lote de documentos en Discovery Engine
async function indexarEnDiscoveryEngine(documentos) {
  if (!documentos.length) return;
  try {
    const [operation] = await getDocClient().importDocuments({
      parent: DE_PARENT,
      inlineSource: {
        documents: documentos.map(({ id, data }) => ({
          id,
          // _firestoreId embebido para recuperarlo desde structData en búsqueda
          jsonData: JSON.stringify({ ...data, _firestoreId: id }),
        })),
      },
      reconciliationMode: 'INCREMENTAL',
    });
    logger.info(`DE import iniciado: ${documentos.length} docs`, operation.name);
  } catch (e) {
    logger.error('Error indexando en Discovery Engine:', e.message);
  }
}

// Inicializar Firebase
admin.initializeApp();

// Constantes
const BATCH_SIZE = 1000;
const BATCH_SIZE_DETAILS = 200;
const API_TIMEOUT = 10000;
const CONCURRENT_LIMIT = 15;
const BASE_URL = "https://api.mercadopublico.cl/APISOCDS/OCDS";

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
  while (hasMore) {
    const url = `${BASE_URL}/listaOCDSAgnoMes/${year}/${month}/${offset}/${BATCH_SIZE}`;
    const response = await axios.get(url, { timeout: API_TIMEOUT }).catch(() => null);
    const data = response?.data?.data || [];
    
    if (data.length === 0) break;

    const bulkWriter = db.bulkWriter();
    const collectionRef = db.collection("licitaciones_activas");

    for (const licitacion of data) {
      const codigoExterno = extractCodigoExterno(licitacion.ocid);
      if (!codigoExterno) continue;

      const docRef = collectionRef.doc(codigoExterno);
      bulkWriter.set(docRef, {
        ocid: licitacion.ocid || null,
        procesado: false,
        error: false,
        fechaIngreso: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await bulkWriter.close();
    hasMore = data.length === BATCH_SIZE;
    offset += BATCH_SIZE;
  }
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
  
  for (const { year, month } of months) {
    await processMonth(db, year, month);
  }
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

    for (const result of results) {
      if (result.status !== 'fulfilled' || !result.value.success) continue;
      const { codigoExterno, status, data } = result.value;
      const activaRef = db.collection("licitaciones_activas").doc(codigoExterno);

      if (status === 404) {
        bulkWriter.update(activaRef, { procesado: true, error: true });
        continue;
      }

      try {
        const release = data.releases[0];
        const releaseData = convertDatesToTimestamps(release);

        const descripcionesItems = (releaseData.tender?.items || [])
          .map(item => item?.description).filter(Boolean).join(" ");

        const textoBusqueda = `
          ${releaseData.tender?.title || ''}
          ${releaseData.tender?.description || ''}
          ${descripcionesItems}
        `.replace(/\s+/g, ' ').trim();

        const ocdsRef = db.collection("licitaciones_ocds").doc(codigoExterno);

        bulkWriter.set(ocdsRef, {
            ...releaseData,
            texto_busqueda: textoBusqueda,
            fechaProceso: serverTimestamp
        }, { merge: true });

        bulkWriter.update(activaRef, { procesado: true, error: false });

        // Acumular para indexar en Discovery Engine
        docsParaIndexar.push({ id: codigoExterno, data: { ...release, texto_busqueda: textoBusqueda } });

      } catch (e) {
        bulkWriter.update(activaRef, { procesado: true, error: true });
      }
    }
  }
  await bulkWriter.close();

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
        'de','la','el','en','y','a','que','por','con','del','al','los','las',
        'un','una','para','es','se','no','como','más','este','esta','pero','sus',
        'le','ya','o','fue','ha','me','si','sin','sobre','entre','cuando','muy',
        'hasta','todo','ser','hay','su','les','lo','también','ni','e','u','ante',
        'bajo','tras','según','durante','mediante','cada','otras','otros','dicho',
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
          pageSize: 15,
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

      // 3. Tokens léxicos de la query (sin acentos, sin stopwords)
      const tokens = tokenizarQuery(query);

      // 4. Formatear y filtrar por relevancia léxica
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
              return `${String(d.getDate()).padStart(2,'0')}-${String(d.getMonth()+1).padStart(2,'0')}-${d.getFullYear()}`;
          } catch(e) { return "S/F"; }
      };

      const resultados = snapshots
          .filter(snap => {
              if (!snap.exists) return false;
              if (!tokens.length) return true;
              // Filtro léxico: al menos un token debe aparecer en el texto del doc
              const data = snap.data();
              let tender = data.tender;
              if (Array.isArray(tender)) tender = tender[0];
              const texto = [tender?.title, tender?.description, data.texto_busqueda]
                  .filter(Boolean).join(' ')
                  .toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
              return tokens.some(t => texto.includes(t));
          })
          .map(snap => {
              const data = snap.data();
              const id   = snap.id;

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
                  titulo:           tender?.title?.trim() || "Sin título",
                  descripcion:      tender?.description   || "Sin descripción",
                  fechaPublicacion: formatDate(tender?.tenderPeriod?.startDate || data.date),
                  fechaCierre:      formatDate(tender?.tenderPeriod?.endDate || tender?.awardPeriod?.startDate),
                  monto:            tender?.value?.amount
                      ? new Intl.NumberFormat('es-CL').format(tender.value.amount) : 'S/M',
                  comprador,
                  rawData: data,
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
    // Hace 7 días (para métrica "recientes")
    const hace7diasUTC = new Date(Date.UTC(ahora.getUTCFullYear(), ahora.getUTCMonth(), ahora.getUTCDate() - 7) + offsetMs);

    // Usar el campo 'date' del release OCDS (fecha real de publicación en Mercado Público)
    const [totalSnap, recientesSnap, mesSnap, statsDoc] = await Promise.all([
      db.collection('licitaciones_ocds').count().get(),
      db.collection('licitaciones_ocds')
        .where('date', '>=', admin.firestore.Timestamp.fromDate(hace7diasUTC))
        .count().get(),
      db.collection('licitaciones_ocds')
        .where('date', '>=', admin.firestore.Timestamp.fromDate(inicioMesUTC))
        .count().get(),
      db.collection('_stats').doc('resumen').get(),
    ]);

    const cache = statsDoc.exists ? statsDoc.data() : null;
    const ultimaActualizacion = new Date().toLocaleDateString('es-CL', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });

    res.status(200).json({
      total: totalSnap.data().count,
      recientes: recientesSnap.data().count,
      esteMes: mesSnap.data().count,
      ti: cache?.ti || 0,
      categorias: cache?.categorias || [],
      ultimaActualizacion,
    });
  } catch (error) {
    logger.error("Error en obtenerResumen:", error);
    res.status(500).send("Error obteniendo estadísticas");
  }
});

// --- Lógica compartida: calcula categorías/TI del mes actual y guarda en caché ---
async function _ejecutarCalculoEstadisticas(db) {
  const ahora = new Date();
  const offsetMs = 3 * 60 * 60 * 1000; // Chile UTC-3
  const inicioMesUTC = new Date(Date.UTC(ahora.getUTCFullYear(), ahora.getUTCMonth(), 1) + offsetMs);
  const inicioSigMesUTC = new Date(Date.UTC(ahora.getUTCFullYear(), ahora.getUTCMonth() + 1, 1) + offsetMs);

  const categoriaCounts = {};
  let tiCount = 0;
  let cursor = null;
  let totalProcesados = 0;

  while (true) {
    let q = db.collection('licitaciones_ocds')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(inicioMesUTC))
      .where('date', '<', admin.firestore.Timestamp.fromDate(inicioSigMesUTC))
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
    .sort((a, b) => b.cantidad - a.cantidad)
    .slice(0, 12);

  await db.collection('_stats').doc('resumen').set({
    ti: tiCount,
    categorias,
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
  const prefix = req.query.prefix;
  const limite = Math.min(parseInt(req.query.limit) || 20, 50);
  const cursorId = req.query.cursor;

  if (!prefix) return res.status(400).send("Falta el parámetro 'prefix'");

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
      return `${String(d.getDate()).padStart(2,'0')}-${String(d.getMonth()+1).padStart(2,'0')}-${d.getFullYear()}`;
    } catch(e) { return "S/F"; }
  };

  try {
    let q = db.collection('licitaciones_ocds')
      .where('_unspsc_prefixes', 'array-contains', prefix)
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
        titulo:           tender?.title?.trim() || "Sin título",
        descripcion:      tender?.description   || "Sin descripción",
        fechaPublicacion: formatDate(tender?.tenderPeriod?.startDate || data.date),
        fechaCierre:      formatDate(tender?.tenderPeriod?.endDate || tender?.awardPeriod?.startDate),
        monto:            tender?.value?.amount
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

  try {
    const type = req.query.type === 'award' ? 'award' : 'tender';
    const url = `${BASE_URL}/${type}/${id}`;
    const response = await axios.get(url, { timeout: API_TIMEOUT });
    res.status(200).json(response.data);
  } catch (error) {
    if (error.response) {
      logger.error(`Error buscando licitación ${id}: status ${error.response.status}`);
      res.status(error.response.status).json({ error: `Error ${error.response.status} al consultar la API` });
    } else {
      logger.error(`Error buscando licitación ${id}:`, error.message);
      res.status(500).json({ error: "Error interno al consultar la licitación" });
    }
  }
});

// --- CLOUD FUNCTION 10: Buscar Orden de Compra por ID ---
const OC_TICKET = 'EE36DCF4-F727-4EED-9026-20EF36A6DD54';
const OC_BASE_URL = 'https://api.mercadopublico.cl/servicios/v1/publico/ordenesdecompra.json';

exports.buscarOrdenCompra = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 30,
  memory: '256MiB',
}, async (req, res) => {
  const id = req.query.id;
  if (!id) return res.status(400).json({ error: "Falta el parámetro 'id'" });

  try {
    const url = `${OC_BASE_URL}?codigo=${encodeURIComponent(id)}&ticket=${OC_TICKET}`;
    const response = await axios.get(url, { timeout: 20000 });
    const data = response.data;

    // La API devuelve { Listado: [...], Cantidad: N }
    const listado = data?.Listado ?? [];
    if (!listado.length) {
      return res.status(404).json({ error: 'No se encontró la orden de compra' });
    }
    return res.json(listado[0]); // Devolver el primer (único) resultado
  } catch (error) {
    if (error.response) {
      logger.error(`Error buscando OC ${id}: status ${error.response.status}`);
      return res.status(error.response.status).json({ error: `Error ${error.response.status}` });
    }
    logger.error(`Error buscando OC ${id}:`, error.message);
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

    return res.json(data);
  } catch (error) {
    if (error.response) {
      logger.error(`Error obteniendo CM ${url}: status ${error.response.status}`);
      return res.json({ id, url, titulo: '', comprador: '', convenioMarco: '', estado: '', campos: [], fetchError: `Error ${error.response.status}` });
    }
    logger.error(`Error obteniendo CM ${url}:`, error.message);
    return res.json({ id, url, titulo: '', comprador: '', convenioMarco: '', estado: '', campos: [], fetchError: error.message });
  }
});

// PROYECTOS CRUD

exports.obtenerProyectos = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  try {
    const snapshot = await admin.firestore()
      .collection('proyectos')
      .orderBy('fechaCreacion', 'desc')
      .get();
    const toIso = (v) => v?.toDate?.()?.toISOString() ?? null;
    const proyectos = snapshot.docs.map(doc => {
      const d = doc.data();
      return {
        id: doc.id,
        ...d,
        fechaCreacion:    toIso(d.fechaCreacion),
        fechaInicio:      toIso(d.fechaInicio),
        fechaTermino:     toIso(d.fechaTermino),
        fechaInicioRuta:  toIso(d.fechaInicioRuta),
        fechaTerminoRuta: toIso(d.fechaTerminoRuta),
        fechaPublicacion:     toIso(d.fechaPublicacion),
        fechaCierre:          toIso(d.fechaCierre),
        fechaConsultasInicio: toIso(d.fechaConsultasInicio),
        fechaConsultas:       toIso(d.fechaConsultas),
        fechaAdjudicacion:    toIso(d.fechaAdjudicacion),
        fechaAdjudicacionFin: toIso(d.fechaAdjudicacionFin),
      };
    });
    return res.json(proyectos);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.crearProyecto = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
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
  try {
    const { id, institucion, productos, modalidadCompra, valorMensual, fechaInicio, fechaTermino, idLicitacion, documentoUrl, notas, completado, _campoEditado, _valorAnterior, _valorNuevo } = req.body;
    if (!id) return res.status(400).json({ error: 'Missing id' });
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

    await batch.commit();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.obtenerHistorialProyecto = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  const id = req.query.id;
  if (!id) return res.status(400).json({ error: 'Missing id' });
  try {
    const snap = await admin.firestore()
      .collection('proyectos').doc(id).collection('historial')
      .orderBy('fecha', 'desc').limit(50).get();
    const items = snap.docs.map(d => ({
      id: d.id,
      ...d.data(),
      fecha: d.data().fecha?.toDate?.()?.toISOString() ?? null,
    }));
    return res.json(items);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.eliminarProyecto = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { id } = req.body;
    if (!id) return res.status(400).json({ error: 'Missing id' });
    await admin.firestore().collection('proyectos').doc(id).delete();
    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.obtenerConfiguracion = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  try {
    const doc = await admin.firestore().collection('configuracion').doc('opciones').get();
    if (!doc.exists) {
      return res.json({
        estados: ['Vigente', 'X Vencer', 'Finalizado', 'Sin fecha'],
        modalidades: ['Licitación Pública', 'Convenio Marco', 'Trato Directo', 'Otro'],
        productos: [],
      });
    }
    return res.json(doc.data());
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

exports.guardarConfiguracion = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { estados, modalidades, productos } = req.body; // tiposDocumento ya no se recibe aquí
    await admin.firestore().collection('configuracion').doc('opciones').set({
      estados: estados ?? [],
      modalidades: modalidades ?? [],
      productos: productos ?? [],
    }, { merge: true }); // Usar merge: true para no sobrescribir la subcolección de documentos
    return res.json({ ok: true });
  } catch (e) {
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

// 2. Agregar un nuevo texto a la lista (arrayUnion)
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

exports.obtenerCacheExterno = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
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

exports.guardarCacheExterno = onRequest({ cors: true, region: 'us-central1' }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
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
