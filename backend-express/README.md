# Backend Express · conexión web ↔ PostgreSQL (Acceso a Datos)

Servidor **Node.js + Express** que conecta la web corporativa con la base de datos PostgreSQL del proyecto
(`base-de-datos/`). Sustituye a la interfaz Java/JDBC del enunciado de Acceso a Datos: la persistencia, los triggers,
los permisos y la auditoría siguen estando **dentro de PostgreSQL**; el backend solo propaga la identidad del usuario y
presenta los resultados.

```
Navegador ── web (lenguaje-de-marcas) ──► POST /api/solicitudes ─┐
Navegador ── panel /gestion (login) ───► /api/pedidos, ...  ─────┤  driver pg (consultas parametrizadas)
                                                                 ▼
                         PostgreSQL: triggers (importes, stock, auditoría) + permisos por rol
                                                                 │
              logs/actividad_sneaker.txt · data/usuarios_sneaker.json · data/export/*.csv (PSP + Python)
```

## Puesta en marcha
Requisitos: Node.js 18+ y PostgreSQL 14+.
```bat
:: 1. Base de datos (desde la carpeta base-de-datos\base-de-datos\bd)
createdb SPEAKE
psql -d SPEAKE -v ON_ERROR_STOP=1 -f 01_esquema.sql
psql -d SPEAKE -v ON_ERROR_STOP=1 -f 02_datos.sql
:: 2. Ampliación para el backend (desde backend-express\sql)
psql -d SPEAKE -v ON_ERROR_STOP=1 -f 07_web_backend.sql
psql -d SPEAKE -v ON_ERROR_STOP=1 -f 10_integracion_odoo.sql
psql -d SPEAKE -v ON_ERROR_STOP=1 -f 11_colores_catalogo.sql
:: 3. Servidor
cd backend-express
copy .env.example .env          (y poner la contraseña de PostgreSQL en .env)
npm install
npm start
```
- Web: <http://localhost:3000/> (la misma web de Lenguaje de Marcas, ahora conectada)
- Panel de gestión: <http://localhost:3000/gestion/>
- Pruebas automáticas (con el servidor arrancado y la base recién cargada): `npm test`

Usuarios ficticios: `admin / Admin#2026` · `comercial1 / Comercial#2026` · `almacen1 / Almacen#2026`
(contraseñas guardadas con bcrypt en la BD; cambiarlas desde el panel si se desea).

## Ficheros
| Fichero | Qué hace |
|---|---|
| `src/server.js` | Arranque, cabeceras de seguridad, sirve la web y el panel |
| `src/db.js` | Pool de conexiones y `comoUsuario()`: transacción + `set_config('app.id_usuario', id, true)` |
| `src/auth.js` | Login con `fn_login()` (bcrypt en PostgreSQL) y token de sesión aleatorio |
| `src/routes/publico.js` | Catálogo, stock por talla y **solicitudes Custom de la web** |
| `src/routes/gestion.js` | Consultas con filtros, alta, confirmar/cancelar/entregar, indicadores, auditoría, usuarios, exportaciones |
| `src/actividad.js` | Log externo `actividad_sneaker.txt` (append, UTF-8) |
| `src/exportaciones.js` | CSV (contrato con PSP/Python y CSV filtrado) y `usuarios_sneaker.json` con escritura segura |
| `src/errores.js` | Traduce los errores de PostgreSQL a mensajes comprensibles |
| `src/odoo.js` | Cliente de la API de Odoo (JSON-RPC): busca/crea el cliente y crea el pedido de venta |
| `panel/` | Interfaz de gestión (HTML + CSS + JS sin librerías) |
| `sql/07_web_backend.sql` | Rol técnico **Web**, usuario `web_publica`, funciones de detalle/análisis y vista de conciliación |
| `sql/08_exportar_reconciliacion.sql` | Exporta las cifras SQL que Python concilia |
| `sql/10_integracion_odoo.sql` | Tabla `pedidos_odoo` (qué pedido de Odoo corresponde a cada uno) y funciones de envío |
| `sql/11_colores_catalogo.sql` | Tabla `colores_catalogo` (3 combinaciones por modelo) y columna `id_color` en las líneas |
| `sql/12_pruebas_web_odoo.sql` | 16 pruebas en pgAdmin de colores de catálogo y envío a Odoo (termina en ROLLBACK) |
| `test/api.test.js` | 9 pruebas de extremo a extremo |
| `test/odoo.test.js` | 6 pruebas de la integración con un Odoo simulado (`npm run test:odoo`) |

