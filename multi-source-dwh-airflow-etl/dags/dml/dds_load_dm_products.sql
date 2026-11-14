WITH settings AS (
    -- 1. Считываем метку времени последнего успешного запуска для продуктов
    SELECT (workflow_settings->>'last_update_ts')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings 
    WHERE workflow_key = 'load_products_to_dds'
),
src_extracted AS (
    -- 2. Разворачиваем массив menu из документов ресторанов за отчетный инкремент
    SELECT DISTINCT
        items.value -> '_id' ->> '$oid' AS product_id,
        items.value ->> 'name' AS product_name,
        (items.value ->> 'price')::NUMERIC(14, 2) AS product_price,
        r.id AS restaurant_id,
        o.update_ts
    FROM stg.ordersystem_restaurants o
    CROSS JOIN settings
    -- Разворачиваем JSON-массив элементов меню ресторана
    CROSS JOIN LATERAL jsonb_array_elements((o.object_value::JSONB) -> 'menu') AS items
    -- Поиск версии ресторана с ближайшей верхней границей active_to к дате обновления
    JOIN LATERAL (
        SELECT id
        FROM dds.dm_restaurants
        WHERE restaurant_id = o.object_id
          AND active_to >= o.update_ts
        ORDER BY active_to ASC
        LIMIT 1
    ) r ON TRUE
    WHERE o.update_ts > settings.last_ts
),
upd_old AS (
    -- 3. Закрываем исторические версии продуктов (SCD 2), если изменилось название или цена
    UPDATE dds.dm_products p
    SET active_to = src.update_ts
    FROM src_extracted src
    WHERE p.product_id = src.product_id
      AND p.restaurant_id = src.restaurant_id
      AND (p.product_name <> src.product_name OR p.product_price <> src.product_price)
      AND p.active_to = '2500-01-01 00:00:00'::TIMESTAMP
),
do_insert AS (
    -- 4. Вставляем новые продукты или новые версии старых продуктов
    INSERT INTO dds.dm_products (product_id, product_name, product_price, restaurant_id, active_from, active_to)
    SELECT 
        src.product_id,
        src.product_name,
        src.product_price,
        src.restaurant_id,
        src.update_ts,
        '2500-01-01 00:00:00'::TIMESTAMP
    FROM src_extracted src
    LEFT JOIN dds.dm_products p 
        ON p.product_id = src.product_id 
       AND p.restaurant_id = src.restaurant_id
       AND p.active_to = '2500-01-01 00:00:00'::TIMESTAMP
    WHERE p.id IS NULL OR p.product_name <> src.product_name OR p.product_price <> src.product_price
    RETURNING product_id
)
-- 5. Сдвигаем метку времени srv_wf_settings для продуктов
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object(
    'last_update_ts', 
    (SELECT COALESCE(MAX(update_ts), (SELECT last_ts FROM settings)) FROM src_extracted)
)
WHERE workflow_key = 'load_products_to_dds';
