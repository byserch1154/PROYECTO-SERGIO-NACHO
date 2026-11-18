from datetime import datetime
from pathlib import Path

import pandas as pd

import config


# error propio para cuando no se pueden cargar los csv
class ErrorCarga(Exception):
    pass


# tabla con la info de cada fichero (si existe, filas, columnas, tamaño y fecha)
def manifiesto(directorio):
    nombres = list(config.ESQUEMA.keys())
    nombres.append("reconciliacion_sql")
    ahora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    filas = []
    for nombre in nombres:
        ruta = Path(directorio) / (nombre + ".csv")
        fila = {"fichero": ruta.name, "existe": False, "fecha_analisis": ahora,
                "filas": 0, "columnas": 0, "bytes": 0, "modificado": ""}
        if ruta.exists():
            fila["existe"] = True
            fila["bytes"] = ruta.stat().st_size
            fila["modificado"] = datetime.fromtimestamp(ruta.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
            if fila["bytes"] > 0:
                df = pd.read_csv(ruta, dtype=str)
                fila["filas"] = len(df)
                fila["columnas"] = len(df.columns)
        filas.append(fila)
    return pd.DataFrame(filas)


# R01: leer los csv y comprobar que estan todos y con sus columnas
def cargar(directorio):
    directorio = Path(directorio)
    if not directorio.is_dir():
        raise ErrorCarga("R01 · No existe la carpeta " + str(directorio))

    tablas = {}
    for nombre in config.ESQUEMA:
        columnas = config.ESQUEMA[nombre]
        ruta = directorio / (nombre + ".csv")
        if not ruta.exists():
            raise ErrorCarga("R01 · Falta el fichero " + ruta.name)

        # todo como texto, luego convertimos nosotros los tipos
        try:
            df = pd.read_csv(ruta, dtype=str, encoding="utf-8", sep=",", keep_default_na=False, na_values=[""])
        except pd.errors.EmptyDataError:
            raise ErrorCarga("R01 · " + ruta.name + " está vacío")

        # quitamos espacios y el BOM que a veces mete excel en la primera columna
        nuevas = []
        for c in df.columns:
            nuevas.append(c.strip().lstrip("﻿"))
        df.columns = nuevas

        faltan = []
        for c in columnas:
            if c not in df.columns:
                faltan.append(c)
        if len(faltan) > 0:
            raise ErrorCarga("R01 · " + ruta.name + ": faltan columnas " + str(faltan))

        tablas[nombre] = df[columnas].copy()
    return tablas


# pasa un texto a numero entero; si no se puede queda vacio (NA)
def a_entero(columna):
    return pd.to_numeric(columna, errors="coerce").astype("Int64")


def a_numero(columna):
    return pd.to_numeric(columna, errors="coerce")


def a_fecha(columna):
    return pd.to_datetime(columna, format="%Y-%m-%d", errors="coerce")


# convertimos cada columna a su tipo; lo que no se puede convertir queda nulo
def convertir_tipos(t):
    t["clientes"]["id_cliente"] = a_entero(t["clientes"]["id_cliente"])
    t["modelos"]["id_modelo"] = a_entero(t["modelos"]["id_modelo"])

    p = t["pedidos"]
    p["id_pedido"] = a_entero(p["id_pedido"])
    p["id_cliente"] = a_entero(p["id_cliente"])
    p["fecha"] = a_fecha(p["fecha"])
    p["estado"] = p["estado"].str.strip().str.lower()
    p["tipo"] = p["tipo"].str.strip().str.lower()

    lin = t["lineas_pedido"]
    lin["id_linea"] = a_entero(lin["id_linea"])
    lin["id_pedido"] = a_entero(lin["id_pedido"])
    lin["id_modelo"] = a_entero(lin["id_modelo"])
    lin["talla"] = a_entero(lin["talla"])
    lin["cantidad"] = a_numero(lin["cantidad"])
    lin["precio_unitario"] = a_numero(lin["precio_unitario"])

    s = t["stock"]
    s["id_modelo"] = a_entero(s["id_modelo"])
    s["talla"] = a_entero(s["talla"])
    s["stock_disponible"] = a_numero(s["stock_disponible"])
    s["fecha_corte"] = a_fecha(s["fecha_corte"])
    return t


# aqui vamos guardando cada fila que incumple una regla
class Auditoria:
    def __init__(self):
        self.filas = []

    # mascara = serie de True/False con las filas que fallan
    def marcar(self, df, mascara, tabla, regla, gravedad, tratamiento, clave):
        mascara = mascara.fillna(False).astype(bool)
        malas = df[mascara]
        for i in range(len(malas)):
            self.filas.append({
                "tabla": tabla,
                "registro": malas[clave].iloc[i],
                "regla": regla,
                "gravedad": gravedad,
                "tratamiento": tratamiento,
            })
        return mascara

    def tabla(self):
        return pd.DataFrame(self.filas, columns=["tabla", "registro", "regla", "gravedad", "tratamiento"])


# reglas de calidad R02-R12
# bloqueante = no se publica ningun calculo
# recuperable = se quita esa fila y seguimos
# advertencia = solo se avisa
def validar(tablas):
    # copia para no tocar lo que hemos leido
    t = {}
    for nombre in tablas:
        t[nombre] = tablas[nombre].copy()
    t = convertir_tipos(t)

    entrada = {}
    for nombre in t:
        entrada[nombre] = len(t[nombre])

    c = t["clientes"]
    m = t["modelos"]
    p = t["pedidos"]
    lin = t["lineas_pedido"]
    s = t["stock"]

    # fecha de corte = la del stock; si no hay, la del ultimo pedido
    if s["fecha_corte"].notna().any():
        fecha_corte = s["fecha_corte"].max()
    else:
        fecha_corte = p["fecha"].max()

    a = Auditoria()

    # R02 ids repetidos
    a.marcar(c, c["id_cliente"].duplicated(keep=False), "clientes", "R02 · id_cliente duplicado", "bloqueante", "no se publica", "id_cliente")
    a.marcar(m, m["id_modelo"].duplicated(keep=False), "modelos", "R02 · id_modelo duplicado", "bloqueante", "no se publica", "id_modelo")
    a.marcar(p, p["id_pedido"].duplicated(keep=False), "pedidos", "R02 · id_pedido duplicado", "bloqueante", "no se publica", "id_pedido")
    a.marcar(lin, lin["id_linea"].duplicated(keep=False), "lineas_pedido", "R02 · id_linea duplicado", "bloqueante", "no se publica", "id_linea")

    # R03 ids que apuntan a algo que no existe (como una clave ajena rota)
    sin_cliente = p["id_cliente"].notna() & ~p["id_cliente"].isin(c["id_cliente"])
    a.marcar(p, sin_cliente, "pedidos", "R03 · cliente inexistente", "bloqueante", "no se publica", "id_pedido")
    sin_pedido = lin["id_pedido"].notna() & ~lin["id_pedido"].isin(p["id_pedido"])
    a.marcar(lin, sin_pedido, "lineas_pedido", "R03 · pedido inexistente", "bloqueante", "no se publica", "id_linea")
    sin_modelo = lin["id_modelo"].notna() & ~lin["id_modelo"].isin(m["id_modelo"])
    a.marcar(lin, sin_modelo, "lineas_pedido", "R03 · modelo inexistente", "bloqueante", "no se publica", "id_linea")

    # pedidos que quitamos (R04, R07, R09)
    fuera_p = a.marcar(p, p["fecha"].isna(), "pedidos", "R04 · fecha nula o imposible", "recuperable", "se excluye el pedido", "id_pedido")
    fuera_p = fuera_p | a.marcar(p, ~p["estado"].isin(config.ESTADOS), "pedidos", "R07 · estado fuera de catálogo", "recuperable", "se excluye el pedido", "id_pedido")
    fuera_p = fuera_p | a.marcar(p, ~p["tipo"].isin(config.TIPOS), "pedidos", "R07 · tipo fuera de catálogo", "recuperable", "se excluye el pedido", "id_pedido")
    fuera_p = fuera_p | a.marcar(p, p["id_cliente"].isna(), "pedidos", "R09 · pedido sin cliente", "recuperable", "se excluye el pedido", "id_pedido")
    a.marcar(p, p["fecha"] > fecha_corte, "pedidos", "R12 · fecha posterior al corte", "advertencia", "se conserva", "id_pedido")

    # lineas que quitamos (R05, R06, R08, R09 y las de pedidos quitados)
    mala_cantidad = lin["cantidad"].isna() | (lin["cantidad"] <= 0)
    fuera_l = a.marcar(lin, mala_cantidad, "lineas_pedido", "R05 · cantidad nula, cero o negativa", "recuperable", "se excluye la línea", "id_linea")
    mal_precio = lin["precio_unitario"].isna() | (lin["precio_unitario"] < 0)
    fuera_l = fuera_l | a.marcar(lin, mal_precio, "lineas_pedido", "R06 · precio no numérico o negativo", "recuperable", "se excluye la línea", "id_linea")
    fuera_l = fuera_l | a.marcar(lin, ~lin["talla"].isin(config.TALLAS), "lineas_pedido", "R08 · talla no válida", "recuperable", "se excluye la línea", "id_linea")
    fuera_l = fuera_l | a.marcar(lin, lin["id_modelo"].isna(), "lineas_pedido", "R09 · línea sin modelo", "recuperable", "se excluye la línea", "id_linea")
    pedidos_quitados = p.loc[fuera_p, "id_pedido"]
    fuera_l = fuera_l | a.marcar(lin, lin["id_pedido"].isin(pedidos_quitados), "lineas_pedido", "R12 · línea de un pedido excluido", "recuperable", "se excluye la línea", "id_linea")

    # R10 lineas iguales: solo avisamos porque pueden ser de distinto color
    repetidas = lin.duplicated(["id_pedido", "id_modelo", "talla", "precio_unitario"], keep=False)
    a.marcar(lin, repetidas, "lineas_pedido", "R10 · línea repetida (pedido, modelo, talla, precio)", "advertencia", "se conserva: puede ser otro color", "id_linea")

    # R11 stock
    mal_stock = s["stock_disponible"].isna() | (s["stock_disponible"] < 0)
    fuera_s = a.marcar(s, mal_stock, "stock", "R11 · stock nulo o negativo", "recuperable", "se excluye la variante", "id_modelo")
    fuera_s = fuera_s | a.marcar(s, s.duplicated(["id_modelo", "talla"]), "stock", "R11 · variante modelo-talla duplicada", "recuperable", "se conserva la primera", "id_modelo")
    fuera_s = fuera_s | a.marcar(s, ~s["talla"].isin(config.TALLAS), "stock", "R08 · talla no válida", "recuperable", "se excluye la variante", "id_modelo")

    # nos quedamos solo con lo bueno
    p_ok = p[~fuera_p]
    l_ok = lin[~fuera_l & lin["id_pedido"].isin(p_ok["id_pedido"])]
    s_ok = s[~fuera_s]

    venta_sin_lineas = p_ok["estado"].isin(config.ESTADOS_VENTA) & ~p_ok["id_pedido"].isin(l_ok["id_pedido"])
    a.marcar(p_ok, venta_sin_lineas, "pedidos", "R12 · pedido de venta sin líneas", "advertencia", "se conserva", "id_pedido")

    limpias = {"clientes": c, "modelos": m, "pedidos": p_ok, "lineas_pedido": l_ok, "stock": s_ok}
    incidencias = a.tabla()
    resumen = resumen_calidad(t, limpias, entrada, incidencias)
    return limpias, incidencias, resumen, fecha_corte


# una fila por tabla: cuantas entran, cuantas valen y cuantos fallos de cada tipo
def resumen_calidad(originales, limpias, entrada, incidencias):
    filas = []
    for nombre in originales:
        total = entrada[nombre]
        validas = len(limpias[nombre])
        inc = incidencias[incidencias["tabla"] == nombre]
        if total > 0:
            pct = round(100 * validas / total, 1)
        else:
            pct = 0.0
        filas.append({
            "tabla": nombre,
            "filas_entrada": total,
            "filas_validas": validas,
            "filas_rechazadas": total - validas,
            "pct_calidad": pct,
            "nulos": int(originales[nombre].isna().sum().sum()),
            "bloqueantes": int((inc["gravedad"] == "bloqueante").sum()),
            "recuperables": int((inc["gravedad"] == "recuperable").sum()),
            "advertencias": int((inc["gravedad"] == "advertencia").sum()),
        })
    return pd.DataFrame(filas)


# juntamos lineas + pedidos + clientes + modelos en una sola tabla
# validate="many_to_one": cada linea tiene que encontrar UN solo pedido, cliente y modelo
# si no, pandas da error en vez de duplicar filas sin avisar
def unir(t, fecha_corte):
    clientes = t["clientes"].rename(columns={"tipo": "tipo_cliente"})
    if (~t["pedidos"]["id_cliente"].isin(clientes["id_cliente"])).any():
        raise ErrorCarga("R03 · hay pedidos cuyo cliente no se encuentra")
    pedidos = t["pedidos"].merge(clientes, on="id_cliente", how="left", validate="many_to_one")

    if (~t["lineas_pedido"]["id_pedido"].isin(pedidos["id_pedido"])).any():
        raise ErrorCarga("R03 · hay líneas cuyo pedido no se encuentra")
    lineas = t["lineas_pedido"].merge(pedidos, on="id_pedido", how="left", validate="many_to_one")

    lineas = lineas.merge(t["modelos"], on="id_modelo", how="left", validate="many_to_one")

    # comprobacion extra: tienen que salir las mismas filas que lineas habia
    if len(lineas) != len(t["lineas_pedido"]):
        raise ErrorCarga("El cruce de tablas ha multiplicado filas")

    # columnas nuevas que usamos en los calculos
    lineas["importe_linea"] = lineas["cantidad"] * lineas["precio_unitario"]
    lineas["es_venta"] = lineas["estado"].isin(config.ESTADOS_VENTA)
    lineas["anio"] = lineas["fecha"].dt.year
    lineas["mes"] = lineas["fecha"].dt.to_period("M").astype(str)
    lineas["trimestre"] = lineas["fecha"].dt.to_period("Q").astype(str)
    lineas["dia_semana"] = lineas["fecha"].dt.day_name()
    lineas["antiguedad_dias"] = (fecha_corte - lineas["fecha"]).dt.days
    return lineas


# todo el proceso: cargar -> validar -> unir (lo usan main.py y el dashboard)
def ejecutar(directorio=config.DIR_REAL):
    inicio = datetime.now()
    tablas = cargar(directorio)
    limpias, incidencias, resumen, fecha_corte = validar(tablas)

    # si hay alguna incidencia bloqueante no seguimos
    valido = True
    if (incidencias["gravedad"] == "bloqueante").any():
        valido = False

    lineas = None
    if valido:
        lineas = unir(limpias, fecha_corte)

    # totales calculados en SQL para comparar luego (df12)
    sql = None
    ruta_sql = Path(directorio) / config.FICHERO_SQL
    if ruta_sql.exists():
        sql = pd.read_csv(ruta_sql)

    segundos = round((datetime.now() - inicio).total_seconds(), 2)
    return {
        "tablas": limpias,
        "lineas": lineas,
        "incidencias": incidencias,
        "resumen_calidad": resumen,
        "manifiesto": manifiesto(directorio),
        "fecha_corte": fecha_corte,
        "valido": valido,
        "sql": sql,
        "segundos": segundos,
    }


# añade una linea al log cada vez que se ejecuta
def registrar_log(origen, estado, filas, segundos, detalle=""):
    config.DIR_LOGS.mkdir(exist_ok=True)
    fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    linea = fecha + " | " + origen + " | estado=" + estado + " | filas=" + str(filas) + " | " + str(segundos) + "s | " + detalle + "\n"
    with open(config.DIR_LOGS / "ejecuciones.log", "a", encoding="utf-8") as f:
        f.write(linea)
