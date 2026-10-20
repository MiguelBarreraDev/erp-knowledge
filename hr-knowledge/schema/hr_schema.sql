-- =============================================================================
-- MÓDULO RRHH – ERP MULTITENANT (DB POR TENANT) – PostgreSQL 14+
-- Esquema consolidado (incluye nómina y lógica de periodos). Una sola fuente de verdad:
-- las migraciones se numeran a partir del primer despliegue en producción.
-- =============================================================================
-- Decisiones de diseño:
--  * DB por tenant => NO hay columna tenant_id. El aislamiento es la propia BD.
--  * Un schema `hr`. Las migraciones se aplican a cada BD de tenant (Flyway/Liquibase/etc.)
--    y se registra la versión en una tabla de control del catálogo central.
--  * PK uuid (v7 si tu motor lo permite, mejor localidad de índice).
--  * Datos con vigencia (asignaciones, compensación, etc.) => valid_from / valid_to
--    con EXCLUDE para evitar solapes. valid_to NULL = vigente.
--  * Nómina inmutable: los resultados calculados se guardan (snapshot), no se recalculan.
--  * Saldos de vacaciones = libro mayor (ledger), el saldo se deriva.
--  * Catálogos genéricos (lookup_*) para listas pequeñas y editables por tenant.
--  * Columnas de auditoría (created_*, updated_*, deleted_at) y triggers se añaden
--    al final de forma automática a todas las tablas.
--  * Nómina: tablas marcadas [MVP] (primera nómina mensual) o [F2] (fase 2).
--  * Datos sensibles (salud, cuentas bancarias, documentos de identidad):
--    cifrar a nivel columna o aplicación, y restringir con roles / RLS.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA IF NOT EXISTS hr;
SET search_path = hr, public;

-- =============================================================================
-- 0. CATÁLOGOS GENÉRICOS
--    Tipos sugeridos: GENDER, MARITAL_STATUS, ID_DOC_TYPE, RELATIONSHIP,
--    EDUCATION_LEVEL, TERMINATION_REASON, CHANGE_REASON, CONTRACT_TYPE,
--    EMPLOYMENT_TYPE, LABOR_REGIME, DOC_CATEGORY, SKILL_LEVEL, INCIDENT_TYPE, SANCTION_TYPE
-- =============================================================================
CREATE TABLE lookup_type (
  code        text PRIMARY KEY,
  name        text NOT NULL,
  description text
);

CREATE TABLE lookup_value (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type_code   text NOT NULL REFERENCES lookup_type(code),
  code        text NOT NULL,
  name        text NOT NULL,
  sort_order  int  NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  meta        jsonb NOT NULL DEFAULT '{}',
  UNIQUE (type_code, code)
);

-- =============================================================================
-- 1. ESTRUCTURA ORGANIZACIONAL
-- =============================================================================
CREATE TABLE legal_entity (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL UNIQUE,
  legal_name     text NOT NULL,
  trade_name     text,
  tax_id         text,
  country_code   char(2) NOT NULL,
  currency_code  char(3) NOT NULL,
  address        jsonb,
  is_active      boolean NOT NULL DEFAULT true
);

CREATE TABLE location (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id  uuid NOT NULL REFERENCES legal_entity(id),
  code             text NOT NULL,
  name             text NOT NULL,
  address_line1    text,
  address_line2    text,
  city             text,
  state            text,
  postal_code      text,
  country_code     char(2),
  timezone         text NOT NULL DEFAULT 'UTC',
  is_active        boolean NOT NULL DEFAULT true,
  UNIQUE (legal_entity_id, code)
);

CREATE TABLE cost_center (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id  uuid REFERENCES cost_center(id),
  code       text NOT NULL UNIQUE,
  name       text NOT NULL,
  gl_account text,                      -- vínculo con contabilidad
  is_active  boolean NOT NULL DEFAULT true
);

CREATE TABLE department (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id      uuid NOT NULL REFERENCES legal_entity(id),
  parent_id            uuid REFERENCES department(id),
  code                 text NOT NULL,
  name                 text NOT NULL,
  cost_center_id       uuid REFERENCES cost_center(id),
  manager_employee_id  uuid,            -- FK diferida (ver más abajo)
  valid_from           date NOT NULL DEFAULT current_date,
  valid_to             date,
  is_active            boolean NOT NULL DEFAULT true,
  UNIQUE (legal_entity_id, code)
);

CREATE TABLE job_family (
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code  text NOT NULL UNIQUE,
  name  text NOT NULL
);

CREATE TABLE job_grade (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL UNIQUE,
  name          text NOT NULL,
  level         int  NOT NULL,
  min_salary    numeric(14,2),
  mid_salary    numeric(14,2),
  max_salary    numeric(14,2),
  currency_code char(3)
);

CREATE TABLE job (                      -- Puesto genérico (catálogo de cargos)
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL UNIQUE,
  title         text NOT NULL,
  family_id     uuid REFERENCES job_family(id),
  grade_id      uuid REFERENCES job_grade(id),
  description   text,
  requirements  text,
  is_active     boolean NOT NULL DEFAULT true
);

CREATE TABLE position (                 -- Plaza concreta dentro de la estructura
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                  text NOT NULL UNIQUE,
  job_id                uuid NOT NULL REFERENCES job(id),
  department_id         uuid NOT NULL REFERENCES department(id),
  location_id           uuid REFERENCES location(id),
  reports_to_position_id uuid REFERENCES position(id),
  headcount             int  NOT NULL DEFAULT 1 CHECK (headcount >= 0),
  status                text NOT NULL DEFAULT 'open'
                        CHECK (status IN ('planned','open','filled','frozen','closed')),
  valid_from            date NOT NULL DEFAULT current_date,
  valid_to              date
);

-- =============================================================================
-- 2. PERSONA Y EMPLEADO
-- =============================================================================
CREATE TABLE person (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name         text NOT NULL,
  middle_name        text,
  last_name          text NOT NULL,
  second_last_name   text,
  preferred_name     text,
  birth_date         date,
  birth_country      char(2),
  nationality        char(2),
  gender_id          uuid REFERENCES lookup_value(id),
  marital_status_id  uuid REFERENCES lookup_value(id),
  personal_email     text,
  mobile_phone       text,
  photo_document_id  uuid
);

CREATE TABLE person_identification (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id      uuid NOT NULL REFERENCES person(id),
  doc_type_id    uuid NOT NULL REFERENCES lookup_value(id),
  number         text NOT NULL,         -- cifrar si aplica
  issuing_country char(2),
  issue_date     date,
  expiry_date    date,
  is_primary     boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX uq_person_ident ON person_identification (doc_type_id, number);

CREATE TABLE person_address (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES person(id),
  address_type  text NOT NULL DEFAULT 'home' CHECK (address_type IN ('home','mailing','work','other')),
  line1         text NOT NULL,
  line2         text,
  city          text,
  state         text,
  postal_code   text,
  country_code  char(2),
  is_primary    boolean NOT NULL DEFAULT false,
  valid_from    date NOT NULL DEFAULT current_date,
  valid_to      date
);

CREATE TABLE person_relative (          -- Contactos de emergencia y dependientes
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id        uuid NOT NULL REFERENCES person(id),
  full_name        text NOT NULL,
  relationship_id  uuid REFERENCES lookup_value(id),
  birth_date       date,
  phone            text,
  email            text,
  is_emergency_contact boolean NOT NULL DEFAULT false,
  is_dependent     boolean NOT NULL DEFAULT false,
  is_beneficiary   boolean NOT NULL DEFAULT false,
  beneficiary_pct  numeric(5,2) CHECK (beneficiary_pct BETWEEN 0 AND 100)
);

CREATE TABLE person_bank_account (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id        uuid NOT NULL REFERENCES person(id),
  bank_name        text NOT NULL,
  account_type     text,                -- ahorros, corriente, etc.
  account_number   text NOT NULL,       -- cifrar
  iban             text,
  swift_bic        text,
  currency_code    char(3),
  is_primary       boolean NOT NULL DEFAULT false,
  valid_from       date NOT NULL DEFAULT current_date,
  valid_to         date
);

CREATE TABLE skill (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code      text NOT NULL UNIQUE,
  name      text NOT NULL,
  category  text
);

CREATE TABLE person_skill (
  person_id  uuid NOT NULL REFERENCES person(id),
  skill_id   uuid NOT NULL REFERENCES skill(id),
  level_id   uuid REFERENCES lookup_value(id),
  years_exp  numeric(4,1),
  PRIMARY KEY (person_id, skill_id)
);

CREATE TABLE person_education (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id      uuid NOT NULL REFERENCES person(id),
  level_id       uuid REFERENCES lookup_value(id),
  institution    text NOT NULL,
  degree         text,
  field_of_study text,
  start_date     date,
  end_date       date,
  is_completed   boolean NOT NULL DEFAULT false
);

CREATE TABLE person_certification (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES person(id),
  name          text NOT NULL,
  issuer        text,
  credential_no text,
  issued_on     date,
  expires_on    date
);

CREATE TABLE person_work_experience (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   uuid NOT NULL REFERENCES person(id),
  employer    text NOT NULL,
  job_title   text,
  start_date  date,
  end_date    date,
  description text
);

CREATE TABLE employee (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id         uuid NOT NULL REFERENCES person(id),
  legal_entity_id   uuid NOT NULL REFERENCES legal_entity(id),
  employee_number   text NOT NULL,
  user_id           uuid,               -- usuario del ERP (módulo de seguridad)
  work_email        text,
  work_phone        text,
  hire_date         date NOT NULL,
  original_hire_date date,              -- antigüedad reconocida (recontrataciones)
  seniority_date    date,
  status            text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('pre_hire','active','on_leave','suspended','terminated')),
  termination_date  date,
  UNIQUE (legal_entity_id, employee_number)
);
CREATE INDEX ix_employee_person ON employee(person_id);

ALTER TABLE department
  ADD CONSTRAINT fk_department_manager FOREIGN KEY (manager_employee_id) REFERENCES employee(id);

