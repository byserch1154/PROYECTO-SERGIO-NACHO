import argparse
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd

import analiticas as an
import config
import graficos
import informes
import pipeline as pl

TAREAS = {
    "calidad": ["df09_calidad", "df12_reconciliacion"],
    "descriptivo": ["kpis", "df01_pedidos_unicos", "df02_ventas_periodo", "df03_modelos_abc", "df04_modelo_talla",
                    "df05_custom_vs_estandar", "df08_stock_cobertura", "df10_anomalias", "df11_margen", "descriptivos",
                    "demanda_modelo_mes"],
    "segmentacion": ["df06_clientes_rfm", "df07_cohortes", "clustering_k", "clustering_clientes"],
}


def argumentos(argv):
    a = argparse.ArgumentParser(description="SPEAKE · análisis de datos por consola")
    a.add_argument("--modo", choices=["real", "sintetico"], default="real")
    a.add_argument("--entrada", type=Path)
    a.add_argument("--salida", type=Path, default=config.DIR_SALIDA)
    a.add_argument("--tarea", choices=["calidad", "descriptivo", "segmentacion", "informe", "todo"], default="todo")
    a.add_argument("--desde")
    a.add_argument("--hasta")
    a.add_argument("--modelo", nargs="*")
    a.add_argument("--talla", nargs="*", type=int)
    a.add_argument("--tipo", nargs="*", choices=config.TIPOS)
    a.add_argument("--estado", nargs="*", choices=config.ESTADOS)
    return a.parse_args(argv)


def main(argv=None):
    args = argumentos(argv)
    origen = "ACC · REAL" if args.modo == "real" else "SINTÉTICO"
    entrada = args.entrada or (config.DIR_REAL if args.modo == "real" else config.DIR_SINTETICO)
    salida = args.salida / args.modo
    filtros = {"desde": args.desde, "hasta": args.hasta, "modelos": args.modelo, "tallas": args.talla,
               "tipos": args.tipo, "estados": args.estado}
    texto_filtros = {k: v for k, v in filtros.items() if v}

    try:
        r = pl.ejecutar(entrada)
    except pl.ErrorCarga as e:
        print(f"ERROR de carga: {e}")
        pl.registrar_log(origen, "error de carga", 0, 0, str(e))
        return 2

    salida.mkdir(parents=True, exist_ok=True)
    r["manifiesto"].to_csv(salida / "manifiesto.csv", index=False, encoding="utf-8")
    r["incidencias"].to_csv(salida / "incidencias.csv", index=False, encoding="utf-8")
    r["resumen_calidad"].to_csv(salida / "resumen_calidad.csv", index=False, encoding="utf-8")
    print(r["resumen_calidad"].to_string(index=False))

    if not r["valido"]:
        print("\nDATOS INVÁLIDOS: hay incidencias bloqueantes. No se publican cálculos (ver incidencias.csv).")
        pl.registrar_log(origen, "datos inválidos", 0, r["segundos"], f"{len(r['incidencias'])} incidencias")
        return 1

    res = an.calcular_todo(r, filtros)
    nombres = [n for t in TAREAS.values() for n in t] if args.tarea in ("todo", "informe") else TAREAS[args.tarea]
    ahora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    linaje = []
    for n in nombres:
        df = res[n]
        df.to_csv(salida / f"{n}.csv", index=False, encoding="utf-8")
        linaje.append({"archivo": f"{n}.csv", "funcion": f"analiticas.{n}", "origen": origen, "ejecucion": ahora,
                       "fecha_corte": f"{r['fecha_corte']:%Y-%m-%d}", "filtros": str(texto_filtros or "ninguno"),
                       "filas": len(df)})
    pd.DataFrame(linaje).to_csv(salida / "linaje.csv", index=False, encoding="utf-8")

    if args.tarea in ("todo", "informe"):
        etiqueta = f"{origen} · corte {r['fecha_corte']:%Y-%m-%d} · {ahora}"
        lecturas = graficos.guardar_todas(res, salida / "graficos", etiqueta)
        (salida / "informe_ejecutivo.md").write_text(
            informes.ejecutivo(res, origen, r["fecha_corte"], texto_filtros), encoding="utf-8")
        (salida / "informe_tecnico.md").write_text(
            informes.tecnico(res, r, origen, lecturas, texto_filtros), encoding="utf-8")

    print("\n" + res["kpis"][["indicador", "valor"]].to_string(index=False))
    filas = len(res["df_lineas_enriquecidas"])
    pl.registrar_log(origen, "correcto", filas, r["segundos"], f"tarea={args.tarea} filtros={texto_filtros or 'ninguno'}")
    print(f"\nResultados ({origen}) en {salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
