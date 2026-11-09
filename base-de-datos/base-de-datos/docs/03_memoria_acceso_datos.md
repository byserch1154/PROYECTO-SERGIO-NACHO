# 03 · Memoria · Apartado de Acceso a Datos (borrador para la memoria común)

## 1. Objetivo y alcance
Base de datos PostgreSQL de Sneaker Factory (clientes, modelos, pedidos, líneas, stock, usuarios,
roles y auditoría), con la lógica de negocio dentro de PostgreSQL (PL/pgSQL). Los datos son los mismos
que usan la web (6 modelos, colores, tallas, precios), Odoo y PSP. La interfaz Java queda fuera de este documento.

## 2. Diseño
Ver `01_diseno_ER.md` (diagrama y decisiones).

## 3. Reconstrucción
Ver `README.md`: `01_esquema.sql` → `02_datos.sql` en una base vacía; recrea roles, usuarios y permisos.

## 4. Automatizaciones (qué tabla dispara qué, cuándo y qué modifica)
| Trigger | Tabla que lo dispara | Cuándo | Qué hace | Tablas que modifica |
|---|---|---|---|---|
| `t1_pedidos_permisos` | pedidos | BEFORE INSERT/UPDATE/DELETE | Comprueba permiso del rol; un pedido nuevo solo nace `pendiente`; anota `creado_por` | ninguna |
| `t2_pedidos_validar` | pedidos | BEFORE UPDATE/DELETE | Transiciones válidas de estado; no confirmar sin líneas; no editar pedidos cerrados | ninguna |
| `t3_pedidos_stock` | pedidos | AFTER UPDATE OF estado | **Automatización 2**: confirmar descuenta, cancelar un confirmado devuelve | stock |
| `t4_pedidos_audit_altabaja` / `_cambios` | pedidos | AFTER INSERT/DELETE · AFTER UPDATE (solo estado, cliente o fecha) | Auditoría | log_eventos |
| `t1_lineas_antes` | lineas_pedido | BEFORE INSERT/UPDATE/DELETE | Permiso, pedido pendiente, limpia el texto y calcula el precio si va vacío | ninguna |
| `t2_lineas_total` | lineas_pedido | AFTER INSERT/UPDATE/DELETE | **Automatización 1**: recalcula `total` y `tipo` del pedido desde sus líneas | pedidos (total, tipo) |
| `t3_lineas_audit` | lineas_pedido | AFTER INSERT/UPDATE/DELETE | Auditoría | log_eventos |

**Importes**: el total se *recalcula* con `SUM(cantidad × precio)` sobre las líneas (nunca se suma sobre el
valor anterior), así editar una línea no duplica importes.

**Existencias**: solo reaccionan al *cambio de estado*, no a editar líneas (las líneas de un pedido no
pendiente son inmutables). Confirmar usa `UPDATE ... WHERE stock_disponible >= cantidad`: si no hay,
se lanza una excepción y se deshace **todo** el pedido (sin cambios parciales, sin stock negativo).
Cancelar un pedido `confirmado` devuelve exactamente lo descontado; cancelar uno `pendiente` no toca stock.

**Sin recursión ni cascadas**: `t2_lineas_total` actualiza `pedidos`, pero los triggers de pedidos lo
ignoran (no cambia el estado, y la auditoría tiene un `WHEN` que solo mira estado, cliente y fecha).
`stock` y `log_eventos` no tienen triggers. Orden determinista: los triggers del mismo momento se ejecutan
por orden alfabético (t1, t2, t3, t4).

## 5. Auditoría y transacciones
`log_eventos` se escribe con triggers `AFTER` **dentro de la transacción** que hace el cambio:
- Con `COMMIT`, el dato y su evento se hacen visibles a las demás conexiones a la vez.
- Con `ROLLBACK`, se deshacen los dos: no queda evento de algo que no ocurrió.
Cada evento guarda fecha/hora (`now()` = inicio de la transacción), tabla, operación, id, usuario y un
resumen (en los UPDATE, solo los campos que cambian: `estado: pendiente -> confirmado`).
Demostración: `04_pruebas.sql` sección 6 y `06_transacciones.sql` (demos 1 y 2, con dos terminales).
La eliminación lógica de un pedido es pasar a `cancelado` y queda auditada.

## 6. Seguridad e identidad
- Contraseñas: **bcrypt con sal** (`pgcrypto`: `crypt()` + `gen_salt('bf')`). Nunca en texto plano; cada hash lleva sal distinta (probado).
- Login: `fn_login(usuario, contraseña)` devuelve el id o NULL; los usuarios inactivos no entran.
- **Propagación de la identidad**: al abrir cada transacción, la aplicación ejecuta
  `SELECT set_config('app.id_usuario', '<id>', true)`. El `true` limita el valor a esa transacción, así no
  se filtra entre sesiones aunque haya pool de conexiones. Los triggers leen ese valor con `fn_usuario_actual()`,
  que además comprueba que el usuario existe y está activo. Sin usuario, la operación se rechaza (`28000`).
