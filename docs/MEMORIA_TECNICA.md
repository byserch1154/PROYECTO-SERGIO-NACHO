# Memoria técnica · SPEAKE (Sneaker Factory)
Proyecto Intermodular · 2º DAM · Primer trimestre

> Borrador completo generado a partir del código del repositorio. Las partes marcadas con **[COMPLETAR]** son las que el
> equipo debe redactar con sus palabras (dificultades reales, capturas y reparto).

## 1. Empresa, problema y alcance
**SPEAKE** diseña, fabrica y vende zapatillas: 6 modelos de catálogo (Court, Pulse, High, Retro, Street, Aero) y una
línea **Custom** en la que el cliente elige el color de 6 partes y un texto en la suela. Los clubes y equipos piden
decenas de pares repartidos por tallas.

Problema: la empresa no tenía presencia digital ni un flujo que conectara la solicitud del cliente con ventas,
fabricación e inventario, ni herramientas para preparar el trabajo de taller o analizar las ventas.

Alcance entregado (versión 1):
| Bloque | Entregado |
|---|---|
| Web | 5 páginas responsive, configurador Custom con vista previa SVG y precio orientativo, formulario de solicitud conectado |
| Acceso a Datos | PostgreSQL con 9 tablas, triggers de importes/stock/auditoría, roles y permisos; **interfaz web (Express) en lugar de Java/JDBC** |
| Odoo | Guía de instalación y configuración, carga de datos por XML-RPC, flujo CRM → Ventas → Fabricación (MTO) → Inventario → Facturación |
| PSP | Aplicación Java con proceso coordinador y 3 procesos hijos (validar, analizar tallas, ficha de taller) |
| Python | Pipeline pandas con 12 reglas de calidad, 12 DataFrames, 19 KPIs, RFM, KMeans, predicción y dashboard Streamlit (60 s) |

Fuera de alcance: pagos reales, envío de correos, integración automática web → Odoo (se propone como mejora).

## 2. Arquitectura y relación entre módulos
```
Web ──HTTP/JSON──► Backend Express ──SQL parametrizado──► PostgreSQL
                         │                                   │ (mismo pedido SO003)
                         ├─► CSV contrato (data/export) ─────┼──► PSP (Java) ──► ficha de taller + log
                         │                                   └──► Python ──► KPIs, informes, dashboard
Odoo (VM Ubuntu) ◄── carga XML-RPC (productos, clientes, SO003)
Odoo ──► exportar_pedido_odoo.py ──► CSV ──► PSP
```
- **Odoo** es el sistema de gestión oficial del pedido (oportunidad, venta, fabricación, entrega, factura).
- **PostgreSQL** es la base de datos propia de la web y del módulo de Acceso a Datos, con la misma referencia SO003.
- **PSP** trabaja sobre una **copia exportada** (nunca escribe en Odoo ni en la BD).
- **Python** analiza las **exportaciones** de la BD; no se conecta directamente a PostgreSQL (lo pide el enunciado).
- La integración se hace con **CSV/JSON y procedimientos documentados**, como permite el documento del proyecto.

### Modelo de datos común del pedido
| Dato | Web | PostgreSQL | Odoo | PSP | Python |
|---|---|---|---|---|---|
| Identificador | referencia devuelta | `pedidos.referencia` (SO + 3 cifras, columna generada) | `sale.order.name` | `referencia` | `id_pedido` |
| Cliente | nombre, email | `clientes` (email único) | `res.partner` | `cliente` | `id_cliente` |
| Producto/variante | `court`… + 6 colores + texto | `modelos` + `lineas_pedido.color_*` | producto (+Custom) × talla | columnas `color_*` | `id_modelo`, `talla` |
| Cantidad | reparto por tallas | `lineas_pedido.cantidad` | `product_uom_qty` | `cantidad` | `cantidad` |
| Estado | mensaje de solicitud | pendiente/confirmado/entregado/cancelado | presupuesto/pedido/entrega/factura | código de salida y log | `estado` (venta = confirmado + entregado) |

Precio común: base del modelo + 15 € si es Custom + 5 € si lleva texto (web, trigger de PostgreSQL y Odoo).

## 3. Diseño de la interfaz y criterios responsive
- Cabecera y pie compartidos (`sf-layout.js` + `css/estilos.css`) idénticos en todas las páginas; menú hamburguesa por
  debajo de 860 px.
