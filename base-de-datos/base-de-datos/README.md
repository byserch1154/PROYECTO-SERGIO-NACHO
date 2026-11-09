# Base de datos · Sneaker Factory (Acceso a Datos)

Requisitos: PostgreSQL 14 o superior (necesita la extensión `pgcrypto`, incluida en `contrib`).

## Reconstruir desde cero
```bash
createdb sneaker_factory
psql -d sneaker_factory -v ON_ERROR_STOP=1 -f bd/01_esquema.sql     # tablas, restricciones, funciones y triggers
psql -d sneaker_factory -v ON_ERROR_STOP=1 -f bd/02_datos.sql       # roles, usuarios ficticios, catálogo, stock y 12 pedidos
psql -d sneaker_factory -f bd/04_pruebas.sql                         # pruebas automáticas (terminan en ROLLBACK)
```
Comprobar: el último mensaje debe ser `=== TODAS LAS PRUEBAS SUPERADAS CON ÉXITO ===`.

## Contenido de `bd/`
| Fichero | Qué es |
|---|---|
| `01_esquema.sql` | Tablas, PK/FK/CHECK, funciones de permisos, triggers (importes, stock, auditoría), vistas de exportación |
| `02_datos.sql` | Roles, matriz de permisos, 3 usuarios ficticios, 6 modelos, 6 clientes, stock y 12 pedidos (4 Custom) |
| `03_consultas.sql` | 12 consultas de explotación |
| `04_pruebas.sql` | Pruebas de restricciones, permisos, triggers, rollback, coherencia e indicadores |
| `05_exportar_csv.sql` | Exportación a CSV con `\copy` (carpeta `bd/export/`) |
| `06_transacciones.sql` | Demo de COMMIT / ROLLBACK / stock / DELETE (dos terminales) |

## Usuarios de prueba (ficticios)
`admin / Admin#2026` · `comercial1 / Comercial#2026` · `almacen1 / Almacen#2026`

## Exportar CSV (para PSP y Python)
Desde la carpeta `bd/`: `psql -d sneaker_factory -f 05_exportar_csv.sql`. Repetirlo genera una nueva exportación.

## Documentación (`docs/`)
`01_diseno_ER.md` (diagrama y decisiones) · `02_matriz_permisos.md` · `03_memoria_acceso_datos.md`
