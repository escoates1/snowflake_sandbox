CREATE OR REPLACE PROCEDURE DWH_DEV.RAW.INGEST_USGS_EARTHQUAKES(
    DATABASE_NAME STRING,
    SCHEMA_NAME STRING
)
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    PACKAGES = ('snowflake-snowpark-python', 'requests')
    HANDLER = 'run'
    EXTERNAL_ACCESS_INTEGRATIONS = (USGS_EARTHQUAKE_ACCESS_INTEGRATION)
    EXECUTE AS CALLER
AS
$$
import requests
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import current_timestamp

def run(session: Session, database_name: str, schema_name: str) -> str:
    status = 'SUCCESS'
    error_message = None
    rows_ingested = 0

    # Build fully qualified table references
    landing_table = f"{database_name}.{schema_name}.USGS_EARTHQUAKES_FDSNWS_LANDING"
    main_table = f"{database_name}.{schema_name}.USGS_EARTHQUAKES_FDSNWS"
    metadata_table = f"{database_name}.ADMIN.INGESTION_METADATA"

    try:
        # Set session context for temporary object creation
        session.sql(f"USE DATABASE {database_name}").collect()
        session.sql(f"USE SCHEMA {schema_name}").collect()

        # Step 1: Get the watermark from INGESTION_METADATA
        watermark_df = session.sql(f"""
            SELECT COALESCE(
                TO_VARCHAR(LAST_UPDATED_TIME, 'YYYY-MM-DD"T"HH24:MI:SS'),
                '2026-01-01'
            ) AS START_TIME
            FROM {metadata_table}
            WHERE LOAD_ID = 'P1'
        """).collect()

        if watermark_df:
            start_time = watermark_df[0]['START_TIME']
        else:
            start_time = '2026-01-01'

        # Step 2: Query the USGS API
        url = 'https://earthquake.usgs.gov/fdsnws/event/1/query'
        params = {
            'format': 'geojson',
            'starttime': start_time,
            'minmagnitude': 5
        }

        response = requests.get(url, params=params, timeout=120)
        response.raise_for_status()
        data = response.json()

        features = data.get('features', [])
        rows_ingested = len(features)

        if rows_ingested == 0:
            # No new data — update metadata and return
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    ROWS_INGESTED = 0,
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()
            return 'SUCCESS: No new records to ingest.'

        # Step 3: Parse GeoJSON features into flat rows
        rows = []
        for feature in features:
            props = feature.get('properties', {})
            geometry = feature.get('geometry', {})
            coordinates = geometry.get('coordinates', [None, None, None])

            rows.append({
                'ID': feature.get('id'),
                'MAG': float(props['mag']) if props.get('mag') is not None else None,
                'PLACE': props.get('place'),
                'TIME': props.get('time'),
                'UPDATED': props.get('updated'),
                'TZ': props.get('tz'),
                'URL': props.get('url'),
                'DETAIL': props.get('detail'),
                'FELT': props.get('felt'),
                'CDI': float(props['cdi']) if props.get('cdi') is not None else None,
                'MMI': float(props['mmi']) if props.get('mmi') is not None else None,
                'ALERT': props.get('alert'),
                'STATUS': props.get('status'),
                'TSUNAMI': props.get('tsunami'),
                'SIG': props.get('sig'),
                'NET': props.get('net'),
                'CODE': props.get('code'),
                'IDS': props.get('ids'),
                'SOURCES': props.get('sources'),
                'TYPES': props.get('types'),
                'NST': props.get('nst'),
                'DMIN': float(props['dmin']) if props.get('dmin') is not None else None,
                'RMS': float(props['rms']) if props.get('rms') is not None else None,
                'GAP': float(props['gap']) if props.get('gap') is not None else None,
                'MAGTYPE': props.get('magType'),
                'TYPE': props.get('type'),
                'TITLE': props.get('title'),
                'LONGITUDE': float(coordinates[0]) if len(coordinates) > 0 and coordinates[0] is not None else None,
                'LATITUDE': float(coordinates[1]) if len(coordinates) > 1 and coordinates[1] is not None else None,
                'DEPTH': float(coordinates[2]) if len(coordinates) > 2 and coordinates[2] is not None else None
            })

        # Step 4: Create a Snowpark DataFrame and insert into LANDING table
        df = session.create_dataframe(rows)

        # Truncate landing table before loading the new batch
        session.sql(f"TRUNCATE TABLE {landing_table}").collect()

        # Insert into landing table with DWH_CREATE_TIMESTAMP
        df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp()) \
          .write.mode("append") \
          .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS_LANDING"])

        # Step 5: On success, also append into the main table
        df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp()) \
          .write.mode("append") \
          .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS"])

        # Step 6: Determine the max event updated time for the new watermark
        max_updated = max(
            (r['UPDATED'] for r in rows if r['UPDATED'] is not None),
            default=None
        )

        # Update watermark in INGESTION_METADATA
        if max_updated:
            # Convert epoch ms to timestamp string
            max_updated_ts = datetime.utcfromtimestamp(max_updated / 1000).strftime('%Y-%m-%d %H:%M:%S')
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    LAST_UPDATED_TIME = '{max_updated_ts}'::TIMESTAMP_NTZ,
                    ROWS_INGESTED = {rows_ingested},
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()
        else:
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    ROWS_INGESTED = {rows_ingested},
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()

    except Exception as e:
        status = 'FAILURE'
        error_message = str(e).replace("'", "''")

        # Log the failure to INGESTION_METADATA
        session.sql(f"""
            UPDATE {metadata_table}
            SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                ROWS_INGESTED = 0,
                STATUS = 'FAILURE',
                ERROR_MESSAGE = '{error_message}'
            WHERE LOAD_ID = 'P1'
        """).collect()

        return f'FAILURE: {str(e)}'

    return f'SUCCESS: {rows_ingested} rows ingested.'
