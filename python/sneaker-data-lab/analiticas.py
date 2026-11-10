"""DataFrames de análisis y KPIs a partir de las líneas enriquecidas."""

import pandas as pd

import config


def pedidos_unicos(lineas: pd.DataFrame) -> pd.DataFrame:
    """Una fila por pedido (un pedido con 3 líneas cuenta una sola vez)."""
    return (
        lineas.groupby(["id_pedido", "fecha", "nombre", "estado", "tipo", "es_venta"])
        .agg(pares=("cantidad", "sum"), importe=("importe", "sum"))
        .reset_index()
    )


def kpis(lineas: pd.DataFrame, stock: pd.DataFrame) -> pd.DataFrame:
    pedidos = pedidos_unicos(lineas)
    ventas = pedidos[pedidos["es_venta"]]
    filas = [
        ("pedidos_totales", len(pedidos)),
        ("pedidos_venta", len(ventas)),
        ("ingresos", round(ventas["importe"].sum(), 2)),
        ("pares_vendidos", int(ventas["pares"].sum())),
        ("ticket_medio", round(ventas["importe"].mean(), 2) if len(ventas) else 0),
        ("variantes_stock_bajo", int((stock["stock_disponible"] < config.STOCK_MINIMO).sum())),
    ]
    # TODO: más KPIs: % de pedidos Custom, pares por pedido, tasa de cancelación,
    #   modelo más vendido y talla más vendida.
    return pd.DataFrame(filas, columns=["indicador", "valor"], dtype=object)


def ventas_por_mes(lineas: pd.DataFrame) -> pd.DataFrame:
    v = lineas[lineas["es_venta"]].copy()
    v["mes"] = v["fecha"].dt.to_period("M").astype(str)
    return v.groupby("mes").agg(pares=("cantidad", "sum"), ingresos=("importe", "sum")).reset_index()


def ranking_modelos(lineas: pd.DataFrame) -> pd.DataFrame:
    v = lineas[lineas["es_venta"]]
    return (
        v.groupby("modelo")
        .agg(pares=("cantidad", "sum"), ingresos=("importe", "sum"))
        .sort_values("ingresos", ascending=False)
        .reset_index()
    )


# TODO: matriz modelo × talla (pares vendidos), comparación Custom frente a estándar,
#   clientes RFM (recencia, frecuencia, importe) y cobertura de stock por modelo.
# TODO (ampliación): segmentación de clientes con KMeans y predicción de pares por
#   modelo y mes con scikit-learn, comparada con un baseline (repetir el mes anterior).


def calcular_todo(t: dict, lineas: pd.DataFrame) -> dict:
    return {
        "kpis": kpis(lineas, t["stock"]),
        "pedidos": pedidos_unicos(lineas),
        "ventas_mes": ventas_por_mes(lineas),
        "ranking_modelos": ranking_modelos(lineas),
    }
