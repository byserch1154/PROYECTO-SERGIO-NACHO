# SPEAKE · Fábrica de zapatillas

Proyecto Intermodular de 2º DAM. SPEAKE fabrica y vende zapatillas: 6 modelos de catálogo y una línea Custom en la
que el cliente elige los colores y un texto para la suela. Clubes y equipos piden muchos pares repartidos por tallas.

**Equipo:** Sergio Sierra y Nacho.

## Cómo encaja todo
Un mismo pedido (por ejemplo SO003, Club Halcones, 40 pares) pasa por todas las partes con la misma referencia:

```
Web ──► Express ──► PostgreSQL ──(al confirmar)──► Odoo: venta, fabricación, entrega y factura
                        │
                        └──(exportar CSV)──► Java (ficha para el taller)
                                        └──► Python (análisis y dashboard)
```

| Carpeta | Qué hay | Asignatura |
|---|---|---|
| `lenguaje-de-marcas/` | La web: 5 páginas HTML, un único CSS y el configurador de zapatillas | Lenguaje de Marcas · Desarrollo de Interfaces |
| `base-de-datos/` | Scripts SQL de PostgreSQL, diagrama E-R y matriz de permisos | Acceso a Datos |
| `backend-express/` | Servidor Node que conecta la web con PostgreSQL y con Odoo, y panel de gestión | Acceso a Datos · Sistemas de Gestión |
| `java/untitled/` | Proceso padre que lanza 3 procesos hijos para preparar la ficha del taller | PSP |
| `python/sneaker-data-lab/` | Limpieza de datos, KPIs y dashboard en Streamlit | Python |
| `docs/` | Memoria técnica y manual de demostración | Todas |

Odoo está instalado en una máquina virtual y no va en el repositorio.

## Qué hace falta
PostgreSQL 14 o superior con pgAdmin · Node.js 20 o superior · JDK 17 o superior (IntelliJ) · Python 3.12 o superior.

## Puesta en marcha

**1. Base de datos.** Crear una base vacía llamada `SPEAKE` y ejecutar en pgAdmin, en este orden:
`base-de-datos/base-de-datos/bd/01_esquema.sql` y `02_datos.sql`, y después
`backend-express/sql/07_web_backend.sql`, `10_integracion_odoo.sql` y `11_colores_catalogo.sql`.

**2. Backend y web.**
```bat
cd backend-express
copy .env.example .env
npm install
npm start
```
En el `.env` se pone la contraseña de PostgreSQL y los datos de Odoo. Ese fichero no se sube a GitHub.
Después: web en `http://localhost:3000` y panel de gestión en `http://localhost:3000/gestion/`.

**3. Java.** Abrir `java/untitled` en IntelliJ y pulsar Run sobre `Main`. Lee `datos/ficha_fabricacion.csv` y deja la
ficha y el log en `salida/`. Para probar otros casos se cambian los argumentos en Run → Edit Configurations:

| Argumentos | Qué pasa |
|---|---|
| (ninguno) | Procesa 3 pedidos y genera sus fichas. Salida 0 |
| `datos/pedido_erroneo.csv` | El validador encuentra 4 errores y se para. Salida 1 |
| `datos/pedido_sin_columnas.csv` | Faltan columnas. Salida 1 |
| `datos/no_existe.csv` | El fichero no existe. Salida 2 |
| `--retardo-ms 8000 --timeout 3` | El analizador tarda demasiado y el padre lo corta. TIMEOUT, salida 1 |
| `--paralelo` | Procesa los pedidos a la vez con 3 hilos |
| `datos/pedido_SO003.json` | Lee el pedido en JSON. Misma ficha que con el CSV |
| `datos/pedido_roto.json` | JSON incompleto. Salida 2 |

**4. Python.**
```bat
cd python\sneaker-data-lab
py -m pip install -r requirements.txt
py main.py
py -m streamlit run app_dashboard.py
```

## Pasar datos de la base a Java y Python
En el panel de gestión, botón **Exportar CSV PSP/Python**. Deja los ficheros en `backend-express/data/export/`:
`ficha_fabricacion.csv` se copia a `java/untitled/datos/` y el resto a `python/sneaker-data-lab/entrada_acc/`.
También se puede hacer desde pgAdmin con `05_exportar_csv.sql`.

## Pruebas
| Parte | Cómo | Resultado |
|---|---|---|
| Base de datos | `04_pruebas.sql` y `backend-express/sql/12_pruebas_web_odoo.sql` en pgAdmin | todas superadas |
| Backend | `npm test` y `npm run test:odoo` | 9 y 6 correctas |
| Java | los 8 casos de la tabla de arriba | el código esperado en cada uno |
| Python | `py -m pytest` | 17 correctas |

Usuarios de prueba del panel: `admin` / `Admin#2026`, `comercial1` / `Comercial#2026`, `almacen1` / `Almacen#2026`.
