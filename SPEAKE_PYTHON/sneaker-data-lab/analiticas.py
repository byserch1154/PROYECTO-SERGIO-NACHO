import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

import config


# cuando no hay datos suficientes devolvemos esto en vez de inventar numeros
def no_calculable(motivo):
    return pd.DataFrame([{"estado": "NO CALCULABLE", "motivo": motivo}])


# porcentaje evitando dividir entre 0
def porcentaje(parte, total):
    if total == 0:
        return 0.0
    return round(100 * parte / total, 1)


# filtros del dashboard y de la consola
def filtrar(lineas, desde=None, hasta=None, modelos=None, tallas=None, tipos=None, estados=None, clientes=None):
    f = lineas
    if desde is not None:
        f = f[f["fecha"] >= pd.Timestamp(desde)]
    if hasta is not None:
        f = f[f["fecha"] <= pd.Timestamp(hasta)]
    if modelos:
        f = f[f["modelo"].isin(modelos)]
    if tallas:
        f = f[f["talla"].isin(tallas)]
    if tipos:
        f = f[f["tipo"].isin(tipos)]
    if estados:
        f = f[f["estado"].isin(estados)]
    if clientes:
        f = f[f["nombre"].isin(clientes)]
    return f


# df01: pasamos de lineas a una fila por pedido
# n_lineas con nunique para no contar dos veces la misma linea
def df01_pedidos_unicos(lineas):
    p = lineas.groupby("id_pedido").agg(
        fecha=("fecha", "first"),
        id_cliente=("id_cliente", "first"),
        cliente=("nombre", "first"),
        estado=("estado", "first"),
        tipo=("tipo", "first"),
        es_venta=("es_venta", "first"),
        n_lineas=("id_linea", "nunique"),
        pares=("cantidad", "sum"),
        ticket_pedido=("importe_linea", "sum"),
    )
    p = p.reset_index()
    p["precio_medio_par"] = (p["ticket_pedido"] / p["pares"]).round(2)
    return p


# df02: ventas por mes y como cambian
def df02_ventas_periodo(lineas):
    v = lineas[lineas["es_venta"]]
    if len(v) == 0:
        return no_calculable("No hay ventas válidas en el filtro")

    # Grouper con "MS" agrupa por mes y saca tambien los meses sin ventas
    m = v.groupby(pd.Grouper(key="fecha", freq="MS")).agg(
        ingresos=("importe_linea", "sum"),
        pares=("cantidad", "sum"),
        pedidos=("id_pedido", "nunique"),
    )
    m = m.reset_index()
    m["mes"] = m["fecha"].dt.to_period("M").astype(str)
    m["ticket_medio"] = (m["ingresos"] / m["pedidos"]).round(2)
    # % de cambio respecto al mes anterior
    m["var_ingresos_pct"] = (m["ingresos"].pct_change() * 100).round(1)
    # media de los 3 meses de antes (sin contar el mes actual)
    m["media_3m_previos"] = m["ingresos"].shift(1).rolling(3, min_periods=3).mean().round(2)
    # comparar con el mismo mes del año anterior solo si hay mas de 12 meses
    if len(m) > 12:
        m["var_interanual_pct"] = (m["ingresos"].pct_change(12) * 100).round(1)
    else:
        m["var_interanual_pct"] = np.nan
    return m[["mes", "pedidos", "pares", "ingresos", "ticket_medio", "var_ingresos_pct", "media_3m_previos", "var_interanual_pct"]]


