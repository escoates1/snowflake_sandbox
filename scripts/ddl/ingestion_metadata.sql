USE ROLE ENGINEER;

CREATE TABLE IF NOT EXISTS DWH_DEV.ADMIN.INGESTION_METADATA (
    LOAD_ID INT AUTOINCREMENT START 1 INCREMENT 1 COMMENT 'Surrogate key that increments for each new batch inserted.',
    JOB_ID VARCHAR(10) COMMENT 'User-defined identifier for the specific load job.',
    SOURCE_NAME VARCHAR(50) NOT NULL COMMENT 'Name of the data source being loaded.',
    LAST_QUERY_TIME TIMESTAMP_NTZ COMMENT 'Time when the most recent query was executed.',
    LAST_UPDATED_TIME TIMESTAMP_NTZ COMMENT 'Time when the last record was updated i.e. the high watermark,',
    NEW_ROWS_INGESTED INT DEFAULT 0 COMMENT 'Number of rows ingested per batch.',
    STATUS VARCHAR(10) COMMENT 'The job completion status: SUCCESS, FAILURE, PROCESSING.',
    ERROR_MESSAGE VARCHAR(16777216) COMMENT 'Error message relating to a failure'
);

CREATE TABLE IF NOT EXISTS DWH_TEST.ADMIN.INGESTION_METADATA (
    LOAD_ID INT AUTOINCREMENT START 1 INCREMENT 1 COMMENT 'Surrogate key that increments for each new batch inserted.',
    JOB_ID VARCHAR(10) COMMENT 'User-defined identifier for the specific load job.',
    SOURCE_NAME VARCHAR(50) NOT NULL COMMENT 'Name of the data source being loaded.',
    LAST_QUERY_TIME TIMESTAMP_NTZ COMMENT 'Time when the most recent query was executed.',
    LAST_UPDATED_TIME TIMESTAMP_NTZ COMMENT 'Time when the last record was updated i.e. the high watermark,',
    NEW_ROWS_INGESTED INT DEFAULT 0 COMMENT 'Number of rows ingested per batch.',
    STATUS VARCHAR(10) COMMENT 'The job completion status: SUCCESS, FAILURE, PROCESSING.',
    ERROR_MESSAGE VARCHAR(16777216) COMMENT 'Error message relating to a failure'
);

CREATE TABLE IF NOT EXISTS DWH_PROD.ADMIN.INGESTION_METADATA (
    LOAD_ID INT AUTOINCREMENT START 1 INCREMENT 1 COMMENT 'Surrogate key that increments for each new batch inserted.',
    JOB_ID VARCHAR(10) COMMENT 'User-defined identifier for the specific load job.',
    SOURCE_NAME VARCHAR(50) NOT NULL COMMENT 'Name of the data source being loaded.',
    LAST_QUERY_TIME TIMESTAMP_NTZ COMMENT 'Time when the most recent query was executed.',
    LAST_UPDATED_TIME TIMESTAMP_NTZ COMMENT 'Time when the last record was updated i.e. the high watermark,',
    NEW_ROWS_INGESTED INT DEFAULT 0 COMMENT 'Number of rows ingested per batch.',
    STATUS VARCHAR(10) COMMENT 'The job completion status: SUCCESS, FAILURE, PROCESSING.',
    ERROR_MESSAGE VARCHAR(16777216) COMMENT 'Error message relating to a failure'
);