$$;

CREATE OR REPLACE PROCEDURE DWH_TEST.RAW.INGEST_USGS_EARTHQUAKES(
    DATABASE_NAME STRING,
    SCHEMA_NAME STRING
)
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    PACKAGES = ('snowflake-snowpark-python', 'requests')
    HANDLER = 'run'
    EXTERNAL_ACCESS_INTEGRATIONS = (USGS_EARTHQUAKE_ACCESS_INTEGRATION)
    EXECUTE AS CALLER
AS
$$
import requests
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import current_timestamp

def run(session: Session, database_name: str, schema_name: str) -> str:
    status = 'SUCCESS'
    error_message = None
    rows_ingested = 0

    # Build fully qualified table references
    landing_table = f"{database_name}.{schema_name}.USGS_EARTHQUAKES_FDSNWS_LANDING"
    main_table = f"{database_name}.{schema_name}.USGS_EARTHQUAKES_FDSNWS"
    metadata_table = f"{database_name}.ADMIN.INGESTION_METADATA"

    try:
        # Set session context for temporary object creation
        session.sql(f"USE DATABASE {database_name}").collect()
        session.sql(f"USE SCHEMA {schema_name}").collect()

        # Step 1: Get the watermark from INGESTION_METADATA
        watermark_df = session.sql(f"""
            SELECT COALESCE(
                TO_VARCHAR(LAST_UPDATED_TIME, 'YYYY-MM-DD"T"HH24:MI:SS'),
                '2026-01-01'
            ) AS START_TIME
            FROM {metadata_table}
            WHERE LOAD_ID = 'P1'
        """).collect()

        if watermark_df:
            start_time = watermark_df[0]['START_TIME']
        else:
            start_time = '2026-01-01'

        # Step 2: Query the USGS API
        url = 'https://earthquake.usgs.gov/fdsnws/event/1/query'
        params = {
            'format': 'geojson',
            'starttime': start_time,
            'minmagnitude': 5
        }

        response = requests.get(url, params=params, timeout=120)
        response.raise_for_status()
        data = response.json()

        features = data.get('features', [])
        rows_ingested = len(features)

        if rows_ingested == 0:
            # No new data — update metadata and return
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    ROWS_INGESTED = 0,
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()
            return 'SUCCESS: No new records to ingest.'

        # Step 3: Parse GeoJSON features into flat rows
        rows = []
        for feature in features:
            props = feature.get('properties', {})
            geometry = feature.get('geometry', {})
            coordinates = geometry.get('coordinates', [None, None, None])

            rows.append({
                'ID': feature.get('id'),
                'MAG': float(props['mag']) if props.get('mag') is not None else None,
                'PLACE': props.get('place'),
                'TIME': props.get('time'),
                'UPDATED': props.get('updated'),
                'TZ': props.get('tz'),
                'URL': props.get('url'),
                'DETAIL': props.get('detail'),
                'FELT': props.get('felt'),
                'CDI': float(props['cdi']) if props.get('cdi') is not None else None,
                'MMI': float(props['mmi']) if props.get('mmi') is not None else None,
                'ALERT': props.get('alert'),
                'STATUS': props.get('status'),
                'TSUNAMI': props.get('tsunami'),
                'SIG': props.get('sig'),
                'NET': props.get('net'),
                'CODE': props.get('code'),
                'IDS': props.get('ids'),
                'SOURCES': props.get('sources'),
                'TYPES': props.get('types'),
                'NST': props.get('nst'),
                'DMIN': float(props['dmin']) if props.get('dmin') is not None else None,
                'RMS': float(props['rms']) if props.get('rms') is not None else None,
                'GAP': float(props['gap']) if props.get('gap') is not None else None,
                'MAGTYPE': props.get('magType'),
                'TYPE': props.get('type'),
                'TITLE': props.get('title'),
                'LONGITUDE': float(coordinates[0]) if len(coordinates) > 0 and coordinates[0] is not None else None,
                'LATITUDE': float(coordinates[1]) if len(coordinates) > 1 and coordinates[1] is not None else None,
                'DEPTH': float(coordinates[2]) if len(coordinates) > 2 and coordinates[2] is not None else None
            })

        # Step 4: Create a Snowpark DataFrame and insert into LANDING table
        df = session.create_dataframe(rows)

        # Truncate landing table before loading the new batch
        session.sql(f"TRUNCATE TABLE {landing_table}").collect()

        # Insert into landing table with DWH_CREATE_TIMESTAMP
        df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp()) \
          .write.mode("append") \
          .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS_LANDING"])

        # Step 5: On success, also append into the main table
        df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp()) \
          .write.mode("append") \
          .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS"])

        # Step 6: Determine the max event updated time for the new watermark
        max_updated = max(
            (r['UPDATED'] for r in rows if r['UPDATED'] is not None),
            default=None
        )

        # Update watermark in INGESTION_METADATA
        if max_updated:
            # Convert epoch ms to timestamp string
            max_updated_ts = datetime.utcfromtimestamp(max_updated / 1000).strftime('%Y-%m-%d %H:%M:%S')
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    LAST_UPDATED_TIME = '{max_updated_ts}'::TIMESTAMP_NTZ,
                    ROWS_INGESTED = {rows_ingested},
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()
        else:
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    ROWS_INGESTED = {rows_ingested},
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()

    except Exception as e:
        status = 'FAILURE'
        error_message = str(e).replace("'", "''")

        # Log the failure to INGESTION_METADATA
        session.sql(f"""
            UPDATE {metadata_table}
            SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                ROWS_INGESTED = 0,
                STATUS = 'FAILURE',
                ERROR_MESSAGE = '{error_message}'
            WHERE LOAD_ID = 'P1'
        """).collect()

        return f'FAILURE: {str(e)}'

    return f'SUCCESS: {rows_ingested} rows ingested.'
