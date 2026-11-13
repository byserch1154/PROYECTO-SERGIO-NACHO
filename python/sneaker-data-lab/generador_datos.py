import argparse

import numpy as np
import pandas as pd

import config

MODELOS = [
    ("SPEAKE Court", "Urbano", 89), ("SPEAKE Pulse", "Deportivo", 109), ("SPEAKE High", "Baloncesto", 99),
    ("SPEAKE Retro", "Urbano", 95), ("SPEAKE Street", "Urbano", 92), ("SPEAKE Aero", "Running", 105),
    ("SPEAKE Trail", "Montaña", 115), ("SPEAKE Kids", "Infantil", 59), ("SPEAKE Pro", "Deportivo", 129),
    ("SPEAKE Flow", "Running", 112), ("SPEAKE Classic", "Urbano", 85), ("SPEAKE Court Low", "Urbano", 79),
]
TALLAS = np.array(config.TALLAS)
PESO_TALLAS = np.array([3, 6, 10, 15, 19, 17, 13, 10, 7], dtype=float)
PESO_MES = np.array([0.7, 0.8, 1.0, 1.1, 1.2, 1.0, 0.8, 0.7, 1.3, 1.4, 1.2, 1.5])


def generar(semilla=config.SEMILLA, n_pedidos=900, n_clientes=40, meses=18):
    rng = np.random.default_rng(semilla)
    tipos_cli = rng.choice(["particular", "club", "equipo"], n_clientes, p=[0.7, 0.2, 0.1])
    clientes = pd.DataFrame({
        "id_cliente": range(1, n_clientes + 1),
        "nombre": [f"Cliente sintético {i:02d}" for i in range(1, n_clientes + 1)],
        "tipo": tipos_cli,
    })
    modelos = pd.DataFrame([
        {"id_modelo": i + 1, "modelo": n, "categoria": c} for i, (n, c, _) in enumerate(MODELOS)
    ])
    precios = {i + 1: p for i, (_, _, p) in enumerate(MODELOS)}

    inicio = pd.Timestamp("2025-05-01")
    dias = pd.date_range(inicio, inicio + pd.DateOffset(months=meses) - pd.Timedelta(days=1))
    peso_dia = PESO_MES[dias.month - 1]
    fechas = rng.choice(dias, n_pedidos, p=peso_dia / peso_dia.sum())
    peso_cli = rng.gamma(1.5, 1.0, n_clientes)
    id_cli = rng.choice(clientes["id_cliente"], n_pedidos, p=peso_cli / peso_cli.sum())
    tipo_cli = clientes.set_index("id_cliente").loc[id_cli, "tipo"].to_numpy()
    custom = np.where(tipo_cli == "particular", rng.random(n_pedidos) < 0.15, rng.random(n_pedidos) < 0.7)
    pedidos = pd.DataFrame({
        "id_pedido": range(1, n_pedidos + 1),
        "fecha": pd.to_datetime(fechas).strftime("%Y-%m-%d"),
        "id_cliente": id_cli,
        "estado": rng.choice(config.ESTADOS, n_pedidos, p=[0.1, 0.35, 0.45, 0.1]),
        "tipo": np.where(custom, "custom", "estandar"),
    }).sort_values("fecha").reset_index(drop=True)
    pedidos["id_pedido"] = range(1, n_pedidos + 1)

    peso_mod = np.linspace(2.0, 0.5, len(MODELOS))
    lineas = []
    for _, p in pedidos.iterrows():
        grande = p["tipo"] == "custom" and rng.random() < 0.3
        n_lineas = rng.integers(3, 8) if grande else rng.integers(1, 3)
        modelo = rng.choice(modelos["id_modelo"], p=peso_mod / peso_mod.sum())
        for talla in rng.choice(TALLAS, n_lineas, replace=False, p=PESO_TALLAS / PESO_TALLAS.sum()):
            cantidad = int(rng.integers(2, 9)) if grande else int(rng.integers(1, 3))
            extra = 15 if p["tipo"] == "custom" else 0
            lineas.append({
                "id_linea": len(lineas) + 1,
                "id_pedido": p["id_pedido"],
                "id_modelo": int(modelo),
                "talla": int(talla),
                "cantidad": cantidad,
                "precio_unitario": float(precios[modelo] + extra),
            })
    lineas = pd.DataFrame(lineas)

    corte = dias[-1].strftime("%Y-%m-%d")
    stock = pd.DataFrame([
        {"id_modelo": m, "talla": t, "stock_disponible": int(rng.integers(0, 60)), "fecha_corte": corte}
        for m in modelos["id_modelo"] for t in TALLAS
    ])
    return {"clientes": clientes, "modelos": modelos, "pedidos": pedidos, "lineas_pedido": lineas, "stock": stock}


def con_incidencias(datos):
    d = {k: v.astype(str) for k, v in datos.items()}
    d["pedidos"].loc[0, "fecha"] = "2025-13-45"
    d["pedidos"].loc[1, "estado"] = "perdido"
    d["lineas_pedido"].loc[0, "cantidad"] = "-2"
    d["lineas_pedido"].loc[1, "talla"] = "52"
    d["lineas_pedido"].loc[2, "precio_unitario"] = "gratis"
    d["stock"].loc[0, "stock_disponible"] = "-5"
    return d


def guardar(datos, carpeta):
    carpeta.mkdir(parents=True, exist_ok=True)
    for nombre, df in datos.items():
        df.to_csv(carpeta / f"{nombre}.csv", index=False, encoding="utf-8")
    (carpeta / "LEEME.txt").write_text(
        "DATOS SINTÉTICOS generados con generador_datos.py (semilla fija). No son ventas reales.\n", encoding="utf-8"
    )


def main():
    parser = argparse.ArgumentParser(description="Genera el histórico SINTÉTICO de SPEAKE")
    parser.add_argument("--semilla", type=int, default=config.SEMILLA)
    args = parser.parse_args()
    datos = generar(args.semilla)
    guardar(datos, config.DIR_SINTETICO)
    guardar(con_incidencias(datos), config.DIR_SINTETICO / "con_incidencias")
    print({k: len(v) for k, v in datos.items()})


if __name__ == "__main__":
    main()
