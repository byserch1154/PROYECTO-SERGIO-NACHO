import time
from datetime import datetime

import matplotlib.pyplot as plt
import streamlit as st

import analiticas as an
import config
import graficos
import pipeline as pl

# se arranca con: streamlit run app_dashboard.py
st.set_page_config(page_title="SPEAKE · Dashboard", layout="wide")
st.title("SPEAKE · Dashboard de negocio")

# session_state guarda cosas entre una recarga y otra (filtros, ultimo resultado bueno...)
ss = st.session_state
FILTROS_VACIOS = {"desde": None, "hasta": None, "modelos": [], "tallas": [], "tipos": [], "estados": [], "clientes": []}


def restablecer():
    for clave in FILTROS_VACIOS:
        ss[clave] = FILTROS_VACIOS[clave]


# filtros de la barra lateral
def filtros_laterales():
    st.sidebar.header("Filtros")
    try:
        lineas = pl.ejecutar(config.DIR_REAL)["lineas"]
    except pl.ErrorCarga:
        lineas = None
    if lineas is None:
        st.sidebar.warning("Sin datos válidos para construir los filtros")
        return

    st.sidebar.date_input("Desde", value=None, key="desde")
    st.sidebar.date_input("Hasta", value=None, key="hasta")
    st.sidebar.multiselect("Modelo", sorted(lineas["modelo"].unique()), key="modelos", placeholder="Todos")
    st.sidebar.multiselect("Talla", config.TALLAS, key="tallas", placeholder="Todos")
    st.sidebar.multiselect("Tipo de pedido", config.TIPOS, key="tipos", placeholder="Todos")
    st.sidebar.multiselect("Estado", config.ESTADOS, key="estados", placeholder="Todos")
    st.sidebar.multiselect("Cliente", sorted(lineas["nombre"].unique()), key="clientes", placeholder="Todos")
    st.sidebar.button("Restablecer filtros", on_click=restablecer)
    st.sidebar.caption("Los filtros reducen el denominador de todos los KPIs: ticket y pares por pedido se calculan solo con los pedidos filtrados.")


# pinta un grafico a la izquierda y su explicacion y sus datos a la derecha
def figura(funcion, res, tabla):
    fig, lectura = funcion(res)
    izquierda, derecha = st.columns([3, 2])
    izquierda.pyplot(fig)
    plt.close(fig)
    derecha.caption(lectura)
    with derecha.expander("Ver datos del gráfico"):
        st.dataframe(res[tabla], hide_index=True)


def descargar(res, nombre):
    datos = res[nombre].to_csv(index=False).encode("utf-8")
    st.download_button("Descargar " + nombre + ".csv", datos, nombre + ".csv", "text/csv", key="dl_" + nombre)


# vuelve a leer los csv y recalcula
# devuelve el estado (correcto, sin cambios, datos inválidos o error de carga) y un mensaje
def ciclo():
    inicio = time.perf_counter()
    ss["ultima_comprobacion"] = datetime.now()

    try:
        r = pl.ejecutar(config.DIR_REAL)
    except pl.ErrorCarga as e:
        pl.registrar_log("ACC · REAL", "error de carga", 0, 0, str(e))
        return "error de carga", str(e)

    if not r["valido"]:
        pl.registrar_log("ACC · REAL", "datos inválidos", 0, r["segundos"], str(len(r["incidencias"])) + " incidencias")
        ss["incidencias_bloqueo"] = r["incidencias"]
        return "datos inválidos", "Hay incidencias bloqueantes: no se publican cálculos parciales"

    # "firma" = nombre, tamaño y fecha de cada fichero
    # si es igual que la de la vez anterior es que no ha llegado nada nuevo
    firma = r["manifiesto"][["fichero", "bytes", "modificado"]].to_dict("records")
    if ss.get("firma") == firma:
        estado = "sin cambios"
    else:
        estado = "correcto"

    filtros = {}
    for clave in FILTROS_VACIOS:
        filtros[clave] = ss.get(clave)
    res = an.calcular_todo(r, filtros)
    segundos = round(time.perf_counter() - inicio, 2)

    # guardamos este resultado como el ultimo bueno
    ss["firma"] = firma
    ss["publicado"] = (r, res)
    ss["ultima_valida"] = datetime.now()
    ss["segundos"] = segundos
    pl.registrar_log("ACC · REAL", estado, len(res["df_lineas_enriquecidas"]), segundos)
    return estado, ""