# df03: clasificacion ABC de los modelos por ingresos
# A = hasta el 80% de los ingresos, B = hasta el 95%, C = el resto
def df03_abc(lineas):
    v = lineas[lineas["es_venta"]]
    if len(v) == 0:
        return no_calculable("No hay ventas válidas en el filtro")

    r = v.groupby("modelo").agg(ingresos=("importe_linea", "sum"), pares=("cantidad", "sum"))
    r = r.sort_values("ingresos", ascending=False).reset_index()
    r["peso_pct"] = (100 * r["ingresos"] / r["ingresos"].sum()).round(1)
    r["acumulado_pct"] = r["peso_pct"].cumsum().round(1)

    # la clase se decide con lo acumulado ANTES de este modelo
    clases = []
    acumulado_antes = 0
    for acumulado in r["acumulado_pct"]:
        if acumulado_antes <= config.ABC_A * 100:
            clases.append("A")
        elif acumulado_antes <= config.ABC_B * 100:
            clases.append("B")
        else:
            clases.append("C")
        acumulado_antes = acumulado
    r["clase"] = clases

    r["ranking_pares"] = r["pares"].rank(ascending=False, method="min").astype(int)
    return r


# df04: pares por modelo y talla (para saber que fabricar)
def df04_modelo_talla(lineas):
    v = lineas[lineas["es_venta"]]
    if len(v) == 0:
        return no_calculable("No hay ventas válidas en el filtro")

    # filas = modelos, columnas = tallas
    tabla = v.pivot_table(index="modelo", columns="talla", values="cantidad", aggfunc="sum", fill_value=0)
    talla_top = tabla.idxmax(axis=1).astype(str)

    # % de cada talla dentro de su modelo
    pct = (tabla.div(tabla.sum(axis=1), axis=0) * 100).round(1)
    pct.columns = ["pct_" + str(c) for c in pct.columns]
    tabla.columns = ["t" + str(c) for c in tabla.columns]

    out = pd.concat([tabla, pct], axis=1)
    out["total_pares"] = tabla.sum(axis=1)
    out["talla_mas_solicitada"] = talla_top
    return out.reset_index()


# df05: pedidos personalizados (custom) frente a los normales
def df05_custom_vs_estandar(pedidos):
    if len(pedidos) == 0:
        return no_calculable("No hay pedidos en el filtro")

    p = pedidos.copy()
    p["cancelado"] = p["estado"] == "cancelado"
    todos = p.groupby("tipo").agg(pedidos_totales=("id_pedido", "count"), cancelados=("cancelado", "sum"))

    ventas = p[p["es_venta"]]
    vendidos = ventas.groupby("tipo").agg(pedidos_venta=("id_pedido", "count"), pares=("pares", "sum"), ingresos=("ticket_pedido", "sum"))

    r = todos.join(vendidos).fillna(0)
    r["ticket_medio"] = (r["ingresos"] / r["pedidos_venta"].replace(0, np.nan)).round(2)
    r["cuota_ingresos_pct"] = (100 * r["ingresos"] / r["ingresos"].sum()).round(1)
    r["tasa_cancelacion_pct"] = (100 * r["cancelados"] / r["pedidos_totales"]).round(1)
    return r.reset_index()


# df06: RFM de cada cliente
# R = dias desde su ultima compra, F = cuantos pedidos, M = cuanto ha gastado
def df06_rfm(pedidos, clientes, fecha_corte):
    v = pedidos[pedidos["es_venta"]].copy()
    v["es_custom"] = v["tipo"] == "custom"
    v = v.sort_values("fecha")
    v["dias_desde_anterior"] = v.groupby("id_cliente")["fecha"].diff().dt.days

    # agrupamos por id_cliente y no por nombre: dos clientes se pueden llamar igual
    r = v.groupby("id_cliente").agg(
        ultima=("fecha", "max"),
        frequency=("id_pedido", "nunique"),
        monetary=("ticket_pedido", "sum"),
    )
    r["pct_custom"] = (v.groupby("id_cliente")["es_custom"].mean() * 100).round(1)
    r["intervalo_medio_dias"] = v.groupby("id_cliente")["dias_desde_anterior"].mean()
    r["recency_dias"] = (fecha_corte - r["ultima"]).dt.days
    r = r.reset_index()

    # metemos tambien a los clientes que no han comprado
    lista = clientes[["id_cliente", "nombre"]].rename(columns={"nombre": "cliente"})
    r = lista.merge(r, on="id_cliente", how="left", validate="one_to_one")
    r = r.drop(columns="id_cliente")
    r["frequency"] = r["frequency"].fillna(0).astype(int)
    r["monetary"] = r["monetary"].fillna(0).round(2)

    # "gran cuenta" = el 25% que mas gasta
    compradores = r[r["frequency"] > 0]
    if len(compradores) > 0:
        alto = compradores["monetary"].quantile(0.75)
    else:
        alto = 0

    segmentos = []
    for i in range(len(r)):
        f = r.iloc[i]
        if f["frequency"] == 0:
            segmentos.append("Sin compras válidas")
        elif f["recency_dias"] <= config.RFM_DIAS_ACTIVO and f["frequency"] >= 2:
            segmentos.append("Fiel")
        elif f["monetary"] >= alto:
            segmentos.append("Gran cuenta")
        elif f["recency_dias"] <= config.RFM_DIAS_ACTIVO:
            segmentos.append("Reciente ocasional")
        else:
            segmentos.append("En riesgo")
    r["segmento_rfm"] = segmentos

    return r.drop(columns="ultima").sort_values("monetary", ascending=False)


