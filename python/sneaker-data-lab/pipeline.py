from pathlib import Path

import pandas as pd

import config


class ErrorCarga(Exception):
    pass


def cargar(directorio=config.DIR_ENTRADA):
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


def _quitar(df, malas, tabla, regla, incidencias):
    for _, fila in df[malas].iterrows():
        incidencias.append({"tabla": tabla, "regla": regla, "id": fila.iloc[0]})
    return df[~malas]


def validar(tablas):
    t = {k: v.copy() for k, v in tablas.items()}
    inc = []

    p = t["pedidos"]
    p["fecha"] = pd.to_datetime(p["fecha"], format="%Y-%m-%d", errors="coerce")
    p = _quitar(p, p["fecha"].isna(), "pedidos", "fecha no válida", inc)
    p = _quitar(p, p["id_pedido"].duplicated(), "pedidos", "id_pedido duplicado", inc)
    p = _quitar(p, ~p["estado"].isin(config.ESTADOS), "pedidos", "estado desconocido", inc)
    p = _quitar(p, ~p["id_cliente"].isin(t["clientes"]["id_cliente"]), "pedidos", "cliente inexistente", inc)
    t["pedidos"] = p

    lin = t["lineas_pedido"]
    lin = _quitar(lin, lin["id_linea"].duplicated(), "lineas_pedido", "id_linea duplicado", inc)
    lin = _quitar(lin, lin["cantidad"] <= 0, "lineas_pedido", "cantidad no positiva", inc)
    lin = _quitar(lin, lin["precio_unitario"] < 0, "lineas_pedido", "precio negativo", inc)
    lin = _quitar(lin, ~lin["talla"].isin(config.TALLAS), "lineas_pedido", "talla fuera de 38-46", inc)
    lin = _quitar(lin, ~lin["id_pedido"].isin(p["id_pedido"]), "lineas_pedido", "pedido inexistente", inc)
    lin = _quitar(lin, ~lin["id_modelo"].isin(t["modelos"]["id_modelo"]), "lineas_pedido", "modelo inexistente", inc)
    t["lineas_pedido"] = lin

    s = t["stock"]
    t["stock"] = _quitar(s, s["stock_disponible"] < 0, "stock", "stock negativo", inc)

    return t, pd.DataFrame(inc, columns=["tabla", "regla", "id"])


def construir_lineas(t):
    pedidos = t["pedidos"].merge(
        t["clientes"].rename(columns={"tipo": "tipo_cliente"}),
        on="id_cliente",
        how="left",
        validate="many_to_one",
    )
    lineas = t["lineas_pedido"].merge(pedidos, on="id_pedido", how="inner", validate="many_to_one")
    lineas = lineas.merge(t["modelos"], on="id_modelo", how="left", validate="many_to_one")
    lineas["importe"] = lineas["cantidad"] * lineas["precio_unitario"]
    lineas["es_venta"] = lineas["estado"].isin(config.ESTADOS_VENTA)
    return lineas


def ejecutar(directorio=config.DIR_ENTRADA):
    t, incidencias = validar(cargar(directorio))
    return t, construir_lineas(t), incidencias
