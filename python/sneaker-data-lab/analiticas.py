import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

import config


def no_calculable(motivo):
    return pd.DataFrame([{"estado": "NO CALCULABLE", "motivo": motivo}])


def filtrar(lineas, desde=None, hasta=None, modelos=None, tallas=None, tipos=None, estados=None, clientes=None):
    f = lineas
    if desde is not None:
        f = f[f["fecha"] >= pd.Timestamp(desde)]
    if hasta is not None:
        f = f[f["fecha"] <= pd.Timestamp(hasta)]
    for col, valores in [("modelo", modelos), ("talla", tallas), ("tipo", tipos), ("estado", estados), ("nombre", clientes)]:
        if valores:
            f = f[f[col].isin(valores)]
    return f


def df01_pedidos_unicos(lineas):
    p = (
        lineas.groupby("id_pedido")
        .agg(
            fecha=("fecha", "first"),
            cliente=("nombre", "first"),
            estado=("estado", "first"),
            tipo=("tipo", "first"),
            es_venta=("es_venta", "first"),
            n_lineas=("id_linea", "nunique"),
            pares=("cantidad", "sum"),
            ticket_pedido=("importe_linea", "sum"),
        )
        .reset_index()
    )
    p["precio_medio_par"] = (p["ticket_pedido"] / p["pares"]).round(2)
    return p


def df02_ventas_periodo(lineas):
    v = lineas[lineas["es_venta"]]
    if v.empty:
        return no_calculable("No hay ventas válidas en el filtro")
    m = (
        v.groupby(pd.Grouper(key="fecha", freq="MS"))
        .agg(ingresos=("importe_linea", "sum"), pares=("cantidad", "sum"), pedidos=("id_pedido", "nunique"))
        .reset_index()
    )
    m["mes"] = m["fecha"].dt.to_period("M").astype(str)
    m["ticket_medio"] = (m["ingresos"] / m["pedidos"]).round(2)
    m["var_ingresos_pct"] = (m["ingresos"].pct_change() * 100).round(1)
    m["media_3m_previos"] = m["ingresos"].shift(1).rolling(3, min_periods=3).mean().round(2)
    m["var_interanual_pct"] = (m["ingresos"].pct_change(12) * 100).round(1) if len(m) > 12 else np.nan
    return m.drop(columns="fecha")[["mes", "pedidos", "pares", "ingresos", "ticket_medio", "var_ingresos_pct", "media_3m_previos", "var_interanual_pct"]]


def df03_abc(lineas):
    v = lineas[lineas["es_venta"]]
    if v.empty:
        return no_calculable("No hay ventas válidas en el filtro")
    r = v.groupby("modelo").agg(ingresos=("importe_linea", "sum"), pares=("cantidad", "sum")).sort_values("ingresos", ascending=False).reset_index()
    r["peso_pct"] = (100 * r["ingresos"] / r["ingresos"].sum()).round(1)
    r["acumulado_pct"] = r["peso_pct"].cumsum().round(1)
    r["clase"] = pd.cut(r["acumulado_pct"].shift(fill_value=0), [-1, config.ABC_A * 100, config.ABC_B * 100, 101], labels=["A", "B", "C"])
    r["ranking_pares"] = r["pares"].rank(ascending=False, method="min").astype(int)
    return r


def df04_modelo_talla(lineas):
    v = lineas[lineas["es_venta"]]
    if v.empty:
        return no_calculable("No hay ventas válidas en el filtro")
    t = v.pivot_table(index="modelo", columns="talla", values="cantidad", aggfunc="sum", fill_value=0)
    prop = (t.div(t.sum(axis=1), axis=0) * 100).round(1).add_prefix("pct_")
    t.columns = [f"t{c}" for c in t.columns]
    out = pd.concat([t, prop], axis=1)
    out["total_pares"] = t.sum(axis=1)
    out["talla_mas_solicitada"] = t.idxmax(axis=1).str[1:]
    return out.reset_index()


def df05_custom_vs_estandar(pedidos):
    if pedidos.empty:
        return no_calculable("No hay pedidos en el filtro")
    ventas = pedidos[pedidos["es_venta"]]
    g = pedidos.groupby("tipo").agg(pedidos_totales=("id_pedido", "count"), cancelados=("estado", lambda s: (s == "cancelado").sum()))
    v = ventas.groupby("tipo").agg(pedidos_venta=("id_pedido", "count"), pares=("pares", "sum"), ingresos=("ticket_pedido", "sum"))
    r = g.join(v).fillna(0)
    r["ticket_medio"] = (r["ingresos"] / r["pedidos_venta"].replace(0, np.nan)).round(2)
    r["cuota_ingresos_pct"] = (100 * r["ingresos"] / r["ingresos"].sum()).round(1)
    r["tasa_cancelacion_pct"] = (100 * r["cancelados"] / r["pedidos_totales"]).round(1)
    return r.reset_index()


