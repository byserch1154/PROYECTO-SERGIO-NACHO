import argparse
import sys
from datetime import datetime

import pandas as pd

import analiticas as an
import config
import graficos
import informes
import pipeline as pl
from pathlib import Path

# que tablas se guardan en cada tarea
TAREAS = {
    "calidad": ["df09_calidad", "df12_reconciliacion"],
    "descriptivo": ["kpis", "df01_pedidos_unicos", "df02_ventas_periodo", "df03_modelos_abc", "df04_modelo_talla",
                    "df05_custom_vs_estandar", "df08_stock_cobertura", "df10_anomalias", "df11_margen", "descriptivos",
                    "demanda_modelo_mes"],
    "segmentacion": ["df06_clientes_rfm", "df07_cohortes", "clustering_k", "clustering_clientes"],
}


# opciones que se pueden pasar por consola
# ejemplo: python main.py --modo sintetico --tarea calidad
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

    # real = csv de la base de datos, sintetico = datos inventados
    if args.modo == "real":
        origen = "ACC · REAL"
        entrada = config.DIR_REAL
    else:
        origen = "SINTÉTICO"
        entrada = config.DIR_SINTETICO
    if args.entrada:
        entrada = args.entrada
    salida = args.salida / args.modo

    filtros = {"desde": args.desde, "hasta": args.hasta, "modelos": args.modelo, "tallas": args.talla,
               "tipos": args.tipo, "estados": args.estado}
    # solo los filtros que se han usado, para el log
    filtros_usados = {}
    for clave in filtros:
        if filtros[clave]:
            filtros_usados[clave] = filtros[clave]

    # 1. cargar, validar y unir
    try:
        r = pl.ejecutar(entrada)
    except pl.ErrorCarga as e:
        print("ERROR de carga:", e)
        pl.registrar_log(origen, "error de carga", 0, 0, str(e))
        return 2

    salida.mkdir(parents=True, exist_ok=True)
    r["manifiesto"].to_csv(salida / "manifiesto.csv", index=False, sep=";", encoding="utf-8-sig")
    r["incidencias"].to_csv(salida / "incidencias.csv", index=False, sep=";", encoding="utf-8-sig")
    r["resumen_calidad"].to_csv(salida / "resumen_calidad.csv", index=False, sep=";", encoding="utf-8-sig")
    print(r["resumen_calidad"].to_string(index=False))

    # si hay errores bloqueantes no se calcula nada
    if not r["valido"]:
        print("\nDATOS INVÁLIDOS: hay incidencias bloqueantes. No se publican cálculos (ver incidencias.csv).")
        pl.registrar_log(origen, "datos inválidos", 0, r["segundos"], str(len(r["incidencias"])) + " incidencias")
        return 1

    # 2. calculos
    res = an.calcular_todo(r, filtros)

    if args.tarea == "todo" or args.tarea == "informe":
        nombres = TAREAS["calidad"] + TAREAS["descriptivo"] + TAREAS["segmentacion"]
    else:
        nombres = TAREAS[args.tarea]

    # 3. guardar cada resultado en csv y apuntar de donde sale (linaje)
    ahora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    fecha_corte = r["fecha_corte"].strftime("%Y-%m-%d")
    if filtros_usados:
        texto_filtros = str(filtros_usados)
    else:
        texto_filtros = "ninguno"

    linaje = []
    for n in nombres:
        df = res[n]
        df.to_csv(salida / (n + ".csv"), index=False, sep=";", encoding="utf-8-sig")
        linaje.append({"archivo": n + ".csv", "funcion": "analiticas." + n, "origen": origen, "ejecucion": ahora,
                       "fecha_corte": fecha_corte, "filtros": texto_filtros, "filas": len(df)})
    pd.DataFrame(linaje).to_csv(salida / "linaje.csv", index=False, sep=";", encoding="utf-8-sig")

    # 4. graficos e informes
    if args.tarea == "todo" or args.tarea == "informe":
        etiqueta = origen + " · corte " + fecha_corte + " · " + ahora
        lecturas = graficos.guardar_todas(res, salida / "graficos", etiqueta)
        ejecutivo = informes.ejecutivo(res, origen, r["fecha_corte"], filtros_usados)
        (salida / "informe_ejecutivo.md").write_text(ejecutivo, encoding="utf-8")
        tecnico = informes.tecnico(res, r, origen, lecturas, filtros_usados)
        (salida / "informe_tecnico.md").write_text(tecnico, encoding="utf-8")

    print()
    print(res["kpis"][["indicador", "valor"]].to_string(index=False))
    filas = len(res["df_lineas_enriquecidas"])
    pl.registrar_log(origen, "correcto", filas, r["segundos"], "tarea=" + args.tarea + " filtros=" + texto_filtros)
    print("\nResultados (" + origen + ") en", salida)
    return 0


if __name__ == "__main__":
    sys.exit(main())
