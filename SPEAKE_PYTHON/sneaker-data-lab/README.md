# sneaker-data-lab · Python

Lee los CSV que exporta la base de datos SPEAKE, comprueba que están bien, calcula los indicadores del negocio y los
enseña en un dashboard de Streamlit que se recalcula solo cada 60 segundos.

```
entrada_acc/*.csv ─► pipeline.py ─► analiticas.py ─► main.py           (CSV, 8 gráficos e informes en outputs/)
                     (cargar y       (DataFrames,     app_dashboard.py  (dashboard)
                      comprobar)      KPIs, clientes)
```

## Instalación
Hace falta Python 3.12 o superior. Las librerías están en `requirements.txt` (pandas, NumPy, Matplotlib,
scikit-learn, Streamlit y pytest):
```bat
py -m pip install -r requirements.txt
```

## Cómo se ejecuta
```bat
py main.py                       :: datos reales
py main.py --modo sintetico      :: datos sintéticos
py main.py --tarea calidad       :: solo una parte: calidad, descriptivo, segmentacion, informe o todo
py main.py --desde 2026-09-01 --tipo custom --modelo "SPEAKE Pulse" --talla 42 43 --estado confirmado
py -m streamlit run app_dashboard.py
py -m pytest
```
Los resultados se guardan en `outputs/real/` o en `outputs/sintetico/`, nunca mezclados. Cada ejecución queda
apuntada en `logs/ejecuciones.log`.

## De dónde salen los datos
De la base de datos de Acceso a Datos. En el panel de gestión se pulsa **Exportar CSV PSP/Python** (o se ejecuta
`05_exportar_csv.sql` en pgAdmin) y se copian a `entrada_acc/` estos 6 ficheros:
`clientes.csv`, `modelos.csv`, `pedidos.csv`, `lineas_pedido.csv`, `stock.csv` y `reconciliacion_sql.csv`.
Las columnas de cada uno, las reglas de negocio y las de calidad están en `diccionario_datos.md`.

## Real y sintético
- **Real** (`entrada_acc/`): lo que sale de la base de datos. Es lo que enseña el dashboard.
- **Sintético** (`datos_sinteticos/`): un histórico inventado de 900 pedidos que crea `py generador_datos.py` con
  semilla fija. Solo sirve para demostrar la segmentación de clientes, porque con los datos reales hay muy pocos
  clientes. Siempre aparece rotulado como SINTÉTICO.

## Filtros del dashboard
Fecha desde y hasta, modelo, talla, tipo de pedido, estado y cliente. Se pueden combinar, se mantienen entre
refrescos y se quitan con **Restablecer filtros**. Los KPIs se calculan solo con los pedidos filtrados.

## Actualización cada 60 segundos
Cada 60 segundos (o al pulsar **Actualizar ahora**) el dashboard vuelve a leer los CSV y lo recalcula todo con la
misma foto de datos. Arriba se ve la última comprobación, la última actualización válida, las filas válidas,
el tiempo que ha tardado y el estado: correcto, sin cambios, datos inválidos o error de carga.

**Probar con datos nuevos:** hacer un pedido en la web, confirmarlo en el panel, exportar y copiar los CSV.
En el siguiente ciclo los KPIs cambian y la conciliación con SQL sigue cuadrando.

**Si llega un CSV erróneo:** el dashboard avisa, no publica cálculos a medias y sigue enseñando el último resultado
bueno marcado como DESACTUALIZADO. Al volver a exportar un CSV correcto, se recupera solo en el siguiente ciclo.
