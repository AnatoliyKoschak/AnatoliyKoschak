WITH settings AS (
    -- 1. Считываем метку времени последнего успешного запуска для фактов продаж
    SELECT (workflow_settings->>'last_update_ts')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings 
    WHERE workflow_key = 'load_fct_product_sales_to_dds'
),
src_orders AS (
    -- 2. Извлекаем закрытые/отмененные заказы и разворачиваем массив позиций order_items
    SELECT 
        o_dds.id AS order_id,
        o_dds.order_key,
        (items.value -> 'id' ->> '$oid') AS src_product_id,
        (items.value ->> 'quantity')::INTEGER AS count,
        (items.value ->> 'price')::NUMERIC(14, 2) AS price,
        (items.value ->> 'quantity')::INTEGER * (items.value ->> 'price')::NUMERIC(14, 2) AS total_sum,
        date_trunc('second', st.dttm::TIMESTAMP) AS order_ts
    FROM stg.ordersystem_orders o
    CROSS JOIN settings
    -- Разворачиваем массив статусов для получения точного времени order_ts
    CROSS JOIN LATERAL jsonb_to_recordset((o.object_value::JSONB) -> 'statuses') AS st(status TEXT, dttm TEXT)
    -- Связываем с заголовком заказа в DDS
    JOIN dds.dm_orders o_dds 
        ON o_dds.order_key = o.object_id
    -- Разворачиваем массив блюд в заказе
    CROSS JOIN LATERAL jsonb_array_elements((o.object_value::JSONB) -> 'order_items') AS items
    WHERE st.dttm::TIMESTAMP > settings.last_ts
      AND (o.object_value::JSONB) ->> 'final_status' IN ('CLOSED', 'CANCELLED')
      AND st.status = (o.object_value::JSONB) ->> 'final_status'
      AND st.dttm IS NOT NULL
),
src_orders_with_products AS (
    -- 3. Находим нужную версию продукта в SCD 2 измерении по ближайшей верхней границе active_to
    SELECT 
        so.order_id,
        so.order_key,
        so.src_product_id,
        p_dds.id AS product_id,
        so.count,
        so.price,
        so.total_sum,
        so.order_ts
    FROM src_orders so
    JOIN LATERAL (
        SELECT id
        FROM dds.dm_products
        WHERE product_id = so.src_product_id
          AND active_to >= so.order_ts
        ORDER BY active_to ASC
        LIMIT 1
    ) p_dds ON TRUE
),
src_bonuses AS (
    -- 4. Парсим события бонусных транзакций из Outbox-лога за этот же период
    SELECT 
        (event_value::JSONB ->> 'order_id') AS order_key,
        (bonus_items.value ->> 'product_id') AS src_product_id,
        (bonus_items.value ->> 'bonus_payment')::NUMERIC(14, 2) AS bonus_payment,
        (bonus_items.value ->> 'bonus_grant')::NUMERIC(14, 2) AS bonus_grant
    FROM stg.bonussystem_events
    CROSS JOIN settings
    CROSS JOIN LATERAL jsonb_array_elements((event_value::JSONB) -> 'product_payments') AS bonus_items
    WHERE event_type = 'bonus_transaction'
      AND event_ts > settings.last_ts
),
do_upsert AS (
    -- 5. Объединяем продажи с бонусами и вставляем в таблицу фактов
    INSERT INTO dds.fct_product_sales (
        product_id, 
        order_id, 
        count, 
        price, 
        total_sum, 
        bonus_payment, 
        bonus_grant
    )
    SELECT 
        sop.product_id,
        sop.order_id,
        sop.count,
        sop.price,
        sop.total_sum,
        COALESCE(sb.bonus_payment, 0.00) AS bonus_payment,
        COALESCE(sb.bonus_grant, 0.00) AS bonus_grant
    FROM src_orders_with_products sop
    LEFT JOIN src_bonuses sb 
        ON sop.order_key = sb.order_key 
       AND sop.src_product_id = sb.src_product_id
    -- Идемпотентность: при повторном запуске обновляем метрики
    ON CONFLICT (order_id, product_id) DO UPDATE 
    SET 
        count         = EXCLUDED.count,
        price         = EXCLUDED.price,
        total_sum     = EXCLUDED.total_sum,
        bonus_payment = EXCLUDED.bonus_payment,
        bonus_grant   = EXCLUDED.bonus_grant
    RETURNING order_id
)
-- 6. Сдвигаем метку прогресса в srv_wf_settings для таблицы фактов продаж
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object(
    'last_update_ts', 
    (SELECT COALESCE(MAX(order_ts), (SELECT last_ts FROM settings)) FROM src_orders)
)
WHERE workflow_key = 'load_fct_product_sales_to_dds';
