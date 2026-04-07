/**
 * sugerencias_encadenamiento.js
 *
 * Cloud Function programada (lunes 03:00 UTC) que analiza cada proyecto
 * y genera sugerencias de encadenamiento (predecesor/sucesor) buscando
 * DENTRO de la propia colección 'proyectos' — misma institución + producto similar.
 *
 * Subcollección destino: /proyectos/{pid}/sugerencias_cadena/{sid}
 */

const admin = require('firebase-admin');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');

// ── Constantes ────────────────────────────────────────────────────────────────

const SCORE_MINIMO = 0.5;     // Score mínimo para guardar sugerencia
const MAX_SUGERENCIAS = 5;    // Máximo de sugerencias pendientes por proyecto
const VENTANA_DIAS = 365;     // ±365 días como ventana de proximidad temporal
const LOTE_SIZE = 10;         // Proyectos por lote
const DELAY_MS = 200;         // Delay entre lotes (ms)

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Convierte Timestamp de Firestore, string ISO o número a Date. */
function toDate(raw) {
  if (!raw) return null;
  if (raw instanceof admin.firestore.Timestamp) return raw.toDate();
  if (raw._seconds !== undefined) return new Date(raw._seconds * 1000);
  if (typeof raw === 'string') { const d = new Date(raw); return isNaN(d) ? null : d; }
  if (typeof raw === 'number') return new Date(raw > 1e12 ? raw : raw * 1000);
  return null;
}

/** Retorna true si el proyecto tiene estado procesable. */
function estadoActivo(data) {
  const estado = (data.estadoManual || '').toLowerCase();
  return !['archivado', 'cancelado'].includes(estado);
}

/**
 * Calcula score de similitud entre dos proyectos.
 * Base 0.5 + misma modalidad (+0.2) + productos en común (+0.15 por producto, max +0.3).
 */
function calcularScore(proyData, candidatoData) {
  let score = 0.5;

  if (proyData.modalidadCompra && proyData.modalidadCompra === candidatoData.modalidadCompra) {
    score += 0.2;
  }

  const proyProd = new Set(
    (proyData.productos || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean)
  );
  const candProd = new Set(
    (candidatoData.productos || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean)
  );
  const overlap = [...proyProd].filter(p => candProd.has(p)).length;
  if (overlap > 0) score += Math.min(overlap * 0.15, 0.3);

  return Math.min(score, 1.0);
}

/**
 * Clasifica un proyecto candidato como predecesor o sucesor respecto al proyecto base.
 * Predecesor: candidato terminó antes de que inicie el proyecto base.
 * Sucesor:    candidato inicia después de que termine el proyecto base.
 */
function clasificarRelacion(proyData, candidatoData) {
  const proyInicio  = toDate(proyData.fechaInicio);
  const proyTermino = toDate(proyData.fechaTermino) || toDate(proyData.fechaTerminoRuta);
  const candTermino = toDate(candidatoData.fechaTermino) || toDate(candidatoData.fechaTerminoRuta);
  const candInicio  = toDate(candidatoData.fechaInicio);

  const ventana = VENTANA_DIAS * 24 * 60 * 60 * 1000;

  if (proyInicio && candTermino) {
    const diff = proyInicio.getTime() - candTermino.getTime();
    if (diff > 0 && diff < ventana) return 'predecesor';
  }

  if (proyTermino && candInicio) {
    const diff = candInicio.getTime() - proyTermino.getTime();
    if (diff > 0 && diff < ventana) return 'sucesor';
  }

  // Sin fechas en el proyecto base → sucesor potencial
  if (!proyInicio && !proyTermino) return 'sucesor';

  return null;
}

/**
 * Obtiene todos los IDs de proyectos en la cadena del proyecto dado
 * (directos + transitivos) para no sugerir proyectos ya encadenados.
 */
async function getCadenaIds(db, proyData, proyId, todosMap) {
  const visitados = new Set([proyId]);
  const cola = [...(proyData.proyectoContinuacionIds || [])];

  while (cola.length) {
    const id = cola.pop();
    if (visitados.has(id)) continue;
    visitados.add(id);
    const data = todosMap.get(id);
    if (data) {
      (data.proyectoContinuacionIds || []).forEach(i => {
        if (!visitados.has(i)) cola.push(i);
      });
    }
  }

  // También proyectos que apuntan a este
  for (const [id, data] of todosMap) {
    if ((data.proyectoContinuacionIds || []).includes(proyId)) {
      visitados.add(id);
    }
  }

  return visitados;
}

