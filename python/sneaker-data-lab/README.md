# sneaker-data-lab · Python

Lee los CSV exportados desde la base de datos SPEAKE (`entrada_acc/`), los valida, calcula indicadores
y los muestra en un dashboard de Streamlit que se actualiza cada 60 segundos.

```
entrada_acc/*.csv ─► pipeline.py ─► analiticas.py ─► main.py          (CSV + 8 gráficos en outputs/)
                     (carga y       (KPIs, tablas,   app_dashboard.py (Streamlit, 5 vistas, 4 filtros)
                      validación)    KMeans, regresión)
```

| Fichero | Qué hace |
|---|---|
| `config.py` | Rutas, columnas obligatorias, estados de venta, refresco |
| `pipeline.py` | Carga los 5 CSV, aplica 11 reglas de calidad y une las tablas |
| `analiticas.py` | KPIs, ventas por mes, ranking, modelo × talla, Custom/estándar, RFM, stock, KMeans y regresión |
| `graficos.py` | 8 gráficos PNG con Matplotlib |
| `main.py` | Ejecución por consola, guarda resultados y log |
| `app_dashboard.py` | Dashboard: Dirección, Producto, Clientes, Almacén y Calidad |
| `tests/` | 8 pruebas con pytest |

```bat
py -m pip install -r requirements.txt
py main.py
py -m pytest
py -m streamlit run app_dashboard.py
```

Para usar datos nuevos: exportar desde el panel (*Exportar CSV PSP/Python*) o con `05_exportar_csv.sql`
y copiar los 5 CSV a `entrada_acc/`.
