import os
import sys
import json
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator
from bson.json_util import dumps as bson_dumps

# Подключаем локальный пакет lib для работы с источниками
sys.path.insert(0, os.path.dirname(__file__))
from lib import ConnectionBuilder, MongoConnect

DAG_PATH = os.path.dirname(__file__)

default_args = {
    'owner': 'dwh_team',
    'depends_on_past': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=2),
}

# Чтение конфигурации MongoDB на верхнем уровне
cert_path = Variable.get("MONGO_DB_CERTIFICATE_PATH")
db_user = Variable.get("MONGO_DB_USER")
db_pw = Variable.get("MONGO_DB_PASSWORD")
rs = Variable.get("MONGO_DB_REPLICA_SET")
db = Variable.get("MONGO_DB_DATABASE_NAME")
host = Variable.get("MONGO_DB_HOST")


def load_mongo_to_stg(collection_name: str, **kwargs):
    """Инкрементальный Upsert документов из MongoDB в stg.ordersystem_{collection_name}"""
    pg_dwh = ConnectionBuilder.pg_conn("PG_WAREHOUSE_CONNECTION")
    workflow_key = f"stg_load_{collection_name}"
    
    # 1. Читаем и выводим в лог текущие настройки из srv_wf_settings
    with pg_dwh.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO stg.srv_wf_settings (workflow_key, workflow_settings)
                VALUES (%s, '{"last_update_ts": "2026-01-01 00:00:00"}')
                ON CONFLICT (workflow_key) DO NOTHING;
            """, (workflow_key,))
            
            cur.execute("""
                SELECT workflow_settings::TEXT 
                FROM stg.srv_wf_settings 
                WHERE workflow_key = %s;
            """, (workflow_key,))
            
            current_settings_str = cur.fetchone()[0]
            
    print(f"[METADATA] Текущие настройки для '{workflow_key}': {current_settings_str}")
    
    current_settings = json.loads(current_settings_str)
    start_ts = datetime.strptime(current_settings["last_update_ts"], "%Y-%m-%d %H:%M:%S")
    end_ts = datetime.utcnow() 

    # 2. Инициализация коннектора и поиск инкремента в MongoDB
    mongo_conn = MongoConnect(cert_path, db_user, db_pw, host, rs, db, db)
    mongo_db = mongo_conn.client()
    collection = mongo_db.get_collection(collection_name)
    
    query = {"update_ts": {"$gte": start_ts, "$lt": end_ts}}
    documents = list(collection.find(query).sort("update_ts", 1))

    print(f"[EXTRACT] Найдено {len(documents)} новых/измененных документов в коллекции MongoDB '{collection_name}'")

    if not documents:
        print(f"[EXTRACT] Загрузка не требуется. Нет новых изменений с момента {start_ts}")
        return

    table_name = f"stg.ordersystem_{collection_name}"
    max_update_ts = start_ts
    records_upserted = 0

    # 3. Запись инкремента в Postgres DWH в режиме Upsert
    with pg_dwh.connection() as conn:
        with conn.cursor() as cur:
            for doc in documents:
                object_id = str(doc['_id'])
                current_update_ts = doc['update_ts']
                object_value = bson_dumps(doc, ensure_ascii=False)
                
                cur.execute(f"""
                    INSERT INTO {table_name} (object_id, object_value, update_ts)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (object_id) DO UPDATE 
                    SET object_value = EXCLUDED.object_value, update_ts = EXCLUDED.update_ts;
                """, (object_id, object_value, current_update_ts))
                
                records_upserted += 1
                if current_update_ts > max_update_ts:
                    max_update_ts = current_update_ts
            
            # 4. Обновляем техническую метку прогресса srv_wf_settings
            new_settings_dict = {"last_update_ts": max_update_ts.strftime("%Y-%m-%d %H:%M:%S")}
            new_settings_json = json.dumps(new_settings_dict)
            
            cur.execute("""
                UPDATE stg.srv_wf_settings 
                SET workflow_settings = %s 
                WHERE workflow_key = %s;
            """, (new_settings_json, workflow_key))
            
            print(f"[METADATA] Новые настройки для '{workflow_key}' успешно сохранены: {new_settings_json}")
                
    print(f"[LOAD] Успешно добавлено/обновлено {records_upserted} записей в таблице '{table_name}'")


with DAG(
    dag_id='stg_load_from_mongodb',
    default_args=default_args,
    description='Автономная инкрементальная загрузка из MongoDB в STG слой',
    schedule_interval='*/15 * * * *',
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'stg', 'mongodb'],
) as dag:

    begin = EmptyOperator(task_id='begin')

    for col in ['users', 'restaurants', 'orders']:
        task = PythonOperator(
            task_id=f'load_stg_ordersystem_{col}',
            python_callable=load_mongo_to_stg,
            op_kwargs={'collection_name': col},
        )
        begin >> task
