"""Carga y validación de los CSV exportados desde la base de datos SPEAKE."""

from pathlib import Path

import pandas as pd

import config


class ErrorCarga(Exception):
    """Los datos no se pueden usar: falta un fichero, una columna o hay claves rotas."""


def cargar(directorio: Path = config.DIR_ENTRADA) -> dict:
    """Lee los 5 CSV y comprueba que tienen las columnas obligatorias."""
    directorio = Path(directorio)
    if not directorio.is_dir():
        raise ErrorCarga(f"No existe la carpeta {directorio}")
    tablas = {}
    for nombre, columnas in config.ESQUEMA.items():
        ruta = directorio / f"{nombre}.csv"
        if not ruta.exists():
            raise ErrorCarga(f"Falta el fichero {ruta.name}")
        try:
            df = pd.read_csv(ruta, encoding="utf-8")
        except pd.errors.EmptyDataError:
            raise ErrorCarga(f"{ruta.name} está vacío")
        faltan = [c for c in columnas if c not in df.columns]
        if faltan:
            raise ErrorCarga(f"{ruta.name}: faltan columnas {faltan}")
        tablas[nombre] = df
    return tablas


def validar(tablas: dict) -> dict:
    """Limpia tipos y comprueba la integridad. Devuelve copias, nunca toca los originales."""
    t = {k: v.copy() for k, v in tablas.items()}

    pedidos = t["pedidos"]
    pedidos["fecha"] = pd.to_datetime(pedidos["fecha"], errors="coerce")
    if pedidos["fecha"].isna().any():
        raise ErrorCarga("pedidos.csv tiene fechas no válidas")
    if pedidos["id_pedido"].duplicated().any():
        raise ErrorCarga("pedidos.csv tiene id_pedido duplicados")
    if not pedidos["estado"].isin(config.ESTADOS).all():
        raise ErrorCarga("pedidos.csv tiene estados desconocidos")

    lineas = t["lineas_pedido"]
    if (lineas["cantidad"] <= 0).any():
        raise ErrorCarga("lineas_pedido.csv tiene cantidades no positivas")
    if not lineas["id_pedido"].isin(pedidos["id_pedido"]).all():
        raise ErrorCarga("lineas_pedido.csv tiene líneas de pedidos que no existen")
    if not lineas["id_modelo"].isin(t["modelos"]["id_modelo"]).all():
        raise ErrorCarga("lineas_pedido.csv tiene modelos que no existen")
    if not pedidos["id_cliente"].isin(t["clientes"]["id_cliente"]).all():
        raise ErrorCarga("pedidos.csv tiene clientes que no existen")

    # TODO: más reglas de calidad (tallas fuera de 38-46, precios negativos, stock negativo,
    #   id_linea duplicados...) y en vez de parar en el primer error, guardar todas las
    #   incidencias en una tabla para enseñarlas en el dashboard.
    return t


def construir_lineas(t: dict) -> pd.DataFrame:
    """Una fila por línea de pedido con los datos del pedido, el cliente y el modelo."""
    pedidos = t["pedidos"].merge(
        t["clientes"].rename(columns={"tipo": "tipo_cliente"}),
        on="id_cliente",
        how="left",
        validate="many_to_one",
    )
    lineas = t["lineas_pedido"].merge(pedidos, on="id_pedido", how="left", validate="many_to_one")
    lineas = lineas.merge(t["modelos"], on="id_modelo", how="left", validate="many_to_one")
    lineas["importe"] = lineas["cantidad"] * lineas["precio_unitario"]
    lineas["es_venta"] = lineas["estado"].isin(config.ESTADOS_VENTA)
    return lineas


def ejecutar(directorio: Path = config.DIR_ENTRADA) -> tuple[dict, pd.DataFrame]:
    """Carga, valida y une. Devuelve (tablas limpias, líneas enriquecidas)."""
    t = validar(cargar(directorio))
    return t, construir_lineas(t)
