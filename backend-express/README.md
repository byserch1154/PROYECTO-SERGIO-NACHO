# Backend Express · cómo se conecta la web con la base de datos

Este servidor está hecho con **Node.js y Express**. Hace de puente entre la web y la base de datos PostgreSQL: recibe
los pedidos de la web, los guarda en la base y ofrece un **panel de gestión** para los empleados.

El enunciado de Acceso a Datos pedía una aplicación Java con JDBC. En nuestro caso no hacía falta: lo hemos hecho con
este backend, que cumple lo mismo (consultas seguras, transacciones, login, log, JSON y CSV). Lo importante (importes,
stock, permisos y auditoría) lo sigue controlando PostgreSQL con sus triggers; el backend solo le pasa los datos y le
dice qué usuario está trabajando.

```
Web ──────────► pedido nuevo ──────┐
Panel (login) ─► consultas, etc. ──┤──► PostgreSQL (triggers, permisos, auditoría)
                                   │
                                   └──► ficheros: log TXT, JSON de usuarios y CSV para Java y Python
```

## Cómo se arranca
Hace falta Node.js 18 o superior y la base `SPEAKE` ya cargada (ver el README de `base-de-datos`).
```bat
cd backend-express
copy .env.example .env
npm install
npm start
```
En el `.env` se pone la contraseña de PostgreSQL y los datos de Odoo. Ese fichero no se sube a GitHub.

- Web: http://localhost:3000/
- Panel de gestión: http://localhost:3000/gestion/
- Pruebas: `npm test` (con el servidor arrancado) y `npm run test:odoo`

Usuarios de prueba: `admin / Admin#2026`, `comercial1 / Comercial#2026` y `almacen1 / Almacen#2026`.

## Qué hay en cada fichero
| Fichero | Qué hace |
|---|---|
| `src/server.js` | Arranca el servidor y sirve la web y el panel |
| `src/db.js` | Conexión con PostgreSQL. Cada operación va en una transacción que lleva el usuario que la hace |
| `src/auth.js` | Login (la contraseña la comprueba PostgreSQL con bcrypt) |
| `src/routes/publico.js` | Lo que usa la web: catálogo, stock y pedidos nuevos |
| `src/routes/gestion.js` | Lo que usa el panel: buscar, crear, confirmar, cancelar, entregar, indicadores, auditoría, usuarios y exportar |
| `src/actividad.js` | Escribe el log `logs/actividad_sneaker.txt` |
| `src/exportaciones.js` | Crea los CSV y el `usuarios_sneaker.json` |
| `src/errores.js` | Convierte los errores de PostgreSQL en mensajes que se entienden |
| `src/odoo.js` | Envía los pedidos confirmados a Odoo |
| `panel/` | La pantalla del panel de gestión (HTML, CSS y JavaScript) |
| `sql/07_web_backend.sql` | Usuario técnico de la web y funciones del panel |
| `sql/10_integracion_odoo.sql` | Tabla que apunta qué pedido de Odoo corresponde a cada uno |
| `sql/11_colores_catalogo.sql` | Los 3 colores de catálogo de cada modelo |
| `sql/12_pruebas_web_odoo.sql` | 16 pruebas para pgAdmin (acaba en ROLLBACK, no cambia nada) |
| `test/` | Pruebas automáticas del backend y de la conexión con Odoo |

## Cómo se cumplen los requisitos de Acceso a Datos
- **Consultas seguras.** Los valores van siempre aparte del SQL (`$1, $2…`), como un PreparedStatement en Java. Así no
  se puede colar código en una búsqueda.
- **Transacciones.** La cabecera y las líneas de un pedido se guardan juntas. Si una línea falla, se deshace todo
  (ROLLBACK) y no queda un pedido a medias.
- **Conexiones.** Cada conexión se devuelve siempre al terminar, aunque haya un error.
- **Contraseñas fuera del código.** Van en el `.env`, que no se sube. En el repositorio solo está `.env.example`.
- **El usuario llega a PostgreSQL.** Al empezar cada transacción, el backend le dice a la base qué usuario está
  trabajando. Los triggers lo usan para comprobar sus permisos y para apuntarlo en la auditoría. Los pedidos de la web
  quedan a nombre del usuario técnico `web_publica`.
- **Permisos de verdad.** El panel esconde los botones que un rol no puede usar, pero eso es solo comodidad: si alguien
  llama a la API a mano sin permiso, PostgreSQL lo rechaza y no cambia nada.
- **Log TXT.** Cada login, búsqueda, alta, cambio de estado, exportación o intento sin permiso añade una línea con la
  hora, el usuario, el rol, la acción y el resultado. Nunca se escriben contraseñas. Se escribe después de saber si la
  operación salió bien o se deshizo.
- **JSON de usuarios.** Lista de usuarios con su rol y si están activos, sin contraseñas. Se rehace cada vez que se
  crea, desactiva o cambia de rol un usuario.
- **CSV.** En UTF-8 y con cabecera. El CSV del panel tiene exactamente las filas que se ven en la tabla.

## Colores de catálogo
Además del configurador, cada modelo se vende en 3 combinaciones de color ya diseñadas. Se eligen en la ficha de
producto y el pedido es estándar (precio base). En el configurador el pedido es Custom (precio base + 15 €, +5 € con
texto). La base de datos no deja mezclar las dos cosas ni usar un color de otro modelo.

## Conexión con Odoo
Odoo tiene su propia base de datos y no la tocamos. Cuando el comercial **confirma** un pedido en el panel, el backend
lo crea en Odoo por su API, igual que si alguien lo hiciera desde la pantalla de Ventas.

1. Ejecutar `sql/10_integracion_odoo.sql` en la base SPEAKE.
2. Tener en Odoo los productos con sus tallas (los cargamos con un script que está en la máquina virtual de Odoo).
3. Poner en el `.env` la dirección de Odoo, la base, el usuario y una clave API (Odoo → Mi perfil → Seguridad de la
   cuenta → Nueva clave API) y volver a hacer `npm start`.
4. Al confirmar un pedido, aparece en Odoo con nuestra referencia (SO0xx) en «Referencia del cliente».

Si algo falla:
- Si Odoo no responde, el pedido sigue confirmado en SPEAKE y en el panel sale «error». El botón «Reenviar a Odoo» lo
  vuelve a intentar.
- Reenviar no duplica el pedido: si ya existe uno con esa referencia, se usa ese.
- Solo se envían pedidos confirmados o entregados, y solo puede hacerlo quien tiene permiso para confirmar.
- **IVA.** En SPEAKE los importes van sin IVA y Odoo le suma el 21 %. Por eso SO003 vale 5.160 € en SPEAKE y
  6.243,60 € en Odoo.

## Pruebas
`npm test` (9 pruebas, con el servidor arrancado): login, pedido de la web, confirmar y cancelar con el stock, pedido
sin stock, permisos, búsquedas con filtros, log TXT, indicadores, CSV, usuarios y JSON.

`npm run test:odoo` (6 pruebas): no necesitan la máquina virtual porque usan un Odoo simulado. Comprueban que se crea
el pedido en Odoo, que no se duplica al reenviar, que si Odoo está caído el pedido no se pierde y que solo se envía lo
que se debe.
