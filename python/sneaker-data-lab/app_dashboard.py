"""Dashboard de SPEAKE con Streamlit. Vuelve a leer los CSV cada 60 segundos.

Uso:  streamlit run app_dashboard.py
"""

from datetime import datetime

import streamlit as st

import analiticas as an
import config
import pipeline as pl

st.set_page_config(page_title="SPEAKE · Dashboard", layout="wide")
st.title("SPEAKE · Dashboard de negocio")


@st.fragment(run_every=f"{config.REFRESCO_SEGUNDOS}s")
def panel():
    st.caption(f"Última comprobación: {datetime.now():%H:%M:%S}")
    try:
        t, lineas = pl.ejecutar()
    except pl.ErrorCarga as e:
        st.error(f"Datos no válidos: {e}")
        # TODO: seguir enseñando el último resultado correcto marcado como DESACTUALIZADO
        return

    res = an.calcular_todo(t, lineas)
    columnas = st.columns(len(res["kpis"]))
    for col, (_, fila) in zip(columnas, res["kpis"].iterrows()):
        col.metric(fila["indicador"].replace("_", " "), fila["valor"])

    st.subheader("Ventas por mes")
    st.bar_chart(res["ventas_mes"], x="mes", y="ingresos")
    st.subheader("Ranking de modelos")
    st.dataframe(res["ranking_modelos"], hide_index=True)

    # TODO: filtros en la barra lateral (fechas, modelo, talla, tipo de pedido) guardados
    #   en st.session_state, y vistas separadas para Dirección, Producto, Clientes y Almacén.


panel()