$$;

CREATE OR REPLACE PROCEDURE DWH_PROD.RAW.INGEST_USGS_EARTHQUAKES(
    DATABASE_NAME STRING,
    SCHEMA_NAME STRING
)
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    PACKAGES = ('snowflake-snowpark-python', 'requests')
    HANDLER = 'run'
    EXTERNAL_ACCESS_INTEGRATIONS = (USGS_EARTHQUAKE_ACCESS_INTEGRATION)
    EXECUTE AS CALLER
AS
$$
import requests
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import current_timestamp

def run(session: Session, database_name: str, schema_name: str) -> str:
    status = 'SUCCESS'
    error_message = None
    rows_ingested = 0

    # Build fully qualified table references
    landing_table = f"{database_name}.{schema_name}.USGS_EARTHQUAKES_FDSNWS_LANDING"
    main_table = f"{database_name}.{schema_name}.USGS_EARTHQUAKES_FDSNWS"
    metadata_table = f"{database_name}.ADMIN.INGESTION_METADATA"

    try:
        # Set session context for temporary object creation
        session.sql(f"USE DATABASE {database_name}").collect()
        session.sql(f"USE SCHEMA {schema_name}").collect()

        # Step 1: Get the watermark from INGESTION_METADATA
        watermark_df = session.sql(f"""
            SELECT COALESCE(
                TO_VARCHAR(LAST_UPDATED_TIME, 'YYYY-MM-DD"T"HH24:MI:SS'),
                '2026-01-01'
            ) AS START_TIME
            FROM {metadata_table}
            WHERE LOAD_ID = 'P1'
        """).collect()

        if watermark_df:
            start_time = watermark_df[0]['START_TIME']
        else:
            start_time = '2026-01-01'

        # Step 2: Query the USGS API
        url = 'https://earthquake.usgs.gov/fdsnws/event/1/query'
        params = {
            'format': 'geojson',
            'starttime': start_time,
            'minmagnitude': 5
        }

        response = requests.get(url, params=params, timeout=120)
        response.raise_for_status()
        data = response.json()

        features = data.get('features', [])
        rows_ingested = len(features)

        if rows_ingested == 0:
            # No new data — update metadata and return
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    ROWS_INGESTED = 0,
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()
            return 'SUCCESS: No new records to ingest.'

        # Step 3: Parse GeoJSON features into flat rows
        rows = []
        for feature in features:
            props = feature.get('properties', {})
            geometry = feature.get('geometry', {})
            coordinates = geometry.get('coordinates', [None, None, None])

            rows.append({
                'ID': feature.get('id'),
                'MAG': float(props['mag']) if props.get('mag') is not None else None,
                'PLACE': props.get('place'),
                'TIME': props.get('time'),
                'UPDATED': props.get('updated'),
                'TZ': props.get('tz'),
                'URL': props.get('url'),
                'DETAIL': props.get('detail'),
                'FELT': props.get('felt'),
                'CDI': float(props['cdi']) if props.get('cdi') is not None else None,
                'MMI': float(props['mmi']) if props.get('mmi') is not None else None,
                'ALERT': props.get('alert'),
                'STATUS': props.get('status'),
                'TSUNAMI': props.get('tsunami'),
                'SIG': props.get('sig'),
                'NET': props.get('net'),
                'CODE': props.get('code'),
                'IDS': props.get('ids'),
                'SOURCES': props.get('sources'),
                'TYPES': props.get('types'),
                'NST': props.get('nst'),
                'DMIN': float(props['dmin']) if props.get('dmin') is not None else None,
                'RMS': float(props['rms']) if props.get('rms') is not None else None,
                'GAP': float(props['gap']) if props.get('gap') is not None else None,
                'MAGTYPE': props.get('magType'),
                'TYPE': props.get('type'),
                'TITLE': props.get('title'),
                'LONGITUDE': float(coordinates[0]) if len(coordinates) > 0 and coordinates[0] is not None else None,
                'LATITUDE': float(coordinates[1]) if len(coordinates) > 1 and coordinates[1] is not None else None,
                'DEPTH': float(coordinates[2]) if len(coordinates) > 2 and coordinates[2] is not None else None
            })

        # Step 4: Create a Snowpark DataFrame and insert into LANDING table
        df = session.create_dataframe(rows)

        # Truncate landing table before loading the new batch
        session.sql(f"TRUNCATE TABLE {landing_table}").collect()

        # Insert into landing table with DWH_CREATE_TIMESTAMP
        df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp()) \
          .write.mode("append") \
          .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS_LANDING"])

        # Step 5: On success, also append into the main table
        df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp()) \
          .write.mode("append") \
          .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS"])

        # Step 6: Determine the max event updated time for the new watermark
        max_updated = max(
            (r['UPDATED'] for r in rows if r['UPDATED'] is not None),
            default=None
        )

        # Update watermark in INGESTION_METADATA
        if max_updated:
            # Convert epoch ms to timestamp string
            max_updated_ts = datetime.utcfromtimestamp(max_updated / 1000).strftime('%Y-%m-%d %H:%M:%S')
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    LAST_UPDATED_TIME = '{max_updated_ts}'::TIMESTAMP_NTZ,
                    ROWS_INGESTED = {rows_ingested},
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()
        else:
            session.sql(f"""
                UPDATE {metadata_table}
                SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                    ROWS_INGESTED = {rows_ingested},
                    STATUS = 'SUCCESS',
                    ERROR_MESSAGE = NULL
                WHERE LOAD_ID = 'P1'
            """).collect()

    except Exception as e:
        status = 'FAILURE'
        error_message = str(e).replace("'", "''")

        # Log the failure to INGESTION_METADATA
        session.sql(f"""
            UPDATE {metadata_table}
            SET LAST_QUERY_TIME = CURRENT_TIMESTAMP(),
                ROWS_INGESTED = 0,
                STATUS = 'FAILURE',
                ERROR_MESSAGE = '{error_message}'
            WHERE LOAD_ID = 'P1'
        """).collect()

        return f'FAILURE: {str(e)}'

    return f'SUCCESS: {rows_ingested} rows ingested.'
$$;