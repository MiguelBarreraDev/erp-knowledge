# Localización Perú

Reglas y parámetros de nómina para Perú. Cada valor indica desde cuándo rige, su fuente y su estado de
verificación. **Verificado** = contrastado con la fuente en la fecha indicada. **Verificar** = conocimiento
general que falta contrastar con la norma vigente o un especialista.

Última revisión general: 2026-10-14.

## Parámetros legales

| Código | Valor | Vigente desde | Fuente | Estado | Revisar |
|---|---|---|---|---|---|
| RMV (remuneración mínima vital) | S/ 1,130.00 | 2025-01-01 | DS 006-2024-TR | Verificado | — |
| RMV | S/ 1,230.00 | 2026-10-01 | DS 015-2026-TR | Verificado | Próximo decreto |
| UIT 2026 | S/ 5,500.00 | 2026-01-01 | DS 301-2025-EF | Verificado | Enero 2027 |
| RMA (remuneración máxima asegurable, tope de la prima AFP) | S/ 12,598.91 | 2026-04-01 a 2026-06-30 | SBS | Verificado | Cada trimestre |

En el esquema: `legal_parameter` (código, valor, vigencia, fuente). Todo lo que depende de un parámetro
(asignación familiar, piso de EsSalud, tope de la prima) se recalcula solo desde su fecha.

## Aportes y retenciones

| Concepto | Paga | Tasa | Base | Estado |
|---|---|---|---|---|
| AFP aporte obligatorio | Trabajador | 10% | Remuneración afecta | Verificado (2026) |
| AFP prima de seguro | Trabajador | 1.37% | Remuneración afecta con tope RMA | Verificado (2026) |
| AFP comisión sobre flujo | Trabajador | Habitat 1.47% · Integra 1.55% · Prima 1.60% · Profuturo 1.69% | Remuneración afecta | Verificado (2026, SBS) |
| AFP comisión mixta | Trabajador | Se cobra sobre el saldo, fuera de planilla | — | Verificar si queda componente sobre flujo |
| ONP | Trabajador | 13% | Remuneración afecta | Verificado |
| EsSalud | Empleador | 9% | Remuneración afecta, mínimo la RMV | Verificado |
| EsSalud con EPS | Empleador | 6.75% EsSalud + 2.25% como crédito para la EPS | Igual | Verificar |
| Vida Ley | Empleador | Según póliza | Remuneración | Desde el inicio de la relación; verificar |
| SCTR | Empleador | Según póliza | Remuneración | Solo actividades de riesgo; verificar |
| Renta de 5ta categoría | Trabajador (retención) | Tramos (abajo) | Proyección anual menos 7 UIT | Verificado (tramos) |

En el esquema: `statutory_scheme`, `statutory_provider` (cada AFP), `statutory_rate` (tasa del
trabajador y del empleador, con piso y tope tomados de parámetros) y la afiliación de cada empleado con
su administradora y tipo de comisión (`employee_statutory_enrollment`).

### Renta de 5ta categoría

Tramos sobre la renta neta anual (proyección − 7 UIT):

| Tramo | Tasa |
|---|---|
| Hasta 5 UIT | 8% |
| Más de 5 hasta 20 UIT | 14% |
| Más de 20 hasta 35 UIT | 17% |
| Más de 35 hasta 45 UIT | 20% |
| Más de 45 UIT | 30% |

Retención mensual = (impuesto anual proyectado − retenido en el año) ÷ divisor del mes:

| Mes | Divisor |
|---|---|
| Enero a marzo | 12 |
| Abril | 9 |
| Mayo a julio | 8 |
| Agosto | 5 |
| Setiembre a noviembre | 4 |
| Diciembre | Regularización: impuesto real del año − retenido |

La proyección incluye lo percibido en el año, las remuneraciones de los meses que faltan y las
gratificaciones de julio y diciembre con su bonificación extraordinaria. Estado: tramos y divisores
verificados con el ejemplo de abajo; la mecánica fina (renta de otros empleadores, no domiciliados,
deducción adicional de 3 UIT en la declaración anual) se verifica con SUNAT.

## Conceptos de remuneración

| Concepto | Regla | Estado |
|---|---|---|
| Asignación familiar | 10% de la RMV vigente, para trabajadores con hijos menores de edad (o mayores cursando estudios superiores, con límite de edad) | Verificado el 10%; verificar condiciones |
| Horas extra | Sobretasa de 25% las dos primeras horas y 35% las siguientes; trabajo en día de descanso o feriado con sobretasa de 100% | Verificar con la norma vigente |
| Gratificaciones | Julio y diciembre, una remuneración por semestre completo, proporcional por meses completos; se pagan hasta el 15 de cada mes | Verificar |
| Bonificación extraordinaria | 9% de la gratificación (equivale a lo que sería EsSalud), porque la gratificación está inafecta a EsSalud | Verificar qué otros aportes la afectan |
| CTS | Depósitos semestrales: en mayo (por noviembre a abril) y en noviembre (por mayo a octubre); base = remuneración computable + 1/6 de la gratificación; va a una cuenta CTS distinta de la de sueldo | Verificar |
| Vacaciones | 30 días calendario por año completo en el régimen general; menos en regímenes especiales | Verificar por régimen |

