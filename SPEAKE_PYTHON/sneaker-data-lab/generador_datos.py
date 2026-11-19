import argparse

import numpy as np
import pandas as pd

import config

# modelos inventados: nombre, categoria y precio
MODELOS = [
    ("SPEAKE Court", "Urbano", 89), ("SPEAKE Pulse", "Deportivo", 109), ("SPEAKE High", "Baloncesto", 99),
    ("SPEAKE Retro", "Urbano", 95), ("SPEAKE Street", "Urbano", 92), ("SPEAKE Aero", "Running", 105),
    ("SPEAKE Trail", "Montaña", 115), ("SPEAKE Kids", "Infantil", 59), ("SPEAKE Pro", "Deportivo", 129),
    ("SPEAKE Flow", "Running", 112), ("SPEAKE Classic", "Urbano", 85), ("SPEAKE Court Low", "Urbano", 79),
]
TALLAS = np.array(config.TALLAS)
# las tallas del medio se venden mas
PESO_TALLAS = np.array([3, 6, 10, 15, 19, 17, 13, 10, 7], dtype=float)
# unos meses se vende mas que otros (de enero a diciembre)
PESO_MES = np.array([0.7, 0.8, 1.0, 1.1, 1.2, 1.0, 0.8, 0.7, 1.3, 1.4, 1.2, 1.5])


# genera datos inventados para tener mas volumen que los reales
# con la misma semilla siempre salen los mismos datos
def generar(semilla=config.SEMILLA, n_pedidos=900, n_clientes=40, meses=18):
    rng = np.random.default_rng(semilla)

    # clientes
    tipos_cli = rng.choice(["particular", "club", "equipo"], n_clientes, p=[0.7, 0.2, 0.1])
    nombres = []
    for i in range(1, n_clientes + 1):
        nombres.append(f"Cliente sintético {i:02d}")
    clientes = pd.DataFrame({
        "id_cliente": range(1, n_clientes + 1),
        "nombre": nombres,
        "tipo": tipos_cli,
    })

    # modelos y sus precios
    filas_modelos = []
    precios = {}
    for i in range(len(MODELOS)):
        nombre, categoria, precio = MODELOS[i]
        filas_modelos.append({"id_modelo": i + 1, "modelo": nombre, "categoria": categoria})
        precios[i + 1] = precio
    modelos = pd.DataFrame(filas_modelos)

    # fechas de los pedidos repartidas en 18 meses
    inicio = pd.Timestamp("2025-05-01")
    dias = pd.date_range(inicio, inicio + pd.DateOffset(months=meses) - pd.Timedelta(days=1))
    peso_dia = PESO_MES[dias.month - 1]
    fechas = rng.choice(dias, n_pedidos, p=peso_dia / peso_dia.sum())

    # unos clientes compran mucho mas que otros
    peso_cli = rng.gamma(1.5, 1.0, n_clientes)
    id_cli = rng.choice(clientes["id_cliente"], n_pedidos, p=peso_cli / peso_cli.sum())

    # los clubes y equipos piden custom mas a menudo que los particulares
    tipo_cli = clientes.set_index("id_cliente").loc[id_cli, "tipo"].to_numpy()
    custom_particular = rng.random(n_pedidos) < 0.15
    custom_club = rng.random(n_pedidos) < 0.7
    custom = np.where(tipo_cli == "particular", custom_particular, custom_club)

    pedidos = pd.DataFrame({
        "id_pedido": range(1, n_pedidos + 1),
        "fecha": pd.to_datetime(fechas).strftime("%Y-%m-%d"),
        "id_cliente": id_cli,
        "estado": rng.choice(config.ESTADOS, n_pedidos, p=[0.1, 0.35, 0.45, 0.1]),
        "tipo": np.where(custom, "custom", "estandar"),
    })
    # ordenamos por fecha y volvemos a numerar
    pedidos = pedidos.sort_values("fecha").reset_index(drop=True)
    pedidos["id_pedido"] = range(1, n_pedidos + 1)

    # lineas de cada pedido
    peso_mod = np.linspace(2.0, 0.5, len(MODELOS))
    lineas = []
    for i in range(len(pedidos)):
        p = pedidos.iloc[i]
        # algunos custom son pedidos grandes de club (varias tallas y muchos pares)
        grande = False
        if p["tipo"] == "custom":
            grande = rng.random() < 0.3
        if grande:
            n_lineas = rng.integers(3, 8)
        else:
            n_lineas = rng.integers(1, 3)

        modelo = rng.choice(modelos["id_modelo"], p=peso_mod / peso_mod.sum())
        tallas = rng.choice(TALLAS, n_lineas, replace=False, p=PESO_TALLAS / PESO_TALLAS.sum())
        for talla in tallas:
            if grande:
                cantidad = int(rng.integers(2, 9))
            else:
                cantidad = int(rng.integers(1, 3))
            # el custom cuesta 15 euros mas
            extra = 0
            if p["tipo"] == "custom":
                extra = 15
            lineas.append({
                "id_linea": len(lineas) + 1,
                "id_pedido": p["id_pedido"],
                "id_modelo": int(modelo),
                "talla": int(talla),
                "cantidad": cantidad,
                "precio_unitario": float(precios[modelo] + extra),
            })
    lineas = pd.DataFrame(lineas)

    # stock de cada modelo y talla en el ultimo dia
    corte = dias[-1].strftime("%Y-%m-%d")
    filas_stock = []
    for m in modelos["id_modelo"]:
        for t in TALLAS:
            filas_stock.append({"id_modelo": m, "talla": t, "stock_disponible": int(rng.integers(0, 60)), "fecha_corte": corte})
    stock = pd.DataFrame(filas_stock)

    return {"clientes": clientes, "modelos": modelos, "pedidos": pedidos, "lineas_pedido": lineas, "stock": stock}


# la misma copia pero con errores metidos a proposito para probar la validacion
def con_incidencias(datos):
    d = {}
    for nombre in datos:
        d[nombre] = datos[nombre].astype(str)
    d["pedidos"].loc[0, "fecha"] = "2025-13-45"
    d["pedidos"].loc[1, "estado"] = "perdido"
    d["lineas_pedido"].loc[0, "cantidad"] = "-2"
    d["lineas_pedido"].loc[1, "talla"] = "52"
    d["lineas_pedido"].loc[2, "precio_unitario"] = "gratis"
    d["stock"].loc[0, "stock_disponible"] = "-5"
    return d


# guarda cada tabla en su csv
def guardar(datos, carpeta):
    carpeta.mkdir(parents=True, exist_ok=True)
    for nombre in datos:
        datos[nombre].to_csv(carpeta / (nombre + ".csv"), index=False, encoding="utf-8")
    aviso = "DATOS SINTÉTICOS generados con generador_datos.py (semilla fija). No son ventas reales.\n"
    (carpeta / "LEEME.txt").write_text(aviso, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Genera el histórico SINTÉTICO de SPEAKE")
    parser.add_argument("--semilla", type=int, default=config.SEMILLA)
    args = parser.parse_args()

    datos = generar(args.semilla)
    guardar(datos, config.DIR_SINTETICO)
    guardar(con_incidencias(datos), config.DIR_SINTETICO / "con_incidencias")
    for nombre in datos:
        print(nombre, len(datos[nombre]))


if __name__ == "__main__":
    main()
