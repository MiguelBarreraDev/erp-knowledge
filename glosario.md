# Glosario

Términos del dominio y su equivalente en los productos del mercado.

## General

- **Gross-to-net:** cálculo de ingresos brutos a neto. **Net-to-gross:** el inverso, cuando se pacta neto y hay que hallar el bruto.
- **Devengo o haber:** ingreso generado en el periodo, se pague o no en él.
- **Base imponible o de cotización:** monto sobre el que se aplica una tasa.
- **Effective dating:** manejo de datos con fecha de inicio y fin de vigencia.
- **Cutoff:** fecha límite para que una novedad entre al periodo.
- **Off-cycle:** corrida fuera del calendario regular.
- **Retro pay:** pago de diferencias por cambios con fecha anterior a periodos cerrados.
- **Truncas:** conceptos devengados proporcionalmente que se liquidan al salir (vacaciones, gratificaciones).
- **Proration:** prorrateo por días trabajados o FTE.
- **Accrual y carry-over:** devengo de un saldo y su traspaso a otro año.
- **Garnishment:** retención judicial al sueldo.
- **Maker-checker:** control de dos personas.
- **SoD:** segregación de funciones.


- **Período de pago:** rango cuyo sueldo se liquida; define prorrateos, valores legales vigentes y mes de declaración.
- **Ventana de insumos (de asistencia):** rango de eventos medidos (horas extra, faltas) que entra en un pago.
- **Período de cómputo:** meses sobre los que se calcula un beneficio (gratificación, CTS); no es un período de planilla.
- **In-period / for-period:** el período en que se paga una novedad y el período al que corresponde.
- **Corrida (payroll run):** una ejecución del cálculo sobre un período. Regular, fuera de ciclo, retroactiva, liquidación, simulación.
- **Fuera de ciclo (off-cycle):** corrida o período fuera del calendario regular.
- **Snapshot:** foto inmutable de datos al momento del cálculo.
- **Paquete legal (legal pack):** conjunto versionado de reglas legales de un país.
- **Remuneración afecta (base pensionable, base imponible):** suma de conceptos sobre la que se aplica una tasa.
- **Recálculo en sombra:** re-ejecutar un período cerrado sin grabarlo, para obtener diferencias.
- **Expand / contract:** migración en pasos aditivos y reversibles, quitando lo viejo al final.

## Perú

- **Planilla:** nómina. **Boleta:** recibo de pago al trabajador.
- **RMV:** remuneración mínima vital. **UIT:** unidad impositiva tributaria. **RMA:** remuneración máxima asegurable (tope de la prima AFP).
- **AFP / SPP:** sistema privado de pensiones. **ONP / SNP:** sistema nacional de pensiones. **CUSPP:** código único de afiliado al SPP.
- **EsSalud:** seguro social de salud (aporte del empleador). **EPS:** entidad prestadora de salud privada.
- **SCTR:** seguro complementario de trabajo de riesgo. **Vida Ley:** seguro de vida a cargo del empleador.
- **Renta de 5ta categoría:** impuesto a la renta del trabajo dependiente, retenido por el empleador.
- **Gratificación:** pago de julio y diciembre. **Bonificación extraordinaria:** 9% sobre la gratificación.
- **CTS:** compensación por tiempo de servicios, depositada en mayo y noviembre.
- **Asignación familiar:** 10% de la RMV por hijos.
- **PLAME:** planilla mensual de pagos que se declara a SUNAT. **T-Registro:** registro de trabajadores.
- **Régimen laboral:** general, MYPE, agrario, entre otros; cambia beneficios.
- **Truncas:** beneficios proporcionales que se liquidan al cese.

## Equivalencias con el mercado

| Aquí | SAP | Workday | Oracle | Odoo |
|---|---|---|---|---|
| Concepto | Wage type | Earning / Deduction | Element | Salary rule |
| Grupo de pago | Área de nómina | Pay group | Payroll definition | Estructura / tipo de contrato |
| Período | Período de nómina (registro de control) | Period (period schedule) | Time period | Lote desde / hasta |
| Corrida | Payroll run | Pay run | Payroll flow | Lote de nóminas |
| Novedad | Infotipo 0015 / 2010 | Input | Element entry | Entrada de trabajo / input |
| Base | Cumulation / evaluation class | Accumulation | Balance | Categoría de regla |
