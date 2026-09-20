from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import sys

sys.path.append("/opt/rentease")  # repo root is mounted here

from extract.run_all import main as run_all_extracts

with DAG(
    dag_id="rentease_extract_all",
    start_date=datetime(2026, 1, 1),
    schedule="@daily",
    catchup=False,
    tags=["rentease", "extract"],
) as dag:

    extract_task = PythonOperator(
        task_id="extract_all_tables",
        python_callable=run_all_extracts,
    )