# df07: cohortes = clientes agrupados por el mes de su primera compra
# y que % sigue comprando en los meses siguientes
def df07_cohortes(pedidos):
    v = pedidos[pedidos["es_venta"]].copy()
    meses_distintos = v["fecha"].dt.to_period("M").nunique()
    if v["cliente"].nunique() < 3 or meses_distintos < 2:
        return no_calculable("Muestra insuficiente: menos de 3 clientes o de 2 meses con ventas")

    v["mes"] = v["fecha"].dt.to_period("M")
    v["cohorte"] = v.groupby("cliente")["mes"].transform("min")

    # numero de mes (año*12 + mes) para poder restar
    v["n_mes"] = v["fecha"].dt.year * 12 + v["fecha"].dt.month
    v["edad_meses"] = v["n_mes"] - v.groupby("cliente")["n_mes"].transform("min")

    t = v.pivot_table(index="cohorte", columns="edad_meses", values="cliente", aggfunc="nunique", fill_value=0)
    ret = (t.div(t[0], axis=0) * 100).round(1)
    ret.columns = ["mes_" + str(c) for c in ret.columns]
    ret.insert(0, "clientes", t[0])
    ret = ret.reset_index()
    ret["cohorte"] = ret["cohorte"].astype(str)
    return ret


# df08: stock frente a lo que se ha vendido las ultimas 4 semanas
def df08_stock_cobertura(lineas, stock, modelos, fecha_corte):
    desde = fecha_corte - pd.Timedelta(days=config.DIAS_DEMANDA)
    v = lineas[lineas["es_venta"] & (lineas["fecha"] > desde)]
    demanda = v.groupby(["id_modelo", "talla"])["cantidad"].sum().rename("demanda_28d").reset_index()

    s = stock.merge(modelos[["id_modelo", "modelo"]], on="id_modelo", how="left", validate="many_to_one")
    s = s.merge(demanda, on=["id_modelo", "talla"], how="left", validate="one_to_one")
    s["demanda_28d"] = s["demanda_28d"].fillna(0).astype(int)

    # semanas que aguanta el stock al ritmo de venta actual
    semanas = s["stock_disponible"] / (s["demanda_28d"] / 4)
    s["cobertura_semanas"] = "N/D"
    hay_demanda = s["demanda_28d"] > 0
    s.loc[hay_demanda, "cobertura_semanas"] = semanas[hay_demanda].round(1).astype(str)

    s["alerta_stock"] = "ok"
    s.loc[s["stock_disponible"] < config.STOCK_MINIMO, "alerta_stock"] = "BAJO"
    return s[["modelo", "talla", "stock_disponible", "demanda_28d", "cobertura_semanas", "alerta_stock", "fecha_corte"]]


