INSERT INTO dds.dm_couriers (courier_id, courier_name)
SELECT DISTINCT
    object_id AS courier_id,
    (object_value::JSONB) ->> 'name' AS courier_name
FROM stg.api_couriers
ON CONFLICT (courier_id) DO UPDATE 
SET courier_name = EXCLUDED.courier_name;
