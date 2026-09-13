import os
import snowflake.connector
from dotenv import load_dotenv

load_dotenv()


def get_snowflake_conn():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role=os.environ.get("SNOWFLAKE_ROLE", "LOADER"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "LOAD_WH"),
        database="RENTEASE_RAW",
        schema="MYSQL",
    )
