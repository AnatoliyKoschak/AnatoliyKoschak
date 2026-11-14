-- Создание схемы, если она еще не существует
CREATE SCHEMA IF NOT EXISTS cdm;

-- Создание таблицы витрины dm_settlement_report 
DROP TABLE IF EXISTS cdm.dm_settlement_report;

CREATE TABLE cdm.dm_settlement_report (
    id                         SERIAL NOT NULL,
    restaurant_id              VARCHAR NOT NULL,
    restaurant_name            VARCHAR NOT NULL,
    settlement_date            DATE NOT NULL,
    orders_count               INTEGER NOT NULL,
    orders_total_sum           NUMERIC(14, 2) NOT NULL,
    orders_bonus_payment_sum   NUMERIC(14, 2) NOT NULL,
    orders_bonus_granted_sum   NUMERIC(14, 2) NOT NULL,
    order_processing_fee       NUMERIC(14, 2) NOT NULL,
    restaurant_reward_sum      NUMERIC(14, 2) NOT NULL
);

-- Комментарии к полям остаются для документирования структуры
COMMENT ON TABLE cdm.dm_settlement_report IS 'Отчетная витрина для расчетов с ресторанами';
COMMENT ON COLUMN cdm.dm_settlement_report.id IS 'Идентификатор записи';
COMMENT ON COLUMN cdm.dm_settlement_report.restaurant_id IS 'Идентификатор ресторана (из системы-источника)';
COMMENT ON COLUMN cdm.dm_settlement_report.restaurant_name IS 'Название ресторана';
COMMENT ON COLUMN cdm.dm_settlement_report.settlement_date IS 'Дата отчёта';
COMMENT ON COLUMN cdm.dm_settlement_report.orders_count IS 'Количество заказов';
COMMENT ON COLUMN cdm.dm_settlement_report.orders_total_sum IS 'Общая сумма заказов клиентов';
COMMENT ON COLUMN cdm.dm_settlement_report.orders_bonus_payment_sum IS 'Сумма оплат бонусами';
COMMENT ON COLUMN cdm.dm_settlement_report.orders_bonus_granted_sum IS 'Сумма накопленных бонусов';
COMMENT ON COLUMN cdm.dm_settlement_report.order_processing_fee IS 'Сумма, удержанная компанией за обработку заказов';
COMMENT ON COLUMN cdm.dm_settlement_report.restaurant_reward_sum IS 'Сумма, которую необходимо перечислить ресторану';


-- 1. Добавление первичного ключа
ALTER TABLE cdm.dm_settlement_report 
    ADD CONSTRAINT dm_settlement_report_pkey PRIMARY KEY (id);

-- 2. Добавление ограничения на диапазон дат
ALTER TABLE cdm.dm_settlement_report
    ADD CONSTRAINT dm_settlement_report_settlement_date_check 
    CHECK (EXTRACT(YEAR FROM settlement_date) >= 2022 AND EXTRACT(YEAR FROM settlement_date) < 2500);

-- 3. Настройка значений по умолчанию (DEFAULT 0) для агрегатов
ALTER TABLE cdm.dm_settlement_report ALTER COLUMN orders_count SET DEFAULT 0;
ALTER TABLE cdm.dm_settlement_report ALTER COLUMN orders_total_sum SET DEFAULT 0;
ALTER TABLE cdm.dm_settlement_report ALTER COLUMN orders_bonus_payment_sum SET DEFAULT 0;
ALTER TABLE cdm.dm_settlement_report ALTER COLUMN orders_bonus_granted_sum SET DEFAULT 0;
ALTER TABLE cdm.dm_settlement_report ALTER COLUMN order_processing_fee SET DEFAULT 0;
ALTER TABLE cdm.dm_settlement_report ALTER COLUMN restaurant_reward_sum SET DEFAULT 0;

-- 4. Добавление проверок на неотрицательность (>= 0) для агрегатов
ALTER TABLE cdm.dm_settlement_report ADD CONSTRAINT dm_settlement_report_orders_count_check CHECK (orders_count >= 0);
ALTER TABLE cdm.dm_settlement_report ADD CONSTRAINT dm_settlement_report_orders_total_sum_check CHECK (orders_total_sum >= 0);
ALTER TABLE cdm.dm_settlement_report ADD CONSTRAINT dm_settlement_report_orders_bonus_payment_sum_check CHECK (orders_bonus_payment_sum >= 0);
ALTER TABLE cdm.dm_settlement_report ADD CONSTRAINT dm_settlement_report_orders_bonus_granted_sum_check CHECK (orders_bonus_granted_sum >= 0);
ALTER TABLE cdm.dm_settlement_report ADD CONSTRAINT dm_settlement_report_order_processing_fee_check CHECK (order_processing_fee >= 0);
ALTER TABLE cdm.dm_settlement_report ADD CONSTRAINT dm_settlement_report_restaurant_reward_sum_check CHECK (restaurant_reward_sum >= 0);

-- 5. Добавление ограничения уникальности для пары ресторан + период
ALTER TABLE cdm.dm_settlement_report
    ADD CONSTRAINT dm_settlement_report_restaurant_date_unique UNIQUE (restaurant_id, settlement_date);

DROP TABLE IF EXISTS cdm.srv_wf_settings;

CREATE TABLE IF NOT EXISTS cdm.srv_wf_settings (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    workflow_key varchar NOT NULL UNIQUE,
    workflow_settings JSON NOT NULL
);

DROP TABLE IF EXISTS cdm.dm_courier_ledger;

CREATE TABLE IF NOT EXISTS cdm.dm_courier_ledger (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    courier_id varchar NOT NULL,
    courier_name varchar NOT NULL,
    settlement_year int NOT NULL,
    settlement_month int NOT NULL,
    orders_count int NOT NULL DEFAULT 0,
    orders_total_sum numeric(14, 2) NOT NULL DEFAULT 0,
    rate_avg numeric(3, 2) NOT NULL DEFAULT 0,
    order_processing_fee numeric(14, 2) NOT NULL DEFAULT 0,
    courier_order_sum numeric(14, 2) NOT NULL DEFAULT 0,
    courier_tips_sum numeric(14, 2) NOT NULL DEFAULT 0,
    courier_reward_sum numeric(14, 2) NOT NULL DEFAULT 0,

    -- Ограничения целостности данных
    CONSTRAINT dm_courier_ledger_settlement_year_check CHECK (settlement_year >= 2022 AND settlement_year < 2500),
    CONSTRAINT dm_courier_ledger_settlement_month_check CHECK (settlement_month >= 1 AND settlement_month <= 12),
    CONSTRAINT dm_courier_ledger_orders_count_check CHECK (orders_count >= 0),
    CONSTRAINT dm_courier_ledger_orders_total_sum_check CHECK (orders_total_sum >= 0),
    CONSTRAINT dm_courier_ledger_rate_avg_check CHECK (rate_avg >= 1 AND rate_avg <= 5),
    CONSTRAINT dm_courier_ledger_order_processing_fee_check CHECK (order_processing_fee >= 0),
    CONSTRAINT dm_courier_ledger_courier_order_sum_check CHECK (courier_order_sum >= 0),
    CONSTRAINT dm_courier_ledger_courier_tips_sum_check CHECK (courier_tips_sum >= 0),
    CONSTRAINT dm_courier_ledger_courier_reward_sum_check CHECK (courier_reward_sum >= 0),



    -- Уникальный индекс для идемпотентного обновления (ON CONFLICT)
    CONSTRAINT dm_courier_ledger_courier_month_unique UNIQUE (courier_id, settlement_year, settlement_month)
);
