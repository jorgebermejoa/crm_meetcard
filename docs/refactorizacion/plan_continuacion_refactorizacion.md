# 📋 PLAN DE CONTINUACIÓN - REFACTORIZACIÓN

## 🎯 ESTADO ACTUAL

**Progreso Total: 35%**

### ✅ COMPLETADO (Fase 1: Cimientos)
- [x] Estructura de carpetas `lib/features/proyecto/`
- [x] Utility `ResponsiveHelper`
- [x] `DetalleProyectoProvider` (Versión base)
- [x] `HeaderSection` (Extracción y limpieza)
- [x] `CadenaTimeline` (Refactorización completa)
- [x] `DetalleProyectoPage` (Página principal nueva)
- [x] Integración en `main.dart` (GoRouter)

### ⚠️ PROBLEMAS PENDIENTES
- [ ] Archivo `detalle_proyecto_view.dart` sigue siendo de 11k líneas (referencia).
- [ ] Lógica de exportación (PDF/CSV) sigue acoplada a la vista antigua.
- [ ] Algunas pestañas solo tienen placeholders.

### ❓ DUDAS / RIESGOS
- Complejidad de la pestaña de Análisis BQ (requiere BigQueryService y lógica pesada).
- Manejo de carga de archivos en la pestaña de Documentos.

---

## 🚀 PRÓXIMOS PASOS (Fase 2: Pestañas)

### PASO 1: Pestaña OCDS (Licitación) 🔴
**Prioridad: ALTA**
- Migrar `_buildTabOcds` y `_buildMpApiSection`.
- Crear `TabLicitacion` widget.
- Mover lógica de parsing de JSON OCDS al Provider.

### PASO 2: Pestaña Foro (Comentarios) 🟡
**Prioridad: MEDIA**
- Migrar lógica de Firestore para consultas y respuestas.
- Implementar buscador interno de foro.
- Crear `TabForo` widget.

### PASO 3: Pestaña Documentos 🟢
**Prioridad: MEDIA**
- Integrar `UploadService`.
- Migrar lista de certificados y reclamos.
- Crear `TabDocumentos` widget.

---

## 📐 PATRÓN A SEGUIR

Cada nueva pestaña debe seguir esta estructura:
1. **Modelos**: Asegurar que `Proyecto` tiene los campos necesarios.
2. **Provider**: Implementar método `cargar[Pestaña]()` con manejo de estados (loading, error, data).
3. **Widget**: Crear un `StatelessWidget` en `presentation/widgets/tabs/`.
4. **Integración**: Añadir el widget al `DetalleTabs`.
