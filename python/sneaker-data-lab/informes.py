from datetime import datetime


def _kpi(res, nombre):
    k = res["kpis"]
    fila = k[k["indicador"] == nombre]
    return fila["valor"].iloc[0] if len(fila) else "-"


def _tabla(df, filas=10):
    if df is None or df.empty:
        return "_Sin datos._"
    d = df.head(filas)
    cab = "| " + " | ".join(map(str, d.columns)) + " |"
    sep = "|" + "---|" * len(d.columns)
    cuerpo = ["| " + " | ".join(str(v) for v in fila) + " |" for fila in d.itertuples(index=False)]
    return "\n".join([cab, sep, *cuerpo])


def ejecutivo(res, origen, fecha_corte, filtros):
    abc = res["df03_modelos_abc"]
    stock = res["df08_stock_cobertura"]
    rfm = res["df06_clientes_rfm"]
    tallas = res["df04_modelo_talla"]
    bajos = stock[stock["alerta_stock"] == "BAJO"] if "alerta_stock" in stock.columns else stock.iloc[0:0]
    riesgo = rfm[rfm["segmento_rfm"] == "En riesgo"]["cliente"].tolist()
    top = abc["modelo"].iloc[0] if "modelo" in abc.columns else "-"
    talla_top = _kpi(res, "Talla top")
    decisiones = [
        (
            "Priorizar la fabricación de los modelos de clase A",
            f"{top} es el modelo con más ingresos (clase A en el ABC).",
            "Concentra la mayor parte de la facturación.",
            "Asegurar materiales y turnos para los modelos A antes que para los C.",
            "df03_modelos_abc · gráfico 03_pareto",
            "Menos roturas en los modelos que más facturan.",
            "Pocos meses de historia: el ranking puede cambiar.",
        ),
        (
            "Reponer las variantes con stock bajo",
            f"{len(bajos)} combinaciones modelo-talla están por debajo del umbral.",
            "Con demanda activa podrían quedarse sin existencias.",
            "Revisar y reponer primero las de menor cobertura en semanas.",
            "df08_stock_cobertura",
            "Evitar pedidos que no se puedan servir.",
            "El stock es una foto de la fecha de corte, no un histórico.",
        ),
        (
            "Ajustar la producción a las tallas más pedidas",
            f"La talla más vendida es la {talla_top}.",
            "La demanda se concentra en tallas centrales.",
            "Fabricar más pares de las tallas centrales y menos de los extremos.",
            "df04_modelo_talla · gráfico 06_mapa_calor_talla",
            "Menos stock parado en tallas poco pedidas.",
            f"Basado en {int(tallas['total_pares'].sum()) if 'total_pares' in tallas.columns else 0} pares vendidos.",
        ),
        (
            "Potenciar los pedidos Custom para clubes",
            f"Los Custom suponen el {_kpi(res, '% ingresos Custom')} % de los ingresos.",
            "Son pedidos grandes de clubes y equipos.",
            "Campaña comercial dirigida a clubes y equipos.",
            "df05_custom_vs_estandar · gráfico 08_comparativa_custom",
            "Más ingresos por pedido.",
            "Pocos clientes concentran el importe: dependencia de grandes cuentas.",
        ),
        (
            "Recuperar clientes en riesgo",
            f"{len(riesgo)} cliente(s) llevan tiempo sin comprar: {', '.join(riesgo[:5]) or 'ninguno'}.",
            "Pueden estar dejando de comprar.",
            "Contactarles con una oferta antes de perderlos.",
            "df06_clientes_rfm · gráfico 07_dispersion_clientes",
            "Mantener la base de clientes.",
            "La recencia depende de la fecha de corte elegida.",
        ),
    ]
    partes = [
        "# Informe ejecutivo · SPEAKE",
        f"Origen de los datos: **{origen}** · fecha de corte: {fecha_corte:%Y-%m-%d} · "
        f"generado: {datetime.now():%Y-%m-%d %H:%M} · filtros: {filtros or 'ninguno'}",
        "",
        f"Ingresos válidos: **{_kpi(res, 'Ingresos (€)')} €** · pedidos de venta: **{_kpi(res, 'Pedidos de venta')}** · "
        f"pares: **{_kpi(res, 'Pares vendidos')}** · ticket medio: **{_kpi(res, 'Ticket medio (€)')} €**",
        "",
        "## Cinco decisiones priorizadas",
    ]
    for i, (titulo, obs, interp, prop, evid, impacto, limite) in enumerate(decisiones, 1):
        partes += [
            f"### {i}. {titulo}",
            f"- **Observación:** {obs}",
            f"- **Interpretación:** {interp}",
            f"- **Propuesta:** {prop}",
            f"- **Evidencia:** {evid}",
            f"- **Impacto esperado:** {impacto}",
            f"- **Limitación:** {limite}",
            f"- **Origen:** {origen}",
            "",
        ]
    return "\n".join(partes)


def tecnico(res, r, origen, lecturas, filtros):
    partes = [
        "# Informe técnico · SPEAKE",
        f"Origen: **{origen}** · fecha de corte: {r['fecha_corte']:%Y-%m-%d} · generado: {datetime.now():%Y-%m-%d %H:%M} · "
        f"filtros: {filtros or 'ninguno'} · tiempo de proceso: {r['segundos']} s",
        "",
        "## 1. Ficheros de entrada (manifiesto)",
        _tabla(r["manifiesto"]),
        "",
        "## 2. Calidad de los datos",
        _tabla(r["resumen_calidad"]),
        "",
        f"Incidencias registradas: {len(r['incidencias'])} (detalle en incidencias.csv).",
        "",
        "## 3. Reconciliación con SQL de Acceso a Datos",
        _tabla(res["df12_reconciliacion"]),
        "",
        "## 4. KPIs y fórmulas",
        _tabla(res["kpis"], 30),
        "",
        "## 5. Estadística descriptiva",
        _tabla(res["descriptivos"]),
        "",
        "## 6. Segmentación de clientes (KMeans)",
        _tabla(res["clustering_k"]),
        "",
        "Un clúster es un grupo matemático según recencia, frecuencia e importe; no equivale automáticamente a un "
        "segmento comercial RFM, que se define con umbrales de negocio.",
        "",
        "## 7. Gráficos",
        *[f"- **{n}.png:** {t}" for n, t in lecturas.items()],
        "",
        "## 8. Limitaciones y sesgos",
        "- Los datos reales tienen pocos pedidos y meses: medias móviles, cohortes y clustering pueden no ser calculables.",
        "- El stock es una foto de la fecha de corte, no un histórico de existencias.",
        "- Sin coste unitario no se calcula margen (df11).",
        "- Los datos sintéticos sirven para demostrar métodos, no describen la demanda real.",
    ]
    return "\n".join(partes)
