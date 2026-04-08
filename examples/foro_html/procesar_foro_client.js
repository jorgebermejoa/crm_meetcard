#!/usr/bin/env node

/**
 * Cliente para procesar archivos XLS del foro vía Cloud Function
 * Uso: node procesar_foro_client.js <archivo.xls> <proyectoId> <licitacionId> [token]
 */

const fs = require('fs');
const path = require('path');
const axios = require('axios');

const args = process.argv.slice(2);
if (args.length < 3) {
  console.error(`
Uso: node procesar_foro_client.js <archivo.xls> <proyectoId> <licitacionId> [token]

Ejemplo:
  node procesar_foro_client.js \\
    ./Foro_PreguntasRespuestas_06-04-2026_17-06.xls \\
    mi_proyecto \\
    2026-123456 \\
    eyJhbGciOiJSUzI1NiIs...

Si no proporcionas token, se intentará leer de FIREBASE_TOKEN env var.
`);
  process.exit(1);
}

const [archivoPath, proyectoId, licitacionId, tokenArg] = args;

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════╗');
  console.log('║   CLIENTE: Procesar Foro XLS                              ║');
  console.log('╚════════════════════════════════════════════════════════════╝\n');

  // 1. Validar archivo
  const rutaCompleta = path.resolve(archivoPath);
  if (!fs.existsSync(rutaCompleta)) {
    console.error(`✗ Archivo no encontrado: ${rutaCompleta}`);
    process.exit(1);
  }

  const stats = fs.statSync(rutaCompleta);
  console.log(`📄 Archivo: ${path.basename(rutaCompleta)}`);
  console.log(`📊 Tamaño: ${(stats.size / 1024).toFixed(2)} KB`);
  console.log(`🗂️  Proyecto: ${proyectoId}`);
  console.log(`🎫 Licitación: ${licitacionId}\n`);

  // 2. Obtener token
  let token = tokenArg;
  if (!token) {
    token = process.env.FIREBASE_TOKEN;
    if (!token) {
      console.error('✗ Token no proporcionado y FIREBASE_TOKEN no configurada');
      process.exit(1);
    }
    console.log('ℹ️  Usando token de FIREBASE_TOKEN env var\n');
  }

  // 3. Leer archivo
  console.log('📖 Leyendo archivo...');
  const buffer = fs.readFileSync(rutaCompleta);
  console.log(`✓ Leído: ${buffer.length} bytes\n`);

  // 4. Enviar a Cloud Function
  const url = `https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?` +
    `proyectoId=${encodeURIComponent(proyectoId)}&` +
    `licitacionId=${encodeURIComponent(licitacionId)}&` +
    `generarResumen=true`;

  console.log('📤 Enviando a Cloud Function...');
  console.log(`   URL: ${url.split('?')[0]}?...\n`);

  try {
    const startTime = Date.now();
    const response = await axios.post(url, buffer, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/octet-stream',
      },
      timeout: 180000, // 3 minutos
    });

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    const result = response.data;

    console.log(`✓ Éxito (${elapsed}s)\n`);
    console.log('📊 Resultado:');
    console.log(`  • Total preguntas: ${result.totalPreguntas}`);
    console.log(`  • Respondidas: ${result.respondidas}`);
    console.log(`  • Sin responder: ${result.sinResponder}`);
    console.log(`  • Resumen IA: ${result.resumenGenerado ? '✓ Generado' : '✗ No'}\n`);

    if (result.resumen) {
      console.log('📝 Resumen (preview):');
      console.log('─'.repeat(60));
      console.log(result.resumen);
      console.log('─'.repeat(60));
      console.log();
    }

    console.log('✨ Completado\n');
    console.log('Datos guardados en:');
    console.log(`  • Firestore: proyectos/${proyectoId}/foro/${licitacionId}`);
    console.log(`  • Caché: licitaciones_foro/${licitacionId}\n`);

    return result;

  } catch (error) {
    console.error(`✗ Error (${error.code || error.status}):\n`);

    if (error.response?.data) {
      console.error(JSON.stringify(error.response.data, null, 2));
    } else if (error.message) {
      console.error(error.message);
    } else {
      console.error(error);
    }

    console.error();
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
