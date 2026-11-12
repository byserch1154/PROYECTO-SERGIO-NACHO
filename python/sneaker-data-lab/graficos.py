import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def _guardar(fig, carpeta, nombre):
    fig.tight_layout()
    fig.savefig(carpeta / f"{nombre}.png", dpi=110)
    plt.close(fig)


def generar(res, lineas, carpeta):
    carpeta.mkdir(parents=True, exist_ok=True)
    v = lineas[lineas["es_venta"]]

    fig, ax = plt.subplots()
    ax.bar(res["ventas_mes"]["mes"], res["ventas_mes"]["ingresos"])
    ax.set(title="Ingresos por mes", ylabel="€")
    _guardar(fig, carpeta, "01_ingresos_mes")

    fig, ax = plt.subplots()
    ax.plot(res["ventas_mes"]["mes"], res["ventas_mes"]["pares"], marker="o")
    ax.set(title="Pares vendidos por mes", ylabel="pares")
    _guardar(fig, carpeta, "02_pares_mes")

    fig, ax = plt.subplots()
    r = res["ranking_modelos"]
    ax.barh(r["modelo"], r["ingresos"])
    ax.set(title="Ingresos por modelo", xlabel="€")
    _guardar(fig, carpeta, "03_ranking_modelos")

    fig, ax = plt.subplots()
    t = v.groupby("talla")["cantidad"].sum()
    ax.bar(t.index.astype(str), t.values)
    ax.set(title="Pares vendidos por talla", xlabel="talla")
    _guardar(fig, carpeta, "04_tallas")

    fig, ax = plt.subplots()
    c = res["custom_vs_estandar"]
    if len(c):
        ax.pie(c["ingresos"], labels=c["tipo"], autopct="%1.0f%%")
    ax.set(title="Ingresos Custom frente a estándar")
    _guardar(fig, carpeta, "05_custom_estandar")

    fig, ax = plt.subplots()
    e = lineas.drop_duplicates("id_pedido")["estado"].value_counts()
    ax.bar(e.index, e.values)
    ax.set(title="Pedidos por estado")
    _guardar(fig, carpeta, "06_estados")

    fig, ax = plt.subplots()
    s = res["stock"]
    ax.bar(s["modelo"], s["stock"])
    ax.set(title="Stock disponible por modelo")
    ax.tick_params(axis="x", rotation=30)
    _guardar(fig, carpeta, "07_stock")

    fig, ax = plt.subplots()
    seg = res["segmentos"]
    ax.scatter(seg["frecuencia"], seg["importe"])
    for _, f in seg.iterrows():
        ax.annotate(str(f["segmento"]), (f["frecuencia"], f["importe"]), fontsize=7)
    ax.set(title="Segmentos de clientes", xlabel="pedidos", ylabel="€")
    _guardar(fig, carpeta, "08_segmentos")
