from datetime import datetime


# saca el valor de un KPI por su nombre
def valor_kpi(res, nombre):
    k = res["kpis"]
    fila = k[k["indicador"] == nombre]
    if len(fila) == 0:
        return "-"
    return fila["valor"].iloc[0]


# pasa un dataframe a tabla de markdown (| a | b |)
def tabla_md(df, filas=10):
    if df is None or len(df) == 0:
        return "_Sin datos._"
    d = df.head(filas)

    columnas = []
    for c in d.columns:
        columnas.append(str(c))
    lineas = ["| " + " | ".join(columnas) + " |"]
    lineas.append("|" + "---|" * len(columnas))

    for i in range(len(d)):
        valores = []
        for v in d.iloc[i]:
            valores.append(str(v))
        lineas.append("| " + " | ".join(valores) + " |")
    return "\n".join(lineas)


# informe corto para direccion con 5 decisiones
def ejecutivo(res, origen, fecha_corte, filtros):
    abc = res["df03_modelos_abc"]
    stock = res["df08_stock_cobertura"]
    rfm = res["df06_clientes_rfm"]
    tallas = res["df04_modelo_talla"]

    if "alerta_stock" in stock.columns:
        n_bajos = len(stock[stock["alerta_stock"] == "BAJO"])
    else:
        n_bajos = 0

    en_riesgo = list(rfm[rfm["segmento_rfm"] == "En riesgo"]["cliente"])
    if len(en_riesgo) > 0:
        nombres_riesgo = ", ".join(en_riesgo[:5])
    else:
        nombres_riesgo = "ninguno"

    if "modelo" in abc.columns:
        modelo_top = abc["modelo"].iloc[0]
    else:
        modelo_top = "-"

    if "total_pares" in tallas.columns:
        total_pares = int(tallas["total_pares"].sum())
    else:
        total_pares = 0

    # cada decision: titulo, observacion, interpretacion, propuesta, evidencia, impacto, limitacion
    decisiones = [
        ["Priorizar la fabricación de los modelos de clase A",
         modelo_top + " es el modelo con más ingresos (clase A en el ABC).",
         "Concentra la mayor parte de la facturación.",
         "Asegurar materiales y turnos para los modelos A antes que para los C.",
         "df03_modelos_abc · gráfico 03_pareto",
         "Menos roturas en los modelos que más facturan.",
         "Pocos meses de historia: el ranking puede cambiar."],
        ["Reponer las variantes con stock bajo",
         str(n_bajos) + " combinaciones modelo-talla están por debajo del umbral.",
         "Con demanda activa podrían quedarse sin existencias.",
         "Revisar y reponer primero las de menor cobertura en semanas.",
         "df08_stock_cobertura",
         "Evitar pedidos que no se puedan servir.",
         "El stock es una foto de la fecha de corte, no un histórico."],
        ["Ajustar la producción a las tallas más pedidas",
         "La talla más vendida es la " + str(valor_kpi(res, "Talla top")) + ".",
         "La demanda se concentra en tallas centrales.",
         "Fabricar más pares de las tallas centrales y menos de los extremos.",
         "df04_modelo_talla · gráfico 06_mapa_calor_talla",
         "Menos stock parado en tallas poco pedidas.",
         "Basado en " + str(total_pares) + " pares vendidos."],
        ["Potenciar los pedidos Custom para clubes",
         "Los Custom suponen el " + str(valor_kpi(res, "% ingresos Custom")) + " % de los ingresos.",
         "Son pedidos grandes de clubes y equipos.",
         "Campaña comercial dirigida a clubes y equipos.",
         "df05_custom_vs_estandar · gráfico 08_comparativa_custom",
         "Más ingresos por pedido.",
         "Pocos clientes concentran el importe: dependencia de grandes cuentas."],
        ["Recuperar clientes en riesgo",
         str(len(en_riesgo)) + " cliente(s) llevan tiempo sin comprar: " + nombres_riesgo + ".",
         "Pueden estar dejando de comprar.",
         "Contactarles con una oferta antes de perderlos.",
         "df06_clientes_rfm · gráfico 07_dispersion_clientes",
         "Mantener la base de clientes.",
         "La recencia depende de la fecha de corte elegida."],
    ]

    if not filtros:
        filtros = "ninguno"
    ahora = datetime.now().strftime("%Y-%m-%d %H:%M")

    texto = []
    texto.append("# Informe ejecutivo · SPEAKE")
    texto.append("Origen de los datos: **" + origen + "** · fecha de corte: " + fecha_corte.strftime("%Y-%m-%d")
                 + " · generado: " + ahora + " · filtros: " + str(filtros))
    texto.append("")
    texto.append("Ingresos válidos: **" + str(valor_kpi(res, "Ingresos (€)")) + " €** · pedidos de venta: **"
                 + str(valor_kpi(res, "Pedidos de venta")) + "** · pares: **" + str(valor_kpi(res, "Pares vendidos"))
                 + "** · ticket medio: **" + str(valor_kpi(res, "Ticket medio (€)")) + " €**")
    texto.append("")
    texto.append("## Cinco decisiones priorizadas")

    numero = 1
    for d in decisiones:
        texto.append("### " + str(numero) + ". " + d[0])
        texto.append("- **Observación:** " + d[1])
        texto.append("- **Interpretación:** " + d[2])
        texto.append("- **Propuesta:** " + d[3])
        texto.append("- **Evidencia:** " + d[4])
        texto.append("- **Impacto esperado:** " + d[5])
        texto.append("- **Limitación:** " + d[6])
        texto.append("- **Origen:** " + origen)
        texto.append("")
        numero = numero + 1
    return "\n".join(texto)


