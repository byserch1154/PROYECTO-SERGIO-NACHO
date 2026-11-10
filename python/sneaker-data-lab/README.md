# sneaker-data-lab · Python

Lee los CSV exportados desde la base de datos SPEAKE (`entrada_acc/`), los valida, calcula KPIs y los
muestra en un dashboard de Streamlit que se actualiza cada 60 segundos.

```
entrada_acc/*.csv ─► pipeline.py (carga y validación) ─► analiticas.py (KPIs y tablas)
                                                         ├─► main.py         (consola, outputs/)
                                                         └─► app_dashboard.py (Streamlit)
```

## Uso
```bat
pip install -r requirements.txt
python main.py
streamlit run app_dashboard.py
python -m pytest
```

## Estado
| Parte | Estado |
|---|---|
| Carga de los 5 CSV y columnas obligatorias | hecho |
| Validación: fechas, duplicados, cantidades, claves huérfanas | hecho |
| Merge de líneas con pedidos, clientes y modelos | hecho |
| KPIs básicos, ventas por mes y ranking de modelos | hecho |
| Dashboard con refresco cada 60 s | hecho |
| 5 pruebas pytest | hecho |
| Más reglas de calidad y tabla de incidencias | **pendiente** |
| Más KPIs, matriz modelo × talla, RFM, stock | **pendiente** |
| Gráficos PNG e informe | **pendiente** |
| Filtros y vistas del dashboard | **pendiente** |
| Clustering y predicción (scikit-learn) | **pendiente** |

Cada parte pendiente está marcada con `TODO` en el código.
