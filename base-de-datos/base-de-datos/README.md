# Base de datos · SPEAKE (Acceso a Datos)

Hace falta PostgreSQL 14 o superior (usa la extensión `pgcrypto`, que viene incluida).

## Montarla desde cero
Crear una base vacía llamada `SPEAKE` y ejecutar en pgAdmin (Query Tool) o con psql, en este orden:
```bash
createdb SPEAKE
psql -d SPEAKE -v ON_ERROR_STOP=1 -f bd/01_esquema.sql                       # tablas, restricciones, funciones y triggers
psql -d SPEAKE -v ON_ERROR_STOP=1 -f bd/02_datos.sql                         # roles, usuarios de prueba, catálogo, stock y 12 pedidos
psql -d SPEAKE -v ON_ERROR_STOP=1 -f ../../backend-express/sql/07_web_backend.sql
psql -d SPEAKE -v ON_ERROR_STOP=1 -f ../../backend-express/sql/10_integracion_odoo.sql
psql -d SPEAKE -v ON_ERROR_STOP=1 -f ../../backend-express/sql/11_colores_catalogo.sql
psql -d SPEAKE -f bd/04_pruebas.sql                                           # pruebas automáticas (terminan en ROLLBACK)
```
Si todo va bien, el último mensaje de las pruebas es `=== TODAS LAS PRUEBAS SUPERADAS CON ÉXITO ===`.

## Contenido de `bd/`
| Fichero | Qué es |
|---|---|
| `01_esquema.sql` | Tablas, PK/FK/CHECK, funciones de permisos, triggers (importes, stock y auditoría) y vistas de exportación |
| `02_datos.sql` | Roles, permisos, 3 usuarios de prueba, 6 modelos, 6 clientes, stock y 12 pedidos (4 Custom) |
| `03_consultas.sql` | 12 consultas de explotación |
| `04_pruebas.sql` | Pruebas de restricciones, permisos, triggers, rollback, coherencia e indicadores |
| `05_exportar_csv.sql` | Exportación a CSV con `\copy` (carpeta `bd/export/`) |
| `06_transacciones.sql` | Ejemplo de COMMIT, ROLLBACK, stock y DELETE (con dos terminales) |

## Usuarios de prueba (ficticios)
`admin / Admin#2026` · `comercial1 / Comercial#2026` · `almacen1 / Almacen#2026`

## Exportar CSV para Java y Python
Desde la carpeta `bd/`: `psql -d SPEAKE -f 05_exportar_csv.sql`. También se puede hacer desde el panel de gestión con
el botón «Exportar CSV PSP/Python».

## Documentación
El diagrama entidad-relación, la matriz de permisos y la explicación de todo están en la memoria de Acceso a Datos
(`SERGIO-SIERRA-NACHO-MEMORIA_ACCESO_DATOS.docx`).
