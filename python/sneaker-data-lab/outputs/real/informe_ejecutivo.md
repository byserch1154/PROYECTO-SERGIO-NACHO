# Informe ejecutivo · SPEAKE
Origen de los datos: **ACC · REAL** · fecha de corte: 2026-11-05 · generado: 2026-11-12 09:58 · filtros: ninguno

Ingresos válidos: **7191.0 €** · pedidos de venta: **7** · pares: **59** · ticket medio: **1027.29 €**

## Cinco decisiones priorizadas
### 1. Priorizar la fabricación de los modelos de clase A
- **Observación:** SPEAKE Pulse es el modelo con más ingresos (clase A en el ABC).
- **Interpretación:** Concentra la mayor parte de la facturación.
- **Propuesta:** Asegurar materiales y turnos para los modelos A antes que para los C.
- **Evidencia:** df03_modelos_abc · gráfico 03_pareto
- **Impacto esperado:** Menos roturas en los modelos que más facturan.
- **Limitación:** Pocos meses de historia: el ranking puede cambiar.
- **Origen:** ACC · REAL

### 2. Reponer las variantes con stock bajo
- **Observación:** 5 combinaciones modelo-talla están por debajo del umbral.
- **Interpretación:** Con demanda activa podrían quedarse sin existencias.
- **Propuesta:** Revisar y reponer primero las de menor cobertura en semanas.
- **Evidencia:** df08_stock_cobertura
- **Impacto esperado:** Evitar pedidos que no se puedan servir.
- **Limitación:** El stock es una foto de la fecha de corte, no un histórico.
- **Origen:** ACC · REAL

### 3. Ajustar la producción a las tallas más pedidas
- **Observación:** La talla más vendida es la 42.
- **Interpretación:** La demanda se concentra en tallas centrales.
- **Propuesta:** Fabricar más pares de las tallas centrales y menos de los extremos.
- **Evidencia:** df04_modelo_talla · gráfico 06_mapa_calor_talla
- **Impacto esperado:** Menos stock parado en tallas poco pedidas.
- **Limitación:** Basado en 59 pares vendidos.
- **Origen:** ACC · REAL

### 4. Potenciar los pedidos Custom para clubes
- **Observación:** Los Custom suponen el 91.6 % de los ingresos.
- **Interpretación:** Son pedidos grandes de clubes y equipos.
- **Propuesta:** Campaña comercial dirigida a clubes y equipos.
- **Evidencia:** df05_custom_vs_estandar · gráfico 08_comparativa_custom
- **Impacto esperado:** Más ingresos por pedido.
- **Limitación:** Pocos clientes concentran el importe: dependencia de grandes cuentas.
- **Origen:** ACC · REAL

### 5. Recuperar clientes en riesgo
- **Observación:** 2 cliente(s) llevan tiempo sin comprar: Pedro Ruiz, Marta Sánchez.
- **Interpretación:** Pueden estar dejando de comprar.
- **Propuesta:** Contactarles con una oferta antes de perderlos.
- **Evidencia:** df06_clientes_rfm · gráfico 07_dispersion_clientes
- **Impacto esperado:** Mantener la base de clientes.
- **Limitación:** La recencia depende de la fecha de corte elegida.
- **Origen:** ACC · REAL
