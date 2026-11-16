# 01 · Diseño: diagrama entidad-relación

El diagrama está hecho con Mermaid: al abrir este fichero en GitHub o en VS Code se ve dibujado.

```mermaid
erDiagram
    ROLES        ||--o{ PERMISOS     : "tiene"
    ROLES        ||--o{ USUARIOS     : "pertenece"
    CLIENTES     ||--o{ PEDIDOS      : "realiza"
    USUARIOS     ||--o{ PEDIDOS      : "crea (creado_por)"
    PEDIDOS      ||--|{ LINEAS_PEDIDO: "contiene"
    MODELOS      ||--o{ LINEAS_PEDIDO: "se pide en"
    MODELOS      ||--o{ STOCK        : "existencias por talla"
    USUARIOS     ||--o{ LOG_EVENTOS  : "responsable"
    MODELOS      ||--o{ COLORES_CATALOGO : "se vende en"
    COLORES_CATALOGO ||--o{ LINEAS_PEDIDO : "color elegido"
    PEDIDOS      ||--o| PEDIDOS_ODOO : "se envía a Odoo"

    ROLES { smallint id_rol PK  text nombre UK }
    PERMISOS { smallint id_rol PK,FK  text operacion PK  boolean permitido }
    USUARIOS { int id_usuario PK  text username UK  text password_hash  smallint id_rol FK  boolean activo  timestamptz fecha_creacion }
    CLIENTES { int id_cliente PK  text nombre  text email UK  text telefono  text tipo  date fecha_alta }
    MODELOS  { smallint id_modelo PK  text codigo UK  text nombre  text categoria  numeric precio_base }
    PEDIDOS  { int id_pedido PK  text referencia UK  int id_cliente FK  date fecha  text estado  text tipo  numeric total  int creado_por FK }
    LINEAS_PEDIDO { int id_linea PK  int id_pedido FK  smallint id_modelo FK  smallint talla  int cantidad  numeric precio_unitario  text color_cuerpo  text color_franja  text color_puntera  text color_talon  text color_suela  text color_cordones  varchar texto_suela  smallint id_color FK }
    STOCK    { smallint id_modelo PK,FK  smallint talla PK  int stock_disponible  timestamptz fecha_corte }
    LOG_EVENTOS { bigint id_evento PK  timestamptz fecha  text tabla  text operacion  text id_registro  int id_usuario FK  text resumen }
    COLORES_CATALOGO { smallint id_color PK  text codigo UK  smallint id_modelo FK  text nombre  boolean activo }
    PEDIDOS_ODOO { int id_pedido PK,FK  text pedido_odoo  int id_odoo  text estado  text mensaje  timestamptz actualizado }
```

## Tablas
| Tabla | Para qué sirve |
|---|---|
| `clientes` | Particulares, clubes y equipos. |
| `modelos` | Los 6 modelos de la web, con el mismo código, nombre y precio. |
| `pedidos` | La cabecera del pedido: cliente, fecha, estado, tipo y total. |
| `lineas_pedido` | Cada línea es un modelo en una talla, con su cantidad y, si es Custom, sus 6 colores y el texto. |
| `stock` | Cuántos pares hay de cada modelo en cada talla. |
| `roles`, `permisos`, `usuarios` | Los usuarios de la aplicación, su rol y qué puede hacer cada rol. |
| `log_eventos` | La auditoría: quién creó, cambió o borró cada pedido y cuándo. |
| `colores_catalogo` | Las 3 combinaciones de color que se venden de cada modelo. |
| `pedidos_odoo` | Qué pedido de Odoo corresponde a cada uno y si el envío dio error. |

## Por qué está diseñada así
1. **Cabecera y líneas.** Un pedido tiene varias tallas (SO003 tiene 9 líneas). Así el cliente y la fecha no se
   repiten en cada línea.
2. **Los colores van en la línea.** Cada talla podría llevar colores distintos. Una regla obliga a que estén los 6
   colores o ninguno.
3. **El total y el tipo los calcula la base.** Los triggers los recalculan cada vez que cambian las líneas, así nunca
   hay un total que no cuadre.
4. **La referencia se genera sola** (SO + el número con ceros). Es la que une el pedido con Odoo y con Java.
5. **Tallas y colores con valores fijos.** Solo se admiten las tallas 38 a 46 y los 8 colores del configurador.
6. **No hay borrado en cascada.** Borrar un pedido nunca arrastra datos por accidente: primero hay que borrar sus líneas.
7. **No se repiten líneas.** No puede haber dos líneas iguales (mismo pedido, modelo, talla y colores).
8. **El stock nunca baja de cero.** Lo impide una regla de la tabla, además del trigger.
9. **El precio se guarda en la línea.** Si mañana cambia el precio del catálogo, los pedidos antiguos no cambian.
10. **Los pedidos se cancelan, no se borran.** Así queda la historia en la auditoría. Borrar de verdad solo puede el
    administrador y solo pedidos pendientes.
