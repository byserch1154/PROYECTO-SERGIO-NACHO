import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler

import config


def filtrar(lineas, desde=None, hasta=None, modelos=None, tallas=None, tipos=None):
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
    return f


def pedidos_unicos(lineas):
    return (
        lineas.groupby(["id_pedido", "fecha", "nombre", "estado", "tipo", "es_venta"])
        .agg(pares=("cantidad", "sum"), importe=("importe", "sum"))
        .reset_index()
    )


def kpis(lineas, stock):
    pedidos = pedidos_unicos(lineas)
    ventas = pedidos[pedidos["es_venta"]]
    v = lineas[lineas["es_venta"]]
    filas = [
        ("pedidos_totales", len(pedidos)),
        ("pedidos_venta", len(ventas)),
        ("ingresos", round(ventas["importe"].sum(), 2)),
        ("pares_vendidos", int(ventas["pares"].sum())),
        ("ticket_medio", round(ventas["importe"].mean(), 2) if len(ventas) else 0),
        ("pares_por_pedido", round(ventas["pares"].mean(), 2) if len(ventas) else 0),
        ("pct_custom", round(100 * (ventas["tipo"] == "custom").mean(), 1) if len(ventas) else 0),
        ("pct_cancelados", round(100 * (pedidos["estado"] == "cancelado").mean(), 1) if len(pedidos) else 0),
        ("modelo_top", v.groupby("modelo")["cantidad"].sum().idxmax() if len(v) else "-"),
        ("talla_top", int(v.groupby("talla")["cantidad"].sum().idxmax()) if len(v) else "-"),
        ("variantes_stock_bajo", int((stock["stock_disponible"] < config.STOCK_MINIMO).sum())),
    ]
    return pd.DataFrame(filas, columns=["indicador", "valor"], dtype=object)


def ventas_por_mes(lineas):
    v = lineas[lineas["es_venta"]].copy()
    v["mes"] = v["fecha"].dt.to_period("M").astype(str)
    return v.groupby("mes").agg(pares=("cantidad", "sum"), ingresos=("importe", "sum")).reset_index()


def ranking_modelos(lineas):
    v = lineas[lineas["es_venta"]]
    return (
        v.groupby("modelo")
        .agg(pares=("cantidad", "sum"), ingresos=("importe", "sum"))
        .sort_values("ingresos", ascending=False)
        .reset_index()
    )


def modelo_talla(lineas):
    v = lineas[lineas["es_venta"]]
    return v.pivot_table(index="modelo", columns="talla", values="cantidad", aggfunc="sum", fill_value=0)


def custom_vs_estandar(lineas):
    p = pedidos_unicos(lineas)
    p = p[p["es_venta"]]
    return (
        p.groupby("tipo")
        .agg(pedidos=("id_pedido", "count"), pares=("pares", "sum"), ingresos=("importe", "sum"), ticket_medio=("importe", "mean"))
        .round(2)
        .reset_index()
    )


def clientes_rfm(lineas):
    p = pedidos_unicos(lineas)
    p = p[p["es_venta"]]
    if p.empty:
        return pd.DataFrame(columns=["nombre", "recencia_dias", "frecuencia", "importe"])
    hoy = p["fecha"].max()
    return (
        p.groupby("nombre")
        .agg(ultima=("fecha", "max"), frecuencia=("id_pedido", "count"), importe=("importe", "sum"))
        .assign(recencia_dias=lambda d: (hoy - d["ultima"]).dt.days)
        .drop(columns="ultima")
        .reset_index()[["nombre", "recencia_dias", "frecuencia", "importe"]]
        .sort_values("importe", ascending=False)
    )


def stock_cobertura(lineas, stock, modelos):
    v = lineas[lineas["es_venta"]].groupby("id_modelo")["cantidad"].sum()
    s = stock.groupby("id_modelo")["stock_disponible"].sum()
    bajo = stock[stock["stock_disponible"] < config.STOCK_MINIMO].groupby("id_modelo").size()
    df = modelos[["id_modelo", "modelo"]].set_index("id_modelo")
    df["stock"] = s
    df["vendidos"] = v
    df["tallas_stock_bajo"] = bajo
    return df.fillna(0).astype({"stock": int, "vendidos": int, "tallas_stock_bajo": int}).reset_index(drop=True)


def segmentacion(rfm):
    if len(rfm) < 4:
        return rfm.assign(segmento="sin datos suficientes")
    x = StandardScaler().fit_transform(rfm[["recencia_dias", "frecuencia", "importe"]])
    km = KMeans(n_clusters=3, n_init=10, random_state=config.SEMILLA).fit(x)
    df = rfm.assign(cluster=km.labels_)
    orden = df.groupby("cluster")["importe"].mean().sort_values(ascending=False).index
    nombres = dict(zip(orden, ["Alto valor", "Medio", "Bajo valor"]))
    return df.assign(segmento=df["cluster"].map(nombres)).drop(columns="cluster")


def prediccion(ventas_mes):
    if len(ventas_mes) < 3:
        return pd.DataFrame([{"mes": "siguiente", "pares_previstos": None, "metodo": "sin datos suficientes"}])
    x = np.arange(len(ventas_mes)).reshape(-1, 1)
    y = ventas_mes["pares"].to_numpy()
    modelo = LinearRegression().fit(x, y)
    previsto = max(0, round(float(modelo.predict([[len(ventas_mes)]])[0]), 1))
    return pd.DataFrame(
        [
            {"mes": "siguiente", "pares_previstos": previsto, "metodo": "regresión lineal"},
            {"mes": "siguiente", "pares_previstos": float(y[-1]), "metodo": "baseline (mes anterior)"},
        ]
    )


def calcular_todo(t, lineas, incidencias):
    vm = ventas_por_mes(lineas)
    rfm = clientes_rfm(lineas)
    return {
        "kpis": kpis(lineas, t["stock"]),
        "pedidos": pedidos_unicos(lineas),
        "ventas_mes": vm,
        "ranking_modelos": ranking_modelos(lineas),
        "modelo_talla": modelo_talla(lineas).rename(columns=str).reset_index(),
        "custom_vs_estandar": custom_vs_estandar(lineas),
        "clientes_rfm": rfm,
        "segmentos": segmentacion(rfm),
        "prediccion": prediccion(vm),
        "stock": stock_cobertura(lineas, t["stock"], t["modelos"]),
        "incidencias": incidencias,
    }
