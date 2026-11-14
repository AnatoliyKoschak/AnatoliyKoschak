from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.operators.empty import EmptyOperator

default_args = {
    'owner': 'dwh_team',
    'depends_on_past': True,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    dag_id='dds_load_deliveries_layer',
    default_args=default_args,
    description='Инкрементальная загрузка курьеров и доставок из STG в DDS слой',
    schedule_interval='5 * * * *',  # Каждый час на 5-й минуте
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'dds', 'deliveries'],
) as dag:

    # Единая точка входа
    begin = EmptyOperator(task_id='begin')

    # Авто-инициализация метаданных для доставок
    init_dds_deliveries_settings = PostgresOperator(
        task_id='init_dds_deliveries_settings',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql="""
            INSERT INTO dds.srv_wf_settings (workflow_key, workflow_settings)
            VALUES ('load_deliveries_to_dds', '{"last_delivery_ts": "2026-01-01 00:00:00"}')
            ON CONFLICT (workflow_key) DO NOTHING;
        """,
    )

    # Загрузка справочника курьеров
    dds_couriers = PostgresOperator(
        task_id='load_dds_dm_couriers',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_dm_couriers.sql',
    )

    # Загрузка таблицы фактов доставок
    dds_fct_deliveries = PostgresOperator(
        task_id='load_dds_fct_deliveries',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_fct_deliveries.sql',
    )

    # Последовательность выполнения: сначала инициализация и курьеры, затем факты доставок
    begin >> init_dds_deliveries_settings >> dds_couriers >> dds_fct_deliveries
