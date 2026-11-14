CREATE SCHEMA IF NOT EXISTS dds;

DROP TABLE IF EXISTS dds.dm_users CASCADE;
DROP TABLE IF EXISTS dds.dm_restaurants CASCADE;
DROP TABLE IF EXISTS dds.dm_products CASCADE;
DROP TABLE IF EXISTS dds.dm_timestamps CASCADE;
DROP TABLE IF EXISTS dds.dm_orders CASCADE;
DROP TABLE IF EXISTS dds.fct_product_sales CASCADE;
DROP TABLE IF EXISTS dds.fct_deliveries CASCADE;
DROP TABLE IF EXISTS dds.dm_couriers CASCADE;
DROP TABLE IF EXISTS dds.srv_wf_settings;

-- Создание таблицы пользователей в слое dds
CREATE TABLE dds.dm_users (
    id          SERIAL,
    user_id     VARCHAR NOT NULL,
    user_name   VARCHAR NOT NULL,
    user_login  VARCHAR NOT NULL,
    
    CONSTRAINT dm_users_pkey PRIMARY KEY (id),
    CONSTRAINT dm_users_user_id_uindex UNIQUE (user_id)
);

-- Комментарии к таблице для документации
COMMENT ON TABLE dds.dm_users IS 'Измерение пользователей (Слой DDS)';
COMMENT ON COLUMN dds.dm_users.id IS 'Суррогатный первичный ключ с инкрементом';
COMMENT ON COLUMN dds.dm_users.user_id IS 'Уникальный идентификатор пользователя из MongoDB (бизнес-ключ)';
COMMENT ON COLUMN dds.dm_users.user_name IS 'Имя пользователя';
COMMENT ON COLUMN dds.dm_users.user_login IS 'Логин пользователя';


-- Создание таблицы ресторанов в слое dds
CREATE TABLE dds.dm_restaurants (
    id               SERIAL,
    restaurant_id    VARCHAR NOT NULL,
    restaurant_name  VARCHAR NOT NULL,
    active_from      TIMESTAMP NOT NULL,
    active_to        TIMESTAMP NOT NULL,
    
    CONSTRAINT dm_restaurants_pkey PRIMARY KEY (id)
);

-- Комментарии к таблице для документации структуры
COMMENT ON TABLE dds.dm_restaurants IS 'Измерение ресторанов (Слой DDS)';
COMMENT ON COLUMN dds.dm_restaurants.id IS 'Суррогатный первичный ключ с инкрементом';
COMMENT ON COLUMN dds.dm_restaurants.restaurant_id IS 'Уникальный идентификатор ресторана из MongoDB (бизнес-ключ)';
COMMENT ON COLUMN dds.dm_restaurants.restaurant_name IS 'Название ресторана';
COMMENT ON COLUMN dds.dm_restaurants.active_from IS 'Техническое поле версионности: начало действия записи';
COMMENT ON COLUMN dds.dm_restaurants.active_to IS 'Техническое поле версионности: конец действия записи';

-- Создание таблицы продуктов (меню) в слое dds
CREATE TABLE dds.dm_products (
    id               SERIAL,
    product_id       VARCHAR NOT NULL,
    product_name     VARCHAR NOT NULL,
    product_price    NUMERIC(14, 2) DEFAULT 0 NOT NULL,
    restaurant_id    INTEGER NOT NULL,
    active_from      TIMESTAMP NOT NULL,
    active_to        TIMESTAMP NOT NULL,
    
    CONSTRAINT dm_products_pkey PRIMARY KEY (id),
    CONSTRAINT dm_products_product_price_check CHECK (product_price >= 0)
);

-- Комментарии к таблице и полям для документации структуры
COMMENT ON TABLE dds.dm_products IS 'Измерение продуктов/блюд (Слой DDS)';
COMMENT ON COLUMN dds.dm_products.id IS 'Суррогатный первичный ключ с инкрементом';
COMMENT ON COLUMN dds.dm_products.product_id IS 'Уникальный идентификатор продукта из MongoDB (бизнес-ключ)';
COMMENT ON COLUMN dds.dm_products.product_name IS 'Название продукта';
COMMENT ON COLUMN dds.dm_products.product_price IS 'Стоимость продукта (до 999 млрд руб с копейками)';
COMMENT ON COLUMN dds.dm_products.restaurant_id IS 'Идентификатор для связки с рестораном (суррогатный ключ из dds.dm_restaurants)';
COMMENT ON COLUMN dds.dm_products.active_from IS 'Техническое поле версионности SCD 2: начало действия записи';
COMMENT ON COLUMN dds.dm_products.active_to IS 'Техническое поле версионности SCD 2: конец действия записи';