# df09: resumen de calidad + cuantas referencias rotas (R03) hay por tabla
def df09_calidad(resumen, incidencias):
    r = resumen.copy()
    rotas = incidencias[incidencias["regla"].str.startswith("R03")].groupby("tabla").size()
    r["referencias_sin_resolver"] = r["tabla"].map(rotas).fillna(0).astype(int)
    r["tasa_integridad_pct"] = r["pct_calidad"]
    return r


# df10: valores raros con la regla del IQR (rango intercuartilico)
# raro = menor que Q1 - 1.5*IQR o mayor que Q3 + 1.5*IQR, dentro de cada modelo
def df10_anomalias(lineas):
    filas = []
    for col in ["cantidad", "precio_unitario"]:
        q1 = lineas["modelo"].map(lineas.groupby("modelo")[col].quantile(0.25))
        q3 = lineas["modelo"].map(lineas.groupby("modelo")[col].quantile(0.75))
        n = lineas["modelo"].map(lineas.groupby("modelo").size())
        iqr = q3 - q1
        fuera = (n >= config.MIN_FILAS_IQR) & ((lineas[col] < q1 - 1.5 * iqr) | (lineas[col] > q3 + 1.5 * iqr))

        raras = lineas[fuera]
        for i in range(len(raras)):
            f = raras.iloc[i]
            # un club que pide muchos pares custom es normal, no un error
            if col == "cantidad" and f["tipo"] == "custom":
                explicacion = "Pedido Custom de club: volumen alto legítimo"
            else:
                explicacion = "Revisar con comercial"
            filas.append({
                "id_linea": f["id_linea"],
                "id_pedido": f["id_pedido"],
                "modelo": f["modelo"],
                "variable": col,
                "valor": f[col],
                "explicacion": explicacion,
            })

    if len(filas) == 0:
        motivo = "Regla IQR 1,5 por modelo (mínimo " + str(config.MIN_FILAS_IQR) + " líneas)"
        return pd.DataFrame([{"estado": "sin anomalías", "motivo": motivo}])
    return pd.DataFrame(filas)


# df11: margen. La base de datos no tiene el coste, asi que no se puede calcular
def df11_margen():
    return no_calculable("Coste no disponible: Acceso a Datos no exporta coste unitario")


# df12: comparamos nuestros totales con los que calcula SQL; tienen que salir iguales
def df12_reconciliacion(lineas, pedidos, sql):
    if sql is None:
        return no_calculable("Falta reconciliacion_sql.csv en la exportación")

    ventas = pedidos[pedidos["es_venta"]]
    nuestros = {
        "pedidos_totales": len(pedidos),
        "lineas_totales": len(lineas),
        "pedidos_venta": len(ventas),
        "pares_vendidos": ventas["pares"].sum(),
        "importe_ventas": round(ventas["ticket_pedido"].sum(), 2),
        "clientes_con_venta": ventas["cliente"].nunique(),
    }
    r = sql.rename(columns={"valor": "valor_sql"}).copy()
    r["valor_pandas"] = r["indicador"].map(nuestros)
    r["diferencia"] = (r["valor_pandas"] - r["valor_sql"]).round(2)
    r["coincide"] = "NO"
    r.loc[r["diferencia"].abs() < 0.01, "coincide"] = "sí"
    return r