-- Documentos (metadatos; el binario vive en object storage)
CREATE TABLE document (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     uuid REFERENCES employee(id),
  person_id       uuid REFERENCES person(id),
  category_id      uuid REFERENCES lookup_value(id),
  name            text NOT NULL,
  storage_key     text NOT NULL,
  mime_type       text,
  size_bytes      bigint,
  sha256          text,
  expires_on      date,
  is_confidential boolean NOT NULL DEFAULT true,
  uploaded_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_document_employee ON document(employee_id);

ALTER TABLE person
  ADD CONSTRAINT fk_person_photo FOREIGN KEY (photo_document_id) REFERENCES document(id);

-- =============================================================================
-- 3. RELACIÓN LABORAL (con vigencia)
-- =============================================================================
CREATE TABLE employment_contract (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id        uuid NOT NULL REFERENCES employee(id),
  contract_number    text,
  contract_type_id   uuid REFERENCES lookup_value(id),  -- indefinido, plazo fijo, obra, etc.
  labor_regime_id    uuid REFERENCES lookup_value(id),  -- régimen laboral (general, MYPE, agrario…): decide qué conceptos aplican
  start_date         date NOT NULL,
  end_date           date,
  probation_end_date date,
  weekly_hours       numeric(5,2),
  status             text NOT NULL DEFAULT 'active'
                     CHECK (status IN ('draft','active','expired','terminated','renewed')),
  renewed_from_id    uuid REFERENCES employment_contract(id),
  document_id        uuid REFERENCES document(id),
  signed_at          date
);
CREATE INDEX ix_contract_employee ON employment_contract(employee_id);

CREATE TABLE employee_assignment (      -- Historial de puesto/depto/jefe/ubicación
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         uuid NOT NULL REFERENCES employee(id),
  position_id         uuid REFERENCES position(id),
  job_id              uuid REFERENCES job(id),
  department_id       uuid REFERENCES department(id),
  location_id         uuid REFERENCES location(id),
  cost_center_id      uuid REFERENCES cost_center(id),
  manager_employee_id uuid REFERENCES employee(id),
  employment_type_id  uuid REFERENCES lookup_value(id),  -- tiempo completo, parcial, etc.
  worker_type         text NOT NULL DEFAULT 'employee'
                      CHECK (worker_type IN ('employee','contractor','intern','temp')),
  fte                 numeric(4,3) NOT NULL DEFAULT 1.000,
  change_reason_id    uuid REFERENCES lookup_value(id), -- promoción, traslado, etc.
  valid_from          date NOT NULL,
  valid_to            date,
  EXCLUDE USING gist (employee_id WITH =, daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE employee_compensation (    -- Salario base con vigencia
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  pay_basis      text NOT NULL CHECK (pay_basis IN ('hourly','daily','weekly','monthly','annual')),
  amount         numeric(14,2) NOT NULL CHECK (amount >= 0),
  currency_code  char(3) NOT NULL,
  pay_frequency  text NOT NULL DEFAULT 'monthly'
                 CHECK (pay_frequency IN ('weekly','biweekly','semimonthly','monthly')),
  grade_id       uuid REFERENCES job_grade(id),
  change_reason_id uuid REFERENCES lookup_value(id),
  valid_from     date NOT NULL,
  valid_to       date,
  EXCLUDE USING gist (employee_id WITH =, daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE termination (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id        uuid NOT NULL REFERENCES employee(id),
  termination_type   text NOT NULL
                     CHECK (termination_type IN ('resignation','dismissal','end_of_contract','retirement','mutual_agreement','death','abandonment','other')),
  reason_id          uuid REFERENCES lookup_value(id),
  notice_date        date,
  last_working_day   date NOT NULL,
  is_voluntary       boolean,
  rehire_eligible    boolean,
  exit_interview_notes text,
  final_settlement_run_id uuid,          -- FK a payroll_run (diferida)
  status             text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','approved','completed','cancelled'))
);

-- =============================================================================
-- 4. TIEMPO Y ASISTENCIA
-- =============================================================================
CREATE TABLE holiday_calendar (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL UNIQUE,
  name          text NOT NULL,
  country_code  char(2),
  location_id   uuid REFERENCES location(id)
);

CREATE TABLE holiday (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_id  uuid NOT NULL REFERENCES holiday_calendar(id),
  holiday_date date NOT NULL,
  name         text NOT NULL,
  is_paid      boolean NOT NULL DEFAULT true,
  UNIQUE (calendar_id, holiday_date)
);

CREATE TABLE shift (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL UNIQUE,
  name             text NOT NULL,
  start_time       time NOT NULL,
  end_time         time NOT NULL,
  break_minutes    int  NOT NULL DEFAULT 0,
  crosses_midnight boolean NOT NULL DEFAULT false,
  is_night         boolean NOT NULL DEFAULT false
);

CREATE TABLE work_schedule (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL UNIQUE,
  name          text NOT NULL,
  weekly_hours  numeric(5,2) NOT NULL,
  rotation_weeks int NOT NULL DEFAULT 1
);

CREATE TABLE work_schedule_day (
  schedule_id  uuid NOT NULL REFERENCES work_schedule(id),
  week_no      int  NOT NULL DEFAULT 1,
  weekday      int  NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  shift_id     uuid REFERENCES shift(id),      -- NULL = día libre
  PRIMARY KEY (schedule_id, week_no, weekday)
);

CREATE TABLE employee_schedule (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES employee(id),
  schedule_id  uuid NOT NULL REFERENCES work_schedule(id),
  calendar_id  uuid REFERENCES holiday_calendar(id),
  valid_from   date NOT NULL,
  valid_to     date,
  EXCLUDE USING gist (employee_id WITH =, daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE attendance_punch (         -- Marcaciones crudas (biométrico, app, web)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES employee(id),
  punched_at   timestamptz NOT NULL,
  direction    text NOT NULL CHECK (direction IN ('in','out','break_start','break_end')),
  source       text NOT NULL DEFAULT 'manual'
               CHECK (source IN ('manual','biometric','mobile','web','import')),
  device_ref   text,
  latitude     numeric(9,6),
  longitude    numeric(9,6),
  is_adjusted  boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_punch_emp_time ON attendance_punch(employee_id, punched_at);

CREATE TABLE attendance_daily (         -- Consolidado diario procesado
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES employee(id),
  work_date         date NOT NULL,
  shift_id          uuid REFERENCES shift(id),
  scheduled_minutes int NOT NULL DEFAULT 0,
  worked_minutes    int NOT NULL DEFAULT 0,
  late_minutes      int NOT NULL DEFAULT 0,
  early_leave_minutes int NOT NULL DEFAULT 0,
  overtime_minutes  int NOT NULL DEFAULT 0,
  night_minutes     int NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'present'
                    CHECK (status IN ('present','absent','leave','holiday','rest_day','partial')),
  approved_by       uuid REFERENCES employee(id),
  approved_at       timestamptz,
  UNIQUE (employee_id, work_date)
);

CREATE TABLE overtime_request (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES employee(id),
  work_date     date NOT NULL,
  minutes       int  NOT NULL CHECK (minutes > 0),
  overtime_type text NOT NULL DEFAULT 'regular' CHECK (overtime_type IN ('regular','night','holiday','rest_day')),
  reason        text,
  compensation  text NOT NULL DEFAULT 'pay' CHECK (compensation IN ('pay','time_off')),
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled'))
);

CREATE TABLE timesheet_entry (          -- Horas por proyecto/tarea (opcional)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES employee(id),
  work_date    date NOT NULL,
  hours        numeric(5,2) NOT NULL CHECK (hours > 0),
  project_ref  text,                    -- referencia al módulo de proyectos
  task_ref     text,
  is_billable  boolean NOT NULL DEFAULT false,
  notes        text,
  status       text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','approved','rejected'))
);

-- =============================================================================
-- 5. AUSENCIAS Y VACACIONES
-- =============================================================================
CREATE TABLE leave_type (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                text NOT NULL UNIQUE,
  name                text NOT NULL,        -- vacaciones, enfermedad, maternidad, duelo, etc.
  is_paid             boolean NOT NULL DEFAULT true,
  unit                text NOT NULL DEFAULT 'days' CHECK (unit IN ('days','hours')),
  count_calendar_days boolean NOT NULL DEFAULT false,  -- false = solo laborables
  requires_document   boolean NOT NULL DEFAULT false,
  max_consecutive     numeric(6,2),
  allows_negative_balance boolean NOT NULL DEFAULT false,
  affects_payroll     boolean NOT NULL DEFAULT false,
  payroll_concept_id  uuid,                 -- FK diferida
  is_active           boolean NOT NULL DEFAULT true
);

CREATE TABLE leave_policy (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  leave_type_id     uuid NOT NULL REFERENCES leave_type(id),
  code              text NOT NULL UNIQUE,
  name              text NOT NULL,
  accrual_method    text NOT NULL DEFAULT 'annual'
                    CHECK (accrual_method IN ('none','annual','monthly','per_hours_worked','seniority')),
  annual_entitlement numeric(6,2) NOT NULL DEFAULT 0,
  seniority_rules   jsonb,                 -- p.ej. [{"from_years":5,"days":20}]
  carryover_max     numeric(6,2),
  carryover_expires_months int,
  waiting_period_days int NOT NULL DEFAULT 0,
  valid_from        date NOT NULL DEFAULT current_date,
  valid_to          date
);

CREATE TABLE employee_leave_policy (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES employee(id),
  policy_id    uuid NOT NULL REFERENCES leave_policy(id),
  valid_from   date NOT NULL,
  valid_to     date
);

CREATE TABLE leave_request (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  leave_type_id  uuid NOT NULL REFERENCES leave_type(id),
  start_date     date NOT NULL,
  end_date       date NOT NULL,
  start_half_day boolean NOT NULL DEFAULT false,
  end_half_day   boolean NOT NULL DEFAULT false,
  quantity       numeric(6,2) NOT NULL,    -- días/horas efectivamente descontados
  reason         text,
  document_id    uuid REFERENCES document(id),
  status         text NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft','pending','approved','rejected','cancelled','taken')),
  submitted_at   timestamptz,
  CHECK (end_date >= start_date)
);
CREATE INDEX ix_leave_req_emp ON leave_request(employee_id, start_date);

CREATE TABLE leave_ledger (              -- Saldo = SUM(quantity)
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  leave_type_id  uuid NOT NULL REFERENCES leave_type(id),
  entry_date     date NOT NULL,
  entry_type     text NOT NULL
                 CHECK (entry_type IN ('opening','accrual','usage','adjustment','carryover','expiry','payout')),
  quantity       numeric(7,2) NOT NULL,    -- + suma / - resta
  leave_request_id uuid REFERENCES leave_request(id),
  expires_on     date,
  notes          text
);
CREATE INDEX ix_leave_ledger ON leave_ledger(employee_id, leave_type_id);

-- =============================================================================
-- 6. NÓMINA
--    Etiquetas: [MVP] necesaria para la primera nómina mensual real.
--               [F2]  fase 2: se puede posponer sin cambiar el diseño.
--    Lógica de periodos (máquina de estados, bloqueos, generación): sección 16.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 6.1 Paquete legal: reglas del país, versionadas
-- -----------------------------------------------------------------------------
CREATE TABLE legal_pack (                 -- [MVP] versión de las reglas legales de un país
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code    char(2) NOT NULL,
  version         text NOT NULL,          -- p.ej. '2026.03'
  released_on     date NOT NULL,
  effective_from  date NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','superseded')),
  notes           text,
  UNIQUE (country_code, version)
);

CREATE TABLE statutory_scheme (           -- [MVP] régimen: pensión, salud, impuesto…
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_pack_id  uuid REFERENCES legal_pack(id),
  country_code   char(2) NOT NULL,
  code           text NOT NULL,
  name           text NOT NULL,
  scheme_type    text NOT NULL
                 CHECK (scheme_type IN ('social_security','pension','health','income_tax','housing','other')),
  UNIQUE (country_code, code)
);

CREATE TABLE statutory_provider (         -- [MVP] administradora del régimen (AFP, EPS, aseguradora)
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scheme_id      uuid NOT NULL REFERENCES statutory_scheme(id),
  code           text NOT NULL,
  name           text NOT NULL,
  legal_code     text,                    -- código oficial para declaraciones
  is_active      boolean NOT NULL DEFAULT true,
  UNIQUE (scheme_id, code)
);

CREATE TABLE legal_parameter (            -- [MVP] valores legales con vigencia: RMV, UIT, RMA…
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_pack_id  uuid REFERENCES legal_pack(id),
  country_code   char(2) NOT NULL,
  code           text NOT NULL,           -- 'RMV', 'UIT', 'RMA', 'ESSALUD_MIN_BASE'…
  name           text NOT NULL,
  value          numeric(14,4) NOT NULL,
  unit           text NOT NULL DEFAULT 'money' CHECK (unit IN ('money','percent','days','hours','count')),
  valid_from     date NOT NULL,
  valid_to       date,
  source_ref     text,                    -- norma que lo fija (p.ej. 'DS 015-2026-TR')
  EXCLUDE USING gist (country_code WITH =, code WITH =,
                      daterange(valid_from, valid_to, '[)') WITH &&)
);

-- -----------------------------------------------------------------------------
-- 6.2 Conceptos y bases
--     payroll_concept = identidad estable; payroll_concept_version = cómo se calcula
--     en cada rango de fechas; payroll_balance(_feed) = bases, totales y acumulados.
-- -----------------------------------------------------------------------------
CREATE TABLE payroll_concept (            -- [MVP] rubro de la boleta
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 text NOT NULL UNIQUE,
  name                 text NOT NULL,
  concept_type         text NOT NULL
                       CHECK (concept_type IN ('earning','deduction','employer_contribution',
                                               'benefit_in_kind','informative')),
  phase                text NOT NULL DEFAULT 'earning'      -- etapa del motor en que se evalúa
                       CHECK (phase IN ('earning','employee_contribution','tax','deduction',
                                        'employer_contribution','provision','informative')),
  processing_priority  int NOT NULL DEFAULT 1000,           -- orden dentro de la fase
  is_legal             boolean NOT NULL DEFAULT false,      -- definido por el paquete legal (bloqueado)
  legal_pack_id        uuid REFERENCES legal_pack(id),
  legal_code           text,                                -- código oficial para declaraciones
  payslip_section      text NOT NULL DEFAULT 'earnings'
                       CHECK (payslip_section IN ('earnings','deductions','employer','informative','hidden')),
  payslip_label        text,
  sort_order           int NOT NULL DEFAULT 0,
  gl_account           text,                                -- cuenta contable
  is_retro_eligible    boolean NOT NULL DEFAULT true,
  allow_manual_input   boolean NOT NULL DEFAULT false,
  is_active            boolean NOT NULL DEFAULT true
);

ALTER TABLE leave_type
  ADD CONSTRAINT fk_leave_type_concept FOREIGN KEY (payroll_concept_id) REFERENCES payroll_concept(id);

CREATE TABLE payroll_balance (            -- [MVP] suma con nombre: GROSS, NET, BASE_SS, BASE_TAX…
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL UNIQUE,
  name             text NOT NULL,
  balance_type     text NOT NULL CHECK (balance_type IN ('base','total','accumulator','counter')),
  unit             text NOT NULL DEFAULT 'money' CHECK (unit IN ('money','hours','days','count')),
  reset_frequency  text NOT NULL DEFAULT 'year'
                   CHECK (reset_frequency IN ('period','month','quarter','year','never')),
  legal_pack_id    uuid REFERENCES legal_pack(id),
  description      text
);

CREATE TABLE payroll_balance_feed (       -- [MVP] matriz concepto × base (imponibilidad)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  balance_id   uuid NOT NULL REFERENCES payroll_balance(id),
  concept_id   uuid NOT NULL REFERENCES payroll_concept(id),
  factor       numeric(7,4) NOT NULL DEFAULT 1,   -- 1 suma, -1 resta, 0.5 aporta la mitad
  valid_from   date NOT NULL,
  valid_to     date,
  EXCLUDE USING gist (balance_id WITH =, concept_id WITH =,
                      daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE payroll_concept_version (    -- [MVP] cómo se calcula un concepto en cada rango de fechas
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  concept_id        uuid NOT NULL REFERENCES payroll_concept(id),
  calc_method       text NOT NULL
                    CHECK (calc_method IN ('fixed','percentage','rate_x_quantity',
                                           'formula','bracket','external')),
  amount            numeric(14,2),
  rate              numeric(12,6),
  base_balance_id   uuid REFERENCES payroll_balance(id),   -- base para 'percentage'
  formula           text,                                  -- DSL del motor
  proration_method  text NOT NULL DEFAULT 'none'
                    CHECK (proration_method IN ('none','days_30_360','calendar_days',
                                                'working_days','hours','fte')),
  rounding_scale    int NOT NULL DEFAULT 2,
  min_amount        numeric(14,2),
  max_amount        numeric(14,2),
  valid_from        date NOT NULL,
  valid_to          date,
  change_note       text,
  EXCLUDE USING gist (concept_id WITH =, daterange(valid_from, valid_to, '[)') WITH &&),
  CHECK (calc_method <> 'percentage' OR (rate IS NOT NULL AND base_balance_id IS NOT NULL)),
  CHECK (calc_method <> 'formula'    OR formula IS NOT NULL),
  CHECK (calc_method <> 'fixed'      OR amount IS NOT NULL)
);

CREATE TABLE statutory_rate (             -- [MVP] tasas, piso, tope y tramos con vigencia
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scheme_id                  uuid NOT NULL REFERENCES statutory_scheme(id),
  provider_id                uuid REFERENCES statutory_provider(id),  -- NULL = igual para todos
  variant                    text,           -- p.ej. comisión 'flujo' o 'mixta'
  legal_pack_id              uuid REFERENCES legal_pack(id),
  employee_rate              numeric(7,4),
  employer_rate              numeric(7,4),
  salary_floor               numeric(14,2),
  salary_ceiling             numeric(14,2),
  floor_param_code           text,           -- piso tomado de legal_parameter (p.ej. 'RMV')
  ceiling_param_code         text,           -- tope tomado de legal_parameter (p.ej. 'RMA')
  brackets                   jsonb,          -- tramos progresivos: [{"from":0,"to":12000,"rate":0}, …]
  payroll_concept_employee   uuid REFERENCES payroll_concept(id),
  payroll_concept_employer   uuid REFERENCES payroll_concept(id),
  valid_from                 date NOT NULL,
  valid_to                   date,
  EXCLUDE USING gist (scheme_id WITH =,
    (coalesce(provider_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
    (coalesce(variant, '')) WITH =,
    daterange(valid_from, valid_to, '[)') WITH &&)
);

-- -----------------------------------------------------------------------------
-- 6.3 Calendario y periodos
-- -----------------------------------------------------------------------------
CREATE TABLE pay_calendar (               -- [MVP] reglas para generar periodos
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                      text NOT NULL UNIQUE,
  name                      text NOT NULL,
  frequency                 text NOT NULL
                            CHECK (frequency IN ('weekly','biweekly','semimonthly','monthly')),
  anchor_date               date,            -- inicio del primer periodo (weekly/biweekly)
  semimonthly_split_day     int NOT NULL DEFAULT 15 CHECK (semimonthly_split_day BETWEEN 10 AND 20),
  monthly_start_day         int NOT NULL DEFAULT 1 CHECK (monthly_start_day BETWEEN 1 AND 28),
                            -- mensual: 1 = mes calendario; 16 = del 16 al 15 (el periodo toma el mes en que termina)
  pay_date_rule             text NOT NULL DEFAULT 'period_end'
                            CHECK (pay_date_rule IN ('period_end','fixed_day')),
  pay_offset_days           int NOT NULL DEFAULT 0,   -- con 'period_end': +5 después, -3 antes
  pay_day                   int CHECK (pay_day BETWEEN 1 AND 31),   -- con 'fixed_day' (mensual)
  business_day_adjust       text NOT NULL DEFAULT 'previous'
                            CHECK (business_day_adjust IN ('previous','next','none')),
  weekend_days              int[] NOT NULL DEFAULT '{6,7}',  -- ISO: 6 sábado, 7 domingo
  holiday_calendar_id       uuid REFERENCES holiday_calendar(id),
  cutoff_days_before_pay    int NOT NULL DEFAULT 5 CHECK (cutoff_days_before_pay >= 0),  -- días hábiles
  cutoff_time               time NOT NULL DEFAULT '18:00',
  timezone                  text NOT NULL DEFAULT 'UTC',
  fiscal_year_start_month   int NOT NULL DEFAULT 1 CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  fiscal_year_basis         text NOT NULL DEFAULT 'pay_date'
                            CHECK (fiscal_year_basis IN ('pay_date','period_end')),
  is_active                 boolean NOT NULL DEFAULT true,
  CHECK (frequency NOT IN ('weekly','biweekly') OR anchor_date IS NOT NULL),
  CHECK (pay_date_rule <> 'fixed_day' OR (pay_day IS NOT NULL AND frequency = 'monthly')),
  CHECK (monthly_start_day = 1 OR frequency = 'monthly')
);

CREATE TABLE pay_calendar_window_rule (   -- [F2] ventanas de insumos desfasadas (asistencia del 21 al 20)
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_id             uuid NOT NULL REFERENCES pay_calendar(id) ON DELETE CASCADE,
  window_type             text NOT NULL
                          CHECK (window_type IN ('attendance','overtime','leave','commission','expense','other')),
  mode                    text NOT NULL DEFAULT 'same_as_period'
                          CHECK (mode IN ('same_as_period','shift_days','month_end_day')),
  shift_days              int,
  end_day                 int CHECK (end_day BETWEEN 1 AND 28),
  cutoff_days_before_pay  int,             -- NULL = corte del calendario
  UNIQUE (calendar_id, window_type),
  CHECK (mode <> 'shift_days'    OR shift_days IS NOT NULL),
  CHECK (mode <> 'month_end_day' OR end_day IS NOT NULL)
);

CREATE TABLE pay_group (                  -- [MVP] empleados que se procesan juntos
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id  uuid NOT NULL REFERENCES legal_entity(id),
  pay_calendar_id  uuid NOT NULL REFERENCES pay_calendar(id),
  code             text NOT NULL,
  name             text NOT NULL,
  currency_code    char(3) NOT NULL,
  UNIQUE (legal_entity_id, code)
);

CREATE TABLE employee_pay_group (         -- [MVP] pertenencia al grupo con vigencia
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES employee(id),
  pay_group_id  uuid NOT NULL REFERENCES pay_group(id),
  valid_from    date NOT NULL,
  valid_to      date,
  EXCLUDE USING gist (employee_id WITH =, daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE pay_period (                 -- [MVP] periodo concreto; estado controlado en sección 16
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_group_id      uuid NOT NULL REFERENCES pay_group(id),
  pay_calendar_id   uuid REFERENCES pay_calendar(id),
  period_type       text NOT NULL DEFAULT 'regular'
                    CHECK (period_type IN ('regular','off_cycle','adjustment')),
  period_start      date NOT NULL,
  period_end        date NOT NULL,
  pay_date          date NOT NULL,
  cutoff_at         timestamptz,            -- corte de novedades
  accounting_date   date,
  fiscal_year       int,
  period_no         int,                    -- 1..12, 1..24, 1..53
  status            text NOT NULL DEFAULT 'future'
                    CHECK (status IN ('future','open','inputs_closed','processing','closed')),
  opened_at         timestamptz,
  inputs_closed_at  timestamptz,
  closed_at         timestamptz,
  closed_by         text,
  CHECK (period_end >= period_start AND pay_date >= period_start),
  EXCLUDE USING gist (pay_group_id WITH =, daterange(period_start, period_end, '[]') WITH &&)
    WHERE (period_type = 'regular')
);
CREATE INDEX ix_pay_period_group_dates ON pay_period(pay_group_id, period_start, period_end);

CREATE TABLE pay_period_window (          -- [F2] ventanas concretas de cada periodo
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_period_id  uuid NOT NULL REFERENCES pay_period(id) ON DELETE CASCADE,
  window_type    text NOT NULL,
  window_start   date NOT NULL,
  window_end     date NOT NULL,
  cutoff_at      timestamptz,
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  closed_at      timestamptz,
  closed_by      text,
  UNIQUE (pay_period_id, window_type),
  CHECK (window_end >= window_start)
);

CREATE TABLE pay_period_status_log (      -- [MVP] historial de estados del periodo
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pay_period_id  uuid NOT NULL REFERENCES pay_period(id) ON DELETE CASCADE,
  from_status    text,
  to_status      text NOT NULL,
  changed_at     timestamptz NOT NULL DEFAULT now(),
  changed_by     text,
  reason         text
);
CREATE INDEX ix_pay_period_status_log ON pay_period_status_log(pay_period_id, changed_at);

-- -----------------------------------------------------------------------------
-- 6.4 Políticas de nómina (decisiones del cliente que cambian el cálculo)
--     Resolución: grupo de pago > entidad legal > tenant (NULL) > default.
-- -----------------------------------------------------------------------------
CREATE TABLE payroll_setting_def (        -- [MVP] catálogo de políticas (lo define la plataforma)
  setting_key     text PRIMARY KEY,
  description     text NOT NULL,
  allowed_values  jsonb,
  default_value   jsonb NOT NULL
);

INSERT INTO payroll_setting_def (setting_key, description, allowed_values, default_value) VALUES
 ('day_count_convention', 'Cómo se valoriza un día de sueldo mensual al prorratear',
    '["days_30_360","calendar_days","working_days"]', '"days_30_360"'),
 ('monthly_hour_divisor', 'Divisor para obtener el valor hora desde el sueldo mensual', NULL, '240'),
 ('rounding_level', 'Dónde se redondea: por línea o solo en totales', '["line","total"]', '"line"'),
 ('rounding_mode', 'Modo de redondeo monetario', '["half_up","half_even","down","up"]', '"half_up"'),
 ('negative_net_policy', 'Qué hacer si los descuentos superan los ingresos',
    '["carry_forward","reduce_voluntary","employee_debt","block"]', '"carry_forward"'),
 ('min_net_pct', 'Porcentaje mínimo del neto que debe quedar tras descuentos voluntarios', NULL, '0'),
 ('tax_projection_method', 'Cómo se proyecta el ingreso anual para la retención',
    '["annualize_current","ytd_plus_recurring","cumulative_actual"]', '"ytd_plus_recurring"'),
 ('tax_spread_method', 'Cómo se reparte el saldo de impuesto anual',
    '["remaining_periods","current_period"]', '"remaining_periods"'),
 ('tax_period_basis', 'Si el impuesto se imputa por fecha de pago o por periodo de devengo',
    '["payment_date","accrual_period"]', '"payment_date"'),
 ('retro_mode', 'Cómo se procesan los retroactivos', '["shadow_recalc","delta","disabled"]', '"shadow_recalc"'),
 ('retro_max_months', 'Máximo de meses hacia atrás que se recalculan', NULL, '12'),
 ('fx_rate_date', 'Fecha del tipo de cambio para conceptos en otra moneda',
    '["accrual_date","payment_date","period_end"]', '"payment_date"'),
 ('ot_requires_approval', 'Las horas extra solo entran si están aprobadas', '[true,false]', 'true'),
 ('payslip_publish_mode', 'Cuándo se publican las boletas', '["on_approval","on_payment","manual"]', '"on_payment"');

CREATE TABLE payroll_setting (            -- [MVP] valor de una política por alcance y vigencia
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key      text NOT NULL REFERENCES payroll_setting_def(setting_key),
  legal_entity_id  uuid REFERENCES legal_entity(id),   -- NULL = todo el tenant
  pay_group_id     uuid REFERENCES pay_group(id),      -- NULL = toda la entidad
  value            jsonb NOT NULL,
  valid_from       date NOT NULL,
  valid_to         date,
  EXCLUDE USING gist (
    setting_key WITH =,
    (coalesce(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
    (coalesce(pay_group_id,    '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
    daterange(valid_from, valid_to, '[)') WITH &&)
);

-- -----------------------------------------------------------------------------
-- 6.5 Datos de nómina del empleado (todos con vigencia)
--     El sueldo base vive en employee_compensation (sección 3).
-- -----------------------------------------------------------------------------
CREATE TABLE employee_recurring_concept ( -- [MVP] bonos y descuentos fijos de cada periodo
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES employee(id),
  concept_id   uuid NOT NULL REFERENCES payroll_concept(id),
  amount       numeric(14,2),
  percentage   numeric(7,4),
  valid_from   date NOT NULL,
  valid_to     date,
  CHECK (amount IS NOT NULL OR percentage IS NOT NULL),
  EXCLUDE USING gist (employee_id WITH =, concept_id WITH =,
                      daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE employee_statutory_enrollment ( -- [MVP] afiliación a cada régimen
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  scheme_id      uuid NOT NULL REFERENCES statutory_scheme(id),
  provider_id    uuid REFERENCES statutory_provider(id),
  variant        text,                     -- debe coincidir con statutory_rate.variant
  affiliation_no text,                     -- p.ej. CUSPP
  valid_from     date NOT NULL,
  valid_to       date,
  EXCLUDE USING gist (employee_id WITH =, scheme_id WITH =,
                      daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE employee_tax_profile (       -- [MVP] datos para la retención de impuesto
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id                 uuid NOT NULL REFERENCES employee(id),
  tax_residency               text NOT NULL DEFAULT 'resident'
                              CHECK (tax_residency IN ('resident','non_resident')),
  tax_id                      text,
  dependents_count            int NOT NULL DEFAULT 0,
  other_employer_income_ytd   numeric(14,2) NOT NULL DEFAULT 0,
  other_employer_tax_ytd      numeric(14,2) NOT NULL DEFAULT 0,
  deductions                  jsonb NOT NULL DEFAULT '{}',
  valid_from                  date NOT NULL,
  valid_to                    date,
  EXCLUDE USING gist (employee_id WITH =, daterange(valid_from, valid_to, '[)') WITH &&)
);

CREATE TABLE employee_payment_method (    -- [MVP] cómo se reparte el neto entre cuentas
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES employee(id),
  purpose           text NOT NULL DEFAULT 'salary' CHECK (purpose IN ('salary','severance_fund')),
  method            text NOT NULL CHECK (method IN ('bank_transfer','digital_wallet','cash','check','card')),
  bank_account_id   uuid REFERENCES person_bank_account(id),
  priority          int NOT NULL DEFAULT 1,
  allocation_type   text NOT NULL DEFAULT 'remainder'
                    CHECK (allocation_type IN ('remainder','percentage','fixed')),
  allocation_value  numeric(14,4),
  valid_from        date NOT NULL,
  valid_to          date,
  CHECK (method NOT IN ('bank_transfer','digital_wallet') OR bank_account_id IS NOT NULL),
  CHECK (allocation_type = 'remainder' OR allocation_value IS NOT NULL)
);

CREATE TABLE loan (                       -- [MVP] préstamos y adelantos
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id          uuid NOT NULL REFERENCES employee(id),
  loan_type            text NOT NULL DEFAULT 'loan' CHECK (loan_type IN ('loan','salary_advance','other')),
  principal            numeric(14,2) NOT NULL,
  interest_rate        numeric(7,4) NOT NULL DEFAULT 0,
  installments         int NOT NULL CHECK (installments > 0),
  first_due_date       date NOT NULL,
  status               text NOT NULL DEFAULT 'active'
                       CHECK (status IN ('draft','active','paid','cancelled','written_off')),
  deduction_concept_id uuid REFERENCES payroll_concept(id)
);

CREATE TABLE loan_installment (           -- [MVP] cuotas; la vencida se descuenta en nómina
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id                 uuid NOT NULL REFERENCES loan(id) ON DELETE CASCADE,
  installment_no          int NOT NULL,
  due_date                date NOT NULL,
  principal_amount        numeric(14,2) NOT NULL,
  interest_amount         numeric(14,2) NOT NULL DEFAULT 0,
  payroll_result_line_id  uuid,            -- FK en 6.8
  status                  text NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','deducted','paid','skipped')),
  UNIQUE (loan_id, installment_no)
);

CREATE TABLE garnishment_order (          -- [F2] embargos y pensiones de alimentos por mandato
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id          uuid NOT NULL REFERENCES employee(id),
  order_type           text NOT NULL
                       CHECK (order_type IN ('child_support','alimony','tax_authority','creditor','other')),
  case_number          text,
  issuing_authority    text,
  beneficiary_name     text,
  beneficiary_account  text,               -- cifrar
  calc_method          text NOT NULL CHECK (calc_method IN ('percentage','fixed')),
  percentage           numeric(7,4),
  fixed_amount         numeric(14,2),
  base_balance_id      uuid REFERENCES payroll_balance(id),   -- neto embargable
  priority             int NOT NULL,                          -- 1 = primero
  total_debt           numeric(14,2),                         -- NULL = sin tope
  concept_id           uuid NOT NULL REFERENCES payroll_concept(id),
  start_date           date NOT NULL,
  end_date             date,
  status               text NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','suspended','completed','cancelled')),
  document_id          uuid REFERENCES document(id),
  CHECK (calc_method <> 'percentage' OR percentage IS NOT NULL),
  CHECK (calc_method <> 'fixed' OR fixed_amount IS NOT NULL)
);

-- -----------------------------------------------------------------------------
-- 6.6 Corridas
-- -----------------------------------------------------------------------------
CREATE TABLE payroll_run (                -- [MVP] una ejecución del cálculo sobre un periodo
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_period_id      uuid NOT NULL REFERENCES pay_period(id),
  run_type           text NOT NULL DEFAULT 'regular'
                     CHECK (run_type IN ('regular','off_cycle','bonus','retroactive','final_settlement',
                                         'thirteenth','profit_sharing','advance','reversal',
                                         'balance_adjustment')),
  version            int NOT NULL DEFAULT 1,
  scope              text NOT NULL DEFAULT 'all' CHECK (scope IN ('all','selection')),
  status             text NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft','calculating','calculated','approved','paid','posted',
                                       'reversed','failed','discarded')),
  parent_run_id      uuid REFERENCES payroll_run(id),   -- reversa o recálculo de
  is_simulation      boolean NOT NULL DEFAULT false,
  simulation_params  jsonb,                              -- supuestos de la simulación
  engine_version     text,                               -- reproducibilidad
  legal_pack_id      uuid REFERENCES legal_pack(id),
  config_hash        text,
  payment_date       date,                               -- override de pay_period.pay_date
  calculated_at      timestamptz,
  calculated_by      text,
  approved_at        timestamptz,
  approved_by        text,
  paid_at            timestamptz,
  posted_at          timestamptz,
  reversed_at        timestamptz,
  reversal_reason    text,
  notes              text
);

ALTER TABLE termination
  ADD CONSTRAINT fk_termination_run FOREIGN KEY (final_settlement_run_id) REFERENCES payroll_run(id);

CREATE TABLE payroll_run_employee (       -- [MVP] población de la corrida y estado por empleado
  run_id           uuid NOT NULL REFERENCES payroll_run(id) ON DELETE CASCADE,
  employee_id      uuid NOT NULL REFERENCES employee(id),
  status           text NOT NULL DEFAULT 'included'
                   CHECK (status IN ('included','excluded','error','calculated','held')),
  exclusion_reason text,
  input_hash       text,                   -- detecta insumos cambiados después del cálculo
  calculated_at    timestamptz,
  PRIMARY KEY (run_id, employee_id)
);

CREATE TABLE payroll_message (            -- [MVP] validaciones y errores del motor
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id          uuid NOT NULL REFERENCES payroll_run(id) ON DELETE CASCADE,
  employee_id     uuid REFERENCES employee(id),
  severity        text NOT NULL CHECK (severity IN ('error','warning','info')),
  code            text NOT NULL,          -- p.ej. 'NO_BANK_ACCOUNT', 'NET_VARIATION'
  message         text NOT NULL,
  context         jsonb NOT NULL DEFAULT '{}',
  is_blocking     boolean NOT NULL DEFAULT false,
  resolved_at     timestamptz,
  resolved_by     text,
  resolution_note text
);
CREATE INDEX ix_payroll_message_run ON payroll_message(run_id, severity);

CREATE TABLE payroll_retro_trigger (      -- [F2] cambios sobre fechas ya pagadas (sección 16)
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id      uuid NOT NULL REFERENCES employee(id),
  earliest_date    date NOT NULL,
  source_table     text NOT NULL,
  source_id        uuid,
  operation        text NOT NULL,
  detected_at      timestamptz NOT NULL DEFAULT now(),
  detected_by      text,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processed','ignored')),
  processed_run_id uuid REFERENCES payroll_run(id),
  ignore_reason    text,
  CHECK (status <> 'ignored' OR ignore_reason IS NOT NULL)
);
CREATE INDEX ix_retro_trigger_pending ON payroll_retro_trigger(employee_id) WHERE status = 'pending';

-- -----------------------------------------------------------------------------
-- 6.7 Novedades del periodo
--     pay_period_id = periodo en que se paga (in); for_period_id = al que corresponde (for)
-- -----------------------------------------------------------------------------
CREATE TABLE payroll_input (              -- [MVP] insumos variables del periodo
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_period_id     uuid NOT NULL REFERENCES pay_period(id),
  for_period_id     uuid REFERENCES pay_period(id),
  employee_id       uuid NOT NULL REFERENCES employee(id),
  concept_id        uuid NOT NULL REFERENCES payroll_concept(id),
  quantity          numeric(12,4),
  rate              numeric(14,4),
  amount            numeric(14,2),
  effective_date    date,                  -- dentro del periodo, para ubicarla en su tramo
  source            text NOT NULL DEFAULT 'manual'
                    CHECK (source IN ('manual','attendance','leave','overtime','loan','import','expense',
                                      'commission','benefit','system')),
  source_ref        uuid,
  external_key      text,                  -- id del sistema origen (evita duplicados al reimportar)
  batch_ref         text,                  -- lote de importación
  status            text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','validated','locked','processed','cancelled')),
  processed_run_id  uuid REFERENCES payroll_run(id),
  notes             text,
  CHECK (quantity IS NOT NULL OR amount IS NOT NULL)
);
CREATE UNIQUE INDEX uq_payroll_input_external
  ON payroll_input(source, external_key) WHERE external_key IS NOT NULL;
CREATE INDEX ix_payroll_input_period_emp ON payroll_input(pay_period_id, employee_id);

-- -----------------------------------------------------------------------------
-- 6.8 Resultados (inmutables una vez aprobada la corrida)
-- -----------------------------------------------------------------------------
CREATE TABLE payroll_result (             -- [MVP] totales por empleado y corrida
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id             uuid NOT NULL REFERENCES payroll_run(id),
  employee_id        uuid NOT NULL REFERENCES employee(id),
  assignment_id      uuid REFERENCES employee_assignment(id),
  fiscal_year        int,
  gross_amount       numeric(14,2) NOT NULL DEFAULT 0,
  total_deductions   numeric(14,2) NOT NULL DEFAULT 0,
  employer_cost      numeric(14,2) NOT NULL DEFAULT 0,
  net_amount         numeric(14,2) NOT NULL DEFAULT 0,
  currency_code      char(3) NOT NULL,
  days_worked        numeric(6,2),
  employee_snapshot  jsonb,               -- nombre, documento, cargo… tal como estaban al calcular
  status             text NOT NULL DEFAULT 'calculated'
                     CHECK (status IN ('calculated','approved','paid','reversed')),
  UNIQUE (run_id, employee_id)
);

CREATE TABLE payroll_result_segment (     -- [MVP] tramos del periodo cuando algo cambia a mitad
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id        uuid NOT NULL REFERENCES payroll_result(id) ON DELETE CASCADE,
  segment_no       int  NOT NULL,
  segment_start    date NOT NULL,
  segment_end      date NOT NULL,         -- inclusivo
  day_weight       numeric(8,4) NOT NULL, -- días que pesa según la convención
  assignment_id    uuid REFERENCES employee_assignment(id),
  compensation_id  uuid REFERENCES employee_compensation(id),
  cost_center_id   uuid REFERENCES cost_center(id),
  change_reasons   text[],
  UNIQUE (result_id, segment_no),
  CHECK (segment_end >= segment_start)
);

CREATE TABLE payroll_result_line (        -- [MVP] cada línea de la boleta, con su regla y su traza
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id           uuid NOT NULL REFERENCES payroll_result(id) ON DELETE CASCADE,
  segment_id          uuid REFERENCES payroll_result_segment(id),
  concept_id          uuid NOT NULL REFERENCES payroll_concept(id),
  concept_version_id  uuid REFERENCES payroll_concept_version(id),
  concept_type        text NOT NULL,      -- copia histórica
  quantity            numeric(12,4),
  rate                numeric(14,4),
  base_amount         numeric(14,2),
  amount              numeric(14,2) NOT NULL,
  for_period_id       uuid REFERENCES pay_period(id),   -- origen del devengo (retroactivos)
  is_retro            boolean NOT NULL DEFAULT false,
  source_type         text,               -- 'input','recurring','loan','garnishment','statutory','retro','arrear'
  source_id           uuid,
  cost_center_id      uuid REFERENCES cost_center(id),
  gl_account          text,
  payslip_section     text,
  display_order       int,
  explanation         jsonb               -- base, tasa, tope, versión de regla usada
);
CREATE INDEX ix_result_line ON payroll_result_line(result_id);

ALTER TABLE loan_installment
  ADD CONSTRAINT fk_installment_line FOREIGN KEY (payroll_result_line_id) REFERENCES payroll_result_line(id);

CREATE TABLE payroll_balance_value (      -- [MVP] acumulados por corrida (for-period / in-period)
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id           uuid NOT NULL REFERENCES payroll_run(id),
  employee_id      uuid NOT NULL REFERENCES employee(id),
  legal_entity_id  uuid NOT NULL REFERENCES legal_entity(id),
  balance_id       uuid NOT NULL REFERENCES payroll_balance(id),
  for_period_id    uuid NOT NULL REFERENCES pay_period(id),
  in_period_id     uuid NOT NULL REFERENCES pay_period(id),
  fiscal_year      int NOT NULL,
  amount           numeric(16,4) NOT NULL,
  UNIQUE (run_id, employee_id, balance_id, for_period_id)
);
CREATE INDEX ix_balance_value_ytd ON payroll_balance_value(employee_id, balance_id, fiscal_year);

CREATE TABLE payroll_arrear (             -- [F2] saldos pendientes: descuentos no cubiertos, sobrepagos
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES employee(id),
  concept_id        uuid NOT NULL REFERENCES payroll_concept(id),
  arrear_type       text NOT NULL
                    CHECK (arrear_type IN ('unrecovered_deduction','overpayment','garnishment_shortfall')),
  origin_run_id     uuid NOT NULL REFERENCES payroll_run(id),
  garnishment_id    uuid REFERENCES garnishment_order(id),
  amount            numeric(14,2) NOT NULL CHECK (amount > 0),
  amount_recovered  numeric(14,2) NOT NULL DEFAULT 0 CHECK (amount_recovered >= 0),
  status            text NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open','partially_recovered','recovered','written_off')),
  notes             text,
  CHECK (amount_recovered <= amount)
);

-- -----------------------------------------------------------------------------
-- 6.9 Salidas: pagos, boletas, contabilidad, declaraciones
-- -----------------------------------------------------------------------------
CREATE TABLE payment_batch (              -- [MVP] lote/archivo para el banco
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id           uuid NOT NULL REFERENCES payroll_run(id),
  legal_entity_id  uuid NOT NULL REFERENCES legal_entity(id),
  bank_name        text,
  file_format      text,
  document_id      uuid REFERENCES document(id),
  total_amount     numeric(16,2) NOT NULL DEFAULT 0,
  payment_count    int NOT NULL DEFAULT 0,
  status           text NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','generated','sent','confirmed','partially_rejected','cancelled')),
  generated_at     timestamptz,
  sent_at          timestamptz,
  confirmed_at     timestamptz
);

CREATE TABLE payment (                    -- [MVP] cada pago del neto
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_result_id    uuid NOT NULL REFERENCES payroll_result(id),
  batch_id             uuid REFERENCES payment_batch(id),
  payment_method_id    uuid REFERENCES employee_payment_method(id),
  bank_account_id      uuid REFERENCES person_bank_account(id),
  method               text NOT NULL DEFAULT 'bank_transfer'
                       CHECK (method IN ('bank_transfer','digital_wallet','cash','check','card')),
  amount               numeric(14,2) NOT NULL,
  currency_code        char(3) NOT NULL,
  payment_date         date,
  reference            text,
  status               text NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','sent','paid','failed','returned')),
  rejection_reason     text,
  replaces_payment_id  uuid REFERENCES payment(id)
);

CREATE TABLE document_template (          -- [MVP] plantillas versionadas: boleta, certificados, contratos
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type         text NOT NULL CHECK (doc_type IN ('payslip','payslip_detail','tax_certificate',
                                                      'employment_certificate','contract','settlement','other')),
  legal_entity_id  uuid REFERENCES legal_entity(id),   -- NULL = todas
  country_code     char(2),
  locale           text NOT NULL DEFAULT 'es-PE',
  version          int NOT NULL,
  content          text NOT NULL,                      -- plantilla (HTML/Handlebars u otro motor)
  valid_from       date NOT NULL,
  valid_to         date,
  is_active        boolean NOT NULL DEFAULT true,
  UNIQUE (doc_type, legal_entity_id, locale, version)
);

CREATE TABLE payslip (                    -- [MVP] boleta publicada
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_result_id  uuid NOT NULL UNIQUE REFERENCES payroll_result(id),
  document_id        uuid REFERENCES document(id),   -- PDF generado (con sha256 en document)
  template_id        uuid REFERENCES document_template(id),
  supersedes_id      uuid REFERENCES payslip(id),     -- boleta rectificada
  verification_code  text UNIQUE,                     -- código del QR para validar autenticidad
  employer_signed_at timestamptz,                     -- firma digital o electrónica del empleador
  signature_ref      text,                            -- referencia del certificado o proveedor de firma
  delivery_channel   text CHECK (delivery_channel IN ('portal','email','print')),
  published_at       timestamptz,
  delivery_due_date  date,                            -- límite legal de entrega
  viewed_at          timestamptz,                     -- primera apertura (evidencia de acceso)
  acknowledged_at    timestamptz                      -- acuse o firma del trabajador
);

CREATE TABLE payroll_journal (            -- [F2] asiento contable (si el módulo contable no lo arma)
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               uuid NOT NULL REFERENCES payroll_run(id),
  legal_entity_id      uuid NOT NULL REFERENCES legal_entity(id),
  journal_type         text NOT NULL CHECK (journal_type IN ('accrual','payment','provision','reversal')),
  accounting_date      date NOT NULL,
  status               text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','reversed')),
  external_ref         text,               -- id del asiento en el módulo contable
  reverses_journal_id  uuid REFERENCES payroll_journal(id)
);

CREATE TABLE payroll_journal_line (       -- [F2]
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_id      uuid NOT NULL REFERENCES payroll_journal(id) ON DELETE CASCADE,
  gl_account      text NOT NULL,
  cost_center_id  uuid REFERENCES cost_center(id),
  concept_id      uuid REFERENCES payroll_concept(id),
  debit           numeric(16,2) NOT NULL DEFAULT 0 CHECK (debit  >= 0),
  credit          numeric(16,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  description     text,
  CHECK (debit = 0 OR credit = 0)
);

CREATE TABLE statutory_filing (           -- [F2] declaraciones a entes
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id  uuid NOT NULL REFERENCES legal_entity(id),
  scheme_id        uuid REFERENCES statutory_scheme(id),
  filing_type      text NOT NULL,
  fiscal_year      int NOT NULL,
  period_no        int,
  status           text NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','generated','submitted','accepted','rejected','rectified')),
  document_id      uuid REFERENCES document(id),
  submitted_at     timestamptz,
  external_ref     text,
  rectifies_id     uuid REFERENCES statutory_filing(id)
);

CREATE TABLE statutory_filing_run (       -- [F2]
  filing_id  uuid NOT NULL REFERENCES statutory_filing(id) ON DELETE CASCADE,
  run_id     uuid NOT NULL REFERENCES payroll_run(id),
  PRIMARY KEY (filing_id, run_id)
);

-- =============================================================================
-- 7. BENEFICIOS
-- =============================================================================
CREATE TABLE benefit_plan (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                  text NOT NULL UNIQUE,
  name                  text NOT NULL,
  benefit_type          text NOT NULL CHECK (benefit_type IN ('health','life_insurance','dental','pension_plan','meal','transport','education','other')),
  provider              text,
  employer_contribution numeric(14,2),
  employee_contribution numeric(14,2),
  payroll_concept_id    uuid REFERENCES payroll_concept(id),
  is_active             boolean NOT NULL DEFAULT true
);

CREATE TABLE benefit_enrollment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     uuid NOT NULL REFERENCES employee(id),
  plan_id         uuid NOT NULL REFERENCES benefit_plan(id),
  coverage_level  text,
  start_date      date NOT NULL,
  end_date        date,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('pending','active','waived','ended'))
);

CREATE TABLE benefit_enrollment_dependent (
  enrollment_id  uuid NOT NULL REFERENCES benefit_enrollment(id) ON DELETE CASCADE,
  relative_id    uuid NOT NULL REFERENCES person_relative(id),
  PRIMARY KEY (enrollment_id, relative_id)
);

-- =============================================================================
-- 8. RECLUTAMIENTO
-- =============================================================================
CREATE TABLE job_requisition (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code              text NOT NULL UNIQUE,
  position_id       uuid REFERENCES position(id),
  department_id     uuid REFERENCES department(id),
  title             text NOT NULL,
  headcount         int NOT NULL DEFAULT 1,
  requested_by      uuid REFERENCES employee(id),
  salary_min        numeric(14,2),
  salary_max        numeric(14,2),
  status            text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','pending_approval','open','on_hold','filled','cancelled')),
  opened_at         date,
  target_close_date date,
  closed_at         date
);

CREATE TABLE candidate (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id        uuid REFERENCES person(id),     -- se enlaza al contratar
  first_name       text NOT NULL,
  last_name        text NOT NULL,
  email            text,
  phone            text,
  source           text,                           -- portal, referido, LinkedIn…
  referred_by      uuid REFERENCES employee(id),
  resume_document_id uuid REFERENCES document(id),
  consent_data_processing boolean NOT NULL DEFAULT false,
  consent_at       timestamptz
);

CREATE TABLE job_application (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requisition_id   uuid NOT NULL REFERENCES job_requisition(id),
  candidate_id     uuid NOT NULL REFERENCES candidate(id),
  stage            text NOT NULL DEFAULT 'applied'
                   CHECK (stage IN ('applied','screening','interview','assessment','offer','hired','rejected','withdrawn')),
  applied_at       timestamptz NOT NULL DEFAULT now(),
  rejection_reason text,
  UNIQUE (requisition_id, candidate_id)
);

CREATE TABLE interview (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id        uuid NOT NULL REFERENCES job_application(id),
  interviewer_employee_id uuid REFERENCES employee(id),
  interview_type        text,
  scheduled_at          timestamptz NOT NULL,
  duration_minutes      int,
  score                 numeric(4,2),
  recommendation        text CHECK (recommendation IN ('strong_yes','yes','neutral','no','strong_no')),
  feedback              text
);

CREATE TABLE job_offer (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id   uuid NOT NULL REFERENCES job_application(id),
  offered_salary   numeric(14,2),
  currency_code    char(3),
  proposed_start   date,
  status           text NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','sent','accepted','declined','expired','withdrawn')),
  sent_at          timestamptz,
  responded_at     timestamptz,
  document_id      uuid REFERENCES document(id),
  employee_id      uuid REFERENCES employee(id)    -- empleado creado al aceptar
);

-- =============================================================================
-- 9. ONBOARDING / OFFBOARDING
-- =============================================================================
CREATE TABLE checklist_template (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_type text NOT NULL CHECK (checklist_type IN ('onboarding','offboarding','transfer')),
  name          text NOT NULL,
  is_active     boolean NOT NULL DEFAULT true
);

CREATE TABLE checklist_template_task (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id     uuid NOT NULL REFERENCES checklist_template(id) ON DELETE CASCADE,
  title           text NOT NULL,
  description     text,
  owner_role      text,                 -- RRHH, TI, jefe directo, empleado…
  due_offset_days int NOT NULL DEFAULT 0,
  sort_order      int NOT NULL DEFAULT 0
);

CREATE TABLE employee_checklist (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES employee(id),
  template_id   uuid REFERENCES checklist_template(id),
  checklist_type text NOT NULL,
  status        text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','completed','cancelled')),
  started_on    date NOT NULL DEFAULT current_date,
  completed_on  date
);

CREATE TABLE employee_checklist_task (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_id     uuid NOT NULL REFERENCES employee_checklist(id) ON DELETE CASCADE,
  title            text NOT NULL,
  assignee_employee_id uuid REFERENCES employee(id),
  due_date         date,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_progress','done','skipped')),
  completed_at     timestamptz,
  notes            text
);

CREATE TABLE asset_assignment (          -- Activos entregados (laptop, uniforme, llaves)
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES employee(id),
  asset_ref     text,                   -- referencia al módulo de activos fijos
  description   text NOT NULL,
  serial_no     text,
  assigned_on   date NOT NULL,
  returned_on   date,
  condition_on_return text
);

-- =============================================================================
-- 10. DESEMPEÑO Y COMPETENCIAS
-- =============================================================================
CREATE TABLE competency (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,
  name        text NOT NULL,
  description text
);

CREATE TABLE review_cycle (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  cycle_type  text NOT NULL DEFAULT 'annual' CHECK (cycle_type IN ('annual','semiannual','quarterly','probation','360')),
  start_date  date NOT NULL,
  end_date    date NOT NULL,
  status      text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','open','calibration','closed'))
);

CREATE TABLE goal (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES employee(id),
  cycle_id      uuid REFERENCES review_cycle(id),
  parent_goal_id uuid REFERENCES goal(id),
  title         text NOT NULL,
  description   text,
  weight_pct    numeric(5,2),
  target_value  numeric(14,2),
  actual_value  numeric(14,2),
  due_date      date,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','achieved','missed','cancelled'))
);

CREATE TABLE performance_review (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id          uuid NOT NULL REFERENCES review_cycle(id),
  employee_id       uuid NOT NULL REFERENCES employee(id),
  reviewer_employee_id uuid REFERENCES employee(id),
  review_kind       text NOT NULL DEFAULT 'manager' CHECK (review_kind IN ('self','manager','peer','subordinate','calibrated')),
  overall_score     numeric(4,2),
  comments          text,
  status            text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','submitted','acknowledged')),
  submitted_at      timestamptz,
  UNIQUE (cycle_id, employee_id, reviewer_employee_id, review_kind)
);

CREATE TABLE performance_review_rating (
  review_id      uuid NOT NULL REFERENCES performance_review(id) ON DELETE CASCADE,
  competency_id  uuid NOT NULL REFERENCES competency(id),
  score          numeric(4,2) NOT NULL,
  comments       text,
  PRIMARY KEY (review_id, competency_id)
);

-- =============================================================================
-- 11. CAPACITACIÓN
-- =============================================================================
CREATE TABLE course (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL UNIQUE,
  name           text NOT NULL,
  provider       text,
  delivery_mode  text CHECK (delivery_mode IN ('in_person','online','hybrid','self_paced')),
  duration_hours numeric(6,2),
  is_mandatory   boolean NOT NULL DEFAULT false,
  validity_months int,                    -- recertificación
  cost           numeric(14,2)
);

CREATE TABLE course_session (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   uuid NOT NULL REFERENCES course(id),
  start_at    timestamptz NOT NULL,
  end_at      timestamptz,
  location    text,
  instructor  text,
  capacity    int
);

CREATE TABLE training_enrollment (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id     uuid NOT NULL REFERENCES course_session(id),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  status         text NOT NULL DEFAULT 'enrolled' CHECK (status IN ('enrolled','attended','completed','failed','no_show','cancelled')),
  score          numeric(5,2),
  certificate_document_id uuid REFERENCES document(id),
  completed_on   date,
  expires_on     date,
  UNIQUE (session_id, employee_id)
);

-- =============================================================================
-- 12. DISCIPLINA, SEGURIDAD Y SALUD OCUPACIONAL, CASOS
-- =============================================================================
CREATE TABLE disciplinary_case (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  case_date      date NOT NULL,
  category_id    uuid REFERENCES lookup_value(id),
  description    text NOT NULL,
  sanction_id    uuid REFERENCES lookup_value(id),   -- amonestación, suspensión, etc.
  suspension_days int,
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','appealed','closed')),
  document_id    uuid REFERENCES document(id)
);

CREATE TABLE occupational_incident (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id      uuid NOT NULL REFERENCES employee(id),
  incident_date    timestamptz NOT NULL,
  incident_type_id uuid REFERENCES lookup_value(id),
  severity         text CHECK (severity IN ('near_miss','minor','moderate','severe','fatal')),
  location_id      uuid REFERENCES location(id),
  description      text NOT NULL,
  lost_days        int NOT NULL DEFAULT 0,
  reported_to_authority boolean NOT NULL DEFAULT false,
  reported_at      timestamptz,
  corrective_actions text
);

CREATE TABLE medical_exam (               -- Dato sensible: restringir acceso
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES employee(id),
  exam_type      text NOT NULL,           -- ingreso, periódico, retiro
  exam_date      date NOT NULL,
  fitness_result text CHECK (fitness_result IN ('fit','fit_with_restrictions','unfit','pending')),
  restrictions   text,
  next_due_date  date,
  document_id    uuid REFERENCES document(id)
);

CREATE TABLE hr_case (                    -- Quejas, consultas, denuncias, mesa de ayuda RRHH
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid REFERENCES employee(id),
  case_type      text NOT NULL CHECK (case_type IN ('inquiry','grievance','harassment','whistleblower','certificate_request','other')),
  is_anonymous   boolean NOT NULL DEFAULT false,
  subject        text NOT NULL,
  description    text,
  assigned_to    uuid REFERENCES employee(id),
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','closed')),
  opened_at      timestamptz NOT NULL DEFAULT now(),
  closed_at      timestamptz
);

-- =============================================================================
-- 13. APROBACIONES (flujo genérico reutilizable por cualquier entidad de RRHH)
-- =============================================================================
CREATE TABLE approval_request (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type   text NOT NULL,            -- 'leave_request','overtime_request','job_requisition'…
  entity_id     uuid NOT NULL,
  requester_employee_id uuid REFERENCES employee(id),
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  completed_at  timestamptz
);
CREATE INDEX ix_approval_entity ON approval_request(entity_type, entity_id);

CREATE TABLE approval_step (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_request_id  uuid NOT NULL REFERENCES approval_request(id) ON DELETE CASCADE,
  step_no              int NOT NULL,
  approver_employee_id uuid REFERENCES employee(id),
  approver_role        text,
  decision             text NOT NULL DEFAULT 'pending' CHECK (decision IN ('pending','approved','rejected','skipped')),
  decided_at           timestamptz,
  comments             text,
  UNIQUE (approval_request_id, step_no)
);

-- =============================================================================
-- 14. AUDITORÍA
-- =============================================================================
CREATE TABLE audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name  text NOT NULL,
  record_id   uuid,
  action      text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_by  text,                       -- current_setting('app.user_id', true)
  changed_at  timestamptz NOT NULL DEFAULT now(),
  old_data    jsonb,
  new_data    jsonb
);
CREATE INDEX ix_audit_table_rec ON audit_log(table_name, record_id);

CREATE OR REPLACE FUNCTION hr.fn_set_audit() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
    NEW.created_by := nullif(current_setting('app.user_id', true), '');
  END IF;
  NEW.updated_at := now();
  NEW.updated_by := nullif(current_setting('app.user_id', true), '');
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION hr.fn_audit_log() RETURNS trigger AS $$
BEGIN
  INSERT INTO hr.audit_log(table_name, record_id, action, changed_by, old_data, new_data)
  VALUES (TG_TABLE_NAME,
          COALESCE((to_jsonb(NEW)->>'id'), (to_jsonb(OLD)->>'id'))::uuid,
          TG_OP,
          nullif(current_setting('app.user_id', true), ''),
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;

-- Añade columnas de auditoría y triggers a todas las tablas con PK uuid "id".
-- Auditoría de cambios (audit_log) solo en tablas sensibles.
DO $$
DECLARE
  t record;
  sensitive text[] := ARRAY[
    'person','person_identification','person_bank_account','employee',
    'employment_contract','employee_assignment','employee_compensation',
    'termination','payroll_run','payroll_result','payroll_result_line',
    'payment','loan','disciplinary_case','medical_exam','hr_case',
    'employee_recurring_concept','leave_ledger',
    'legal_pack','statutory_rate','payroll_concept','payroll_concept_version',
    'payroll_balance_feed','payroll_setting','pay_calendar','employee_statutory_enrollment',
    'employee_tax_profile','employee_payment_method','garnishment_order','payroll_arrear',
    'payment_batch','payroll_journal','statutory_filing','payroll_retro_trigger',
    'statutory_provider','legal_parameter','document_template','payslip'
  ];
BEGIN
  FOR t IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables tb
      ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name
    WHERE c.table_schema = 'hr' AND c.column_name = 'id'
      AND tb.table_type = 'BASE TABLE' AND c.table_name <> 'audit_log'
  LOOP
    EXECUTE format('ALTER TABLE hr.%I
      ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS created_by text,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_by text,
      ADD COLUMN IF NOT EXISTS deleted_at timestamptz', t.table_name);

    EXECUTE format('CREATE TRIGGER trg_%1$s_audit_cols BEFORE INSERT OR UPDATE ON hr.%1$I
      FOR EACH ROW EXECUTE FUNCTION hr.fn_set_audit()', t.table_name);

    IF t.table_name = ANY (sensitive) THEN
      EXECUTE format('CREATE TRIGGER trg_%1$s_audit_log AFTER INSERT OR UPDATE OR DELETE ON hr.%1$I
        FOR EACH ROW EXECUTE FUNCTION hr.fn_audit_log()', t.table_name);
    END IF;
  END LOOP;
END $$;

-- =============================================================================
-- 16. LÓGICA DE PERIODOS
--   Variables de sesión (SET LOCAL en cada transacción de la app):
--     app.user_id            usuario (auditoría e historial)
--     app.reason             motivo, obligatorio en transiciones hacia atrás
--     app.allow_late_input   'on' permite novedades con el periodo en inputs_closed
--     app.retro_detection    'off' desactiva la detección de retroactivos (migraciones)
-- =============================================================================
-- =============================================================================
-- 16.1 MÁQUINA DE ESTADOS DEL PERIODO [MVP]
--
--   future ──► open ──► inputs_closed ──► processing ──► closed
--                ▲            │  ▲             │
--                └──(motivo)──┘  └──(motivo)───┘
--
--   Precondiciones:
--   · processing → inputs_closed: ninguna corrida real activa (solo descartadas o fallidas)
--   · corrida regular: el periodo regular anterior debe estar cerrado (proceso secuencial)
--   · → closed: corridas reales todas terminadas, al menos una pagada o contabilizada,
--               ventanas cerradas y los periodos regulares anteriores ya cerrados
--   · closed es final: las correcciones se hacen con retroactivos en un periodo abierto
-- =============================================================================
CREATE OR REPLACE FUNCTION hr.fn_pay_period_guard() RETURNS trigger AS $$
DECLARE
  v_reason  text := nullif(current_setting('app.reason', true), '');
  v_user    text := nullif(current_setting('app.user_id', true), '');
  v_allowed boolean;
  v_back    boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    RETURN NEW;   -- el alta se registra en trg_pay_period_log_insert (AFTER)
  END IF;

  -- Cambios de fechas: solo antes de abrir
  IF (NEW.period_start, NEW.period_end, NEW.pay_group_id) IS DISTINCT FROM
     (OLD.period_start, OLD.period_end, OLD.pay_group_id)
     AND OLD.status <> 'future' THEN
    RAISE EXCEPTION 'PERIOD_DATES_LOCKED: las fechas de un periodo solo cambian en estado future';
  END IF;

  IF NEW.status = OLD.status THEN
    IF OLD.status = 'closed' AND (NEW.pay_date, NEW.accounting_date, NEW.cutoff_at)
       IS DISTINCT FROM (OLD.pay_date, OLD.accounting_date, OLD.cutoff_at) THEN
      RAISE EXCEPTION 'PERIOD_CLOSED: un periodo cerrado es inmutable';
    END IF;
    RETURN NEW;
  END IF;

  v_allowed := (OLD.status, NEW.status) IN (
    ('future','open'), ('open','inputs_closed'), ('inputs_closed','open'),
    ('inputs_closed','processing'), ('processing','inputs_closed'), ('processing','closed'));
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'PERIOD_INVALID_TRANSITION: % → % no está permitido', OLD.status, NEW.status;
  END IF;

  v_back := (OLD.status, NEW.status) IN (('inputs_closed','open'), ('processing','inputs_closed'));
  IF v_back AND v_reason IS NULL THEN
    RAISE EXCEPTION 'PERIOD_REASON_REQUIRED: la transición % → % exige motivo (app.reason)',
      OLD.status, NEW.status;
  END IF;

  IF (OLD.status, NEW.status) = ('processing','inputs_closed') AND EXISTS (
       SELECT 1 FROM hr.payroll_run r
       WHERE r.pay_period_id = NEW.id AND r.is_simulation = false
         AND r.status NOT IN ('discarded','failed')) THEN
    RAISE EXCEPTION 'PERIOD_HAS_RUNS: descarta las corridas del periodo antes de reabrir novedades';
  END IF;

  IF NEW.status = 'closed' THEN
    IF EXISTS (SELECT 1 FROM hr.payroll_run r
               WHERE r.pay_period_id = NEW.id AND r.is_simulation = false
                 AND r.status IN ('draft','calculating','calculated','approved')) THEN
      RAISE EXCEPTION 'PERIOD_RUNS_PENDING: hay corridas sin pagar en el periodo';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hr.payroll_run r
                   WHERE r.pay_period_id = NEW.id AND r.is_simulation = false
                     AND r.status IN ('paid','posted')) THEN
      RAISE EXCEPTION 'PERIOD_NO_PAID_RUN: no hay ninguna corrida pagada en el periodo';
    END IF;
    IF EXISTS (SELECT 1 FROM hr.pay_period_window w
               WHERE w.pay_period_id = NEW.id AND w.status = 'open') THEN
      RAISE EXCEPTION 'PERIOD_WINDOWS_OPEN: cierra las ventanas de insumos primero';
    END IF;
    IF NEW.period_type = 'regular' AND EXISTS (
         SELECT 1 FROM hr.pay_period p
         WHERE p.pay_group_id = NEW.pay_group_id AND p.period_type = 'regular'
           AND p.period_end < NEW.period_start AND p.status <> 'closed') THEN
      RAISE EXCEPTION 'PERIOD_PREVIOUS_OPEN: hay periodos regulares anteriores sin cerrar';
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := v_user;
  END IF;

  IF NEW.status = 'open' AND OLD.status = 'future' THEN NEW.opened_at := now(); END IF;
  IF NEW.status = 'inputs_closed' AND OLD.status = 'open' THEN NEW.inputs_closed_at := now(); END IF;

  INSERT INTO hr.pay_period_status_log(pay_period_id, from_status, to_status, changed_by, reason)
  VALUES (NEW.id, OLD.status, NEW.status, v_user, v_reason);
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pay_period_guard
  BEFORE INSERT OR UPDATE ON pay_period
  FOR EACH ROW EXECUTE FUNCTION hr.fn_pay_period_guard();

CREATE OR REPLACE FUNCTION hr.fn_pay_period_log_insert() RETURNS trigger AS $$
BEGIN
  INSERT INTO hr.pay_period_status_log(pay_period_id, from_status, to_status, changed_by, reason)
  VALUES (NEW.id, NULL, NEW.status, nullif(current_setting('app.user_id', true), ''),
          nullif(current_setting('app.reason', true), ''));
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pay_period_log_insert
  AFTER INSERT ON pay_period
  FOR EACH ROW EXECUTE FUNCTION hr.fn_pay_period_log_insert();

-- Al cerrar novedades se bloquean las novedades validadas
CREATE OR REPLACE FUNCTION hr.fn_pay_period_lock_inputs() RETURNS trigger AS $$
BEGIN
  IF OLD.status = 'open' AND NEW.status = 'inputs_closed' THEN
    UPDATE hr.payroll_input SET status = 'locked'
    WHERE pay_period_id = NEW.id AND status = 'validated';
  ELSIF OLD.status = 'inputs_closed' AND NEW.status = 'open' THEN
    UPDATE hr.payroll_input SET status = 'validated'
    WHERE pay_period_id = NEW.id AND status = 'locked';
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pay_period_lock_inputs
  AFTER UPDATE OF status ON pay_period
  FOR EACH ROW EXECUTE FUNCTION hr.fn_pay_period_lock_inputs();

-- =============================================================================
-- 16.2 BLOQUEOS SEGÚN EL ESTADO DEL PERIODO [MVP]
-- =============================================================================

-- 16.2.1 Novedades: solo en future/open; en inputs_closed con permiso; nunca después
CREATE OR REPLACE FUNCTION hr.fn_payroll_input_guard() RETURNS trigger AS $$
DECLARE
  v_status text;
  v_late   boolean := coalesce(current_setting('app.allow_late_input', true), '') = 'on';
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.status = 'processed' THEN
    RAISE EXCEPTION 'INPUT_PROCESSED: una novedad procesada no se modifica; registra un ajuste';
  END IF;

  SELECT status INTO v_status FROM hr.pay_period
  WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.pay_period_id ELSE NEW.pay_period_id END;

  -- Cambios de estado hechos por el propio flujo de cierre o de cálculo
  IF TG_OP = 'UPDATE'
     AND (to_jsonb(NEW) - 'status' - 'processed_run_id' - 'updated_at' - 'updated_by')
       = (to_jsonb(OLD) - 'status' - 'processed_run_id' - 'updated_at' - 'updated_by') THEN
    RETURN NEW;
  END IF;

  IF v_status IN ('future','open') THEN
    NULL;
  ELSIF v_status = 'inputs_closed' AND v_late THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'INPUT_PERIOD_LOCKED: el periodo está en %; carga la novedad en el periodo abierto con for_period_id', v_status;
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payroll_input_guard
  BEFORE INSERT OR UPDATE OR DELETE ON payroll_input
  FOR EACH ROW EXECUTE FUNCTION hr.fn_payroll_input_guard();

-- 16.2.2 Corridas: un periodo regular solo se procesa después del corte
CREATE OR REPLACE FUNCTION hr.fn_payroll_run_period_guard() RETURNS trigger AS $$
DECLARE
  v_status text; v_type text;
BEGIN
  IF NEW.is_simulation THEN RETURN NEW; END IF;
  SELECT status, period_type INTO v_status, v_type FROM hr.pay_period WHERE id = NEW.pay_period_id;

  IF v_status = 'closed' THEN
    RAISE EXCEPTION 'RUN_PERIOD_CLOSED: el periodo está cerrado; usa un retroactivo en el periodo abierto';
  END IF;
  IF v_type = 'regular' AND v_status NOT IN ('inputs_closed','processing') THEN
    RAISE EXCEPTION 'RUN_INPUTS_OPEN: cierra las novedades del periodo antes de crear una corrida (estado %)', v_status;
  END IF;
  -- Los periodos regulares se procesan en orden: el anterior debe estar cerrado
  IF v_type = 'regular' AND NEW.run_type = 'regular' AND EXISTS (
       SELECT 1 FROM hr.pay_period cur
       JOIN hr.pay_period prev ON prev.pay_group_id = cur.pay_group_id
                              AND prev.period_type = 'regular'
                              AND prev.period_end < cur.period_start
       WHERE cur.id = NEW.pay_period_id AND prev.status <> 'closed') THEN
    RAISE EXCEPTION 'RUN_PREVIOUS_PERIOD_OPEN: cierra el periodo regular anterior antes de procesar este';
  END IF;
  IF v_type <> 'regular' AND v_status = 'future' THEN
    RAISE EXCEPTION 'RUN_PERIOD_FUTURE: abre el periodo fuera de ciclo antes de crear la corrida';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payroll_run_period_guard
  BEFORE INSERT ON payroll_run
  FOR EACH ROW EXECUTE FUNCTION hr.fn_payroll_run_period_guard();

-- 16.2.3 Crear la primera corrida mueve el periodo a processing
CREATE OR REPLACE FUNCTION hr.fn_payroll_run_advance_period() RETURNS trigger AS $$
DECLARE v_status text;
BEGIN
  IF NEW.is_simulation THEN RETURN NULL; END IF;
  SELECT status INTO v_status FROM hr.pay_period WHERE id = NEW.pay_period_id;
  IF v_status = 'open' THEN
    UPDATE hr.pay_period SET status = 'inputs_closed' WHERE id = NEW.pay_period_id;
    v_status := 'inputs_closed';
  END IF;
  IF v_status = 'inputs_closed' THEN
    UPDATE hr.pay_period SET status = 'processing' WHERE id = NEW.pay_period_id;
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payroll_run_advance_period
  AFTER INSERT ON payroll_run
  FOR EACH ROW EXECUTE FUNCTION hr.fn_payroll_run_advance_period();

-- =============================================================================
-- 16.3 DETECCIÓN DE RETROACTIVOS [F2]
--    Si un dato con vigencia cambia en una fecha ya liquidada (resultado aprobado,
--    pagado o contabilizado), se registra la fecha más antigua afectada.
-- =============================================================================
-- TG_ARGV[0] = columna de inicio (valid_from, start_date); TG_ARGV[1] = columna de fin o ''
CREATE OR REPLACE FUNCTION hr.fn_detect_retro() RETURNS trigger AS $$
DECLARE
  c_from text := TG_ARGV[0];
  c_to   text := nullif(TG_ARGV[1], '');
  n jsonb; o jsonb; v_emp uuid; v_date date; v_ignore text[];
  d1 date; d2 date;
BEGIN
  IF coalesce(current_setting('app.retro_detection', true), '') = 'off' THEN
    RETURN NULL;
  END IF;

  IF TG_OP <> 'DELETE' THEN n := to_jsonb(NEW); END IF;
  IF TG_OP <> 'INSERT' THEN o := to_jsonb(OLD); END IF;
  v_emp := coalesce(n->>'employee_id', o->>'employee_id')::uuid;
  v_ignore := ARRAY['created_at','created_by','updated_at','updated_by'];

  IF TG_OP = 'INSERT' THEN
    v_date := (n->>c_from)::date;
  ELSIF TG_OP = 'DELETE' THEN
    v_date := (o->>c_from)::date;
  ELSIF c_to IS NOT NULL AND (n - v_ignore - c_to) = (o - v_ignore - c_to) THEN
    -- Solo cambió el fin de vigencia (p.ej. se cerró la fila para insertar otra)
    d1 := (o->>c_to)::date; d2 := (n->>c_to)::date;
    IF d1 IS NULL AND d2 IS NULL THEN RETURN NULL; END IF;
    v_date := least(coalesce(d1, d2), coalesce(d2, d1));
  ELSIF (n - v_ignore) = (o - v_ignore) THEN
    RETURN NULL;
  ELSE
    v_date := least((n->>c_from)::date, (o->>c_from)::date);
  END IF;

  IF v_emp IS NULL OR v_date IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (
    SELECT 1
    FROM hr.payroll_result res
    JOIN hr.payroll_run r  ON r.id = res.run_id
    JOIN hr.pay_period pp  ON pp.id = r.pay_period_id
    WHERE res.employee_id = v_emp
      AND r.is_simulation = false
      AND r.status IN ('approved','paid','posted')
      AND pp.period_end >= v_date) THEN
    INSERT INTO hr.payroll_retro_trigger(employee_id, earliest_date, source_table, source_id,
                                         operation, detected_by)
    VALUES (v_emp, v_date, TG_TABLE_NAME, coalesce(n->>'id', o->>'id')::uuid, TG_OP,
            nullif(current_setting('app.user_id', true), ''));
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_retro_compensation AFTER INSERT OR UPDATE OR DELETE ON employee_compensation
  FOR EACH ROW EXECUTE FUNCTION hr.fn_detect_retro('valid_from','valid_to');
CREATE TRIGGER trg_retro_assignment AFTER INSERT OR UPDATE OR DELETE ON employee_assignment
  FOR EACH ROW EXECUTE FUNCTION hr.fn_detect_retro('valid_from','valid_to');
CREATE TRIGGER trg_retro_recurring AFTER INSERT OR UPDATE OR DELETE ON employee_recurring_concept
  FOR EACH ROW EXECUTE FUNCTION hr.fn_detect_retro('valid_from','valid_to');
CREATE TRIGGER trg_retro_enrollment AFTER INSERT OR UPDATE OR DELETE ON employee_statutory_enrollment
  FOR EACH ROW EXECUTE FUNCTION hr.fn_detect_retro('valid_from','valid_to');
CREATE TRIGGER trg_retro_tax_profile AFTER INSERT OR UPDATE OR DELETE ON employee_tax_profile
  FOR EACH ROW EXECUTE FUNCTION hr.fn_detect_retro('valid_from','valid_to');
CREATE TRIGGER trg_retro_pay_group AFTER INSERT OR UPDATE OR DELETE ON employee_pay_group
  FOR EACH ROW EXECUTE FUNCTION hr.fn_detect_retro('valid_from','valid_to');
CREATE TRIGGER trg_retro_leave AFTER INSERT OR UPDATE ON leave_request
  FOR EACH ROW WHEN (NEW.status IN ('approved','taken','cancelled'))
  EXECUTE FUNCTION hr.fn_detect_retro('start_date','');
CREATE TRIGGER trg_retro_attendance AFTER INSERT OR UPDATE ON attendance_daily
  FOR EACH ROW WHEN (NEW.approved_at IS NOT NULL)
  EXECUTE FUNCTION hr.fn_detect_retro('work_date','');
CREATE TRIGGER trg_retro_overtime AFTER INSERT OR UPDATE ON overtime_request
  FOR EACH ROW WHEN (NEW.status IN ('approved','cancelled'))
  EXECUTE FUNCTION hr.fn_detect_retro('work_date','');

CREATE OR REPLACE VIEW v_retro_pending AS
SELECT employee_id, min(earliest_date) AS retro_from, count(*) AS triggers
FROM payroll_retro_trigger
WHERE status = 'pending'
GROUP BY employee_id;

-- =============================================================================
-- 16.4 FUNCIONES DE CALENDARIO [MVP]
-- =============================================================================
-- 9.1 Mover una fecha a día hábil
CREATE OR REPLACE FUNCTION hr.fn_business_day(p_date date, p_calendar uuid,
                                              p_mode text, p_weekend int[])
RETURNS date AS $$
DECLARE d date := p_date; i int := 0;
BEGIN
  IF p_mode = 'none' THEN RETURN d; END IF;
  WHILE (extract(isodow FROM d)::int = ANY(p_weekend)
         OR EXISTS (SELECT 1 FROM hr.holiday h
                    WHERE h.calendar_id = p_calendar AND h.holiday_date = d)) LOOP
    d := d + CASE p_mode WHEN 'previous' THEN -1 ELSE 1 END;
    i := i + 1;
    IF i > 31 THEN RAISE EXCEPTION 'No se encontró día hábil cerca de %', p_date; END IF;
  END LOOP;
  RETURN d;
END $$ LANGUAGE plpgsql STABLE;

-- 9.2 Restar N días hábiles (el corte se mide en días hábiles antes del pago)
CREATE OR REPLACE FUNCTION hr.fn_business_days_before(p_date date, p_days int, p_calendar uuid,
                                                      p_weekend int[])
RETURNS date AS $$
DECLARE d date := p_date; k int := 0;
BEGIN
  WHILE k < p_days LOOP
    d := d - 1;
    IF NOT (extract(isodow FROM d)::int = ANY(p_weekend)
            OR EXISTS (SELECT 1 FROM hr.holiday h
                       WHERE h.calendar_id = p_calendar AND h.holiday_date = d)) THEN
      k := k + 1;
    END IF;
  END LOOP;
  RETURN d;
END $$ LANGUAGE plpgsql STABLE;

-- 9.3 Generar los periodos regulares de un año fiscal (idempotente)
--     p_from permite empezar a mitad de año (puesta en marcha)
CREATE OR REPLACE FUNCTION hr.fn_generate_pay_periods(p_pay_group uuid, p_fiscal_year int,
                                                      p_from date DEFAULT NULL)
RETURNS int AS $$
DECLARE
  c        hr.pay_calendar%ROWTYPE;
  fy_start date; fy_end date;
  s date; e date; pd date; n int := 0; seq int := 0;
  per      record;
  v_id     uuid;
  w        hr.pay_calendar_window_rule%ROWTYPE;
  ws date; we date; step int;
BEGIN
  SELECT cal.* INTO c FROM hr.pay_calendar cal
  JOIN hr.pay_group g ON g.pay_calendar_id = cal.id
  WHERE g.id = p_pay_group;
  IF NOT FOUND THEN RAISE EXCEPTION 'El grupo de pago no tiene calendario'; END IF;

  fy_start := make_date(p_fiscal_year, c.fiscal_year_start_month, 1);
  IF c.fiscal_year_start_month > 1 THEN fy_start := fy_start - interval '1 year'; END IF;
  fy_end   := (fy_start + interval '1 year')::date - 1;

  IF to_regclass('pg_temp._cand') IS NULL THEN
    CREATE TEMP TABLE _cand(ps date, pe date) ON COMMIT DROP;
  ELSE
    TRUNCATE _cand;
  END IF;

  IF c.frequency = 'monthly' THEN
    FOR i IN 0..11 LOOP
      s := (fy_start + make_interval(months => i))::date;     -- primer día del mes en que termina
      IF c.monthly_start_day = 1 THEN
        INSERT INTO _cand VALUES (s, (s + interval '1 month')::date - 1);
      ELSE
        INSERT INTO _cand VALUES ((s - interval '1 month')::date + c.monthly_start_day - 1,
                                  s + c.monthly_start_day - 2);
      END IF;
    END LOOP;
  ELSIF c.frequency = 'semimonthly' THEN
    FOR i IN 0..11 LOOP
      s := (fy_start + make_interval(months => i))::date;
      INSERT INTO _cand VALUES (s, s + c.semimonthly_split_day - 1);
      INSERT INTO _cand VALUES (s + c.semimonthly_split_day, (s + interval '1 month')::date - 1);
    END LOOP;
  ELSE
    step := CASE c.frequency WHEN 'weekly' THEN 7 ELSE 14 END;
    s := c.anchor_date;
    WHILE s > fy_start - 40 LOOP s := s - step; END LOOP;
    WHILE s <= fy_end + 40 LOOP
      INSERT INTO _cand VALUES (s, s + step - 1);
      s := s + step;
    END LOOP;
  END IF;

  FOR per IN SELECT ps, pe FROM _cand ORDER BY ps LOOP
    IF c.pay_date_rule = 'fixed_day' THEN
      pd := make_date(extract(year FROM per.pe)::int, extract(month FROM per.pe)::int,
                      least(c.pay_day, extract(day FROM per.pe)::int));
    ELSE
      pd := per.pe + c.pay_offset_days;
    END IF;
    pd := hr.fn_business_day(pd, c.holiday_calendar_id, c.business_day_adjust, c.weekend_days);

    -- ¿pertenece al año fiscal?
    IF c.frequency IN ('weekly','biweekly') THEN
      CONTINUE WHEN (CASE c.fiscal_year_basis WHEN 'pay_date' THEN pd ELSE per.pe END)
                    NOT BETWEEN fy_start AND fy_end;
    END IF;
    seq := seq + 1;
    CONTINUE WHEN p_from IS NOT NULL AND per.ps < p_from;
    CONTINUE WHEN EXISTS (SELECT 1 FROM hr.pay_period p
                          WHERE p.pay_group_id = p_pay_group AND p.period_type = 'regular'
                            AND p.period_start = per.ps);

    INSERT INTO hr.pay_period(pay_group_id, pay_calendar_id, period_start, period_end, pay_date,
                              status, period_type, fiscal_year, period_no, cutoff_at, accounting_date)
    VALUES (p_pay_group, c.id, per.ps, per.pe, pd, 'future', 'regular', p_fiscal_year, seq,
            (hr.fn_business_days_before(pd, c.cutoff_days_before_pay, c.holiday_calendar_id, c.weekend_days)
               + c.cutoff_time) AT TIME ZONE c.timezone, per.pe)
    RETURNING id INTO v_id;
    n := n + 1;

    FOR w IN SELECT * FROM hr.pay_calendar_window_rule WHERE calendar_id = c.id LOOP
      IF w.mode = 'same_as_period' THEN
        ws := per.ps; we := per.pe;
      ELSIF w.mode = 'shift_days' THEN
        ws := per.ps + w.shift_days; we := per.pe + w.shift_days;
      ELSE  -- month_end_day: p.ej. 20 → del 21 del mes anterior al 20 del mes del periodo
        we := make_date(extract(year FROM per.pe)::int, extract(month FROM per.pe)::int, w.end_day);
        ws := (we - interval '1 month')::date + 1;
      END IF;
      INSERT INTO hr.pay_period_window(pay_period_id, window_type, window_start, window_end, cutoff_at)
      VALUES (v_id, w.window_type, ws, we,
              (hr.fn_business_days_before(pd, coalesce(w.cutoff_days_before_pay, c.cutoff_days_before_pay),
                                          c.holiday_calendar_id, c.weekend_days)
                 + c.cutoff_time) AT TIME ZONE c.timezone);
    END LOOP;
  END LOOP;
  RETURN n;
END $$ LANGUAGE plpgsql;

-- 9.4 Cambiar el estado de un periodo con motivo (envoltorio para la app)
CREATE OR REPLACE FUNCTION hr.fn_set_period_status(p_period uuid, p_status text,
                                                   p_reason text DEFAULT NULL)
RETURNS void AS $$
BEGIN
  PERFORM set_config('app.reason', coalesce(p_reason, ''), true);
  UPDATE hr.pay_period SET status = p_status WHERE id = p_period;
  IF NOT FOUND THEN RAISE EXCEPTION 'Periodo % no existe', p_period; END IF;
  PERFORM set_config('app.reason', '', true);
END $$ LANGUAGE plpgsql;

-- 9.5 ¿En qué periodo regular cae una fecha para un empleado?
CREATE OR REPLACE FUNCTION hr.fn_employee_period(p_employee uuid, p_date date)
RETURNS uuid AS $$
  SELECT p.id
  FROM hr.employee_pay_group epg
  JOIN hr.pay_period p ON p.pay_group_id = epg.pay_group_id
  WHERE epg.employee_id = p_employee
    AND epg.valid_from <= p_date AND (epg.valid_to IS NULL OR epg.valid_to > p_date)
    AND p.period_type = 'regular'
    AND p_date BETWEEN p.period_start AND p.period_end
  LIMIT 1;
$$ LANGUAGE sql STABLE;

-- 9.6 Periodo abierto actual de un grupo (donde caen las novedades de hoy)
CREATE OR REPLACE FUNCTION hr.fn_current_open_period(p_pay_group uuid)
RETURNS uuid AS $$
  SELECT id FROM hr.pay_period
  WHERE pay_group_id = p_pay_group AND period_type = 'regular' AND status IN ('open','future')
  ORDER BY period_start LIMIT 1;
$$ LANGUAGE sql STABLE;


-- =============================================================================
-- 15. VISTAS ÚTILES
-- =============================================================================
CREATE OR REPLACE VIEW v_employee_current AS
SELECT e.id AS employee_id, e.employee_number, e.status, e.hire_date,
       p.first_name, p.last_name, a.department_id, a.position_id, a.job_id,
       a.location_id, a.manager_employee_id, c.amount AS base_salary, c.currency_code
FROM employee e
JOIN person p ON p.id = e.person_id
LEFT JOIN employee_assignment a
  ON a.employee_id = e.id AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to > current_date)
LEFT JOIN employee_compensation c
  ON c.employee_id = e.id AND c.valid_from <= current_date AND (c.valid_to IS NULL OR c.valid_to > current_date)
WHERE e.deleted_at IS NULL;

CREATE OR REPLACE VIEW v_leave_balance AS
SELECT employee_id, leave_type_id, SUM(quantity) AS balance
FROM leave_ledger
WHERE deleted_at IS NULL
GROUP BY employee_id, leave_type_id;

-- Nómina
-- Tablero de periodos: estado, ventanas, corridas y pendientes
CREATE OR REPLACE VIEW v_pay_period_dashboard AS
SELECT p.id, g.code AS pay_group, p.period_type, p.fiscal_year, p.period_no,
       p.period_start, p.period_end, p.pay_date, p.cutoff_at, p.status,
       (SELECT count(*) FROM hr.pay_period_window w
         WHERE w.pay_period_id = p.id AND w.status = 'open')            AS open_windows,
       (SELECT count(*) FROM hr.payroll_input i
         WHERE i.pay_period_id = p.id AND i.status IN ('draft','validated')) AS pending_inputs,
       (SELECT string_agg(r.run_type || ':' || r.status, ', ' ORDER BY r.created_at)
          FROM hr.payroll_run r
         WHERE r.pay_period_id = p.id AND r.is_simulation = false)      AS runs
FROM hr.pay_period p
JOIN hr.pay_group g ON g.id = p.pay_group_id;

-- Acumulado anual por balance (excluye simulaciones y corridas revertidas o descartadas)
CREATE OR REPLACE VIEW v_payroll_balance_ytd AS
SELECT bv.employee_id, bv.legal_entity_id, b.code AS balance_code, bv.fiscal_year,
       SUM(bv.amount) AS ytd_amount
FROM payroll_balance_value bv
JOIN payroll_balance b ON b.id = bv.balance_id
JOIN payroll_run r     ON r.id = bv.run_id
WHERE r.is_simulation = false
  AND r.status IN ('approved','paid','posted')
  AND bv.deleted_at IS NULL
GROUP BY bv.employee_id, bv.legal_entity_id, b.code, bv.fiscal_year;

-- [F2] Estado de cada embargo: cuánto se lleva descontado y cuánto falta
CREATE OR REPLACE VIEW v_garnishment_status AS
SELECT g.id AS garnishment_id, g.employee_id, g.order_type, g.priority, g.total_debt,
       COALESCE(SUM(l.amount) FILTER (WHERE r.id IS NOT NULL), 0) AS paid_to_date,
       CASE WHEN g.total_debt IS NULL THEN NULL
            ELSE g.total_debt - COALESCE(SUM(l.amount) FILTER (WHERE r.id IS NOT NULL), 0) END AS remaining
FROM garnishment_order g
LEFT JOIN payroll_result_line l
       ON l.source_type = 'garnishment' AND l.source_id = g.id
LEFT JOIN payroll_result res ON res.id = l.result_id
LEFT JOIN payroll_run r ON r.id = res.run_id
      AND r.status IN ('approved','paid','posted') AND r.is_simulation = false
WHERE g.deleted_at IS NULL
GROUP BY g.id;

-- [F2] Contabilidad cuadrada por asiento
CREATE OR REPLACE VIEW v_payroll_journal_check AS
SELECT j.id AS journal_id, j.run_id, SUM(l.debit) AS total_debit, SUM(l.credit) AS total_credit,
       SUM(l.debit) - SUM(l.credit) AS difference
FROM payroll_journal j
JOIN payroll_journal_line l ON l.journal_id = j.id
GROUP BY j.id, j.run_id;
