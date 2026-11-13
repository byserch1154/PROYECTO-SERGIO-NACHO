from datetime import datetime
from pathlib import Path

import pandas as pd

import config


class ErrorCarga(Exception):
    pass


def manifiesto(directorio):
    filas = []
    for nombre in list(config.ESQUEMA) + [config.FICHERO_SQL.removesuffix(".csv")]:
        ruta = Path(directorio) / f"{nombre}.csv"
        existe = ruta.exists()
        df = pd.read_csv(ruta, dtype=str) if existe and ruta.stat().st_size else None
        filas.append({
            "fichero": ruta.name,
            "existe": existe,
            "fecha_analisis": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "filas": 0 if df is None else len(df),
            "columnas": 0 if df is None else len(df.columns),
            "bytes": ruta.stat().st_size if existe else 0,
            "modificado": datetime.fromtimestamp(ruta.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S") if existe else "",
        })
    return pd.DataFrame(filas)


def cargar(directorio):
    directorio = Path(directorio)
    if not directorio.is_dir():
        raise ErrorCarga(f"R01 · No existe la carpeta {directorio}")
    tablas = {}
    for nombre, columnas in config.ESQUEMA.items():
        ruta = directorio / f"{nombre}.csv"
        if not ruta.exists():
            raise ErrorCarga(f"R01 · Falta el fichero {ruta.name}")
        try:
            df = pd.read_csv(ruta, dtype=str, encoding="utf-8", sep=",", keep_default_na=False, na_values=[""])
        except pd.errors.EmptyDataError:
            raise ErrorCarga(f"R01 · {ruta.name} está vacío")
        df.columns = [c.strip().lstrip("﻿") for c in df.columns]
        faltan = [c for c in columnas if c not in df.columns]
        if faltan:
            raise ErrorCarga(f"R01 · {ruta.name}: faltan columnas {faltan}")
        tablas[nombre] = df[columnas].copy()
    return tablas


def convertir_tipos(t):
    num = lambda s: pd.to_numeric(s, errors="coerce")
    t["clientes"]["id_cliente"] = num(t["clientes"]["id_cliente"]).astype("Int64")
    t["modelos"]["id_modelo"] = num(t["modelos"]["id_modelo"]).astype("Int64")
    p = t["pedidos"]
    p["id_pedido"] = num(p["id_pedido"]).astype("Int64")
    p["id_cliente"] = num(p["id_cliente"]).astype("Int64")
    p["fecha"] = pd.to_datetime(p["fecha"], format="%Y-%m-%d", errors="coerce")
    p["estado"] = p["estado"].str.strip().str.lower()
    p["tipo"] = p["tipo"].str.strip().str.lower()
    lin = t["lineas_pedido"]
    for col in ["id_linea", "id_pedido", "id_modelo", "talla"]:
        lin[col] = num(lin[col]).astype("Int64")
    lin["cantidad"] = num(lin["cantidad"])
    lin["precio_unitario"] = num(lin["precio_unitario"])
    s = t["stock"]
    for col in ["id_modelo", "talla"]:
        s[col] = num(s[col]).astype("Int64")
    s["stock_disponible"] = num(s["stock_disponible"])
    s["fecha_corte"] = pd.to_datetime(s["fecha_corte"], format="%Y-%m-%d", errors="coerce")
    return t


class Auditoria:
    def __init__(self):
        self.filas = []

    def marcar(self, df, mascara, tabla, regla, gravedad, tratamiento, clave):
        mascara = mascara.fillna(False).astype(bool)
        for _, f in df[mascara].iterrows():
            self.filas.append({
                "tabla": tabla,
                "registro": f[clave],
                "regla": regla,
                "gravedad": gravedad,
                "tratamiento": tratamiento,
            })
        return mascara

    def tabla(self):
        return pd.DataFrame(self.filas, columns=["tabla", "registro", "regla", "gravedad", "tratamiento"])


def validar(tablas):
    t = convertir_tipos({k: v.copy() for k, v in tablas.items()})
    a = Auditoria()
    entrada = {k: len(v) for k, v in t.items()}

    c, m, p, lin, s = t["clientes"], t["modelos"], t["pedidos"], t["lineas_pedido"], t["stock"]
    fecha_corte = s["fecha_corte"].max() if s["fecha_corte"].notna().any() else p["fecha"].max()

    a.marcar(c, c["id_cliente"].duplicated(keep=False), "clientes", "R02 · id_cliente duplicado", "bloqueante", "no se publica", "id_cliente")
    a.marcar(m, m["id_modelo"].duplicated(keep=False), "modelos", "R02 · id_modelo duplicado", "bloqueante", "no se publica", "id_modelo")
    a.marcar(p, p["id_pedido"].duplicated(keep=False), "pedidos", "R02 · id_pedido duplicado", "bloqueante", "no se publica", "id_pedido")
    a.marcar(lin, lin["id_linea"].duplicated(keep=False), "lineas_pedido", "R02 · id_linea duplicado", "bloqueante", "no se publica", "id_linea")

    huerf_cli = p["id_cliente"].notna() & ~p["id_cliente"].isin(c["id_cliente"])
    a.marcar(p, huerf_cli, "pedidos", "R03 · cliente inexistente", "bloqueante", "no se publica", "id_pedido")
    huerf_ped = lin["id_pedido"].notna() & ~lin["id_pedido"].isin(p["id_pedido"])
    a.marcar(lin, huerf_ped, "lineas_pedido", "R03 · pedido inexistente", "bloqueante", "no se publica", "id_linea")
    huerf_mod = lin["id_modelo"].notna() & ~lin["id_modelo"].isin(m["id_modelo"])
    a.marcar(lin, huerf_mod, "lineas_pedido", "R03 · modelo inexistente", "bloqueante", "no se publica", "id_linea")

    fuera_p = a.marcar(p, p["fecha"].isna(), "pedidos", "R04 · fecha nula o imposible", "recuperable", "se excluye el pedido", "id_pedido")
    fuera_p |= a.marcar(p, ~p["estado"].isin(config.ESTADOS), "pedidos", "R07 · estado fuera de catálogo", "recuperable", "se excluye el pedido", "id_pedido")
    fuera_p |= a.marcar(p, ~p["tipo"].isin(config.TIPOS), "pedidos", "R07 · tipo fuera de catálogo", "recuperable", "se excluye el pedido", "id_pedido")
    fuera_p |= a.marcar(p, p["id_cliente"].isna(), "pedidos", "R09 · pedido sin cliente", "recuperable", "se excluye el pedido", "id_pedido")
    a.marcar(p, p["fecha"] > fecha_corte, "pedidos", "R12 · fecha posterior al corte", "advertencia", "se conserva", "id_pedido")

    fuera_l = a.marcar(lin, lin["cantidad"].isna() | (lin["cantidad"] <= 0), "lineas_pedido", "R05 · cantidad nula, cero o negativa", "recuperable", "se excluye la línea", "id_linea")
    fuera_l |= a.marcar(lin, lin["precio_unitario"].isna() | (lin["precio_unitario"] < 0), "lineas_pedido", "R06 · precio no numérico o negativo", "recuperable", "se excluye la línea", "id_linea")
    fuera_l |= a.marcar(lin, ~lin["talla"].isin(config.TALLAS), "lineas_pedido", "R08 · talla no válida", "recuperable", "se excluye la línea", "id_linea")
    fuera_l |= a.marcar(lin, lin["id_modelo"].isna(), "lineas_pedido", "R09 · línea sin modelo", "recuperable", "se excluye la línea", "id_linea")
    excluidos = p.loc[fuera_p, "id_pedido"]
    fuera_l |= a.marcar(lin, lin["id_pedido"].isin(excluidos), "lineas_pedido", "R12 · línea de un pedido excluido", "recuperable", "se excluye la línea", "id_linea")
    clave = ["id_pedido", "id_modelo", "talla", "precio_unitario"]
    a.marcar(lin, lin.duplicated(clave, keep=False), "lineas_pedido", "R10 · línea repetida (pedido, modelo, talla, precio)", "advertencia", "se conserva: puede ser otro color", "id_linea")

    fuera_s = a.marcar(s, s["stock_disponible"].isna() | (s["stock_disponible"] < 0), "stock", "R11 · stock nulo o negativo", "recuperable", "se excluye la variante", "id_modelo")
    fuera_s |= a.marcar(s, s.duplicated(["id_modelo", "talla"]), "stock", "R11 · variante modelo-talla duplicada", "recuperable", "se conserva la primera", "id_modelo")
    fuera_s |= a.marcar(s, ~s["talla"].isin(config.TALLAS), "stock", "R08 · talla no válida", "recuperable", "se excluye la variante", "id_modelo")

    p_ok = p[~fuera_p]
    l_ok = lin[~fuera_l & lin["id_pedido"].isin(p_ok["id_pedido"])]
    ventas_sin_lineas = p_ok["estado"].isin(config.ESTADOS_VENTA) & ~p_ok["id_pedido"].isin(l_ok["id_pedido"])
    a.marcar(p_ok, ventas_sin_lineas, "pedidos", "R12 · pedido de venta sin líneas", "advertencia", "se conserva", "id_pedido")

    limpias = {"clientes": c, "modelos": m, "pedidos": p_ok, "lineas_pedido": l_ok, "stock": s[~fuera_s]}
    incidencias = a.tabla()
    resumen = resumen_calidad(t, limpias, entrada, incidencias)
    return limpias, incidencias, resumen, fecha_corte


def resumen_calidad(originales, limpias, entrada, incidencias):
    filas = []
    for nombre, df in originales.items():
        validas = len(limpias[nombre])
        inc = incidencias[incidencias["tabla"] == nombre]
        filas.append({
            "tabla": nombre,
            "filas_entrada": entrada[nombre],
            "filas_validas": validas,
            "filas_rechazadas": entrada[nombre] - validas,
            "pct_calidad": round(100 * validas / entrada[nombre], 1) if entrada[nombre] else 0.0,
            "nulos": int(df.isna().sum().sum()),
            "bloqueantes": int((inc["gravedad"] == "bloqueante").sum()),
            "recuperables": int((inc["gravedad"] == "recuperable").sum()),
            "advertencias": int((inc["gravedad"] == "advertencia").sum()),
        })
    return pd.DataFrame(filas)


def unir(t, fecha_corte):
    pedidos = t["pedidos"].merge(
        t["clientes"].rename(columns={"tipo": "tipo_cliente"}),
        on="id_cliente", how="left", validate="many_to_one", indicator=True,
    )
    if (pedidos["_merge"] != "both").any():
        raise ErrorCarga("R03 · hay pedidos cuyo cliente no se encuentra")
    lineas = t["lineas_pedido"].merge(
        pedidos.drop(columns="_merge"), on="id_pedido", how="left", validate="many_to_one", indicator=True,
    )
    if (lineas["_merge"] != "both").any():
        raise ErrorCarga("R03 · hay líneas cuyo pedido no se encuentra")
    lineas = lineas.drop(columns="_merge").merge(t["modelos"], on="id_modelo", how="left", validate="many_to_one")
    if len(lineas) != len(t["lineas_pedido"]):
        raise ErrorCarga("El cruce de tablas ha multiplicado filas")

    lineas["importe_linea"] = lineas["cantidad"] * lineas["precio_unitario"]
    lineas["es_venta"] = lineas["estado"].isin(config.ESTADOS_VENTA)
    lineas["anio"] = lineas["fecha"].dt.year
    lineas["mes"] = lineas["fecha"].dt.to_period("M").astype(str)
    lineas["trimestre"] = lineas["fecha"].dt.to_period("Q").astype(str)
    lineas["dia_semana"] = lineas["fecha"].dt.day_name()
    lineas["antiguedad_dias"] = (fecha_corte - lineas["fecha"]).dt.days
    return lineas


def ejecutar(directorio=config.DIR_REAL):
    inicio = datetime.now()
    tablas = cargar(directorio)
    limpias, incidencias, resumen, fecha_corte = validar(tablas)
    valido = not (incidencias["gravedad"] == "bloqueante").any()
    lineas = unir(limpias, fecha_corte) if valido else None
    ruta_sql = Path(directorio) / config.FICHERO_SQL
    sql = pd.read_csv(ruta_sql) if ruta_sql.exists() else None
    return {
        "tablas": limpias,
        "lineas": lineas,
        "incidencias": incidencias,
        "resumen_calidad": resumen,
        "manifiesto": manifiesto(directorio),
        "fecha_corte": fecha_corte,
        "valido": valido,
        "sql": sql,
        "segundos": round((datetime.now() - inicio).total_seconds(), 2),
    }


def registrar_log(origen, estado, filas, segundos, detalle=""):
    config.DIR_LOGS.mkdir(exist_ok=True)
    linea = f"{datetime.now():%Y-%m-%d %H:%M:%S} | {origen} | estado={estado} | filas={filas} | {segundos}s | {detalle}\n"
    with open(config.DIR_LOGS / "ejecuciones.log", "a", encoding="utf-8") as f:
        f.write(linea)
