INSERT INTO stg.bonussystem_ranks (id, name, bonus_percent, min_payment_threshold)
VALUES (%s, %s, %s, %s)
ON CONFLICT (id) DO UPDATE 
SET 
    name                  = EXCLUDED.name,
    bonus_percent         = EXCLUDED.bonus_percent,
    min_payment_threshold = EXCLUDED.min_payment_threshold;