- Grid y flexbox con `clamp()` para tipografía fluida; el configurador pasa de 2 columnas a 1 en móvil.
- Accesibilidad: etiquetas `label` en todos los campos, `aria-live` en los mensajes, foco visible, contraste alto
  (fondo #080a0e / texto #f5f7fa / acento #1683ff), los colores se eligen con radios con `aria-label`.
- El formulario de contacto añade **reparto por tallas** para pedidos de club y valida en el navegador y en el servidor.
- Funciona sin servidor (modo estático) y, servido por Express, guarda la solicitud en la base de datos.
- Panel de gestión (`/gestion/`): pestañas, tabla con filtros, detalle de pedido y botones según el rol.
**[COMPLETAR]** capturas en escritorio y móvil.

## 4. Configuración de Odoo y flujo demostrado
Ver `odoo/README.md` (instalación, apps, usuarios por rol, productos con variantes de talla, listas de materiales,
rutas Fabricar + MTO, guion del flujo y checklist de evidencias).
Flujo de SO003: oportunidad CRM → presupuesto (9 líneas, 40 pares, 5.160 €) → confirmación → órdenes de fabricación
generadas por MTO → consumo de componentes → entrega validada → factura.
**[COMPLETAR]** capturas e incidencias reales de la instalación.

## 5. Subsistema auxiliar PSP
Ver `java/psp/README.md`. Resumen:
- `ProcesadorPedidosCustom` (padre) agrupa la exportación por pedido y lanza con **ProcessBuilder**
  `ValidadorPedidoCustom` → `AnalizadorTallas` → `GeneradorFichaTaller`, pasando los datos por **stdin/stdout**.
- stdout y stderr se leen por separado en hilos distintos (evita interbloqueos).
- `waitFor(timeout)` + `destroy()`/`destroyForcibly()` para procesos bloqueados.
- Códigos: validador 0/2/3/4, analizador 0/5, generador 0/6, padre 0/1/2. Si un hijo falla, no se lanza el siguiente.
- Evidencias: `procesamiento.log` (hora, pedido, proceso, PID, código, duración, stderr), `informe_procesamiento.csv`,
  CSV normalizado, resumen y ficha de taller con la referencia del pedido de Odoo.
- Ampliación: modo `--paralelo` con `ExecutorService` y log compartido `synchronized`.

## 6. Base de datos, interfaz de acceso a datos e integración
- Diseño y triggers: ver `base-de-datos/base-de-datos/docs/` (ER, matriz de permisos, memoria de Acceso a Datos).
- **Decisión**: la interfaz de acceso a datos se ha hecho en **Express (Node.js)** en lugar de Java/JDBC. Se mantienen
  las mismas garantías: consultas parametrizadas, transacciones, cierre de recursos, credenciales fuera del código,
  identidad propagada con `set_config('app.id_usuario', id, true)` y permisos comprobados dentro de PostgreSQL.
  Detalle requisito por requisito en `backend-express/README.md`.
- Rol técnico **Web** (`07_web_backend.sql`): las solicitudes públicas se insertan con el usuario `web_publica`, que
  solo puede crear pedidos pendientes y sus líneas; un comercial los revisa y confirma.
- Ficheros externos: `actividad_sneaker.txt` (append, intentos y errores incluidos) frente a `log_eventos`
  (solo cambios confirmados, se deshace con ROLLBACK); `usuarios_sneaker.json` sin hashes, regenerado tras cada
  cambio confirmado con escritura temporal + rename.
- Contrato CSV con PSP y Python: `ficha_fabricacion.csv`, `clientes`, `modelos`, `pedidos`, `lineas_pedido`, `stock` y
  `reconciliacion_sql.csv`, exportados en una única instantánea `REPEATABLE READ`.
- Python: ver `python/sneaker-data-lab/README.md` y `diccionario_datos.md`.

## 7. Pruebas realizadas y resultados
| Bloque | Pruebas | Resultado |
|---|---|---|
| PostgreSQL | `04_pruebas.sql` (restricciones, permisos, bcrypt, importes, stock, rollback, auditoría, indicadores) | «TODAS LAS PRUEBAS SUPERADAS» |
| Backend | `npm test`: 9 pruebas de extremo a extremo (A, B, C, E–J, permisos, validación, exportación) | 9/9 |
| Web | Flujo navegador: configurador → contacto → solicitud SO0xx → confirmación en el panel | correcto |
| PSP | `pruebas.bat`: 7 casos (OK, varios pedidos, datos erróneos, sin columnas, timeout, paralelo, fichero inexistente) | códigos esperados |
| Python | `pytest`: 18 pruebas (carga, integridad, cálculo, reproducibilidad, ML) | 18/18 |
| Integración | Solicitud web → confirmar → exportar → PSP genera la ficha → Python concilia 6 cifras con SQL | todas coinciden |
| Odoo | Flujo SO003 completo **[COMPLETAR con capturas]** | – |

## 8. Dificultades, decisiones y mejoras
Decisiones técnicas relevantes:
- Referencia común `SO###` generada en PostgreSQL y reutilizada como nombre del pedido en Odoo.
- Toda la lógica de negocio (importes, stock, auditoría, permisos) vive en PostgreSQL: así da igual qué cliente se conecte.
- Los datos reales son pocos (12 pedidos, 3 meses): clustering y predicción se declaran **NO CALCULABLE** con datos
  reales y se demuestran con un histórico **sintético** separado y rotulado.
- La línea Custom se modela en Odoo como producto aparte con ruta MTO para que cada pedido genere su orden de fabricación.

Mejoras futuras: crear el presupuesto en Odoo directamente desde el backend (XML-RPC); campos de color propios en Odoo;
exportación programada de CSV; despliegue con HTTPS; tests de interfaz automatizados.
**[COMPLETAR]** dificultades reales encontradas por el equipo.

## 9. Reparto del trabajo **[COMPLETAR]**
Propuesta para un equipo de 2 personas (ajustar a lo que haya hecho cada uno):
| Persona | Responsabilidades |
|---|---|
| A | Web (Lenguaje de Marcas), backend Express, Odoo, manual de demostración |
| B | Base de datos y Acceso a Datos, PSP (Java), Python y dashboard, pruebas |
Ambos deben poder explicar el flujo completo: la defensa puede incluir preguntas individuales.
