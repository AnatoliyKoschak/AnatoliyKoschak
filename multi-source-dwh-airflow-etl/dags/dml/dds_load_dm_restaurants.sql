WITH settings AS (
    SELECT (workflow_settings->>'last_update_ts')::TIMESTAMP AS last_ts
    FROM dds.srv_wf_settings WHERE workflow_key = 'load_restaurants_to_dds'
),
src AS (
    SELECT object_id AS restaurant_id, (object_value::JSONB) ->> 'name' AS restaurant_name, update_ts
    FROM stg.ordersystem_restaurants, settings WHERE update_ts > settings.last_ts
),
upd_old AS (
    UPDATE dds.dm_restaurants d
    SET active_to = src.update_ts FROM src
    WHERE d.restaurant_id = src.restaurant_id AND d.restaurant_name <> src.restaurant_name AND d.active_to = '2500-01-01 00:00:00'::TIMESTAMP
),
do_insert AS (
    INSERT INTO dds.dm_restaurants (restaurant_id, restaurant_name, active_from, active_to)
    SELECT src.restaurant_id, src.restaurant_name, src.update_ts, '2500-01-01 00:00:00'::TIMESTAMP
    FROM src LEFT JOIN dds.dm_restaurants d ON d.restaurant_id = src.restaurant_id AND d.active_to = '2500-01-01 00:00:00'::TIMESTAMP
    WHERE d.id IS NULL OR d.restaurant_name <> src.restaurant_name
)
UPDATE dds.srv_wf_settings
SET workflow_settings = json_build_object('last_update_ts', (SELECT COALESCE(MAX(update_ts), (SELECT last_ts FROM settings)) FROM src))
WHERE workflow_key = 'load_restaurants_to_dds';
