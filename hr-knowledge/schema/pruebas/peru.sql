SET search_path = hr, public;
SET app.retro_detection='off';
INSERT INTO legal_pack(id,country_code,version,released_on,effective_from) VALUES ('00000000-0000-0000-0000-00000000aa00','PE','2026.10','2026-09-28','2026-10-01');
INSERT INTO legal_parameter(country_code,code,name,value,valid_from,valid_to,source_ref) VALUES
 ('PE','RMV','Remuneración mínima vital',1130,'2025-01-01','2026-10-01','DS 006-2024-TR'),
 ('PE','RMV','Remuneración mínima vital',1230,'2026-10-01',NULL,'DS 015-2026-TR'),
 ('PE','UIT','Unidad impositiva tributaria',5500,'2026-01-01',NULL,'DS 301-2025-EF'),
 ('PE','RMA','Remuneración máxima asegurable',12598.91,'2026-04-01','2026-07-01','SBS');
-- La RMV vigente cambia el 1 de octubre: ¿cuánto vale la asignación familiar (10% RMV) cada mes?
SELECT d::date AS fecha, value AS rmv, round(value*0.10,2) AS asignacion_familiar
FROM generate_series('2026-09-15'::date,'2026-10-15','30 days') d
JOIN legal_parameter p ON p.code='RMV' AND p.valid_from<=d AND (p.valid_to IS NULL OR p.valid_to>d);
INSERT INTO statutory_scheme(id,country_code,code,name,scheme_type) VALUES
 ('00000000-0000-0000-0000-00000000005a','PE','AFP_COMISION','AFP comisión','pension') ;
INSERT INTO statutory_provider(id,scheme_id,code,name) VALUES
 ('00000000-0000-0000-0000-00000000005b','00000000-0000-0000-0000-00000000005a','INTEGRA','AFP Integra'),
 ('00000000-0000-0000-0000-00000000005c','00000000-0000-0000-0000-00000000005a','HABITAT','AFP Habitat');
INSERT INTO statutory_rate(scheme_id,provider_id,variant,employee_rate,valid_from) VALUES
 ('00000000-0000-0000-0000-00000000005a','00000000-0000-0000-0000-00000000005b','flujo',0.0155,'2026-01-01'),
 ('00000000-0000-0000-0000-00000000005a','00000000-0000-0000-0000-00000000005b','mixta',0.0,'2026-01-01'),
 ('00000000-0000-0000-0000-00000000005a','00000000-0000-0000-0000-00000000005c','flujo',0.0147,'2026-01-01');
DO $$ BEGIN
 INSERT INTO hr.statutory_rate(scheme_id,provider_id,variant,employee_rate,valid_from) VALUES
 ('00000000-0000-0000-0000-00000000005a','00000000-0000-0000-0000-00000000005b','flujo',0.0160,'2026-06-01');
 RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK solape de tasa bloqueado'; END $$;
