WITH settings AS (
    -- 1. Считываем метку времени из индивидуальной настройки для таблицы заказов
    SELECT (workflow_settings->>'last_order_dttm')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings 
    WHERE workflow_key = 'load_orders_to_dds'
),
src_orders AS (
    -- 2. Читаем данные о заказе, извлекая бизнес-ключи и отметку времени получения финального статуса
    SELECT DISTINCT
        ((o.object_value::JSONB) -> 'user' -> 'id' ->> '$oid') AS src_user_id,
        ((o.object_value::JSONB) -> 'restaurant' -> 'id' ->> '$oid') AS src_restaurant_id,
        o.object_id AS order_key,
        (o.object_value::JSONB) ->> 'final_status' AS order_status,
        to_timestamp(st.dttm, 'YYYY-MM-DD HH24:MI:SS') AS order_ts
    FROM stg.ordersystem_orders o
    CROSS JOIN settings
    -- Разворачиваем JSON-массив statuses в строки для получения dttm
    CROSS JOIN LATERAL jsonb_to_recordset((o.object_value::JSONB) -> 'statuses') AS st(status TEXT, dttm TEXT)
    WHERE st.dttm::TIMESTAMP > settings.last_ts
      AND (o.object_value::JSONB) ->> 'final_status' IN ('CLOSED', 'CANCELLED')
      AND st.status = (o.object_value::JSONB) ->> 'final_status'
      AND st.dttm IS NOT NULL
),
do_upsert AS (
    -- 3. Находим нужные версии объектов в измерениях и выполняем вставку
    INSERT INTO dds.dm_orders (user_id, restaurant_id, timestamp_id, order_key, order_status)
    SELECT 
        u.id AS user_id,
        r.id AS restaurant_id,
        t.id AS timestamp_id,
        so.order_key,
        so.order_status
    FROM src_orders so
    -- Связь с пользователями
    JOIN dds.dm_users u 
        ON u.user_id = so.src_user_id
    -- Поиск версии ресторана с ближайшей верхней границей active_to к дате заказа
    JOIN LATERAL (
        SELECT id
        FROM dds.dm_restaurants
        WHERE restaurant_id = so.src_restaurant_id
          AND active_to >= so.order_ts
        ORDER BY active_to ASC
        LIMIT 1
    ) r ON TRUE
    -- Связь с временными метками
    JOIN dds.dm_timestamps t 
        ON t.ts = so.order_ts
    -- Идемпотентность
    ON CONFLICT (order_key) DO UPDATE 
    SET 
        user_id       = EXCLUDED.user_id,
        restaurant_id = EXCLUDED.restaurant_id,
        timestamp_id  = EXCLUDED.timestamp_id,
        order_status  = EXCLUDED.order_status
    RETURNING order_key
)
-- 4. Сдвигаем метку времени srv_wf_settings
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object(
    'last_order_dttm', 
    (SELECT COALESCE(MAX(order_ts), (SELECT last_ts FROM settings)) FROM src_orders)
)
WHERE workflow_key = 'load_orders_to_dds';
