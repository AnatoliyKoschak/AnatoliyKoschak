-- Создание схемы, если она еще не существует
CREATE SCHEMA IF NOT EXISTS stg;

DROP TABLE IF EXISTS stg.bonussystem_users;

CREATE TABLE stg.bonussystem_users (
    id            INTEGER NOT NULL,
    order_user_id TEXT NOT NULL,
    
    CONSTRAINT bonussystem_users_pkey PRIMARY KEY (id)
);

-- Комментарий к таблице для документации структуры
COMMENT ON TABLE stg.bonussystem_users IS 'Сырые данные пользователей из бонусной системы';
COMMENT ON COLUMN stg.bonussystem_users.id IS 'Идентификатор пользователя в системе бонусов';
COMMENT ON COLUMN stg.bonussystem_users.order_user_id IS 'Идентификатор пользователя в системе заказов';

DROP TABLE IF EXISTS stg.bonussystem_ranks;

CREATE TABLE stg.bonussystem_ranks (
    id                    INTEGER NOT NULL,
    name                  VARCHAR(2048) NOT NULL,
    bonus_percent         NUMERIC(19, 5) DEFAULT 0 NOT NULL,
    min_payment_threshold NUMERIC(19, 5) DEFAULT 0 NOT NULL,
    
    CONSTRAINT bonussystem_ranks_pkey PRIMARY KEY (id),
    CONSTRAINT bonussystem_ranks_bonus_percent_check CHECK (bonus_percent >= 0)
);

-- Комментарии к таблице для документации структуры
COMMENT ON TABLE stg.bonussystem_ranks IS 'Сырые данные рангов (уровней лояльности) пользователей из бонусной системы';
COMMENT ON COLUMN stg.bonussystem_ranks.id IS 'Идентификатор ранга';
COMMENT ON COLUMN stg.bonussystem_ranks.name IS 'Название ранга';
COMMENT ON COLUMN stg.bonussystem_ranks.bonus_percent IS 'Процент начисляемых бонусов';
COMMENT ON COLUMN stg.bonussystem_ranks.min_payment_threshold IS 'Минимальный порог трат для получения ранга';

DROP TABLE IF EXISTS stg.bonussystem_events;

CREATE TABLE stg.bonussystem_events (
    id          INTEGER NOT NULL,
    event_ts    TIMESTAMP NOT NULL,
    event_type  VARCHAR NOT NULL,
    event_value TEXT NOT NULL,
    
    CONSTRAINT bonussystem_events_pkey PRIMARY KEY (id)
);

CREATE INDEX idx_bonussystem_events__event_ts ON stg.bonussystem_events USING btree (event_ts);

-- Комментарии к таблице для документации структуры
COMMENT ON TABLE stg.bonussystem_events IS 'Сырые события (логика Outbox) из бонусной системы';
COMMENT ON COLUMN stg.bonussystem_events.id IS 'Идентификатор события (из источника)';
COMMENT ON COLUMN stg.bonussystem_events.event_ts IS 'Время создания события';
COMMENT ON COLUMN stg.bonussystem_events.event_type IS 'Тип события';
COMMENT ON COLUMN stg.bonussystem_events.event_value IS 'Тело события (данные в текстовом/JSON формате)';

-- 1. Таблица для коллекции пользователей
DROP TABLE IF EXISTS stg.ordersystem_users;

CREATE TABLE stg.ordersystem_users (
    id           SERIAL,
    object_id    VARCHAR NOT NULL,
    object_value TEXT NOT NULL,
    update_ts    TIMESTAMP NOT NULL,
    
    CONSTRAINT ordersystem_users_pkey PRIMARY KEY (id)
);

-- 2. Таблица для коллекции ресторанов
DROP TABLE IF EXISTS stg.ordersystem_restaurants;

CREATE TABLE stg.ordersystem_restaurants (
    id           SERIAL,
    object_id    VARCHAR NOT NULL,
    object_value TEXT NOT NULL,
    update_ts    TIMESTAMP NOT NULL,
    
    CONSTRAINT ordersystem_restaurants_pkey PRIMARY KEY (id)
);

-- 3. Таблица для коллекции заказов
DROP TABLE IF EXISTS stg.ordersystem_orders;

CREATE TABLE stg.ordersystem_orders (
    id           SERIAL,
    object_id    VARCHAR NOT NULL,
    object_value TEXT NOT NULL,
    update_ts    TIMESTAMP NOT NULL,
    
    CONSTRAINT ordersystem_orders_pkey PRIMARY KEY (id)
);

-- Комментарии к таблицам для документации структуры
COMMENT ON TABLE stg.ordersystem_users IS 'Сырые данные пользователей из MongoDB (Система заказов)';
COMMENT ON TABLE stg.ordersystem_restaurants IS 'Сырые данные ресторанов из MongoDB (Система заказов)';
COMMENT ON TABLE stg.ordersystem_orders IS 'Сырые данные заказов из MongoDB (Система заказов)';


-- 1. Ограничение уникальности для таблицы пользователей
ALTER TABLE stg.ordersystem_users
    ADD CONSTRAINT ordersystem_users_object_id_uindex UNIQUE (object_id);

-- 2. Ограничение уникальности для таблицы ресторанов
ALTER TABLE stg.ordersystem_restaurants
    ADD CONSTRAINT ordersystem_restaurants_object_id_uindex UNIQUE (object_id);

-- 3. Ограничение уникальности для таблицы заказов
ALTER TABLE stg.ordersystem_orders
    ADD CONSTRAINT ordersystem_orders_object_id_uindex UNIQUE (object_id);

DROP TABLE IF EXISTS stg.srv_wf_settings;

CREATE TABLE IF NOT EXISTS stg.srv_wf_settings (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    workflow_key varchar NOT NULL UNIQUE,
    workflow_settings JSON NOT NULL
);


DROP TABLE IF EXISTS stg.api_couriers;
DROP TABLE IF EXISTS stg.api_deliveries;

CREATE TABLE IF NOT EXISTS stg.api_couriers (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    object_id varchar NOT NULL UNIQUE,
    object_value text NOT NULL
);

CREATE TABLE IF NOT EXISTS stg.api_deliveries (
    id int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    object_id varchar NOT NULL UNIQUE,
    object_value text NOT NULL,
    delivery_ts timestamp NOT NULL
);
