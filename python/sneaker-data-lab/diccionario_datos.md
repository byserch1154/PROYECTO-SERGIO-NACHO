# Diccionario de datos · contrato con Acceso a Datos

Todos los CSV: **UTF-8**, separador **coma**, decimal **punto**, fechas **AAAA-MM-DD**, primera fila = cabecera.
Origen: vistas `v_export_*` y `v_reconciliacion` de PostgreSQL (botón «Exportar CSV PSP/Python» del panel o `05_exportar_csv.sql`).
Moneda: euros, importes brutos. Los `id_*` son claves: sirven para unir tablas, nunca para sumar ni hacer medias.

## Ficheros de entrada

| Fichero | Campo | Significado | Tipo | Unidad | Valores permitidos | Si falta o es nulo |
|---|---|---|---|---|---|---|
| clientes.csv | id_cliente | Cliente | entero (clave) | – | único | R02 |
| | nombre | Nombre o alias ficticio | texto | – | – | se conserva |
| | tipo | Tipo de cliente | categoría | – | particular, club, equipo | se conserva |
| modelos.csv | id_modelo | Modelo | entero (clave) | – | único | R02 |
| | modelo | Nombre comercial | texto | – | – | – |
| | categoria | Familia | categoría | – | Urbano, Deportivo… | se conserva |
| pedidos.csv | id_pedido | Pedido | entero (clave) | – | único | R02 |
| | fecha | Fecha del pedido | fecha | día | fecha real | R04: se excluye |
| | id_cliente | Cliente | entero (clave ajena) | – | existe en clientes | R09 / R03 |
| | estado | Estado | categoría | – | pendiente, confirmado, entregado, cancelado | R07: se excluye |
| | tipo | Tipo de pedido | categoría | – | estandar, custom | R07: se excluye |
| lineas_pedido.csv | id_linea | Línea | entero (clave) | – | único | R02 |
| | id_pedido | Pedido | entero (clave ajena) | – | existe en pedidos | R03 |
| | id_modelo | Modelo | entero (clave ajena) | – | existe en modelos | R09 / R03 |
| | talla | Talla europea | entero | talla | 38–46 | R08: se excluye |
| | cantidad | Pares | entero | pares | > 0 | R05: se excluye |
| | precio_unitario | Precio por par | decimal | € | ≥ 0 | R06: se excluye |
| stock.csv | id_modelo, talla | Variante | clave compuesta | – | única | R11 |
| | stock_disponible | Existencias | entero | pares | ≥ 0 | R11: se excluye |
| | fecha_corte | Fecha de la foto del stock | fecha | día | – | – |
| reconciliacion_sql.csv | indicador, valor | Cifras de control calculadas en SQL | texto, decimal | – | – | df12 «NO CALCULABLE» |

## Reglas de negocio (config.py)
- **Venta válida** = pedido `confirmado` o `entregado`. Pendientes y cancelados son actividad, no venta.
- **Ingresos** = Σ cantidad × precio_unitario de las líneas de pedidos de venta.
- **Ticket medio** = ingresos / nº de pedidos de venta (nunca entre líneas).
- **Pedido único** = una fila por id_pedido: un pedido de 9 líneas cuenta como 1.
- **Fecha de corte** = fecha_corte del stock; si no hay, la última fecha de pedido.
- **ABC**: A hasta el 80 % acumulado de ingresos, B hasta el 95 %, C el resto.
- **RFM**: activo si recencia ≤ 60 días. Segmentos: Fiel (activo y ≥ 2 pedidos), Gran cuenta (importe ≥ percentil 75),
  Reciente ocasional (activo), En riesgo (resto), Sin compras válidas.
- **Cobertura** = stock / (pares vendidos en los últimos 28 días / 4) semanas; sin demanda → «N/D».
- **Margen**: no calculable, Acceso a Datos no exporta coste unitario.

