from datetime import datetime

import streamlit as st

import analiticas as an
import config
import pipeline as pl

st.set_page_config(page_title="SPEAKE · Dashboard", layout="wide")
st.title("SPEAKE · Dashboard de negocio")


def filtros(lineas):
    st.sidebar.header("Filtros")
    st.sidebar.date_input("Desde", lineas["fecha"].min().date(), key="desde")
    st.sidebar.date_input("Hasta", lineas["fecha"].max().date(), key="hasta")
    st.sidebar.multiselect("Modelo", sorted(lineas["modelo"].unique()), key="modelos")
    st.sidebar.multiselect("Talla", config.TALLAS, key="tallas")
    st.sidebar.multiselect("Tipo de pedido", ["estandar", "custom"], key="tipos")


def descargar(df, nombre):
    st.download_button(f"Descargar {nombre}.csv", df.to_csv(index=False).encode("utf-8"), f"{nombre}.csv", "text/csv")


@st.fragment(run_every=f"{config.REFRESCO_SEGUNDOS}s")
def panel():
    try:
        t, lineas, incidencias = pl.ejecutar()
        st.session_state["ultimo"] = (t, lineas, incidencias, datetime.now())
        estado = "actualizado"
    except pl.ErrorCarga as e:
        if "ultimo" not in st.session_state:
            st.error(f"Datos no válidos: {e}")
            return
        t, lineas, incidencias, _ = st.session_state["ultimo"]
        estado = f"DESACTUALIZADO ({e})"

    st.caption(f"Comprobado a las {datetime.now():%H:%M:%S} · {estado}")
    ss = st.session_state
    f = an.filtrar(lineas, ss.get("desde"), ss.get("hasta"), ss.get("modelos"), ss.get("tallas"), ss.get("tipos"))
    res = an.calcular_todo(t, f, incidencias)

    direccion, producto, clientes, almacen, calidad = st.tabs(
        ["Dirección", "Producto", "Clientes", "Almacén", "Calidad"]
    )
    with direccion:
        k = res["kpis"]
        cols = st.columns(4)
        for i, (_, fila) in enumerate(k.iterrows()):
            cols[i % 4].metric(fila["indicador"].replace("_", " "), fila["valor"])
        st.subheader("Ventas por mes")
        st.bar_chart(res["ventas_mes"], x="mes", y="ingresos")
        st.subheader("Previsión del mes siguiente")
        st.dataframe(res["prediccion"], hide_index=True)
        descargar(res["ventas_mes"], "ventas_mes")
    with producto:
        st.subheader("Ranking de modelos")
        st.dataframe(res["ranking_modelos"], hide_index=True)
        st.subheader("Pares por modelo y talla")
        st.dataframe(res["modelo_talla"], hide_index=True)
        st.subheader("Custom frente a estándar")
        st.dataframe(res["custom_vs_estandar"], hide_index=True)
        descargar(res["ranking_modelos"], "ranking_modelos")
    with clientes:
        st.subheader("Clientes (RFM) y segmentos")
        st.dataframe(res["segmentos"], hide_index=True)
        descargar(res["segmentos"], "segmentos")
    with almacen:
        st.subheader("Stock por modelo")
        st.dataframe(res["stock"], hide_index=True)
        descargar(res["stock"], "stock")
    with calidad:
        st.subheader(f"Incidencias de calidad: {len(incidencias)}")
        st.dataframe(incidencias, hide_index=True)
        descargar(res["pedidos"], "pedidos")


try:
    filtros(pl.ejecutar()[1])
except pl.ErrorCarga:
    pass
panel()