# informe tecnico: ficheros, calidad, conciliacion, kpis, estadistica, clustering y graficos
def tecnico(res, r, origen, lecturas, filtros):
    if not filtros:
        filtros = "ninguno"
    ahora = datetime.now().strftime("%Y-%m-%d %H:%M")

    texto = []
    texto.append("# Informe técnico · SPEAKE")
    texto.append("Origen: **" + origen + "** · fecha de corte: " + r["fecha_corte"].strftime("%Y-%m-%d")
                 + " · generado: " + ahora + " · filtros: " + str(filtros)
                 + " · tiempo de proceso: " + str(r["segundos"]) + " s")
    texto.append("")
    texto.append("## 1. Ficheros de entrada (manifiesto)")
    texto.append(tabla_md(r["manifiesto"]))
    texto.append("")
    texto.append("## 2. Calidad de los datos")
    texto.append(tabla_md(r["resumen_calidad"]))
    texto.append("")
    texto.append("Incidencias registradas: " + str(len(r["incidencias"])) + " (detalle en incidencias.csv).")
    texto.append("")
    texto.append("## 3. Reconciliación con SQL de Acceso a Datos")
    texto.append(tabla_md(res["df12_reconciliacion"]))
    texto.append("")
    texto.append("## 4. KPIs y fórmulas")
    texto.append(tabla_md(res["kpis"], 30))
    texto.append("")
    texto.append("## 5. Estadística descriptiva")
    texto.append(tabla_md(res["descriptivos"]))
    texto.append("")
    texto.append("## 6. Segmentación de clientes (KMeans)")
    texto.append(tabla_md(res["clustering_k"]))
    texto.append("")
    texto.append("Un clúster es un grupo matemático según recencia, frecuencia e importe; no equivale automáticamente a un "
                 "segmento comercial RFM, que se define con umbrales de negocio.")
    texto.append("")
    texto.append("## 7. Gráficos")
    for nombre in lecturas:
        texto.append("- **" + nombre + ".png:** " + lecturas[nombre])
    texto.append("")
    texto.append("## 8. Limitaciones y sesgos")
    texto.append("- Los datos reales tienen pocos pedidos y meses: medias móviles, cohortes y clustering pueden no ser calculables.")
    texto.append("- El stock es una foto de la fecha de corte, no un histórico de existencias.")
    texto.append("- Sin coste unitario no se calcula margen (df11).")
    texto.append("- Los datos sintéticos sirven para demostrar métodos, no describen la demanda real.")
    return "\n".join(texto)