# indicadores principales (KPIs) del cuadro de mando
def kpis(pedidos, lineas, stock):
    ventas = pedidos[pedidos["es_venta"]]
    lineas_venta = lineas[lineas["es_venta"]]
    ingresos = ventas["ticket_pedido"].sum()
    n = len(ventas)
    pares = ventas["pares"].sum()
    custom = ventas[ventas["tipo"] == "custom"]
    estados = pedidos["estado"].value_counts()

    if n > 0:
        ticket = round(ingresos / n, 2)
        pares_pedido = round(pares / n, 2)
        cliente_top = ventas.groupby("cliente")["ticket_pedido"].sum().idxmax()
    else:
        ticket = 0
        pares_pedido = 0
        cliente_top = "-"

    # variacion del ultimo mes con ventas frente al anterior
    mensual = lineas_venta.groupby("mes")["importe_linea"].sum()
    if len(mensual) > 1:
        variacion = round(100 * (mensual.iloc[-1] / mensual.iloc[-2] - 1), 1)
    else:
        variacion = "N/D"

    por_modelo = lineas_venta.groupby("modelo")["importe_linea"].sum().sort_values(ascending=False)
    if len(por_modelo) > 0:
        modelo_top = por_modelo.index[0]
    else:
        modelo_top = "-"
    if len(lineas_venta) > 0:
        talla_top = int(lineas_venta.groupby("talla")["cantidad"].sum().idxmax())
    else:
        talla_top = "-"

    # pareto: cuanto factura el 20% de modelos que mas vende
    top20 = max(1, int(np.ceil(len(por_modelo) * 0.2)))
    pareto = porcentaje(por_modelo.iloc[:top20].sum(), ingresos)

    stock_bajo = int((stock["stock_disponible"] < config.STOCK_MINIMO).sum())

    filas = [
        ("Pedidos únicos", len(pedidos), "nº id_pedido distintos (toda la actividad)"),
        ("Pendientes", int(estados.get("pendiente", 0)), "pedidos con estado pendiente"),
        ("Confirmados", int(estados.get("confirmado", 0)), "pedidos con estado confirmado"),
        ("Entregados", int(estados.get("entregado", 0)), "pedidos con estado entregado"),
        ("Cancelados", int(estados.get("cancelado", 0)), "pedidos con estado cancelado"),
        ("Pedidos de venta", n, "confirmados + entregados"),
        ("Pares vendidos", int(pares), "Σ cantidad de pedidos de venta"),
        ("Ingresos (€)", round(ingresos, 2), "Σ cantidad × precio de pedidos de venta"),
        ("Ticket medio (€)", ticket, "ingresos / pedidos de venta"),
        ("Pares por pedido", pares_pedido, "pares / pedidos de venta"),
        ("% pedidos Custom", porcentaje(len(custom), n), "pedidos custom / pedidos de venta"),
        ("% pares Custom", porcentaje(custom["pares"].sum(), pares), "pares custom / pares vendidos"),
        ("% ingresos Custom", porcentaje(custom["ticket_pedido"].sum(), ingresos), "ingresos custom / ingresos"),
        ("Modelo top", modelo_top, "modelo con más ingresos"),
        ("Talla top", talla_top, "talla con más pares"),
        ("Cliente top", cliente_top, "cliente con más ingresos"),
        ("Variación último mes %", variacion, "ingresos último mes / mes anterior − 1"),
        ("Pareto 20 % modelos %", pareto, "ingresos del 20 % de modelos con más ventas / ingresos"),
        ("Variantes con stock bajo", stock_bajo, "modelo-talla con stock < " + str(config.STOCK_MINIMO)),
    ]
    tabla = pd.DataFrame(filas, columns=["indicador", "valor", "formula"])
    tabla["valor"] = tabla["valor"].astype(str)
    return tabla


# estadistica descriptiva de los pedidos de venta
def descriptivos(pedidos):
    v = pedidos[pedidos["es_venta"]]
    filas = []
    for col in ["ticket_pedido", "pares", "precio_medio_par"]:
        s = v[col]
        if len(s) == 0:
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


# pares vendidos de cada modelo en cada mes (para ver la tendencia de la demanda)
def demanda_modelo_mes(lineas):
    v = lineas[lineas["es_venta"]]
    tabla = v.pivot_table(index="mes", columns="modelo", values="cantidad", aggfunc="sum", fill_value=0)
    # de tabla ancha a una fila por mes y modelo
    largo = tabla.stack().rename("unidades_modelo_mes").reset_index()
    largo = largo.sort_values(["modelo", "mes"])

    largo["demanda_mes_anterior"] = np.nan
    largo["media_3_meses_previos"] = np.nan
    for modelo in largo["modelo"].unique():
        filas = largo["modelo"] == modelo
        anterior = largo.loc[filas, "unidades_modelo_mes"].shift(1)
        largo.loc[filas, "demanda_mes_anterior"] = anterior
        largo.loc[filas, "media_3_meses_previos"] = anterior.rolling(3, min_periods=3).mean()
    return largo


