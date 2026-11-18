import matplotlib
matplotlib.use("Agg")  # para poder guardar png sin abrir ventanas
import matplotlib.pyplot as plt
import numpy as np


# si el dataframe tiene la columna "estado" es que salio NO CALCULABLE
def hay_datos(df):
    return "estado" not in df.columns


# grafico vacio con un aviso cuando no hay datos
def grafico_vacio(titulo):
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.text(0.5, 0.5, "Sin datos suficientes", ha="center", va="center")
    ax.set_title(titulo)
    ax.axis("off")
    return fig


# cada funcion devuelve la figura y una frase que la explica

# 1. linea: ingresos de cada mes
def serie_mensual(res):
    df = res["df02_ventas_periodo"]
    titulo = "Ingresos por mes (€)"
    if not hay_datos(df):
        return grafico_vacio(titulo), "No hay ventas en el periodo."

    fig, ax = plt.subplots(figsize=(8, 4))
    ax.plot(df["mes"], df["ingresos"], marker="o", label="Ingresos")
    ax.set_title(titulo)
    ax.set_xlabel("mes")
    ax.set_ylabel("€")
    ax.tick_params(axis="x", rotation=45)
    ax.legend()

    mejor_mes = df.loc[df["ingresos"].idxmax(), "mes"]
    return fig, "El mes con más ingresos es " + mejor_mes + "."


# 2. barras horizontales: modelos ordenados por ingresos, con el color de su clase ABC
def ranking_modelos(res):
    df = res["df03_modelos_abc"]
    titulo = "Ranking de modelos por ingresos (€)"
    if not hay_datos(df):
        return grafico_vacio(titulo), "No hay ventas en el periodo."

    colores_abc = {"A": "tab:green", "B": "tab:orange", "C": "tab:red"}
    colores = []
    for clase in df["clase"]:
        colores.append(colores_abc[clase])

    fig, ax = plt.subplots(figsize=(8, 4))
    # al reves para que el mejor salga arriba
    ax.barh(df["modelo"][::-1], df["ingresos"][::-1], color=colores[::-1])
    ax.set_title(titulo + " · color = clase ABC")
    ax.set_xlabel("€")

    primero = df.iloc[0]
    return fig, primero["modelo"] + " concentra el " + str(primero["peso_pct"]) + " % de los ingresos."


# 3. pareto: barras con el % de cada modelo y linea con el % acumulado
def pareto(res):
    df = res["df03_modelos_abc"]
    titulo = "Pareto de modelos: % acumulado de ingresos"
    if not hay_datos(df):
        return grafico_vacio(titulo), "No hay ventas en el periodo."

    fig, ax = plt.subplots(figsize=(8, 4))
    ax.bar(df["modelo"], df["peso_pct"], label="% del modelo")
    ax.plot(df["modelo"], df["acumulado_pct"], color="black", marker="o", label="% acumulado")
    ax.axhline(80, color="gray", linestyle="--", label="80 %")
    ax.set_title(titulo)
    ax.set_ylabel("%")
    ax.tick_params(axis="x", rotation=45)
    ax.legend()

    n = int((df["acumulado_pct"] <= 80).sum()) + 1
    n = min(n, len(df))
    return fig, str(n) + " modelo(s) suman el 80 % de los ingresos."