ALTER TABLE dds.dm_products
    ADD CONSTRAINT dm_products_restaurant_id_fkey 
    FOREIGN KEY (restaurant_id) REFERENCES dds.dm_restaurants (id);

CREATE TABLE dds.dm_timestamps (
    id      SERIAL,
    ts      TIMESTAMP NOT NULL,
    year    SMALLINT NOT NULL,
    month   SMALLINT NOT NULL,
    day     SMALLINT NOT NULL,
    time    TIME NOT NULL,
    date    DATE NOT NULL,
    
    CONSTRAINT dm_timestamps_pkey PRIMARY KEY (id),
    CONSTRAINT dm_timestamps_year_check CHECK (year >= 2022 AND year < 2500),
    CONSTRAINT dm_timestamps_month_check CHECK (month >= 1 AND month <= 12),
    CONSTRAINT dm_timestamps_day_check CHECK (day >= 1 AND day <= 31)
);

-- Комментарии к таблице для документации структуры
COMMENT ON TABLE dds.dm_timestamps IS 'Измерение даты и времени (Слой DDS)';
COMMENT ON COLUMN dds.dm_timestamps.id IS 'Суррогатный первичный ключ с инкрементом';
COMMENT ON COLUMN dds.dm_timestamps.ts IS 'Полная отметка времени';
COMMENT ON COLUMN dds.dm_timestamps.year IS 'Год (2022-2499)';
COMMENT ON COLUMN dds.dm_timestamps.month IS 'Месяц (1-12)';
COMMENT ON COLUMN dds.dm_timestamps.day IS 'День месяца (1-31)';
COMMENT ON COLUMN dds.dm_timestamps.time IS 'Время дня';
COMMENT ON COLUMN dds.dm_timestamps.date IS 'Дата';

ALTER TABLE dds.dm_timestamps ADD CONSTRAINT dm_timestamps_ts_uindex UNIQUE (ts);

CREATE TABLE dds.dm_orders (
    id            SERIAL,
    user_id       INTEGER NOT NULL,
    restaurant_id INTEGER NOT NULL,
    timestamp_id  INTEGER NOT NULL,
    order_key     VARCHAR NOT NULL,
    order_status  VARCHAR NOT NULL,
    
    CONSTRAINT dm_orders_pkey PRIMARY KEY (id),
    CONSTRAINT dm_orders_order_key_uindex UNIQUE (order_key)
);

-- Комментарии к таблице и полям для документации структуры
COMMENT ON TABLE dds.dm_orders IS 'Таблица фактов/измерений заказов (Слой DDS)';
COMMENT ON COLUMN dds.dm_orders.id IS 'Суррогатный первичный ключ с инкрементом заказа';
COMMENT ON COLUMN dds.dm_orders.user_id IS 'Идентификатор пользователя (ссылка на dds.dm_users.id)';
COMMENT ON COLUMN dds.dm_orders.restaurant_id IS 'Идентификатор ресторана (ссылка на dds.dm_restaurants.id)';
COMMENT ON COLUMN dds.dm_orders.timestamp_id IS 'Идентификатор временной метки (ссылка на dds.dm_timestamps.id)';
COMMENT ON COLUMN dds.dm_orders.order_key IS 'Уникальный бизнес-идентификатор заказа из MongoDB';
COMMENT ON COLUMN dds.dm_orders.order_status IS 'Текущий статус заказа';

ALTER TABLE dds.dm_orders
    ADD CONSTRAINT dm_orders_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES dds.dm_users (id);

ALTER TABLE dds.dm_orders
    ADD CONSTRAINT dm_orders_restaurant_id_fkey 
    FOREIGN KEY (restaurant_id) REFERENCES dds.dm_restaurants (id);

ALTER TABLE dds.dm_orders
    ADD CONSTRAINT dm_orders_timestamp_id_fkey 
    FOREIGN KEY (timestamp_id) REFERENCES dds.dm_timestamps (id);

