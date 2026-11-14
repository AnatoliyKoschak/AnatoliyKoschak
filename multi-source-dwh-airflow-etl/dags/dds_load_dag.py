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
    dag_id='dds_load_layer',
    default_args=default_args,
    description='Инкрементальное наполнение справочников и фактов DDS слоя',
    schedule_interval='0 * * * *',
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['foodtech', 'dds'],
) as dag:

    begin = EmptyOperator(task_id='begin')

    init_dds_settings = PostgresOperator(
        task_id='init_dds_workflow_settings',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql="""
            INSERT INTO dds.srv_wf_settings (workflow_key, workflow_settings) VALUES 
            ('load_users_to_dds', '{"last_update_ts": "2026-01-01 00:00:00"}'),
            ('load_restaurants_to_dds', '{"last_update_ts": "2026-01-01 00:00:00"}'),
            ('load_timestamps_to_dds', '{"last_update_ts": "2026-01-01 00:00:00"}'),
            ('load_products_to_dds', '{"last_update_ts": "2026-01-01 00:00:00"}'),
            ('load_orders_to_dds', '{"last_order_dttm": "2026-01-01 00:00:00"}'),
            ('load_fct_product_sales_to_dds', '{"last_update_ts": "2026-01-01 00:00:00"}')
            ON CONFLICT (workflow_key) DO NOTHING;
        """,
    )

    dds_users = PostgresOperator(
        task_id='load_dds_dm_users',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_dm_users.sql',
    )

    dds_restaurants = PostgresOperator(
        task_id='load_dds_dm_restaurants',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_dm_restaurants.sql',
    )

    dds_timestamps = PostgresOperator(
        task_id='load_dds_dm_timestamps',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_dm_timestamps.sql',
    )

    dds_products = PostgresOperator(
        task_id='load_dds_dm_products',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_dm_products.sql',
    )

    dds_orders = PostgresOperator(
        task_id='load_dds_dm_orders',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_dm_orders.sql',
    )

    dds_fct_product_sales = PostgresOperator(
        task_id='load_dds_fct_product_sales',
        postgres_conn_id='PG_WAREHOUSE_CONNECTION',
        sql='dml/dds_load_fct_product_sales.sql',
    )

    # Зависимости выполнения
    begin >> init_dds_settings >> [dds_users, dds_restaurants, dds_timestamps]
    
    dds_restaurants >> dds_products
    [dds_users, dds_restaurants, dds_timestamps] >> dds_orders
    [dds_orders, dds_products] >> dds_fct_product_sales
