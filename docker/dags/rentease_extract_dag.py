from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import sys

sys.path.append("/opt/rentease")  # so it can import your extract/ scripts

from extract.extract_bookings import extract_bookings

with DAG(
    dag_id="rentease_extract_bookings",
    start_date=datetime(2026, 1, 1),
    schedule="@daily",
    catchup=False,
    tags=["rentease", "extract"],
) as dag:

    extract_task = PythonOperator(
        task_id="extract_bookings",
        python_callable=extract_bookings,
    )