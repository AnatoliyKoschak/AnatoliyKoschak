import os
import sys
import json
import requests
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator

sys.path.insert(0, os.path.dirname(__file__))
from lib import ConnectionBuilder

default_args = {
    'owner': 'dwh_team',
    'depends_on_past': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=2),
}

# Собираем URL по частям, чтобы исключить обрезку при копировании
API_SUBDOMAIN = Variable.get('API_SUBDOMAIN')
API_DOMAIN = Variable.get('API_DOMAIN')
API_URL = f"https://{API_SUBDOMAIN}.{API_DOMAIN}"

HEADERS = {
    "X-Nickname": Variable.get("API_NICKNAME"),
    "X-API-KEY": Variable.get("API_KEY"),
}


def load_couriers_to_stg(**kwargs):
    """Загрузка справочника курьеров из API с пагинацией и сохранением прогресса в srv_wf_settings."""
    pg_dwh = ConnectionBuilder.pg_conn("PG_WAREHOUSE_CONNECTION")
    workflow_key = "stg_load_api_couriers"

    with pg_dwh.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO stg.srv_wf_settings (workflow_key, workflow_settings)
                VALUES (%s, '{"last_offset": 0}')
                ON CONFLICT (workflow_key) DO NOTHING;
            """, (workflow_key,))
            
            cur.execute("""
                SELECT workflow_settings::TEXT 
                FROM stg.srv_wf_settings 
                WHERE workflow_key = %s;
            """, (workflow_key,))
            row = cur.fetchone()
            current_settings_str = row[0]

    print(f"[METADATA] Текущие настройки для '{workflow_key}': {current_settings_str}")
    offset = int(json.loads(current_settings_str).get("last_offset", 0))
    limit = 50
    total_loaded = 0

    with pg_dwh.connection() as conn:
        with conn.cursor() as cur:
            while True:
                params = {
                    "sort_field": "id",
                    "sort_direction": "asc",
                    "limit": limit,
                    "offset": offset
                }
                response = requests.get(f"{API_URL}/couriers", headers=HEADERS, params=params)
                response.raise_for_status()
                couriers = response.json()

                if not couriers:
                    break

                for courier in couriers:
                    courier_id = str(courier["_id"])
                    object_value = json.dumps(courier, ensure_ascii=False)
                    
                    cur.execute("""
                        INSERT INTO stg.api_couriers (object_id, object_value)
                        VALUES (%s, %s)
                        ON CONFLICT (object_id) DO UPDATE 
                        SET object_value = EXCLUDED.object_value;
                    """, (courier_id, object_value))

                batch_len = len(couriers)
                total_loaded += batch_len
                offset += batch_len

                if batch_len < limit:
                    break

            new_settings_json = json.dumps({"last_offset": offset})
            cur.execute("""
                UPDATE stg.srv_wf_settings 
                SET workflow_settings = %s 
                WHERE workflow_key = %s;
            """, (new_settings_json, workflow_key))
            print(f"[METADATA] Новые настройки для '{workflow_key}': {new_settings_json}")

    print(f"[LOAD] Загружено/обновлено {total_loaded} курьеров в stg.api_couriers")


def load_deliveries_to_stg(**kwargs):
    """Инкрементальная загрузка доставок из API по дате доставки (delivery_ts)."""
    pg_dwh = ConnectionBuilder.pg_conn("PG_WAREHOUSE_CONNECTION")
    workflow_key = "stg_load_api_deliveries"

    with pg_dwh.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO stg.srv_wf_settings (workflow_key, workflow_settings)
                VALUES (%s, '{"last_delivery_ts": "2026-01-01 00:00:00"}')
                ON CONFLICT (workflow_key) DO NOTHING;
            """, (workflow_key,))
            
            cur.execute("""
                SELECT workflow_settings::TEXT 
                FROM stg.srv_wf_settings 
                WHERE workflow_key = %s;
            """, (workflow_key,))
            row = cur.fetchone()
            current_settings_str = row[0]

    print(f"[METADATA] Текущие настройки для '{workflow_key}': {current_settings_str}")
    last_delivery_ts_str = json.loads(current_settings_str)["last_delivery_ts"]
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    offset = 0
    limit = 50
    total_loaded = 0
    max_delivery_ts = datetime.strptime(last_delivery_ts_str, "%Y-%m-%d %H:%M:%S")

    with pg_dwh.connection() as conn:
        with conn.cursor() as cur:
            while True:
                params = {
                    "from": last_delivery_ts_str,
                    "to": now_str,
                    "sort_field": "date",
                    "sort_direction": "asc",
                    "limit": limit,
                    "offset": offset
                }
                response = requests.get(f"{API_URL}/deliveries", headers=HEADERS, params=params)
                response.raise_for_status()
                deliveries = response.json()

                if not deliveries:
                    break

                for delivery in deliveries:
                    delivery_id = str(delivery["delivery_id"])
                    # Берем первые 19 символов ('YYYY-MM-DD HH:MM:SS'), чтобы безопасно отрезать микросекунды
                    raw_del_ts = delivery["delivery_ts"][:19]
                    current_del_ts = datetime.strptime(raw_del_ts, "%Y-%m-%d %H:%M:%S")
                    object_value = json.dumps(delivery, ensure_ascii=False)

                    cur.execute("""
                        INSERT INTO stg.api_deliveries (object_id, object_value, delivery_ts)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (object_id) DO UPDATE 
                        SET object_value = EXCLUDED.object_value, delivery_ts = EXCLUDED.delivery_ts;
                    """, (delivery_id, object_value, current_del_ts))

                    if current_del_ts > max_delivery_ts:
                        max_delivery_ts = current_del_ts

                batch_len = len(deliveries)
                total_loaded += batch_len
                offset += batch_len

                if batch_len < limit:
                    break

            if total_loaded > 0:
                new_settings_json = json.dumps({"last_delivery_ts": max_delivery_ts.strftime("%Y-%m-%d %H:%M:%S")})
                cur.execute("""
                    UPDATE stg.srv_wf_settings 
                    SET workflow_settings = %s 
                    WHERE workflow_key = %s;
                """, (new_settings_json, workflow_key))
                print(f"[METADATA] Новые настройки для '{workflow_key}': {new_settings_json}")

    print(f"[LOAD] Загружено/обновлено {total_loaded} доставок в stg.api_deliveries")


with DAG(
    dag_id='stg_load_from_api',
    default_args=default_args,
    description='Загрузка курьеров и доставок из API в STG слой',
    schedule_interval='*/15 * * * *',
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'stg', 'api'],
) as dag:

    begin = EmptyOperator(task_id='begin')

    load_couriers = PythonOperator(
        task_id='load_stg_api_couriers',
        python_callable=load_couriers_to_stg,
    )

    load_deliveries = PythonOperator(
        task_id='load_stg_api_deliveries',
        python_callable=load_deliveries_to_stg,
    )

    begin >> [load_couriers, load_deliveries]
