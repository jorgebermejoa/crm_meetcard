# 🚀 PROMPTS POR PESTAÑA - REFACTORIZACIÓN

## 🔴 PESTAÑA OCDS (Licitación)
**Objetivo**: Refactorizar la lógica de OCDS de `detalle_proyecto_view.dart` a `TabLicitacion`.

**Prompt recomendado**:
```
Refactoriza la pestaña OCDS de DetalleProyectoView (clase _DetalleProyectoViewState).
1. Identifica el método `_buildTabOcds` y `_buildMpApiSection`.
2. Identifica los helpers `_ocdsHero`, `_buyerCard`, `_plazosCard`, `_itemCard`, `_ofertaCard`, `_tenderersCard`.
3. Mueve la lógica de parsing (json) a DetalleProyectoProvider.
4. Crea el widget Stateless `TabLicitacion` en presentation/widgets/tabs/tab_licitacion.dart.
5. Usa el ResponsiveHelper para asegurar que las tarjetas se adapten a móvil.
6. Integra en DetalleTabs.
```

## 🟡 PESTAÑA FORO (Comentarios)
**Objetivo**: Migrar el foro de Firestore a `TabForo`.

**Prompt recomendado**:
```
Refactoriza la pestaña Foro de DetalleProyectoView.
1. Identifica el método `_buildTabForo` y la lógica de Firestore.
2. Mueve la lógica de carga, búsqueda y resumen de foro a DetalleProyectoProvider.
3. Crea el widget `TabForo` en presentation/widgets/tabs/tab_foro.dart.
4. Implementa el buscador y la visualización de la línea de tiempo del foro.
5. Asegura que el ResponsiveHelper se use para los tamaños de fuente y paddings.
```

## 🟢 PESTAÑA DOCUMENTOS
**Objetivo**: Gestionar archivos, certificados y reclamos en `TabDocumentos`.

**Prompt recomendado**:
```
Refactoriza la pestaña de Documentos de DetalleProyectoView.
1. Identifica el método `_buildTabDocumentos` (o equivalente para certificados/reclamos/documentos).
2. Mueve la lógica de subida (UploadService) y edición de campos a DetalleProyectoProvider.
3. Crea el widget `TabDocumentos` en presentation/widgets/tabs/tab_documentos.dart.
4. Incluye las secciones de Documentos, Certificados y Reclamos.
```

## ✨ REFACTORIZACIÓN EXTRA (Análisis BQ)
**Objetivo**: Migrar el análisis de BigQuery a `TabAnalisisBQ`.

**Prompt recomendado**:
```
Refactoriza la pestaña Análisis de DetalleProyectoView.
1. Identifica el método `_buildTabAnalisis` y la lógica de BigQueryService.
2. Mueve la lógica de consulta y procesamiento de BigQuery a DetalleProyectoProvider.
3. Crea el widget `TabAnalisisBQ` en presentation/widgets/tabs/tab_analisis_bq.dart.
4. Implementa las gráficas y tablas de competidores y prediciones.
```