El régimen laboral (general, MYPE, agrario) cambia gratificación, CTS y vacaciones. En el esquema:
`employment_contract.labor_regime_id`, que las fórmulas consultan.

## Tipos de trabajador sin duplicar conceptos

| Tipo | Qué lo distingue |
|---|---|
| AFP flujo, AFP mixta u ONP | La afiliación: administradora y tipo de comisión |
| Régimen general, MYPE o agrario | El régimen del contrato |
| Practicante (modalidad formativa) | Sin afiliación pensionaria; concepto propio de subvención |
| Tiempo parcial | Jornada y FTE del contrato |
| No domiciliado | Perfil tributario: tasa fija, sin deducción de 7 UIT |
| Con EPS | Afiliación adicional; EsSalud aplica el crédito |

## Boleta de pago

| Regla | Fuente | Estado |
|---|---|---|
| Contenido mínimo: empleador (razón social, RUC); trabajador (nombres, documento, cargo o categoría, fecha de ingreso, régimen pensionario y CUSPP); período, días y horas trabajados, horas extra, vacaciones; remuneraciones, descuentos y aportes del empleador; firma del empleador | DS 001-98-TR y guía del MTPE | Verificado (guía); verificar texto vigente |
| Entrega hasta el tercer día hábil siguiente al pago | DS 001-98-TR | Verificado |
| Boleta electrónica válida con firma digital del empleador; la firma del trabajador es opcional | DL 1310 | Verificado |
| Pago de sueldos y beneficios por billetera digital | DS 011-2026-EF | Verificado |

Diseño general de la boleta: [nomina/boleta.md](../nomina/boleta.md).

## Ejemplo completo de una boleta

Trabajadora en régimen general, AFP Integra con comisión sobre flujo, un hijo, sueldo S/ 3,000.00,
octubre de 2026 (RMV S/ 1,230.00 desde el 1 de octubre).

| Concepto | Cálculo | Importe |
|---|---|---|
| Sueldo básico | 30 días de 3,000.00 | 3,000.00 |
| Asignación familiar | 10% × 1,230.00 | 123.00 |
| **Total ingresos** | | **3,123.00** |
| AFP aporte obligatorio | 3,123.00 × 10% | 312.30 |
| AFP prima de seguro | 3,123.00 × 1.37% (bajo el tope RMA) | 42.79 |
| AFP comisión sobre flujo | 3,123.00 × 1.55% | 48.41 |
| Renta de 5ta | ver abajo | 38.28 |
| **Total descuentos** | | **441.78** |
| **Neto a pagar** | | **2,681.22** |
| EsSalud (empleador, no se descuenta) | 3,123.00 × 9% | 281.07 |

Renta de 5ta de octubre:

| Paso | Cálculo | Monto |
|---|---|---|
| Ingresos enero a setiembre | 9 × 3,113.00 (asignación con RMV 1,130) | 28,017.00 |
| Ingresos octubre a diciembre | 3 × 3,123.00 | 9,369.00 |
| Gratificación de julio + 9% | 3,113.00 × 1.09 | 3,393.17 |
| Gratificación de diciembre + 9% | 3,123.00 × 1.09 | 3,404.07 |
| Proyección anual | | 44,183.24 |
| Menos 7 UIT | 7 × 5,500.00 | 38,500.00 |
| Renta neta | | 5,683.24 |
| Impuesto anual (primer tramo) | 5,683.24 × 8% | 454.66 |
| Retenido enero a setiembre (dato del caso) | | 301.52 |
| Retención de octubre | (454.6592 − 301.52) ÷ 4 = 38.2848 | 38.28 |

El redondeo se aplica al final: con el impuesto ya redondeado a 454.66 daría 38.29. La regla de
redondeo es una política del motor y debe fijarse una sola vez.

## Fuentes

- [El Peruano – RMV de S/ 1,230 desde octubre de 2026](https://elperuano.pe/noticia/305879-desde-hoy-rige-la-nueva-rmv-sueldo-minimo-sube-a-s-1230-y-cambia-otros-conceptos-laborales)
- [El Peruano – UIT 2026](https://elperuano.pe/noticia/285318-nueva-uit-2026-conoce-los-montos-que-afectan-sueldos-multas-y-beneficios-laborales)
- [SBS – Comisiones y prima del SPP](https://www.sbs.gob.pe/app/spp/empleadores/comisiones_spp/Paginas/comision_prima.aspx)
- [Modelo.pe – Tasas AFP 2026](https://modelo.pe/blog/afp-porcentaje-de-descuento-2026-peru/)
- [LP Derecho – Guía sobre boletas de pago (MTPE)](https://lpderecho.pe/descargue-pdf-guia-boletas-pago/)
- [BBVA Perú – Boleta de pago: estructura y datos](https://www.bbva.com/es/pe/salud-financiera/boleta-de-pago-en-peru-estructura-y-datos-que-se-debe-tener-en-cuenta/)
- [Buk – Boletas de pago digitales y firma digital](https://www.buk.pe/blog/boletas-de-pago-digitales-firma-digital-en-rr-hh)
- [LP Derecho – DS 011-2026-EF, billetera digital](https://lpderecho.pe/reglamento-ley-habilita-billetera-digital-percibir-pago-sueldos-beneficios-laborales-decreto-supremo-011-2026-ef/)
