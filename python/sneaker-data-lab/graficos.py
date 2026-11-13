import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402


def _calculable(df):
    return "estado" not in df.columns


def _vacio(titulo):
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.text(0.5, 0.5, "Sin datos suficientes", ha="center", va="center")
    ax.set_title(titulo)
    ax.axis("off")
    return fig


def serie_mensual(res):
    df = res["df02_ventas_periodo"]
    titulo = "Ingresos por mes (€)"
    if not _calculable(df):
        return _vacio(titulo), "No hay ventas en el periodo."
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.plot(df["mes"], df["ingresos"], marker="o", label="Ingresos")
    ax.set(title=titulo, xlabel="mes", ylabel="€")
    ax.tick_params(axis="x", rotation=45)
    ax.legend()
    mejor = df.loc[df["ingresos"].idxmax(), "mes"]
    return fig, f"El mes con más ingresos es {mejor}."


def ranking_modelos(res):
    df = res["df03_modelos_abc"]
    titulo = "Ranking de modelos por ingresos (€)"
    if not _calculable(df):
        return _vacio(titulo), "No hay ventas en el periodo."
    fig, ax = plt.subplots(figsize=(8, 4))
    colores = df["clase"].map({"A": "tab:green", "B": "tab:orange", "C": "tab:red"})
    ax.barh(df["modelo"][::-1], df["ingresos"][::-1], color=colores[::-1])
    ax.set(title=titulo + " · color = clase ABC", xlabel="€")
    return fig, f"{df.iloc[0]['modelo']} concentra el {df.iloc[0]['peso_pct']} % de los ingresos."


def pareto(res):
    df = res["df03_modelos_abc"]
    titulo = "Pareto de modelos: % acumulado de ingresos"
    if not _calculable(df):
        return _vacio(titulo), "No hay ventas en el periodo."
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.bar(df["modelo"], df["peso_pct"], label="% del modelo")
    ax.plot(df["modelo"], df["acumulado_pct"], color="black", marker="o", label="% acumulado")
    ax.axhline(80, color="gray", linestyle="--", label="80 %")
    ax.set(title=titulo, ylabel="%")
    ax.tick_params(axis="x", rotation=45)
    ax.legend()
    n80 = int((df["acumulado_pct"] <= 80).sum()) + 1
    return fig, f"{min(n80, len(df))} modelo(s) suman el 80 % de los ingresos."


def histograma_ticket(res):
    p = res["df01_pedidos_unicos"]
    v = p[p["es_venta"]]
    titulo = "Distribución del importe por pedido (€)"
    if v.empty:
        return _vacio(titulo), "No hay ventas en el periodo."
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.hist(v["ticket_pedido"], bins=min(20, max(5, len(v) // 5)), edgecolor="white")
    ax.axvline(v["ticket_pedido"].median(), color="red", linestyle="--", label="mediana")
    ax.set(title=titulo, xlabel="€ por pedido", ylabel="nº de pedidos")
    ax.legend()
    return fig, f"La mediana ({v['ticket_pedido'].median():.0f} €) representa mejor el pedido típico que la media, porque los pedidos de club la disparan."


def boxplot_tipo(res):
    p = res["df01_pedidos_unicos"]
    v = p[p["es_venta"]]
    titulo = "Pares por pedido según tipo"
    if v.empty:
        return _vacio(titulo), "No hay ventas en el periodo."
    tipos = sorted(v["tipo"].unique())
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.boxplot([v.loc[v["tipo"] == t, "pares"] for t in tipos], tick_labels=tipos)
    ax.set(title=titulo, ylabel="pares por pedido")
    return fig, "Los pedidos Custom suelen tener más pares: son pedidos de clubes y equipos."


def mapa_calor(res):
    df = res["df04_modelo_talla"]
    titulo = "Pares vendidos por modelo y talla"
    if not _calculable(df):
        return _vacio(titulo), "No hay ventas en el periodo."
    cols = [c for c in df.columns if c.startswith("t") and c[1:].isdigit()]
    datos = df[cols].to_numpy()
    fig, ax = plt.subplots(figsize=(9, 4))
    im = ax.imshow(datos, cmap="Blues", aspect="auto")
    ax.set_xticks(range(len(cols)), [c[1:] for c in cols])
    ax.set_yticks(range(len(df)), df["modelo"])
    for i in range(datos.shape[0]):
        for j in range(datos.shape[1]):
            ax.text(j, i, int(datos[i, j]), ha="center", va="center", fontsize=7)
    fig.colorbar(im, ax=ax, label="pares")
    ax.set(title=titulo, xlabel="talla")
    return fig, "Las tallas centrales (41-43) concentran la demanda."


def dispersion_clientes(res):
    df = res["df06_clientes_rfm"]
    v = df[df["frequency"] > 0]
    titulo = "Clientes: nº de pedidos frente a importe (€)"
    if v.empty:
        return _vacio(titulo), "No hay clientes con compras."
    fig, ax = plt.subplots(figsize=(8, 4))
    for seg, g in v.groupby("segmento_rfm"):
        ax.scatter(g["frequency"], g["monetary"], label=seg)
    ax.set(title=titulo, xlabel="pedidos de venta", ylabel="€")
    ax.legend(fontsize=7)
    return fig, "Arriba a la derecha están los clientes más valiosos."


def comparativa_segmentos(res):
    df = res["df05_custom_vs_estandar"]
    titulo = "Custom frente a estándar: % de ingresos y de cancelaciones"
    if not _calculable(df):
        return _vacio(titulo), "No hay pedidos en el periodo."
    x = np.arange(len(df))
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(x - 0.2, df["cuota_ingresos_pct"], 0.4, label="% de ingresos")
    ax.bar(x + 0.2, df["tasa_cancelacion_pct"], 0.4, label="% de pedidos cancelados")
    ax.set_xticks(x, df["tipo"])
    ax.set(title=titulo, ylabel="%")
    ax.legend()
    return fig, "Compara el peso en euros con la tasa de cancelación de cada tipo."


FIGURAS = {
    "01_serie_mensual": serie_mensual,
    "02_ranking_modelos": ranking_modelos,
    "03_pareto": pareto,
    "04_histograma_ticket": histograma_ticket,
    "05_boxplot_tipo": boxplot_tipo,
    "06_mapa_calor_talla": mapa_calor,
    "07_dispersion_clientes": dispersion_clientes,
    "08_comparativa_custom": comparativa_segmentos,
}


def guardar_todas(res, carpeta, etiqueta):
    carpeta.mkdir(parents=True, exist_ok=True)
    lecturas = {}
    for nombre, funcion in FIGURAS.items():
        fig, lectura = funcion(res)
        fig.text(0.01, 0.01, etiqueta, fontsize=7, color="gray")
        fig.tight_layout()
        fig.savefig(carpeta / f"{nombre}.png", dpi=110)
        plt.close(fig)
        lecturas[nombre] = lectura
    return lecturas