def df06_rfm(pedidos, clientes, fecha_corte):
    v = pedidos[pedidos["es_venta"]]
    r = v.groupby("cliente").agg(
        ultima=("fecha", "max"),
        frequency=("id_pedido", "nunique"),
        monetary=("ticket_pedido", "sum"),
        pct_custom=("tipo", lambda s: round(100 * (s == "custom").mean(), 1)),
        intervalo_medio_dias=("fecha", lambda s: s.sort_values().diff().dt.days.mean()),
    )
    r["recency_dias"] = (fecha_corte - r["ultima"]).dt.days
    r = clientes[["nombre"]].rename(columns={"nombre": "cliente"}).merge(r.reset_index(), on="cliente", how="left", validate="one_to_one")
    r["frequency"] = r["frequency"].fillna(0).astype(int)
    r["monetary"] = r["monetary"].fillna(0).round(2)
    alto = r.loc[r["frequency"] > 0, "monetary"].quantile(0.75) if (r["frequency"] > 0).any() else 0
    r["segmento_rfm"] = np.select(
        [
            r["frequency"] == 0,
            (r["recency_dias"] <= config.RFM_DIAS_ACTIVO) & (r["frequency"] >= 2),
            r["monetary"] >= alto,
            r["recency_dias"] <= config.RFM_DIAS_ACTIVO,
        ],
        ["Sin compras válidas", "Fiel", "Gran cuenta", "Reciente ocasional"],
        default="En riesgo",
    )
    return r.drop(columns="ultima").sort_values("monetary", ascending=False)


def df07_cohortes(pedidos):
    v = pedidos[pedidos["es_venta"]].copy()
    if v["cliente"].nunique() < 3 or v["fecha"].dt.to_period("M").nunique() < 2:
        return no_calculable("Muestra insuficiente: menos de 3 clientes o de 2 meses con ventas")
    v["mes"] = v["fecha"].dt.to_period("M")
    v["cohorte"] = v.groupby("cliente")["mes"].transform("min")
    v["edad_meses"] = (v["mes"] - v["cohorte"]).apply(lambda d: d.n)
    t = v.pivot_table(index="cohorte", columns="edad_meses", values="cliente", aggfunc="nunique", fill_value=0)
    ret = (t.div(t[0], axis=0) * 100).round(1)
    ret.columns = [f"mes_{c}" for c in ret.columns]
    ret.insert(0, "clientes", t[0])
    return ret.reset_index().assign(cohorte=lambda d: d["cohorte"].astype(str))


def df08_stock_cobertura(lineas, stock, modelos, fecha_corte):
    desde = fecha_corte - pd.Timedelta(days=config.DIAS_DEMANDA)
    v = lineas[lineas["es_venta"] & (lineas["fecha"] > desde)]
    demanda = v.groupby(["id_modelo", "talla"])["cantidad"].sum().rename("demanda_28d").reset_index()
    s = stock.merge(modelos[["id_modelo", "modelo"]], on="id_modelo", how="left", validate="many_to_one")
    s = s.merge(demanda, on=["id_modelo", "talla"], how="left", validate="one_to_one")
    s["demanda_28d"] = s["demanda_28d"].fillna(0).astype(int)
    semanas = s["stock_disponible"] / (s["demanda_28d"] / 4)
    s["cobertura_semanas"] = np.where(s["demanda_28d"] > 0, semanas.round(1).astype(str), "N/D")
    s["alerta_stock"] = np.where(s["stock_disponible"] < config.STOCK_MINIMO, "BAJO", "ok")
    return s[["modelo", "talla", "stock_disponible", "demanda_28d", "cobertura_semanas", "alerta_stock", "fecha_corte"]]


def df09_calidad(resumen, incidencias):
    r = resumen.copy()
    huerfanas = incidencias[incidencias["regla"].str.startswith("R03")].groupby("tabla").size()
    r["referencias_sin_resolver"] = r["tabla"].map(huerfanas).fillna(0).astype(int)
    r["tasa_integridad_pct"] = r["pct_calidad"]
    return r


def df10_anomalias(lineas):
    filas = []
    for col in ["cantidad", "precio_unitario"]:
        g = lineas.groupby("modelo")[col]
        q1, q3, n = g.transform(lambda s: s.quantile(0.25)), g.transform(lambda s: s.quantile(0.75)), g.transform("size")
        iqr = q3 - q1
        fuera = (n >= config.MIN_FILAS_IQR) & ((lineas[col] < q1 - 1.5 * iqr) | (lineas[col] > q3 + 1.5 * iqr))
        for _, f in lineas[fuera].iterrows():
            legitimo = col == "cantidad" and f["tipo"] == "custom"
            filas.append({
                "id_linea": f["id_linea"],
                "id_pedido": f["id_pedido"],
                "modelo": f["modelo"],
                "variable": col,
                "valor": f[col],
                "explicacion": "Pedido Custom de club: volumen alto legítimo" if legitimo else "Revisar con comercial",
            })
    if not filas:
        return pd.DataFrame([{"estado": "sin anomalías", "motivo": f"Regla IQR 1,5 por modelo (mínimo {config.MIN_FILAS_IQR} líneas)"}])
    return pd.DataFrame(filas)