## Reglas de calidad (pipeline.py)
| Código | Regla | Gravedad | Tratamiento |
|---|---|---|---|
| R01 | Fichero ausente, vacío o sin columnas obligatorias | bloqueante | no se carga nada |
| R02 | ID duplicado | bloqueante | no se publica |
| R03 | Clave huérfana (cliente, pedido o modelo inexistente) | bloqueante | no se publica |
| R04 | Fecha nula o imposible | recuperable | se excluye el pedido |
| R05 | Cantidad nula, cero o negativa | recuperable | se excluye la línea |
| R06 | Precio no numérico o negativo | recuperable | se excluye la línea |
| R07 | Estado o tipo fuera de catálogo | recuperable | se excluye el pedido |
| R08 | Talla fuera de 38–46 | recuperable | se excluye |
| R09 | Pedido sin cliente o línea sin modelo | recuperable | se excluye |
| R10 | Línea repetida (pedido, modelo, talla, precio) | advertencia | se conserva: puede ser otro color |
| R11 | Stock negativo o variante duplicada | recuperable | se excluye / se conserva la primera |
| R12 | Fecha posterior al corte, pedido de venta sin líneas, línea de pedido excluido | advertencia / recuperable | se conserva / se excluye |

## Variables derivadas (ingeniería de características)
| Familia | Variable | Cálculo | Nivel | Dónde |
|---|---|---|---|---|
| Calendario | anio, mes, trimestre, dia_semana | de la fecha del pedido | línea | pipeline.unir |
| Calendario | antiguedad_dias | fecha de corte − fecha del pedido | línea | pipeline.unir |
| Economía | importe_linea | cantidad × precio_unitario (€) | línea | pipeline.unir |
| Economía | ticket_pedido | Σ importe de las líneas (€) | pedido | df01 |
| Economía | precio_medio_par | ticket / pares (€) | pedido | df01 |
| Comportamiento | frequency, pct_custom, intervalo_medio_dias | pedidos de venta, % custom, días entre compras | cliente | df06 |
| Demanda | unidades_modelo_mes, demanda_mes_anterior, media_3_meses_previos | solo meses anteriores (sin datos futuros) | modelo-mes | demanda_modelo_mes |
| Operaciones | talla_mas_solicitada | talla con más pares | modelo | df04 |
| Operaciones | alerta_stock, cobertura_semanas | stock < 10; stock / demanda semanal | variante | df08 |

## DataFrames generados
| Nombre | Contenido |
|---|---|
| df_lineas_enriquecidas | una fila por línea con pedido, cliente, modelo y variables derivadas |
| df01_pedidos_unicos | una fila por pedido: pares, importe, nº líneas, ticket |
| df02_ventas_periodo | por mes: ingresos, pares, pedidos, ticket, variación %, media de 3 meses previos |
| df03_modelos_abc | ranking por € y por pares, peso, acumulado y clase ABC |
| df04_modelo_talla | pares por modelo y talla y % de cada talla dentro del modelo |
| df05_custom_vs_estandar | pares, ingresos, ticket, cuota de ingresos y tasa de cancelación por tipo |
| df06_clientes_rfm | recencia, frecuencia, importe y segmento por cliente |
| df07_cohortes | retención por mes de primera compra |
| df08_stock_cobertura | stock, demanda de 28 días, cobertura y alerta |
| df09_calidad | filas recibidas, válidas, rechazadas, nulos y referencias sin resolver por tabla |
| df10_anomalias | cantidades y precios atípicos por regla IQR |
| df11_margen | NO CALCULABLE: no hay coste |
| df12_reconciliacion | cifras de pandas frente a las de SQL |

## Datos sintéticos
`generador_datos.py` (semilla 42) crea en `datos_sinteticos/` 40 clientes, 12 modelos, 900 pedidos, unas 1.700 líneas
y 18 meses, con más ventas en otoño, tallas centrales más pedidas y pedidos Custom grandes de clubes. Es una simulación:
no describe la demanda real. `datos_sinteticos/con_incidencias/` es una copia con errores puestos a propósito para
probar las reglas de calidad.
