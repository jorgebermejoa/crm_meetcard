/**
 * diagnostico_cadenas.js
 * ─────────────────────────────────────────────────────────────────────────────
 * Lee todos los proyectos de Firestore y detecta anomalías en las cadenas:
 *   1. Referencias circulares (A → B y B → A)
 *   2. Referencias rotas (A apunta a un ID que no existe en la colección)
 *   3. Cadenas duplicadas (dos proyectos distintos aparecen como heads del
 *      mismo grupo porque el link no está escrito consistentemente)
 *
 * USO (desde la carpeta functions/):
 *   GOOGLE_APPLICATION_CREDENTIALS="C:/Users/jorge/AppData/Local/google-vscode-extension/auth/application_default_credentials.json" node scripts/diagnostico_cadenas.js
 */

const admin = require('firebase-admin');

// ── Init ──────────────────────────────────────────────────────────────────────
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'licitaciones-prod',
  });
}
const db = admin.firestore();

// ── BFS bidireccional ─────────────────────────────────────────────────────────
function resolveChain(startId, proyectoMap) {
  const visited = new Set();
  const queue = [startId];
  while (queue.length) {
    const id = queue.shift();
    if (visited.has(id)) continue;
    visited.add(id);
    const p = proyectoMap.get(id);
    if (!p) continue;
    // Forward edges
    for (const sid of (p.proyectoContinuacionIds || [])) {
      if (!visited.has(sid)) queue.push(sid);
    }
    // Backward edges (proyectos que apuntan a este)
    for (const [pid, proj] of proyectoMap) {
      if (!visited.has(pid) && (proj.proyectoContinuacionIds || []).includes(id)) {
        queue.push(pid);
      }
    }
  }
  return visited;
}

function dateOf(p) {
  const d = p.fechaInicio || p.fechaCreacion;
  return d ? (d.toDate ? d.toDate() : new Date(d)) : new Date(0);
}

async function main() {
  console.log('Cargando proyectos desde Firestore…');
  const snap = await db.collection('proyectos').get();
  const proyectoMap = new Map();
  snap.docs.forEach(doc => proyectoMap.set(doc.id, { id: doc.id, ...doc.data() }));
  console.log(`Total proyectos: ${proyectoMap.size}\n`);

  const issues = [];

  // ── 1. Referencias rotas ───────────────────────────────────────────────────
  for (const [id, p] of proyectoMap) {
    for (const sid of (p.proyectoContinuacionIds || [])) {
      if (!proyectoMap.has(sid)) {
        issues.push({
          tipo: 'REFERENCIA_ROTA',
          proyectoId: id,
          institucion: p.institucion,
          detalle: `proyectoContinuacionIds contiene "${sid}" que NO existe en la colección`,
          fix: `Eliminar "${sid}" de proyectoContinuacionIds en ${id}`,
        });
      }
    }
  }

  // ── 2. Referencias circulares ─────────────────────────────────────────────
  for (const [id, p] of proyectoMap) {
    for (const sid of (p.proyectoContinuacionIds || [])) {
      const target = proyectoMap.get(sid);
      if (target && (target.proyectoContinuacionIds || []).includes(id)) {
        // Solo reportar una vez (el de fecha más reciente es el que tiene el link incorrecto)
        const pDate = dateOf(p);
        const tDate = dateOf(target);
        const newer  = pDate >= tDate ? id  : sid;
        const older  = pDate >= tDate ? sid : id;
        issues.push({
          tipo: 'CIRCULAR',
          proyectoId: id,
          institucion: p.institucion,
          detalle: `${id} ↔ ${sid} (referencia bidireccional)`,
          fix: `En el proyecto MÁS RECIENTE (${newer}): eliminar "${older}" de proyectoContinuacionIds.\n      El predecesor (${older}) ya apunta correctamente al sucesor (${newer}).`,
        });
      }
    }
  }

  // ── 3. Cadenas con múltiples heads ────────────────────────────────────────
  const processed = new Set();
  for (const [id] of proyectoMap) {
    if (processed.has(id)) continue;
    const chainIds = resolveChain(id, proyectoMap);
    chainIds.forEach(cid => processed.add(cid));

    // Un head es un proyecto que nadie más apunta a él dentro de la cadena
    const chainArr = [...chainIds].map(cid => proyectoMap.get(cid)).filter(Boolean);
    const heads = chainArr.filter(p =>
      !chainArr.some(other => (other.proyectoContinuacionIds || []).includes(p.id))
    );

    if (heads.length > 1) {
      heads.sort((a, b) => dateOf(b) - dateOf(a));
      issues.push({
        tipo: 'MULTIPLES_HEADS',
        proyectoId: heads.map(h => h.id).join(', '),
        institucion: heads[0].institucion,
        detalle: `Cadena con ${chainIds.size} miembros tiene ${heads.length} heads sin predecesor que los conecte:\n      ${heads.map(h => `${h.id} (${dateOf(h).toISOString().slice(0,10)})`).join('\n      ')}`,
        fix: `En el más antiguo (${heads[heads.length-1].id}): agregar "${heads[heads.length-2].id}" a proyectoContinuacionIds`,
      });
    }
  }

  // ── Reporte ────────────────────────────────────────────────────────────────
  if (issues.length === 0) {
    console.log('✅  Sin anomalías detectadas.');
    return;
  }

  console.log(`⚠️  Se encontraron ${issues.length} anomalía(s):\n`);
  issues.forEach((issue, i) => {
    console.log(`[${i + 1}] ${issue.tipo}`);
    console.log(`    ID:          ${issue.proyectoId}`);
    console.log(`    Institución: ${issue.institucion}`);
    console.log(`    Detalle:     ${issue.detalle}`);
    console.log(`    Fix:         ${issue.fix}`);
    console.log('');
  });

  // Resumen por tipo
  const byType = {};
  issues.forEach(i => { byType[i.tipo] = (byType[i.tipo] || 0) + 1; });
  console.log('Resumen:');
  Object.entries(byType).forEach(([t, n]) => console.log(`  ${t}: ${n}`));
  console.log('\nEjecuta reparar_cadenas.js para aplicar las correcciones automáticamente.');
}

main().catch(e => { console.error(e); process.exit(1); });