/** Delay helper */
const delay = ms => new Promise(r => setTimeout(r, ms));

// ── Lógica compartida ─────────────────────────────────────────────────────────

async function _ejecutarSugerencias(proyectoIdFiltro) {
  const db = admin.firestore();

  // Cargar TODOS los proyectos (incluidos completados — son candidatos a predecesor)
  const todosSnap = await db.collection('proyectos').get();

  // Map id → data para lookups rápidos
  const todosMap = new Map(todosSnap.docs.map(d => [d.id, d.data()]));

  // Solo PROCESAR proyectos activos (no completados)
  let proyectos = todosSnap.docs.filter(d => d.data().completado !== true);
  if (proyectoIdFiltro) {
    proyectos = proyectos.filter(d => d.id === proyectoIdFiltro);
  }

  logger.info(`sugerencias: procesando ${proyectos.length} proyectos`);

  for (let i = 0; i < proyectos.length; i += LOTE_SIZE) {
    const lote = proyectos.slice(i, i + LOTE_SIZE);
    await Promise.all(lote.map(doc => procesarProyecto(db, doc, todosMap)));
    if (i + LOTE_SIZE < proyectos.length) await delay(DELAY_MS);
  }

  logger.info('sugerencias: proceso completo');
  return proyectos.length;
}

// ── Cloud Function programada ─────────────────────────────────────────────────

exports.generarSugerenciasEncadenamiento = onSchedule({
  schedule: 'every monday 03:00',
  timeZone: 'UTC',
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
}, async () => {
  await _ejecutarSugerencias(null);
});

// ── Trigger manual HTTP ───────────────────────────────────────────────────────