- Permisos aplicados **en la base de datos**: da igual qué botón pulse el usuario o si llama directamente a
  la función; un rol sin permiso recibe `42501` y no se modifica nada.
- **Limitación conocida (honesta)**: como la aplicación se conecta con una única cuenta de base de datos,
  quien tuviera esas credenciales podría fijar otro `app.id_usuario`. En producción se reforzaría con
  `GRANT/REVOKE` (cuenta de aplicación solo con EXECUTE sobre las funciones) o con un token de sesión.
  Es una ampliación opcional según el enunciado.

## 7. Consultas, analítica y exportaciones
- `03_consultas.sql`: 12 consultas (búsquedas, JOIN de 4 tablas, GROUP BY, HAVING, subconsulta, stock bajo, indicadores, ficha).
- **Regla de ventas** (única, usada en todas las consultas): ventas = pedidos `confirmado` + `entregado`.
  Se excluyen `cancelado` y `pendiente`. Un pedido con 3 líneas cuenta como 1 pedido (`COUNT(DISTINCT id_pedido)`
  o consulta sobre la cabecera). "Pares solicitados" = pares de pedidos no cancelados.
- `fn_indicadores()`: pedidos totales, pares solicitados, pares vendidos, importe de ventas y pedidos por estado,
  contrastados contra SQL directo en `04_pruebas.sql` sección 10.
- `fn_stock_bajo(umbral)`: stock bajo un umbral configurable, ordenado de menor a mayor.
- Exportación a CSV (`05_exportar_csv.sql`): `ficha_fabricacion.csv` (para PSP) y los 5 CSV del contrato con Python
  (`clientes`, `modelos`, `pedidos`, `lineas_pedido`, `stock`), sin email ni teléfono.

## 8. Correspondencia con Odoo y PSP
La referencia del pedido es `referencia` = `SO` + número de 3 cifras (SO003). **Decisión pendiente del equipo**:
el documento intermodular usa como ejemplo `SO024 · Club Halcones · Runner X · 40 pares`, y esta base usa
`SO003 · Club Halcones · SPEAKE Pulse · 40 pares`. Opciones: (a) que Odoo use SO003 y el modelo se llame igual
en ambos sitios, o (b) mantener una tabla de equivalencias:

| Concepto | BD (PostgreSQL) | Odoo | PSP |
|---|---|---|---|
| Pedido | `pedidos.referencia` (SO003) | pedido de venta (por acordar) | clave del CSV `ficha_fabricacion.csv` |
| Cliente | `clientes.nombre` | contacto | columna `cliente` |
| Modelo | `modelos.nombre` | producto/variante | columna `modelo` |

## 9. Pruebas (qué script las demuestra)
| Prueba del enunciado | Dónde | Estado |
|---|---|---|
| Restricciones (cantidad > 0, cliente existente, etc.) | `04_pruebas.sql` secc. 1 | [CAPTURA] |
| Permisos por rol / denegación sin cambios | `04_pruebas.sql` secc. 2 | [CAPTURA] |
| Login y bcrypt | `04_pruebas.sql` secc. 3 | [CAPTURA] |
| Importes (INSERT/UPDATE/DELETE de línea) | `04_pruebas.sql` secc. 4 | [CAPTURA] |
| **B** confirmar sin stock → rechazo controlado | `04_pruebas.sql` secc. 5; `06` demo 3 | [CAPTURA] |
| **C** cancelar confirmado → stock restituido y auditado | `04_pruebas.sql` secc. 5; `06` demo 3 | [CAPTURA] |
| **D** ROLLBACK deshace dato y auditoría | `04_pruebas.sql` secc. 6; `06` demo 2 | [CAPTURA] |
| COMMIT visible desde otra conexión | `06` demo 1 (dos terminales) | [CAPTURA] |
| Auditoría con usuario y hora | `04_pruebas.sql` secc. 7 | [CAPTURA] |
| Coherencia (totales, stock, conciliación) | `04_pruebas.sql` secc. 8 | [CAPTURA] |
| Gestión de usuarios (alta/desactivar) | `04_pruebas.sql` secc. 9 | [CAPTURA] |
| Indicadores = SQL directo | `04_pruebas.sql` secc. 10 | [CAPTURA] |
| INSERT / UPDATE / DELETE de pedidos | `06` demos 1, 3 y 4 | [CAPTURA] |
| A, E, F, G, H, I (parte Java) | Se cubren con la interfaz Java | pendiente (Java) |

## 10. Dificultades y decisiones
Rellenad con vuestras palabras: qué os costó, qué cambiasteis y quién hizo qué (el enunciado pide
dificultades y aportaciones individuales).