## API
| Método y ruta | Permiso (en PostgreSQL) | Descripción |
|---|---|---|
| `GET /api/modelos` · `GET /api/modelos/:codigo/stock` | público | Catálogo y existencias por talla |
| `GET /api/colores` | público | Colores de catálogo de cada modelo (los muestra la ficha de producto) |
| `POST /api/solicitudes` | rol Web: `crear_pedido` | Cliente (por email, sin duplicar) + pedido **pendiente** + líneas, en UNA transacción |
| `POST /api/login` · `POST /api/logout` · `GET /api/me` | – | Sesión |
| `GET /api/pedidos?cliente&modelo&estado&desde&hasta` | `consultar_pedidos` | Botón «Buscar / Consultar» (filtros vacíos no restringen) |
| `GET /api/pedidos/export.csv?...` | `consultar_pedidos` | CSV con exactamente las filas de la tabla |
| `GET /api/pedidos/:ref` | `consultar_pedidos` | Cabecera + líneas |
| `POST /api/pedidos` | `crear_pedido` + `editar_pedido` | Alta desde el panel |
| `PATCH /api/pedidos/:ref/estado` | `confirmar_/cancelar_/entregar_pedido` | El stock lo mueve el trigger |
| `GET /api/indicadores` | `consultar_pedidos` | Panel de indicadores, modelos y tallas |
| `GET /api/stock-bajo?umbral=5` | `consultar_stock` | Variantes bajo el umbral |
| `GET /api/auditoria` | `ver_auditoria` | `log_eventos` con usuario y fecha |
| `GET/POST /api/usuarios` · `PATCH /api/usuarios/:id` | `gestionar_usuarios` | Alta, activar/desactivar, cambiar rol (regenera el JSON) |
| `POST /api/usuarios/exportar-json` | `exportar_usuarios` | `usuarios_sneaker.json` |
| `POST /api/exportar-contrato` | `consultar_pedidos` | CSV para PSP y Python en `data/export/` |
| `POST /api/pedidos/:ref/odoo` | `confirmar_pedido` | Reenvía a Odoo un pedido confirmado (si antes falló) |
| `GET /api/odoo/estado` | sesión | ¿Integración configurada? ¿Odoo responde? (sin datos sensibles) |

## Cómo se cumplen los requisitos de Acceso a Datos (versión web, sin JDBC)
- **Consultas parametrizadas**: todas con `$1, $2…` (equivalente a `PreparedStatement`); nunca se concatena un valor.
- **Transacciones**: cabecera + líneas en una misma transacción; si una línea falla, `ROLLBACK` de todo.
- **Cierre de recursos**: cada conexión se devuelve al pool en un `finally`.
- **Credenciales fuera del código**: `.env` (no se sube a Git; se entrega `.env.example`).
- **Identidad hasta PostgreSQL**: `set_config('app.id_usuario', id, true)` al inicio de cada transacción. El `true` hace
  que el valor muera con la transacción (seguro con el pool). Los triggers lo leen con `fn_usuario_actual()` y lo escriben
  en `log_eventos`. Las solicitudes de la web quedan auditadas con el usuario técnico `web_publica`.
- **Permisos de verdad**: el panel oculta botones por comodidad, pero la API llama a funciones que ejecutan
  `fn_exigir_permiso()`. Un `curl` directo con un rol sin permiso recibe 403 y no cambia nada (probado en `npm test`).
- **Automatizaciones en la BD**: el backend nunca actualiza totales, stock ni auditoría; lo hacen los triggers.
- **Log TXT**: una línea por login, búsqueda, limpiar filtros, alta, cambio de estado, exportación o intento denegado,
  con fecha/hora, usuario, rol, acción, resultado (`correcto`, `vacio`, `rechazado`, `error`), filtros sin datos
  sensibles y nº de filas. Se escribe **después** del COMMIT/ROLLBACK, así nunca marca como correcto algo deshecho.
- **JSON de usuarios**: sin contraseñas ni hashes; se regenera tras cada cambio confirmado de usuarios, leyendo en
  otra transacción el estado ya confirmado; escritura en temporal + `rename` (nunca queda a medias).
- **CSV**: UTF-8 con cabecera; el filtrado coincide fila a fila con la tabla; el contrato se exporta en una única
  instantánea `REPEATABLE READ` para que los 7 ficheros sean coherentes entre sí.

## Colores de catálogo
Cada modelo se vende en 3 combinaciones de color definidas por la marca (tabla `colores_catalogo`).
En la ficha de producto se elige el color, la foto cambia a esa combinación y «Comprar este color»
lleva al formulario con todo rellenado. Las fotos están en `lenguaje-de-marcas/img/colores/<codigo>.jpg`
y se generan a partir de la foto original de cada modelo con
`lenguaje-de-marcas/herramientas/recolorear_fotos.py` (cambia el azul de los detalles por el color nuevo).

| | Color de catálogo | Personalizado (configurador) |
|---|---|---|
| Línea | `id_color` = combinación elegida, 6 colores vacíos | 6 colores elegidos, `id_color` vacío |
| Tipo de pedido | estándar | custom |
| Precio | base del modelo | base + 15 € (+5 € con texto) |
| En Odoo | producto «SPEAKE Pulse», «Color: …» en la descripción | producto «SPEAKE Pulse Custom» (MTO) |

