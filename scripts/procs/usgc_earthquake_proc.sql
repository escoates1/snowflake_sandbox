USE ROLE ENGINEER;

-- Stored procedure to ingest USGS earthquake data, generated for DEV/TEST/PROD
-- Staging data in a landing table (USGS_EARTHQUAKES_FDSNWS_LANDING) before inserting into the main table (USGS_EARTHQUAKES_FDSNWS)
-- Logs audit records into the INGESTION_METADATA table in the ADMIN schema of the specified database

-- ============================================================
-- DWH_DEV
-- ============================================================
CREATE OR REPLACE PROCEDURE DWH_DEV.RAW.INGEST_USGS_EARTHQUAKES("DATABASE_NAME" VARCHAR, "SCHEMA_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python','requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (USGS_EARTHQUAKE_ACCESS_INTEGRATION)
EXECUTE AS CALLER
AS '
import requests
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import current_timestamp

def run(session: Session, database_name: str, schema_name: str) -> str:
    status = ''SUCCESS''
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

        # Step 1: Get the watermark from the most recent successful metadata row
        watermark_df = session.sql(f"""
            SELECT COALESCE(
                TO_VARCHAR(LAST_UPDATED_TIME, ''YYYY-MM-DD"T"HH24:MI:SS''),
                ''2026-01-01''
            ) AS START_TIME,
            LAST_UPDATED_TIME
            FROM {metadata_table}
            WHERE JOB_ID = ''P1''
              AND SOURCE_NAME = ''USGC_EARTHQUAKES''
              AND STATUS = ''SUCCESS''
            ORDER BY LOAD_ID DESC
            LIMIT 1
        """).collect()

        if watermark_df:
            start_time = watermark_df[0][''START_TIME'']
            previous_watermark = watermark_df[0][''LAST_UPDATED_TIME'']
        else:
            start_time = ''2026-01-01''
            previous_watermark = None

        # Step 2: Query the USGS API
        url = ''https://earthquake.usgs.gov/fdsnws/event/1/query''
        params = {
            ''format'': ''geojson'',
            ''starttime'': start_time,
            ''minmagnitude'': 5
        }

        response = requests.get(url, params=params, timeout=120)
        response.raise_for_status()
        data = response.json()

        features = data.get(''features'', [])
        rows_ingested = len(features)

        if rows_ingested == 0:
            # No new data — carry forward the previous watermark
            prev_wm_clause = f"''{previous_watermark}''::TIMESTAMP_NTZ" if previous_watermark else "NULL"
            session.sql(f"""
                INSERT INTO {metadata_table}
                    (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                     NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
                VALUES
                    (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), {prev_wm_clause},
                     0, ''SUCCESS'', NULL)
            """).collect()
            return ''SUCCESS: No new records to ingest.''

        # Step 3: Parse GeoJSON features into flat rows
        rows = []
        for feature in features:
            props = feature.get(''properties'', {})
            geometry = feature.get(''geometry'', {})
            coordinates = geometry.get(''coordinates'', [None, None, None])

            rows.append({
                ''ID'': feature.get(''id''),
                ''MAG'': float(props[''mag'']) if props.get(''mag'') is not None else None,
                ''PLACE'': props.get(''place''),
                ''TIME'': props.get(''time''),
                ''UPDATED'': props.get(''updated''),
                ''TZ'': props.get(''tz''),
                ''URL'': props.get(''url''),
                ''DETAIL'': props.get(''detail''),
                ''FELT'': props.get(''felt''),
                ''CDI'': float(props[''cdi'']) if props.get(''cdi'') is not None else None,
                ''MMI'': float(props[''mmi'']) if props.get(''mmi'') is not None else None,
                ''ALERT'': props.get(''alert''),
                ''STATUS'': props.get(''status''),
                ''TSUNAMI'': props.get(''tsunami''),
                ''SIG'': props.get(''sig''),
                ''NET'': props.get(''net''),
                ''CODE'': props.get(''code''),
                ''IDS'': props.get(''ids''),
                ''SOURCES'': props.get(''sources''),
                ''TYPES'': props.get(''types''),
                ''NST'': props.get(''nst''),
                ''DMIN'': float(props[''dmin'']) if props.get(''dmin'') is not None else None,
                ''RMS'': float(props[''rms'']) if props.get(''rms'') is not None else None,
                ''GAP'': float(props[''gap'']) if props.get(''gap'') is not None else None,
                ''MAGTYPE'': props.get(''magType''),
                ''TYPE'': props.get(''type''),
                ''TITLE'': props.get(''title''),
                ''LONGITUDE'': float(coordinates[0]) if len(coordinates) > 0 and coordinates[0] is not None else None,
                ''LATITUDE'': float(coordinates[1]) if len(coordinates) > 1 and coordinates[1] is not None else None,
                ''DEPTH'': float(coordinates[2]) if len(coordinates) > 2 and coordinates[2] is not None else None
            })

        # Step 4: Create a Snowpark DataFrame and insert into LANDING table
        df = session.create_dataframe(rows)

        # Truncate landing table before loading the new batch
        session.sql(f"TRUNCATE TABLE {landing_table}").collect()

        # Insert into landing table with DWH_CREATE_TIMESTAMP
        (df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp())
           .write.mode("append")
           .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS_LANDING"]))

        # Step 5: Insert into main table, skipping any IDs that already exist
        insert_result = session.sql(f"""
            INSERT INTO {main_table}
            SELECT src.*
            FROM {landing_table} src
            WHERE src.ID NOT IN (SELECT ID FROM {main_table})
        """).collect()
        actual_new_rows = insert_result[0][''number of rows inserted''] if insert_result and ''number of rows inserted'' in insert_result[0].as_dict() else rows_ingested

        # Step 6: Determine the max event time for the new watermark
        # Add 1 second so the inclusive starttime filter excludes this boundary event next run
        max_event_time = max(
            (r[''TIME''] for r in rows if r[''TIME''] is not None),
            default=None
        )

        max_time_clause = "NULL"
        if max_event_time:
            max_time_ts = datetime.utcfromtimestamp((max_event_time / 1000) + 1).strftime(''%Y-%m-%d %H:%M:%S'')
            max_time_clause = f"''{max_time_ts}''::TIMESTAMP_NTZ"

        # Insert metadata row for this run
        session.sql(f"""
            INSERT INTO {metadata_table}
                (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                 NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
            VALUES
                (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), {max_time_clause},
                 {actual_new_rows}, ''SUCCESS'', NULL)
        """).collect()

    except Exception as e:
        status = ''FAILURE''
        error_message = str(e).replace("''", "''''")

        # Log the failure to INGESTION_METADATA
        session.sql(f"""
            INSERT INTO {metadata_table}
                (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                 NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
            VALUES
                (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), NULL,
                 0, ''FAILURE'', ''{error_message}'')
        """).collect()

        return f''FAILURE: {str(e)}''

    return f''SUCCESS: {actual_new_rows} rows ingested.''
';

-- ============================================================
-- DWH_TEST
-- ============================================================
CREATE OR REPLACE PROCEDURE DWH_TEST.RAW.INGEST_USGS_EARTHQUAKES("DATABASE_NAME" VARCHAR, "SCHEMA_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python','requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (USGS_EARTHQUAKE_ACCESS_INTEGRATION)
EXECUTE AS CALLER
AS '
import requests
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import current_timestamp

def run(session: Session, database_name: str, schema_name: str) -> str:
    status = ''SUCCESS''
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

        # Step 1: Get the watermark from the most recent successful metadata row
        watermark_df = session.sql(f"""
            SELECT COALESCE(
                TO_VARCHAR(LAST_UPDATED_TIME, ''YYYY-MM-DD"T"HH24:MI:SS''),
                ''2026-01-01''
            ) AS START_TIME,
            LAST_UPDATED_TIME
            FROM {metadata_table}
            WHERE JOB_ID = ''P1''
              AND SOURCE_NAME = ''USGC_EARTHQUAKES''
              AND STATUS = ''SUCCESS''
            ORDER BY LOAD_ID DESC
            LIMIT 1
        """).collect()

        if watermark_df:
            start_time = watermark_df[0][''START_TIME'']
            previous_watermark = watermark_df[0][''LAST_UPDATED_TIME'']
        else:
            start_time = ''2026-01-01''
            previous_watermark = None

        # Step 2: Query the USGS API
        url = ''https://earthquake.usgs.gov/fdsnws/event/1/query''
        params = {
            ''format'': ''geojson'',
            ''starttime'': start_time,
            ''minmagnitude'': 5
        }

        response = requests.get(url, params=params, timeout=120)
        response.raise_for_status()
        data = response.json()

        features = data.get(''features'', [])
        rows_ingested = len(features)

        if rows_ingested == 0:
            # No new data — carry forward the previous watermark
            prev_wm_clause = f"''{previous_watermark}''::TIMESTAMP_NTZ" if previous_watermark else "NULL"
            session.sql(f"""
                INSERT INTO {metadata_table}
                    (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                     NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
                VALUES
                    (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), {prev_wm_clause},
                     0, ''SUCCESS'', NULL)
            """).collect()
            return ''SUCCESS: No new records to ingest.''

        # Step 3: Parse GeoJSON features into flat rows
        rows = []
        for feature in features:
            props = feature.get(''properties'', {})
            geometry = feature.get(''geometry'', {})
            coordinates = geometry.get(''coordinates'', [None, None, None])

            rows.append({
                ''ID'': feature.get(''id''),
                ''MAG'': float(props[''mag'']) if props.get(''mag'') is not None else None,
                ''PLACE'': props.get(''place''),
                ''TIME'': props.get(''time''),
                ''UPDATED'': props.get(''updated''),
                ''TZ'': props.get(''tz''),
                ''URL'': props.get(''url''),
                ''DETAIL'': props.get(''detail''),
                ''FELT'': props.get(''felt''),
                ''CDI'': float(props[''cdi'']) if props.get(''cdi'') is not None else None,
                ''MMI'': float(props[''mmi'']) if props.get(''mmi'') is not None else None,
                ''ALERT'': props.get(''alert''),
                ''STATUS'': props.get(''status''),
                ''TSUNAMI'': props.get(''tsunami''),
                ''SIG'': props.get(''sig''),
                ''NET'': props.get(''net''),
                ''CODE'': props.get(''code''),
                ''IDS'': props.get(''ids''),
                ''SOURCES'': props.get(''sources''),
                ''TYPES'': props.get(''types''),
                ''NST'': props.get(''nst''),
                ''DMIN'': float(props[''dmin'']) if props.get(''dmin'') is not None else None,
                ''RMS'': float(props[''rms'']) if props.get(''rms'') is not None else None,
                ''GAP'': float(props[''gap'']) if props.get(''gap'') is not None else None,
                ''MAGTYPE'': props.get(''magType''),
                ''TYPE'': props.get(''type''),
                ''TITLE'': props.get(''title''),
                ''LONGITUDE'': float(coordinates[0]) if len(coordinates) > 0 and coordinates[0] is not None else None,
                ''LATITUDE'': float(coordinates[1]) if len(coordinates) > 1 and coordinates[1] is not None else None,
                ''DEPTH'': float(coordinates[2]) if len(coordinates) > 2 and coordinates[2] is not None else None
            })

        # Step 4: Create a Snowpark DataFrame and insert into LANDING table
        df = session.create_dataframe(rows)

        # Truncate landing table before loading the new batch
        session.sql(f"TRUNCATE TABLE {landing_table}").collect()

        # Insert into landing table with DWH_CREATE_TIMESTAMP
        (df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp())
           .write.mode("append")
           .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS_LANDING"]))

        # Step 5: Insert into main table, skipping any IDs that already exist
        insert_result = session.sql(f"""
            INSERT INTO {main_table}
            SELECT src.*
            FROM {landing_table} src
            WHERE src.ID NOT IN (SELECT ID FROM {main_table})
        """).collect()
        actual_new_rows = insert_result[0][''number of rows inserted''] if insert_result and ''number of rows inserted'' in insert_result[0].as_dict() else rows_ingested

        # Step 6: Determine the max event time for the new watermark
        # Add 1 second so the inclusive starttime filter excludes this boundary event next run
        max_event_time = max(
            (r[''TIME''] for r in rows if r[''TIME''] is not None),
            default=None
        )

        max_time_clause = "NULL"
        if max_event_time:
            max_time_ts = datetime.utcfromtimestamp((max_event_time / 1000) + 1).strftime(''%Y-%m-%d %H:%M:%S'')
            max_time_clause = f"''{max_time_ts}''::TIMESTAMP_NTZ"

        # Insert metadata row for this run
        session.sql(f"""
            INSERT INTO {metadata_table}
                (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                 NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
            VALUES
                (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), {max_time_clause},
                 {actual_new_rows}, ''SUCCESS'', NULL)
        """).collect()

    except Exception as e:
        status = ''FAILURE''
        error_message = str(e).replace("''", "''''")

        # Log the failure to INGESTION_METADATA
        session.sql(f"""
            INSERT INTO {metadata_table}
                (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                 NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
            VALUES
                (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), NULL,
                 0, ''FAILURE'', ''{error_message}'')
        """).collect()

        return f''FAILURE: {str(e)}''

    return f''SUCCESS: {actual_new_rows} rows ingested.''
';

-- ============================================================
-- DWH_PROD
-- ============================================================
CREATE OR REPLACE PROCEDURE DWH_PROD.RAW.INGEST_USGS_EARTHQUAKES("DATABASE_NAME" VARCHAR, "SCHEMA_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python','requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (USGS_EARTHQUAKE_ACCESS_INTEGRATION)
EXECUTE AS CALLER
AS '
import requests
import json
from datetime import datetime
from snowflake.snowpark import Session
from snowflake.snowpark.functions import current_timestamp

def run(session: Session, database_name: str, schema_name: str) -> str:
    status = ''SUCCESS''
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

        # Step 1: Get the watermark from the most recent successful metadata row
        watermark_df = session.sql(f"""
            SELECT COALESCE(
                TO_VARCHAR(LAST_UPDATED_TIME, ''YYYY-MM-DD"T"HH24:MI:SS''),
                ''2026-01-01''
            ) AS START_TIME,
            LAST_UPDATED_TIME
            FROM {metadata_table}
            WHERE JOB_ID = ''P1''
              AND SOURCE_NAME = ''USGC_EARTHQUAKES''
              AND STATUS = ''SUCCESS''
            ORDER BY LOAD_ID DESC
            LIMIT 1
        """).collect()

        if watermark_df:
            start_time = watermark_df[0][''START_TIME'']
            previous_watermark = watermark_df[0][''LAST_UPDATED_TIME'']
        else:
            start_time = ''2026-01-01''
            previous_watermark = None

        # Step 2: Query the USGS API
        url = ''https://earthquake.usgs.gov/fdsnws/event/1/query''
        params = {
            ''format'': ''geojson'',
            ''starttime'': start_time,
            ''minmagnitude'': 5
        }

        response = requests.get(url, params=params, timeout=120)
        response.raise_for_status()
        data = response.json()

        features = data.get(''features'', [])
        rows_ingested = len(features)

        if rows_ingested == 0:
            # No new data — carry forward the previous watermark
            prev_wm_clause = f"''{previous_watermark}''::TIMESTAMP_NTZ" if previous_watermark else "NULL"
            session.sql(f"""
                INSERT INTO {metadata_table}
                    (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                     NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
                VALUES
                    (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), {prev_wm_clause},
                     0, ''SUCCESS'', NULL)
            """).collect()
            return ''SUCCESS: No new records to ingest.''

        # Step 3: Parse GeoJSON features into flat rows
        rows = []
        for feature in features:
            props = feature.get(''properties'', {})
            geometry = feature.get(''geometry'', {})
            coordinates = geometry.get(''coordinates'', [None, None, None])

            rows.append({
                ''ID'': feature.get(''id''),
                ''MAG'': float(props[''mag'']) if props.get(''mag'') is not None else None,
                ''PLACE'': props.get(''place''),
                ''TIME'': props.get(''time''),
                ''UPDATED'': props.get(''updated''),
                ''TZ'': props.get(''tz''),
                ''URL'': props.get(''url''),
                ''DETAIL'': props.get(''detail''),
                ''FELT'': props.get(''felt''),
                ''CDI'': float(props[''cdi'']) if props.get(''cdi'') is not None else None,
                ''MMI'': float(props[''mmi'']) if props.get(''mmi'') is not None else None,
                ''ALERT'': props.get(''alert''),
                ''STATUS'': props.get(''status''),
                ''TSUNAMI'': props.get(''tsunami''),
                ''SIG'': props.get(''sig''),
                ''NET'': props.get(''net''),
                ''CODE'': props.get(''code''),
                ''IDS'': props.get(''ids''),
                ''SOURCES'': props.get(''sources''),
                ''TYPES'': props.get(''types''),
                ''NST'': props.get(''nst''),
                ''DMIN'': float(props[''dmin'']) if props.get(''dmin'') is not None else None,
                ''RMS'': float(props[''rms'']) if props.get(''rms'') is not None else None,
                ''GAP'': float(props[''gap'']) if props.get(''gap'') is not None else None,
                ''MAGTYPE'': props.get(''magType''),
                ''TYPE'': props.get(''type''),
                ''TITLE'': props.get(''title''),
                ''LONGITUDE'': float(coordinates[0]) if len(coordinates) > 0 and coordinates[0] is not None else None,
                ''LATITUDE'': float(coordinates[1]) if len(coordinates) > 1 and coordinates[1] is not None else None,
                ''DEPTH'': float(coordinates[2]) if len(coordinates) > 2 and coordinates[2] is not None else None
            })

        # Step 4: Create a Snowpark DataFrame and insert into LANDING table
        df = session.create_dataframe(rows)

        # Truncate landing table before loading the new batch
        session.sql(f"TRUNCATE TABLE {landing_table}").collect()

        # Insert into landing table with DWH_CREATE_TIMESTAMP
        (df.with_column("DWH_CREATE_TIMESTAMP", current_timestamp())
           .write.mode("append")
           .save_as_table([database_name, schema_name, "USGS_EARTHQUAKES_FDSNWS_LANDING"]))

        # Step 5: Insert into main table, skipping any IDs that already exist
        insert_result = session.sql(f"""
            INSERT INTO {main_table}
            SELECT src.*
            FROM {landing_table} src
            WHERE src.ID NOT IN (SELECT ID FROM {main_table})
        """).collect()
        actual_new_rows = insert_result[0][''number of rows inserted''] if insert_result and ''number of rows inserted'' in insert_result[0].as_dict() else rows_ingested

        # Step 6: Determine the max event time for the new watermark
        # Add 1 second so the inclusive starttime filter excludes this boundary event next run
        max_event_time = max(
            (r[''TIME''] for r in rows if r[''TIME''] is not None),
            default=None
        )

        max_time_clause = "NULL"
        if max_event_time:
            max_time_ts = datetime.utcfromtimestamp((max_event_time / 1000) + 1).strftime(''%Y-%m-%d %H:%M:%S'')
            max_time_clause = f"''{max_time_ts}''::TIMESTAMP_NTZ"

        # Insert metadata row for this run
        session.sql(f"""
            INSERT INTO {metadata_table}
                (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                 NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
            VALUES
                (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), {max_time_clause},
                 {actual_new_rows}, ''SUCCESS'', NULL)
        """).collect()

    except Exception as e:
        status = ''FAILURE''
        error_message = str(e).replace("''", "''''")

        # Log the failure to INGESTION_METADATA
        session.sql(f"""
            INSERT INTO {metadata_table}
                (JOB_ID, SOURCE_NAME, LAST_QUERY_TIME, LAST_UPDATED_TIME,
                 NEW_ROWS_INGESTED, STATUS, ERROR_MESSAGE)
            VALUES
                (''P1'', ''USGC_EARTHQUAKES'', CURRENT_TIMESTAMP(), NULL,
                 0, ''FAILURE'', ''{error_message}'')
        """).collect()

        return f''FAILURE: {str(e)}''

    return f''SUCCESS: {actual_new_rows} rows ingested.''
';
