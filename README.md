# erp-knowledge

Bases de conocimiento profesional para diseñar módulos de un ERP multitenant. Cada base es
independiente y se publica como una skill propia:

| Base | Skill | Dominio |
|---|---|---|
| [hr-knowledge](hr-knowledge/README.md) | `hcm-nomina` | RRHH (HCM), nómina, legislación laboral peruana |
| [logistica-knowledge](logistica-knowledge/README.md) | `logistica` | Inventario, kardex, valorización, almacén, compras, guías de remisión |
| [pos-knowledge](pos-knowledge/README.md) | `pos` | Caja, venta, precios, pagos, comprobantes electrónicos, operación sin red |

## Aislamiento entre bases

- Un dato vive en una sola base. Si un tema pertenece a otra, se enlaza (sección «Bases hermanas»),
  no se copia.
- Cada skill lee solo los archivos de su carpeta; solo abre otra base cuando el tema la deriva ahí.
- Los enlaces entre bases son relativos (`../logistica-knowledge/...`), por eso las tres carpetas viven
  como hermanas en la raíz.

## Instalar las skills

```bash
git clone git@github.com:MiguelBarreraDev/erp-knowledge.git ~/dev/erp-knowledge
for s in hr-knowledge:hcm-nomina logistica-knowledge:logistica pos-knowledge:pos; do
  ln -sfn ~/dev/erp-knowledge/${s%%:*}/skill ~/.claude/skills/${s##*:}
done
```

Instala solo la skill que necesites; ninguna depende de que las otras estén instaladas.
