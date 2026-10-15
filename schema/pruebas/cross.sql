SET search_path = hr, public;
INSERT INTO legal_entity(id, code, legal_name, country_code, currency_code) VALUES ('00000000-0000-0000-0000-0000000000e2','MIN','Minera','PE','PEN');
INSERT INTO pay_calendar(id, code, name, frequency, monthly_start_day, pay_offset_days, timezone) VALUES ('00000000-0000-0000-0000-0000000000a5','M16','Mensual 16 al 15','monthly',16,3,'America/Lima');
INSERT INTO pay_group(id, legal_entity_id, pay_calendar_id, code, name, currency_code) VALUES ('00000000-0000-0000-0000-0000000000b5','00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000a5','MIN','Mina','PEN');
SELECT fn_generate_pay_periods('00000000-0000-0000-0000-0000000000b5', 2026) AS n;
SELECT period_no, period_start, period_end, pay_date, period_end-period_start+1 AS dias FROM pay_period WHERE pay_group_id='00000000-0000-0000-0000-0000000000b5' ORDER BY 1 LIMIT 3;
SELECT period_no, period_start, period_end FROM pay_period WHERE pay_group_id='00000000-0000-0000-0000-0000000000b5' ORDER BY 1 DESC LIMIT 1;