CREATE TABLE dds.fct_product_sales (
    id             SERIAL,
    product_id     INTEGER NOT NULL,
    order_id       INTEGER NOT NULL,
    count          INTEGER DEFAULT 0 NOT NULL,
    price          NUMERIC(14, 2) DEFAULT 0 NOT NULL,
    total_sum      NUMERIC(14, 2) DEFAULT 0 NOT NULL,
    bonus_payment  NUMERIC(14, 2) DEFAULT 0 NOT NULL,
    bonus_grant    NUMERIC(14, 2) DEFAULT 0 NOT NULL,
    
    -- Первичный ключ
    CONSTRAINT fct_product_sales_pkey PRIMARY KEY (id),
    
    -- Проверки на значения больше либо равные 0
    CONSTRAINT fct_product_sales_count_check CHECK (count >= 0),
    CONSTRAINT fct_product_sales_price_check CHECK (price >= 0),
    CONSTRAINT fct_product_sales_total_sum_check CHECK (total_sum >= 0),
    CONSTRAINT fct_product_sales_bonus_payment_check CHECK (bonus_payment >= 0),
    CONSTRAINT fct_product_sales_bonus_grant_check CHECK (bonus_grant >= 0)
);

-- Комментарии к структуре для удобства документации
COMMENT ON TABLE dds.fct_product_sales IS 'Таблица фактов продаж продуктов в разрезе заказов (Слой DDS)';
COMMENT ON COLUMN dds.fct_product_sales.id IS 'Суррогатный первичный ключ строки продажи';
COMMENT ON COLUMN dds.fct_product_sales.product_id IS 'Идентификатор продукта (ссылка на dds.dm_products.id)';
COMMENT ON COLUMN dds.fct_product_sales.order_id IS 'Идентификатор заказа (ссылка на dds.dm_orders.id)';
COMMENT ON COLUMN dds.fct_product_sales.count IS 'Количество единиц товара в заказе';
COMMENT ON COLUMN dds.fct_product_sales.price IS 'Цена за одну единицу товара';
COMMENT ON COLUMN dds.fct_product_sales.total_sum IS 'Общая стоимость позиции (цена * количество)';
COMMENT ON COLUMN dds.fct_product_sales.bonus_payment IS 'Сумма оплаты бонусами за данный товар';
COMMENT ON COLUMN dds.fct_product_sales.bonus_grant IS 'Сумма начисленных бонусов за данный товар';

ALTER TABLE dds.fct_product_sales ADD CONSTRAINT fct_product_sales_order_product_uq UNIQUE (order_id, product_id);

-- 1. Связь с таблицей продуктов
ALTER TABLE dds.fct_product_sales
    ADD CONSTRAINT fct_product_sales_product_id_fkey 
    FOREIGN KEY (product_id) REFERENCES dds.dm_products (id);

-- 2. Связь с таблицей заказов
ALTER TABLE dds.fct_product_sales
    ADD CONSTRAINT fct_product_sales_order_id_fkey 
    FOREIGN KEY (order_id) REFERENCES dds.dm_orders (id);

CREATE TABLE IF NOT EXISTS dds.srv_wf_settings (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    workflow_key varchar NOT NULL UNIQUE,
    workflow_settings JSON NOT NULL
);

-- INSERT INTO dds.srv_wf_settings (workflow_key, workflow_settings)
-- VALUES ('load_stg_to_dds', '{"last_update_ts": "2022-01-01 00:00:00"}')
-- ON CONFLICT (workflow_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS dds.dm_couriers (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    courier_id varchar NOT NULL UNIQUE,
    courier_name varchar NOT NULL
);

CREATE TABLE IF NOT EXISTS dds.fct_deliveries (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    delivery_id varchar NOT NULL UNIQUE,
    courier_id int NOT NULL REFERENCES dds.dm_couriers(id),
    order_id int NOT NULL REFERENCES dds.dm_orders(id),
    order_ts timestamp NOT NULL,
    delivery_ts timestamp NOT NULL,
    address varchar NOT NULL,
    rate int NOT NULL CHECK (rate >= 1 AND rate <= 5),
    sum numeric(14, 2) NOT NULL DEFAULT 0,
    tip_sum numeric(14, 2) NOT NULL DEFAULT 0
);