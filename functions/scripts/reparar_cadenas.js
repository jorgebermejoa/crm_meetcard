/**
 * reparar_cadenas.js
 * ─────────────────────────────────────────────────────────────────────────────
 * Detecta y corrige automáticamente las anomalías en cadenas de proyectos:
 *
 *   CIRCULAR       → Elimina el link en el proyecto más reciente que apunta
 *                    hacia atrás. El predecesor ya apunta correctamente al sucesor.
 *
 *   REFERENCIA_ROTA → Elimina el ID inexistente de proyectoContinuacionIds.
 *
 *   MULTIPLES_HEADS → En el proyecto más antiguo sin predecesor, agrega el link
 *                     hacia el siguiente más reciente del mismo grupo.
 *
 * USO (desde la carpeta functions/):
 *   # Solo diagnóstico (sin escribir):
 *   GOOGLE_APPLICATION_CREDENTIALS="C:/Users/jorge/AppData/Local/google-vscode-extension/auth/application_default_credentials.json" node scripts/reparar_cadenas.js --dry-run
 *
 *   # Aplicar correcciones:
 *   GOOGLE_APPLICATION_CREDENTIALS="C:/Users/jorge/AppData/Local/google-vscode-extension/auth/application_default_credentials.json" node scripts/reparar_cadenas.js
 */

const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');

// ── Init ──────────────────────────────────────────────────────────────────────
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'licitaciones-prod',
  });
}
const db = admin.firestore();

// ── Helpers ───────────────────────────────────────────────────────────────────
function dateOf(p) {
  const d = p.fechaInicio || p.fechaCreacion;
  return d ? (d.toDate ? d.toDate() : new Date(d)) : new Date(0);
}

function resolveChain(startId, proyectoMap) {
  const visited = new Set();
  const queue = [startId];
  while (queue.length) {
    const id = queue.shift();
    if (visited.has(id)) continue;
    visited.add(id);
    const p = proyectoMap.get(id);
    if (!p) continue;
    for (const sid of (p.proyectoContinuacionIds || [])) {
      if (!visited.has(sid)) queue.push(sid);
    }
    for (const [pid, proj] of proyectoMap) {
      if (!visited.has(pid) && (proj.proyectoContinuacionIds || []).includes(id)) {
        queue.push(pid);
      }
    }
  }
  return visited;
}

// ── Colectar correcciones ─────────────────────────────────────────────────────
// Acumula cambios por docId: { remove: Set, add: Set }
function buildFixes(proyectoMap) {
  const fixes = new Map(); // docId → { remove: Set<string>, add: Set<string> }
  const ensure = (id) => {
    if (!fixes.has(id)) fixes.set(id, { remove: new Set(), add: new Set() });
    return fixes.get(id);
  };

  const circularReported = new Set(); // para no duplicar pares

  // ── 1. Referencias rotas ──────────────────────────────────────────────────
  for (const [id, p] of proyectoMap) {
    for (const sid of (p.proyectoContinuacionIds || [])) {
      if (!proyectoMap.has(sid)) {
        console.log(`[REFERENCIA_ROTA] ${id} → "${sid}" no existe → eliminar`);
        ensure(id).remove.add(sid);
      }
    }
  }

  // ── 2. Referencias circulares ─────────────────────────────────────────────
  for (const [id, p] of proyectoMap) {
    for (const sid of (p.proyectoContinuacionIds || [])) {
      const target = proyectoMap.get(sid);
      if (!target) continue;
      if (!(target.proyectoContinuacionIds || []).includes(id)) continue;

      const key = [id, sid].sort().join('↔');
      if (circularReported.has(key)) continue;
      circularReported.add(key);

      // El más reciente NO debe apuntar al más antiguo
      const pDate = dateOf(p);
      const tDate = dateOf(target);
      const newer = pDate >= tDate ? id  : sid;
      const older = pDate >= tDate ? sid : id;

      console.log(`[CIRCULAR] ${newer} (más reciente) apunta hacia atrás a ${older} → eliminar link en ${newer}`);
      ensure(newer).remove.add(older);
      // El más antiguo ya apunta correctamente al más reciente — no tocar
    }
  }

  // ── 3. Múltiples heads en una cadena ──────────────────────────────────────
  const processed = new Set();
  for (const [id] of proyectoMap) {
    if (processed.has(id)) continue;
    const chainIds = resolveChain(id, proyectoMap);
    chainIds.forEach(cid => processed.add(cid));

    const chainArr = [...chainIds].map(cid => proyectoMap.get(cid)).filter(Boolean);
    const heads = chainArr.filter(p =>
      !chainArr.some(other => (other.proyectoContinuacionIds || []).includes(p.id))
    );

    if (heads.length <= 1) continue;

    // Ordenar de más antiguo a más reciente
    heads.sort((a, b) => dateOf(a) - dateOf(b));

    // Por cada par de heads consecutivos sin link: el más antiguo debe apuntar al siguiente
    for (let i = 0; i < heads.length - 1; i++) {
      const older  = heads[i];
      const newer  = heads[i + 1];
      const olderIds = older.proyectoContinuacionIds || [];

      if (!olderIds.includes(newer.id)) {
        console.log(`[MULTIPLES_HEADS] ${older.id} no apunta a ${newer.id} → agregar link`);
        ensure(older.id).add.add(newer.id);
      }
    }
  }

  return fixes;
}

// ── Aplicar correcciones en Firestore (por lotes de 500) ──────────────────────
async function applyFixes(fixes, proyectoMap) {
  if (fixes.size === 0) {
    console.log('\n✅  Sin correcciones que aplicar.');
    return;
  }

  const entries = [...fixes.entries()];
  const BATCH_SIZE = 400;

  for (let i = 0; i < entries.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const slice = entries.slice(i, i + BATCH_SIZE);

    for (const [docId, { remove, add }] of slice) {
      const p = proyectoMap.get(docId);
      if (!p) continue;

      const current = new Set(p.proyectoContinuacionIds || []);
      remove.forEach(id => current.delete(id));
      add.forEach(id => current.add(id));

      const newIds = [...current];
      console.log(`  ${DRY_RUN ? '[DRY-RUN] ' : ''}Actualizando ${docId}: proyectoContinuacionIds = [${newIds.join(', ')}]`);

      if (!DRY_RUN) {
        batch.update(db.collection('proyectos').doc(docId), {
          proyectoContinuacionIds: newIds,
        });
      }
    }

    if (!DRY_RUN) {
      await batch.commit();
      console.log(`  Lote ${Math.floor(i / BATCH_SIZE) + 1} committed (${slice.length} docs).`);
    }
  }

  if (DRY_RUN) {
    console.log('\n[DRY-RUN] No se escribió nada. Ejecuta sin --dry-run para aplicar.');
  } else {
    console.log('\n✅  Reparación completada.');
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`Modo: ${DRY_RUN ? 'DRY-RUN (solo lectura)' : 'ESCRITURA'}\n`);
  console.log('Cargando proyectos desde Firestore…');

  const snap = await db.collection('proyectos').get();
  const proyectoMap = new Map();
  snap.docs.forEach(doc => proyectoMap.set(doc.id, { id: doc.id, ...doc.data() }));
  console.log(`Total proyectos: ${proyectoMap.size}\n`);

  const fixes = buildFixes(proyectoMap);

  console.log(`\nCorrecciones detectadas: ${fixes.size} documento(s) a modificar\n`);
  await applyFixes(fixes, proyectoMap);
}

main().catch(e => { console.error(e); process.exit(1); });