# clustering KMeans con los datos del RFM
# probamos k de 2 a 5 y nos quedamos con el que tenga mejor silhouette
# con los datos reales hay muy pocos clientes, por eso se hace con los sinteticos
def clustering(rfm):
    datos = rfm[rfm["frequency"] > 0].copy()
    if len(datos) < config.MIN_CLIENTES_CLUSTER:
        motivo = "Solo " + str(len(datos)) + " clientes con compras (mínimo " + str(config.MIN_CLIENTES_CLUSTER) + "): usar el histórico sintético"
        return no_calculable(motivo), no_calculable(motivo)

    # escalamos porque los euros son mucho mas grandes que los dias o las veces
    x = StandardScaler().fit_transform(datos[["recency_dias", "frequency", "monetary"]])

    pruebas = []
    for k in [2, 3, 4, 5]:
        if k < len(datos):
            km = KMeans(n_clusters=k, n_init=10, random_state=config.SEMILLA)
            km.fit(x)
            nota = silhouette_score(x, km.labels_)
            pruebas.append({"k": k, "silhouette": round(nota, 3), "inercia": round(km.inertia_, 1)})
    comparacion = pd.DataFrame(pruebas)

    mejor = int(comparacion.loc[comparacion["silhouette"].idxmax(), "k"])
    km = KMeans(n_clusters=mejor, n_init=10, random_state=config.SEMILLA)
    datos["cluster"] = km.fit_predict(x)

    # le ponemos nombre a cada grupo comparando sus medias con la mediana
    medias = datos.groupby("cluster")[["recency_dias", "frequency", "monetary"]].mean()
    nombres = {}
    for c in medias.index:
        f = medias.loc[c]
        if f["monetary"] >= medias["monetary"].median():
            valor = "alto valor"
        else:
            valor = "bajo valor"
        if f["recency_dias"] <= medias["recency_dias"].median():
            actividad = "activos"
        else:
            actividad = "inactivos"
        if f["frequency"] >= medias["frequency"].median():
            frecuencia = "recurrentes"
        else:
            frecuencia = "ocasionales"
        nombres[c] = "C" + str(c) + " · " + valor + ", " + frecuencia + ", " + actividad
    datos["nombre_cluster"] = datos["cluster"].map(nombres)

    comparacion["elegido"] = ""
    comparacion.loc[comparacion["k"] == mejor, "elegido"] = "sí"
    return comparacion, datos


# hace todos los calculos y los devuelve en un diccionario
def calcular_todo(r, filtros=None):
    if filtros is None:
        filtros = {}

    hay_filtro = False
    for valor in filtros.values():
        if valor:
            hay_filtro = True

    lineas = filtrar(
        r["lineas"],
        desde=filtros.get("desde"),
        hasta=filtros.get("hasta"),
        modelos=filtros.get("modelos"),
        tallas=filtros.get("tallas"),
        tipos=filtros.get("tipos"),
        estados=filtros.get("estados"),
        clientes=filtros.get("clientes"),
    )
    t = r["tablas"]
    pedidos = df01_pedidos_unicos(lineas)
    rfm = df06_rfm(pedidos, t["clientes"], r["fecha_corte"])
    comparacion_k, clusters = clustering(rfm)

    # la comparacion con SQL solo tiene sentido con todos los datos
    if hay_filtro:
        reconciliacion = no_calculable("La reconciliación con SQL se hace sin filtros")
    else:
        reconciliacion = df12_reconciliacion(r["lineas"], df01_pedidos_unicos(r["lineas"]), r["sql"])

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
        "df12_reconciliacion": reconciliacion,
        "descriptivos": descriptivos(pedidos),
        "demanda_modelo_mes": demanda_modelo_mes(lineas),
        "clustering_k": comparacion_k,
        "clustering_clientes": clusters,
        "df_lineas_enriquecidas": lineas,
    }
