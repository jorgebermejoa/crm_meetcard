const admin = require("firebase-admin");
const axios = require("axios");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

// --- IMPORTACIÓN PARA VERTEX AI ---
const { SearchServiceClient } = require('@google-cloud/discoveryengine');
const discoveryClient = new SearchServiceClient();

// Inicializar Firebase
admin.initializeApp();

// Constantes
const BATCH_SIZE = 1000; // Para la lista masiva
const BATCH_SIZE_DETAILS = 200; // Para los detalles iterativos
const API_TIMEOUT = 10000;
const CONCURRENT_LIMIT = 15;
const BASE_URL = "https://api.mercadopublico.cl/APISOCDS/OCDS";

// --- FUNCIONES AUXILIARES ---

function getTargetMonths() {
  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = String(now.getMonth() + 1).padStart(2, '0');

  const previousMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const previousYear = previousMonthDate.getFullYear();
  const previousMonth = String(previousMonthDate.getMonth() + 1).padStart(2, '0');
  
  return [
    { year: currentYear, month: currentMonth },
    { year: previousYear, month: previousMonth }
  ];
}

async function fetchOCDSPage(year, month, offset) {
  const url = `${BASE_URL}/listaOCDSAgnoMes/${year}/${month}/${offset}/${BATCH_SIZE}`;
  try {
    const response = await axios.get(url, { timeout: API_TIMEOUT });
    return {
      success: true,
      data: response.data.data || [],
      hasMore: response.data.data && response.data.data.length === BATCH_SIZE
    };
  } catch (error) {
    logger.error(`Error en ${url}:`, error.message);
    return { success: false, data: [], hasMore: false, error: error.message };
  }
}

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
    const result = await fetchOCDSPage(year, month, offset);
    if (!result.success || !result.data || result.data.length === 0) break;

    const bulkWriter = db.bulkWriter();
    const collectionRef = db.collection("licitaciones_activas");

    for (const licitacion of result.data) {
      const codigoExterno = extractCodigoExterno(licitacion.ocid);
      if (!codigoExterno) continue;

      const docRef = collectionRef.doc(codigoExterno);
      const docSnap = await docRef.get();
      
      if (!docSnap.exists) {
        bulkWriter.set(docRef, {
          ocid: licitacion.ocid || null,
          procesado: false,
          error: false,
          fechaIngreso: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
    await bulkWriter.close();
    hasMore = result.hasMore;
    if (hasMore) {
      offset += BATCH_SIZE;
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

// --- CLOUD FUNCTION 1: Buscar Códigos Masivos (Diario) ---
exports.obtenerLicitacionesOCDS = onSchedule({
  schedule: "0 2 * * *", // Todos los días a las 2 AM
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (event) => {
  const db = admin.firestore();
  const monthsToProcess = getTargetMonths(); // Trae el mes actual y el anterior
  
  for (const { year, month } of monthsToProcess) {
    await processMonth(db, year, month);
  }
  logger.info("Proceso masivo diario completado.");
});

// --- CLOUD FUNCTION 2: Procesar Detalle para Vertex AI (Iterativo) ---
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

  for (let i = 0; i < snapshot.docs.length; i += CONCURRENT_LIMIT) {
    const chunk = snapshot.docs.slice(i, i + CONCURRENT_LIMIT);
    
    const apiPromises = chunk.map(doc => {
      const codigoExterno = doc.id;
      return axios.get(`${BASE_URL}/tender/${codigoExterno}`, { validateStatus: s => s < 500 })
        .then(res => ({ codigoExterno, success: true, status: res.status, data: res.data }))
        .catch(err => ({ codigoExterno, success: false }));
    });
    
    const results = await Promise.allSettled(apiPromises);

    for (const result of results) {
      if (result.status !== 'fulfilled' || !result.value.success) continue;
      const { codigoExterno, status, data } = result.value;
      const activaRef = db.collection("licitaciones_activas").doc(codigoExterno);

      if (status === 404) {
         bulkWriter.update(activaRef, { procesado: true, error: true, mensajeError: "404" });
         continue;
      }

      try {
          const releaseData = convertDatesToTimestamps(data.releases[0]);
          const descripcionesItems = (releaseData.tender?.items || [])
              .map(item => item?.description).filter(Boolean).join(" "); 

          // El campo estrella para Vertex AI
          const textoBusqueda = `
            ${releaseData.tender?.title || ''} 
            ${releaseData.tender?.description || ''} 
            ${descripcionesItems}
          `.replace(/\s+/g, ' ').trim(); 

          const ocdsRef = db.collection("licitaciones_ocds").doc(codigoExterno);
          
          bulkWriter.set(ocdsRef, {
              ...releaseData, // Guarda todo el JSON aplanado
              texto_busqueda: textoBusqueda, 
              fechaProceso: serverTimestamp
          }, { merge: true }); 

          bulkWriter.update(activaRef, { procesado: true, error: false });
      } catch (e) {
          bulkWriter.update(activaRef, { procesado: true, error: true });
      }
    }
  }
  await bulkWriter.close();
});

// --- CLOUD FUNCTION 3: Ingesta Manual (Para cargar Enero 2026 después) ---
exports.obtenerLicitacionesOCDSManual = onRequest(
  { timeoutSeconds: 540, memory: "1GiB", region: "us-central1" },
  async (req, res) => {
    const { year, month } = req.query;
    if (!year || !month) return res.status(400).send("Falta year o month. Ej: ?year=2026&month=01");
    
    const db = admin.firestore();
    await processMonth(db, year, month);
    res.status(200).send(`Ingesta masiva iniciada para ${year}/${month}. El procesador de lotes hará el resto.`);
  }
);

// --- CLOUD FUNCTION 4: El Puente de Búsqueda ---
exports.buscarLicitacionesAI = onRequest({ 
  cors: true, 
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "512MiB"
}, async (req, res) => {
  const query = req.query.q; 
  if (!query) return res.status(400).send("Falta el parámetro 'q'");

  try {
      const servingConfig = discoveryClient.projectLocationCollectionDataStoreServingConfigPath(
          'licitaciones-prod', 
          'global', 
          'default_collection', 
          'datos-licitaciones_1772758314411', 
          'default_search'
      );

      const [response] = await discoveryClient.search({
          servingConfig: servingConfig,
          query: query,
          pageSize: 15, 
      });

      const resultados = response.map(result => {
          const rawData = result.document?.structData;
          if (!rawData) return null;
          
          const decode = (v) => {
              if (!v) return null;
              if (v.fields) {
                  const out = {};
                  for (const k in v.fields) out[k] = decode(v.fields[k]);
                  return out;
              }
              if (v.stringValue !== undefined) return v.stringValue;
              if (v.numberValue !== undefined) return v.numberValue;
              if (v.boolValue !== undefined) return v.boolValue;
              if (v.structValue) return decode(v.structValue);
              if (v.listValue) return (v.listValue.values || []).map(decode);
              return v;
          };

          const data = decode(rawData);

          let idCrudo = data.ocid || data.id || result.document.id || "S/I";
          let idLimpio = idCrudo.replace('ocds-70d2nz-', '');

          // Lógica de título mejorada
          let title = (data.tender?.title || data.title || '').trim();
          if (!title && data.texto_busqueda) {
              title = data.texto_busqueda.split('\n')[0].substring(0, 60).trim();
          }

          let fechaFormateada = "Sin fecha";
          let rawDate = data.tender?.tenderPeriod?.endDate || data.date;

          if (rawDate) {
              try {
                  let ms = typeof rawDate === 'string' ? parseInt(rawDate, 10) : rawDate;
                  if (ms > 1e14) ms = Math.floor(ms / 1000);
                  
                  const d = new Date(ms);
                  const dia = String(d.getDate()).padStart(2, '0');
                  const mes = String(d.getMonth() + 1).padStart(2, '0');
                  const anio = d.getFullYear();
                  fechaFormateada = `${dia}-${mes}-${anio}`;
              } catch(e) { fechaFormateada = "S/F"; }
          }

          return {
              id: idLimpio,
              titulo: title || "Licitación sin título",
              descripcion: data.tender?.description || data.description || "Sin descripción",
              fechaCierre: fechaFormateada,
              _debug_data: data // <-- AÑADIDO PARA DEPURACIÓN
          };
      }).filter(item => item !== null); 

      res.status(200).json(resultados);
  } catch (error) {
      logger.error("Error en Vertex AI:", error);
      res.status(500).send("Error interno de búsqueda");
  }
});