def df11_margen():
    return no_calculable("Coste no disponible: Acceso a Datos no exporta coste unitario")


def df12_reconciliacion(lineas, pedidos, sql):
    if sql is None:
        return no_calculable("Falta reconciliacion_sql.csv en la exportación")
    ventas = pedidos[pedidos["es_venta"]]
    pandas_ = {
        "pedidos_totales": len(pedidos),
        "lineas_totales": len(lineas),
        "pedidos_venta": len(ventas),
        "pares_vendidos": ventas["pares"].sum(),
        "importe_ventas": round(ventas["ticket_pedido"].sum(), 2),
        "clientes_con_venta": ventas["cliente"].nunique(),
    }
    r = sql.rename(columns={"valor": "valor_sql"}).copy()
    r["valor_pandas"] = r["indicador"].map(pandas_)
    r["diferencia"] = (r["valor_pandas"] - r["valor_sql"]).round(2)
    r["coincide"] = np.where(r["diferencia"].abs() < 0.01, "sí", "NO")
    return r


def kpis(pedidos, lineas, stock):
    ventas = pedidos[pedidos["es_venta"]]
    vl = lineas[lineas["es_venta"]]
    ingresos = ventas["ticket_pedido"].sum()
    n = len(ventas)
    pct = lambda a, b: round(100 * a / b, 1) if b else 0.0
    estados = pedidos["estado"].value_counts()
    mensual = vl.groupby("mes")["importe_linea"].sum()
    var = round(100 * (mensual.iloc[-1] / mensual.iloc[-2] - 1), 1) if len(mensual) > 1 else "N/D"
    por_modelo = vl.groupby("modelo")["importe_linea"].sum().sort_values(ascending=False)
    top20 = max(1, int(np.ceil(len(por_modelo) * 0.2)))
    filas = [
        ("Pedidos únicos", len(pedidos), "nº id_pedido distintos (toda la actividad)"),
        ("Pendientes", int(estados.get("pendiente", 0)), "pedidos con estado pendiente"),
        ("Confirmados", int(estados.get("confirmado", 0)), "pedidos con estado confirmado"),
        ("Entregados", int(estados.get("entregado", 0)), "pedidos con estado entregado"),
        ("Cancelados", int(estados.get("cancelado", 0)), "pedidos con estado cancelado"),
        ("Pedidos de venta", n, "confirmados + entregados"),
        ("Pares vendidos", int(ventas["pares"].sum()), "Σ cantidad de pedidos de venta"),
        ("Ingresos (€)", round(ingresos, 2), "Σ cantidad × precio de pedidos de venta"),
        ("Ticket medio (€)", round(ingresos / n, 2) if n else 0, "ingresos / pedidos de venta"),
        ("Pares por pedido", round(ventas["pares"].sum() / n, 2) if n else 0, "pares / pedidos de venta"),
        ("% pedidos Custom", pct((ventas["tipo"] == "custom").sum(), n), "pedidos custom / pedidos de venta"),
        ("% pares Custom", pct(ventas.loc[ventas["tipo"] == "custom", "pares"].sum(), ventas["pares"].sum()), "pares custom / pares vendidos"),
        ("% ingresos Custom", pct(ventas.loc[ventas["tipo"] == "custom", "ticket_pedido"].sum(), ingresos), "ingresos custom / ingresos"),
        ("Modelo top", por_modelo.index[0] if len(por_modelo) else "-", "modelo con más ingresos"),
        ("Talla top", int(vl.groupby("talla")["cantidad"].sum().idxmax()) if len(vl) else "-", "talla con más pares"),
        ("Cliente top", ventas.groupby("cliente")["ticket_pedido"].sum().idxmax() if n else "-", "cliente con más ingresos"),
        ("Variación último mes %", var, "ingresos último mes / mes anterior − 1"),
        ("Pareto 20 % modelos %", pct(por_modelo.iloc[:top20].sum(), ingresos), "ingresos del 20 % de modelos con más ventas / ingresos"),
        ("Variantes con stock bajo", int((stock["stock_disponible"] < config.STOCK_MINIMO).sum()), f"modelo-talla con stock < {config.STOCK_MINIMO}"),
    ]
    return pd.DataFrame(filas, columns=["indicador", "valor", "formula"]).astype({"valor": str})