# 4. histograma: cuantos pedidos hay de cada importe
def histograma_ticket(res):
    p = res["df01_pedidos_unicos"]
    v = p[p["es_venta"]]
    titulo = "Distribución del importe por pedido (€)"
    if len(v) == 0:
        return grafico_vacio(titulo), "No hay ventas en el periodo."

    barras = min(20, max(5, len(v) // 5))
    mediana = v["ticket_pedido"].median()

    fig, ax = plt.subplots(figsize=(8, 4))
    ax.hist(v["ticket_pedido"], bins=barras, edgecolor="white")
    ax.axvline(mediana, color="red", linestyle="--", label="mediana")
    ax.set_title(titulo)
    ax.set_xlabel("€ por pedido")
    ax.set_ylabel("nº de pedidos")
    ax.legend()
    return fig, "La mediana (" + str(round(mediana)) + " €) representa mejor el pedido típico que la media, porque los pedidos de club la disparan."


# 5. boxplot: pares por pedido en custom y en estandar
def boxplot_tipo(res):
    p = res["df01_pedidos_unicos"]
    v = p[p["es_venta"]]
    titulo = "Pares por pedido según tipo"
    if len(v) == 0:
        return grafico_vacio(titulo), "No hay ventas en el periodo."

    tipos = sorted(v["tipo"].unique())
    grupos = []
    for t in tipos:
        grupos.append(v[v["tipo"] == t]["pares"])

    fig, ax = plt.subplots(figsize=(7, 4))
    ax.boxplot(grupos, tick_labels=tipos)
    ax.set_title(titulo)
    ax.set_ylabel("pares por pedido")
    return fig, "Los pedidos Custom suelen tener más pares: son pedidos de clubes y equipos."


# 6. mapa de calor: pares de cada modelo en cada talla
def mapa_calor(res):
    df = res["df04_modelo_talla"]
    titulo = "Pares vendidos por modelo y talla"
    if not hay_datos(df):
        return grafico_vacio(titulo), "No hay ventas en el periodo."

    # columnas t38, t39... (las de pares, no las de %)
    columnas = []
    tallas = []
    for c in df.columns:
        if c.startswith("t") and c[1:].isdigit():
            columnas.append(c)
            tallas.append(c[1:])
    datos = df[columnas].to_numpy()

    fig, ax = plt.subplots(figsize=(9, 4))
    imagen = ax.imshow(datos, cmap="Blues", aspect="auto")
    ax.set_xticks(range(len(tallas)), tallas)
    ax.set_yticks(range(len(df)), df["modelo"])
    # escribimos el numero dentro de cada casilla
    for i in range(datos.shape[0]):
        for j in range(datos.shape[1]):
            ax.text(j, i, int(datos[i, j]), ha="center", va="center", fontsize=7)
    fig.colorbar(imagen, ax=ax, label="pares")
    ax.set_title(titulo)
    ax.set_xlabel("talla")
    return fig, "Las tallas centrales (41-43) concentran la demanda."


# 7. dispersion: clientes segun nº de pedidos y dinero, un color por segmento RFM
def dispersion_clientes(res):
    df = res["df06_clientes_rfm"]
    v = df[df["frequency"] > 0]
    titulo = "Clientes: nº de pedidos frente a importe (€)"
    if len(v) == 0:
        return grafico_vacio(titulo), "No hay clientes con compras."

    fig, ax = plt.subplots(figsize=(8, 4))
    for segmento in sorted(v["segmento_rfm"].unique()):
        g = v[v["segmento_rfm"] == segmento]
        ax.scatter(g["frequency"], g["monetary"], label=segmento)
    ax.set_title(titulo)
    ax.set_xlabel("pedidos de venta")
    ax.set_ylabel("€")
    ax.legend(fontsize=7)
    return fig, "Arriba a la derecha están los clientes más valiosos."


# 8. barras dobles: % de ingresos y % de cancelaciones de custom y estandar
def comparativa_segmentos(res):
    df = res["df05_custom_vs_estandar"]
    titulo = "Custom frente a estándar: % de ingresos y de cancelaciones"
    if not hay_datos(df):
        return grafico_vacio(titulo), "No hay pedidos en el periodo."

    x = np.arange(len(df))
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(x - 0.2, df["cuota_ingresos_pct"], 0.4, label="% de ingresos")
    ax.bar(x + 0.2, df["tasa_cancelacion_pct"], 0.4, label="% de pedidos cancelados")
    ax.set_xticks(x, df["tipo"])
    ax.set_title(titulo)
    ax.set_ylabel("%")
    ax.legend()
    return fig, "Compara el peso en euros con la tasa de cancelación de cada tipo."


# nombre del png -> funcion que lo dibuja
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


# guarda los 8 graficos en png y devuelve las frases para el informe
def guardar_todas(res, carpeta, etiqueta):
    carpeta.mkdir(parents=True, exist_ok=True)
    lecturas = {}
    for nombre in FIGURAS:
        funcion = FIGURAS[nombre]
        fig, lectura = funcion(res)
        # abajo a la izquierda ponemos de donde salen los datos y cuando
        fig.text(0.01, 0.01, etiqueta, fontsize=7, color="gray")
        fig.tight_layout()
        fig.savefig(carpeta / (nombre + ".png"), dpi=110)
        plt.close(fig)
        lecturas[nombre] = lectura
    return lecturas
