# Informe técnico · SPEAKE
Origen: **ACC · REAL** · fecha de corte: 2026-11-05 · generado: 2026-11-12 09:58 · filtros: ninguno · tiempo de proceso: 0.24 s

## 1. Ficheros de entrada (manifiesto)
| fichero | existe | fecha_analisis | filas | columnas | bytes | modificado |
|---|---|---|---|---|---|---|
| clientes.csv | True | 2026-11-12 09:58:56 | 6 | 3 | 178 | 2026-11-12 09:51:35 |
| modelos.csv | True | 2026-11-12 09:58:56 | 6 | 3 | 165 | 2026-11-12 09:51:36 |
| pedidos.csv | True | 2026-11-12 09:58:56 | 12 | 5 | 446 | 2026-11-12 09:51:37 |
| lineas_pedido.csv | True | 2026-11-12 09:58:56 | 26 | 6 | 543 | 2026-11-12 09:51:36 |
| stock.csv | True | 2026-11-12 09:58:56 | 54 | 4 | 1066 | 2026-11-12 09:51:38 |
| reconciliacion_sql.csv | True | 2026-11-12 09:58:56 | 6 | 2 | 131 | 2026-11-12 09:51:37 |

## 2. Calidad de los datos
| tabla | filas_entrada | filas_validas | filas_rechazadas | pct_calidad | nulos | bloqueantes | recuperables | advertencias |
|---|---|---|---|---|---|---|---|---|
| clientes | 6 | 6 | 0 | 100.0 | 0 | 0 | 0 | 0 |
| modelos | 6 | 6 | 0 | 100.0 | 0 | 0 | 0 | 0 |
| pedidos | 12 | 12 | 0 | 100.0 | 0 | 0 | 0 | 0 |
| lineas_pedido | 26 | 26 | 0 | 100.0 | 0 | 0 | 0 | 0 |
| stock | 54 | 54 | 0 | 100.0 | 0 | 0 | 0 | 0 |

Incidencias registradas: 0 (detalle en incidencias.csv).

## 3. Reconciliación con SQL de Acceso a Datos
| indicador | valor_sql | valor_pandas | diferencia | coincide |
|---|---|---|---|---|
| pedidos_totales | 12.0 | 12.0 | 0.0 | sí |
| lineas_totales | 26.0 | 26.0 | 0.0 | sí |
| pedidos_venta | 7.0 | 7.0 | 0.0 | sí |
| pares_vendidos | 59.0 | 59.0 | 0.0 | sí |
| importe_ventas | 7191.0 | 7191.0 | 0.0 | sí |
| clientes_con_venta | 5.0 | 5.0 | 0.0 | sí |

## 4. KPIs y fórmulas
| indicador | valor | formula |
|---|---|---|
| Pedidos únicos | 12 | nº id_pedido distintos (toda la actividad) |
| Pendientes | 3 | pedidos con estado pendiente |
| Confirmados | 4 | pedidos con estado confirmado |
| Entregados | 3 | pedidos con estado entregado |
| Cancelados | 2 | pedidos con estado cancelado |
| Pedidos de venta | 7 | confirmados + entregados |
| Pares vendidos | 59 | Σ cantidad de pedidos de venta |
| Ingresos (€) | 7191.0 | Σ cantidad × precio de pedidos de venta |
| Ticket medio (€) | 1027.29 | ingresos / pedidos de venta |
| Pares por pedido | 8.43 | pares / pedidos de venta |
| % pedidos Custom | 42.9 | pedidos custom / pedidos de venta |
| % pares Custom | 89.8 | pares custom / pares vendidos |
| % ingresos Custom | 91.6 | ingresos custom / ingresos |
| Modelo top | SPEAKE Pulse | modelo con más ingresos |
| Talla top | 42 | talla con más pares |
| Cliente top | Club Halcones | cliente con más ingresos |
| Variación último mes % | -85.7 | ingresos último mes / mes anterior − 1 |
| Pareto 20 % modelos % | 74.8 | ingresos del 20 % de modelos con más ventas / ingresos |
| Variantes con stock bajo | 5 | modelo-talla con stock < 10 |

## 5. Estadística descriptiva
| variable | n | media | mediana | moda | desviacion | p25 | p75 | iqr | min | max |
|---|---|---|---|---|---|---|---|---|---|---|
| ticket_pedido | 7 | 1027.29 | 197.0 | 89.0 | 1873.84 | 109.5 | 763.0 | 653.5 | 89.0 | 5160.0 |
| pares | 7 | 8.43 | 2.0 | 1.0 | 14.48 | 1.0 | 7.0 | 6.0 | 1.0 | 40.0 |
| precio_medio_par | 7 | 107.64 | 109.0 | 109.0 | 13.65 | 98.75 | 114.5 | 15.75 | 89.0 | 129.0 |

## 6. Segmentación de clientes (KMeans)
| estado | motivo |
|---|---|
| NO CALCULABLE | Solo 5 clientes con compras (mínimo 8): usar el histórico sintético |

Un clúster es un grupo matemático según recencia, frecuencia e importe; no equivale automáticamente a un segmento comercial RFM, que se define con umbrales de negocio.

## 7. Gráficos
- **01_serie_mensual.png:** El mes con más ingresos es 2026-08.
- **02_ranking_modelos.png:** SPEAKE Pulse concentra el 74.8 % de los ingresos.
- **03_pareto.png:** 2 modelo(s) suman el 80 % de los ingresos.
- **04_histograma_ticket.png:** La mediana (197 €) representa mejor el pedido típico que la media, porque los pedidos de club la disparan.
- **05_boxplot_tipo.png:** Los pedidos Custom suelen tener más pares: son pedidos de clubes y equipos.
- **06_mapa_calor_talla.png:** Las tallas centrales (41-43) concentran la demanda.
- **07_dispersion_clientes.png:** Arriba a la derecha están los clientes más valiosos.
- **08_comparativa_custom.png:** Compara el peso en euros con la tasa de cancelación de cada tipo.

## 8. Limitaciones y sesgos
- Los datos reales tienen pocos pedidos y meses: medias móviles, cohortes y clustering pueden no ser calculables.
- El stock es una foto de la fecha de corte, no un histórico de existencias.
- Sin coste unitario no se calcula margen (df11).
- Los datos sintéticos sirven para demostrar métodos, no describen la demanda real.