exports.triggerSugerenciasEncadenamiento = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
  secrets: ['TRIGGER_SECRET_KEY'],
}, async (req, res) => {
  const secretKey = process.env.TRIGGER_SECRET_KEY;
  const providedKey = req.query.key || req.headers['x-trigger-key'];

  if (secretKey && providedKey === secretKey) {
    // OK
  } else {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'No autorizado.' });
    try { await admin.auth().verifyIdToken(token); }
    catch (e) { return res.status(401).json({ error: 'Token inválido' }); }
  }

  const proyectoId = req.query.proyectoId || null;
  try {
    const total = await _ejecutarSugerencias(proyectoId);
    res.status(200).json({
      ok: true,
      procesados: total,
      mensaje: proyectoId
        ? `Sugerencias generadas para proyecto ${proyectoId}`
        : `Sugerencias generadas para ${total} proyectos`,
    });
  } catch (e) {
    logger.error('triggerSugerencias: error', e.message);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ── Reconciliación de flags ───────────────────────────────────────────────────

exports.reconciliarFlagsSugerencias = onRequest({
  cors: true,
  region: 'us-central1',
  timeoutSeconds: 120,
  memory: '256MiB',
  secrets: ['TRIGGER_SECRET_KEY'],
}, async (req, res) => {
  const secretKey = process.env.TRIGGER_SECRET_KEY;
  const providedKey = req.query.key || req.headers['x-trigger-key'];
  if (!secretKey || providedKey !== secretKey) return res.status(401).json({ error: 'No autorizado' });

  const db = admin.firestore();

  const todasSnap = await db.collectionGroup('sugerencias_cadena').get();
  const conPendientes = new Set();
  for (const doc of todasSnap.docs) {
    if (doc.data().estado === 'pendiente') {
      conPendientes.add(doc.ref.parent.parent.id);
    }
  }

  const proyectosSnap = await db.collection('proyectos').get();
  const BATCH_LIMIT = 400;
  let batch = db.batch();
  let ops = 0;
  let corregidos = 0;

  for (const doc of proyectosSnap.docs) {
    const deberia = conPendientes.has(doc.id);
    const actual = doc.data().hasSugerenciasPendientes === true;
    if (deberia !== actual) {
      batch.update(doc.ref, { hasSugerenciasPendientes: deberia });
      ops++; corregidos++;
      if (ops >= BATCH_LIMIT) { await batch.commit(); batch = db.batch(); ops = 0; }
    }
  }
  if (ops > 0) await batch.commit();

  res.status(200).json({
    ok: true,
    proyectosConSugerencias: conPendientes.size,
    flagsCorregidos: corregidos,
    ids: [...conPendientes],
  });
});

// ── Trigger automático: nuevo proyecto ───────────────────────────────────────

exports.onNuevoProyecto = onDocumentCreated({
  document: 'proyectos/{proyectoId}',
  region: 'us-central1',
  timeoutSeconds: 120,
  memory: '256MiB',
}, async (event) => {
  const snap = event.data;
  if (!snap) return;

  const db = admin.firestore();

  // Cargar todos los proyectos para comparación de candidatos
  const todosSnap = await db.collection('proyectos').get();
  const todosMap = new Map(todosSnap.docs.map(d => [d.id, d.data()]));

  await procesarProyecto(db, snap, todosMap);
  logger.info(`sugerencias: procesado nuevo proyecto ${snap.id}`);
});

// ── Lógica por proyecto ───────────────────────────────────────────────────────

async function procesarProyecto(db, doc, todosMap) {
  const proyId = doc.id;
  const proyData = doc.data();

  if (!estadoActivo(proyData)) return;

  // Solo procesar proyectos con institución definida
  if (!proyData.institucion || !proyData.institucion.trim()) return;

  try {
    const subCol = db.collection('proyectos').doc(proyId).collection('sugerencias_cadena');

    // Verificar sugerencias pendientes existentes
    const pendientesSnap = await subCol.where('estado', '==', 'pendiente').get();
    if (pendientesSnap.size >= MAX_SUGERENCIAS) {
      await db.collection('proyectos').doc(proyId).update({ hasSugerenciasPendientes: true });
      return;
    }

    // IDs ya rechazados
    const rechazadasSnap = await subCol.where('estado', '==', 'rechazada').get();
    const rechazadas = new Set(rechazadasSnap.docs.map(d => d.data().idProyectoRelacionado).filter(Boolean));

    // IDs ya en la cadena
    const cadenaIds = await getCadenaIds(db, proyData, proyId, todosMap);

    // Candidatos: otros proyectos de la misma institución
    const candidatos = [];
    for (const [candidatoId, candidatoData] of todosMap) {
      if (candidatoId === proyId) continue;
      if (cadenaIds.has(candidatoId)) continue;
      if (rechazadas.has(candidatoId)) continue;
      if (candidatoData.institucion !== proyData.institucion) continue;

      const score = calcularScore(proyData, candidatoData);
      if (score < SCORE_MINIMO) continue;

      const tipo = clasificarRelacion(proyData, candidatoData);
      if (!tipo) continue;

      candidatos.push({ id: candidatoId, data: candidatoData, score, tipo });
    }

    if (!candidatos.length) return;

    // Ordenar por score descendente
    candidatos.sort((a, b) => b.score - a.score);

    // Verificar cuáles ya existen como sugerencia (pendiente o aceptada)
    let guardadas = pendientesSnap.size;
    const batch = db.batch();
    let hayEscrituras = false;

    for (const c of candidatos) {
      if (guardadas >= MAX_SUGERENCIAS) break;

      const existeSnap = await subCol
        .where('idProyectoRelacionado', '==', c.id)
        .where('estado', 'in', ['pendiente', 'aceptada'])
        .limit(1)
        .get();
      if (!existeSnap.empty) continue;

      const sugerenciaRef = subCol.doc();
      batch.set(sugerenciaRef, {
        tipo: c.tipo,
        idLicitacion: c.data.idLicitacion || null,
        titulo: c.data.productos || c.data.institucion || 'Sin título',
        institucion: c.data.institucion || '',
        fechaPublicacion: c.data.fechaInicio
          ? admin.firestore.Timestamp.fromDate(toDate(c.data.fechaInicio))
          : null,
        fechaCierre: c.data.fechaTermino
          ? admin.firestore.Timestamp.fromDate(toDate(c.data.fechaTermino))
          : null,
        monto: c.data.valorMensual ?? null,
        idProyectoRelacionado: c.id,
        score: c.score,
        estado: 'pendiente',
        fechaSugerencia: admin.firestore.FieldValue.serverTimestamp(),
      });

      guardadas++;
      hayEscrituras = true;
    }

    if (hayEscrituras) {
      await batch.commit();
      await db.collection('proyectos').doc(proyId).update({ hasSugerenciasPendientes: true });
      logger.info(`sugerencias: ${guardadas - pendientesSnap.size} nuevas para ${proyId}`);
    }

  } catch (e) {
    logger.error(`sugerencias: error en proyecto ${proyId}:`, e.message);
  }
}