# st.fragment con run_every hace que esta parte se vuelva a ejecutar sola cada 60 segundos
@st.fragment(run_every=str(config.REFRESCO_SEGUNDOS) + "s")
def panel():
    st.button("Actualizar ahora")
    estado, mensaje = ciclo()

    # si nunca ha habido un resultado bueno no hay nada que enseñar
    if "publicado" not in ss:
        st.error(estado.upper() + ": " + mensaje)
        return

    r, res = ss["publicado"]
    valida = ss["ultima_valida"]
    if estado == "correcto":
        color = "green"
    elif estado == "sin cambios":
        color = "blue"
    else:
        color = "red"

    st.markdown(
        "**ACC · REAL** · fecha de corte **" + r["fecha_corte"].strftime("%Y-%m-%d") + "** · "
        + "última comprobación **" + ss["ultima_comprobacion"].strftime("%H:%M:%S") + "** · "
        + "última actualización válida **" + valida.strftime("%H:%M:%S") + "** · "
        + "filas válidas **" + str(len(res["df_lineas_enriquecidas"])) + "** · "
        + "tiempo **" + str(ss["segundos"]) + " s** · estado :" + color + "[**" + estado + "**]"
    )

    # si los csv nuevos estan mal, seguimos enseñando el ultimo resultado bueno y lo avisamos
    if estado == "datos inválidos" or estado == "error de carga":
        st.error(mensaje + ". Se muestra el último resultado válido: DESACTUALIZADO desde " + valida.strftime("%Y-%m-%d %H:%M:%S"))
        if estado == "datos inválidos" and "incidencias_bloqueo" in ss:
            st.dataframe(ss["incidencias_bloqueo"], hide_index=True)

    # una pestaña para cada perfil de la empresa
    vistas = st.tabs(["Dirección", "Producto y ventas", "Clientes", "Almacén", "Calidad y auditoría", "Laboratorio (SINTÉTICO)"])
    k = res["kpis"].set_index("indicador")["valor"]
    mensual = res["df02_ventas_periodo"]

    # Direccion: los numeros principales
    with vistas[0]:
        delta = None
        if "var_ingresos_pct" in mensual.columns and len(mensual) > 1:
            delta = str(mensual["var_ingresos_pct"].iloc[-1]) + " % vs mes anterior"
        cols = st.columns(4)
        cols[0].metric("Ingresos válidos (€)", k["Ingresos (€)"], delta)
        cols[1].metric("Pares vendidos", k["Pares vendidos"])
        cols[2].metric("Pedidos únicos", k["Pedidos únicos"], k["Pedidos de venta"] + " de venta", delta_color="off")
        cols[3].metric("Ticket medio (€)", k["Ticket medio (€)"])
        figura(graficos.serie_mensual, res, "df02_ventas_periodo")
        st.dataframe(res["kpis"], hide_index=True)
        descargar(res, "kpis")
        descargar(res, "df02_ventas_periodo")

    # Producto y ventas
    with vistas[1]:
        figura(graficos.ranking_modelos, res, "df03_modelos_abc")
        figura(graficos.pareto, res, "df03_modelos_abc")
        figura(graficos.mapa_calor, res, "df04_modelo_talla")
        figura(graficos.comparativa_segmentos, res, "df05_custom_vs_estandar")
        figura(graficos.boxplot_tipo, res, "df01_pedidos_unicos")
        figura(graficos.histograma_ticket, res, "df01_pedidos_unicos")
        descargar(res, "df03_modelos_abc")
        descargar(res, "df04_modelo_talla")

    # Clientes
    with vistas[2]:
        st.subheader("Ranking de clientes y segmentos RFM")
        st.dataframe(res["df06_clientes_rfm"], hide_index=True)
        figura(graficos.dispersion_clientes, res, "df06_clientes_rfm")
        st.subheader("Retención por cohortes")
        st.dataframe(res["df07_cohortes"], hide_index=True)
        st.subheader("Segmentación KMeans")
        st.dataframe(res["clustering_k"], hide_index=True)
        descargar(res, "df06_clientes_rfm")

    # Almacen
    with vistas[3]:
        st.warning("El stock es una foto del " + r["fecha_corte"].strftime("%Y-%m-%d") + ", no un histórico de existencias.")
        s = res["df08_stock_cobertura"]
        st.subheader("Alertas de stock bajo")
        st.dataframe(s[s["alerta_stock"] == "BAJO"], hide_index=True)
        st.bar_chart(s.groupby("modelo")["stock_disponible"].sum(), y_label="pares en stock")
        st.subheader("Stock, demanda de 28 días y cobertura")
        st.dataframe(s, hide_index=True)
        descargar(res, "df08_stock_cobertura")

    # Calidad: semaforo por tabla, incidencias y comparacion con SQL
    with vistas[4]:
        cal = res["df09_calidad"]
        for i in range(len(cal)):
            f = cal.iloc[i]
            if f["bloqueantes"] > 0:
                icono = "🔴"
            elif f["recuperables"] > 0 or f["advertencias"] > 0:
                icono = "🟡"
            else:
                icono = "🟢"
            st.write(icono + " **" + f["tabla"] + "**: " + str(f["filas_entrada"]) + " recibidas · "
                     + str(f["filas_validas"]) + " válidas · " + str(f["filas_rechazadas"]) + " rechazadas · "
                     + str(f["pct_calidad"]) + " %")
        st.subheader("Incidencias")
        st.dataframe(r["incidencias"], hide_index=True)
        st.subheader("Conciliación con SQL de Acceso a Datos")
        st.dataframe(res["df12_reconciliacion"], hide_index=True)
        st.subheader("Anomalías (IQR)")
        st.dataframe(res["df10_anomalias"], hide_index=True)
        st.subheader("Ficheros de entrada")
        st.dataframe(r["manifiesto"], hide_index=True)
        st.caption("Última ejecución válida: " + valida.strftime("%Y-%m-%d %H:%M:%S"))
        descargar(res, "df09_calidad")

    # Laboratorio: el clustering con los datos inventados
    with vistas[5]:
        st.error("DATOS SINTÉTICOS · no son ventas reales · solo para demostrar la segmentación")
        try:
            rs = pl.ejecutar(config.DIR_SINTETICO)
            lab = an.calcular_todo(rs)
            st.dataframe(lab["clustering_k"], hide_index=True)
            st.dataframe(lab["clustering_clientes"], hide_index=True)
        except pl.ErrorCarga as e:
            st.info("Genera antes los datos con: py generador_datos.py (" + str(e) + ")")


filtros_laterales()
panel()