def descriptivos(pedidos):
    v = pedidos[pedidos["es_venta"]]
    filas = []
    for col in ["ticket_pedido", "pares", "precio_medio_par"]:
        s = v[col]
        if s.empty:
            continue
        filas.append({
            "variable": col,
            "n": len(s),
            "media": round(s.mean(), 2),
            "mediana": round(s.median(), 2),
            "moda": s.mode().iloc[0],
            "desviacion": round(s.std(), 2),
            "p25": s.quantile(0.25),
            "p75": s.quantile(0.75),
            "iqr": round(s.quantile(0.75) - s.quantile(0.25), 2),
            "min": s.min(),
            "max": s.max(),
        })
    return pd.DataFrame(filas)


def demanda_modelo_mes(lineas):
    v = lineas[lineas["es_venta"]]
    t = v.pivot_table(index="mes", columns="modelo", values="cantidad", aggfunc="sum", fill_value=0)
    largo = t.stack().rename("unidades_modelo_mes").reset_index()
    largo = largo.sort_values(["modelo", "mes"])
    g = largo.groupby("modelo")["unidades_modelo_mes"]
    largo["demanda_mes_anterior"] = g.shift(1)
    largo["media_3_meses_previos"] = g.transform(lambda s: s.shift(1).rolling(3, min_periods=3).mean())
    return largo


def clustering(rfm):
    datos = rfm[rfm["frequency"] > 0].copy()
    if len(datos) < config.MIN_CLIENTES_CLUSTER:
        motivo = f"Solo {len(datos)} clientes con compras (mínimo {config.MIN_CLIENTES_CLUSTER}): usar el histórico sintético"
        return no_calculable(motivo), no_calculable(motivo)
    x = StandardScaler().fit_transform(datos[["recency_dias", "frequency", "monetary"]])
    pruebas = []
    for k in [2, 3, 4, 5]:
        if k < len(datos):
            km = KMeans(n_clusters=k, n_init=10, random_state=config.SEMILLA).fit(x)
            pruebas.append({"k": k, "silhouette": round(silhouette_score(x, km.labels_), 3), "inercia": round(km.inertia_, 1)})
    comparacion = pd.DataFrame(pruebas)
    mejor = int(comparacion.loc[comparacion["silhouette"].idxmax(), "k"])
    datos["cluster"] = KMeans(n_clusters=mejor, n_init=10, random_state=config.SEMILLA).fit_predict(x)
    medias = datos.groupby("cluster")[["recency_dias", "frequency", "monetary"]].mean()
    nombre = {}
    for c, f in medias.iterrows():
        valor = "alto valor" if f["monetary"] >= medias["monetary"].median() else "bajo valor"
        actividad = "activos" if f["recency_dias"] <= medias["recency_dias"].median() else "inactivos"
        frecuencia = "recurrentes" if f["frequency"] >= medias["frequency"].median() else "ocasionales"
        nombre[c] = f"C{c} · {valor}, {frecuencia}, {actividad}"
    datos["nombre_cluster"] = datos["cluster"].map(nombre)
    comparacion["elegido"] = np.where(comparacion["k"] == mejor, "sí", "")
    return comparacion, datos


def calcular_todo(r, filtros=None):
    filtros = filtros or {}
    sin_filtro = not any(filtros.values())
    lineas = filtrar(r["lineas"], **filtros)
    t = r["tablas"]
    pedidos = df01_pedidos_unicos(lineas)
    rfm = df06_rfm(pedidos, t["clientes"], r["fecha_corte"])
    comparacion_k, clusters = clustering(rfm)
    return {
        "kpis": kpis(pedidos, lineas, t["stock"]),
        "df01_pedidos_unicos": pedidos,
        "df02_ventas_periodo": df02_ventas_periodo(lineas),
        "df03_modelos_abc": df03_abc(lineas),
        "df04_modelo_talla": df04_modelo_talla(lineas),
        "df05_custom_vs_estandar": df05_custom_vs_estandar(pedidos),
        "df06_clientes_rfm": rfm,
        "df07_cohortes": df07_cohortes(pedidos),
        "df08_stock_cobertura": df08_stock_cobertura(lineas, t["stock"], t["modelos"], r["fecha_corte"]),
        "df09_calidad": df09_calidad(r["resumen_calidad"], r["incidencias"]),
        "df10_anomalias": df10_anomalias(lineas),
        "df11_margen": df11_margen(),
        "df12_reconciliacion": df12_reconciliacion(r["lineas"], df01_pedidos_unicos(r["lineas"]), r["sql"])
        if sin_filtro
        else no_calculable("La reconciliación con SQL se hace sin filtros"),
        "descriptivos": descriptivos(pedidos),
        "demanda_modelo_mes": demanda_modelo_mes(lineas),
        "clustering_k": comparacion_k,
        "clustering_clientes": clusters,
        "df_lineas_enriquecidas": lineas,
    }
