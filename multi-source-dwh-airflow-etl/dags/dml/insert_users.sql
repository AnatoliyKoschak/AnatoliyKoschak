INSERT INTO stg.bonussystem_users (id, order_user_id)
VALUES (%s, %s)
ON CONFLICT (id) DO UPDATE 
SET 
    order_user_id = EXCLUDED.order_user_id;