La base de datos impide mezclar las dos cosas (`ck_color_catalogo_estandar`) y que se use un color
de otro modelo (trigger `t1b_lineas_color`).

## Integración con Odoo
Odoo es el núcleo del negocio y tiene **su propia base de datos**, que gestiona con su ORM. Por eso no se
escribe en sus tablas ni se usan triggers sobre ella: el backend llama a la **API externa de Odoo**
(JSON-RPC), igual que haría un usuario desde la pantalla de Ventas, y Odoo aplica sus propias reglas.

```
Web ──► Express ──► PostgreSQL SPEAKE ──(confirmar en el panel)──► API de Odoo ──► Pedido de venta S000xx
                       (triggers, permisos,                          (busca/crea el     · Ref. cliente = SO0xx
                        stock, auditoría)                             cliente por email)  · fabricación MTO
```

1. Ejecutar `sql/10_integracion_odoo.sql` en SPEAKE (solo añade; no borra nada).
2. Cargar en Odoo los productos con tallas: `odoo/scripts/cargar_datos_odoo.py`.
3. Rellenar en `.env` `ODOO_URL`, `ODOO_DB`, `ODOO_USER` y `ODOO_PASSWORD` (mejor una clave API:
   Odoo → Mi perfil → Seguridad de la cuenta → Nueva clave API). Reiniciar `npm start`.
4. En el panel aparece «Odoo: conectado a …». Al **confirmar** un pedido se crea en Odoo con la
   Referencia del cliente = referencia de SPEAKE, y la columna Odoo muestra su número (S000xx).

Comportamiento ante fallos:
- Si Odoo no responde, el pedido **sigue confirmado en SPEAKE** (stock y auditoría correctos), la columna
  Odoo muestra «error» y el botón «Reenviar a Odoo» lo vuelve a intentar.
- Reenviar no duplica: si ya existe en Odoo un pedido con esa referencia, se reutiliza.
- Solo se envían pedidos confirmados o entregados, y solo quien tiene el permiso `confirmar_pedido`
  (lo comprueba PostgreSQL en `fn_pedido_para_odoo`).
- Cada envío queda en `pedidos_odoo` y en el TXT (`accion=enviar_odoo`).
- **IVA:** SPEAKE guarda los importes sin IVA (como en el contrato de datos con Python). Odoo aplica
  el impuesto de venta del 21 %, por eso SO003 vale 5.160 € en SPEAKE y 6.243,60 € en Odoo
  (5.160 × 1,21). El precio unitario de cada línea es el mismo en los dos sistemas.

Para ver en pgAdmin qué pedido de Odoo corresponde a cada uno:
```sql
SELECT * FROM v_pedidos_odoo ORDER BY actualizado DESC;
```

## Pruebas (`npm test`)
| Prueba | Qué comprueba |
|---|---|
| Login | acceso por rol; contraseña errónea y usuario técnico `web_publica` rechazados |
| A + C | solicitud web → pedido custom pendiente con total calculado por trigger → confirmar descuenta stock → auditoría con usuario → cancelar devuelve stock |
| B | confirmar sin stock: 409, ni la talla con stock se descuenta, el pedido sigue pendiente |
| Permisos | Almacén no puede crear pedidos, Comercial no ve auditoría ni exporta usuarios, sin token = 401 |
| E/F/G | sin filtros, filtros combinados, sin coincidencias y limpiar; 4 líneas nuevas en el TXT al instante y sin contraseñas |
| H/J | indicadores coherentes (suma de estados = total) y CSV filtrado = filas de la tabla |
| I | crear y desactivar usuario actualiza el JSON sin perder los demás; duplicado rechazado |
| Validación | datos incorrectos de la web no crean nada |
| Contrato | exportación de los 7 CSV para PSP y Python |

## Pruebas de Odoo (`npm run test:odoo`)
No necesitan la máquina virtual: levantan un Odoo simulado y un backend propio en otro puerto.

| Prueba | Qué comprueba |
|---|---|
| O1 | el panel ve Odoo conectado y nunca recibe la contraseña |
| O2 | confirmar un pedido web crea en Odoo el cliente y el pedido de venta (variante por talla, colores en la descripción) y lo confirma |
| O3 | reenviar no duplica el pedido en Odoo |
| O4 | con Odoo caído la confirmación se mantiene, queda «error» y el reenvío posterior funciona |
| O5 | no se envían pedidos pendientes y Almacén no tiene permiso |
| O6 | un pedido con color de catálogo llega como producto estándar, a precio base y con su color |

Al terminar, las pruebas cancelan los pedidos que han confirmado, así el stock vuelve a su valor.
