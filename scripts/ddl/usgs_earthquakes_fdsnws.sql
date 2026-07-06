CREATE TABLE IF NOT EXISTS DWH_DEV.RAW.USGS_EARTHQUAKES_FDSNWS (
    -- Event identifier
    ID                      VARCHAR(50)     COMMENT 'Unique event identifier',

    -- Properties from GeoJSON features
    MAG                     FLOAT           COMMENT 'Magnitude of the earthquake',
    PLACE                   VARCHAR(256)    COMMENT 'Textual description of named geographic region near the event',
    TIME                    BIGINT          COMMENT 'Time when the event occurred (epoch milliseconds)',
    UPDATED                 BIGINT          COMMENT 'Time when the event was most recently updated (epoch milliseconds)',
    TZ                      INT             COMMENT 'Timezone offset from UTC in minutes (deprecated)',
    URL                     VARCHAR(512)    COMMENT 'Link to USGS event page',
    DETAIL                  VARCHAR(512)    COMMENT 'Link to GeoJSON detail feed',
    FELT                    INT             COMMENT 'Number of felt reports submitted',
    CDI                     FLOAT           COMMENT 'Maximum reported community decimal intensity',
    MMI                     FLOAT           COMMENT 'Maximum estimated instrumental intensity',
    ALERT                   VARCHAR(10)     COMMENT 'Alert level: green, yellow, orange, or red',
    STATUS                  VARCHAR(20)     COMMENT 'Indicates whether event has been reviewed: automatic or reviewed',
    TSUNAMI                 INT             COMMENT 'Flag: 1 if event is in the tsunami event list',
    SIG                     INT             COMMENT 'A number indicating how significant the event is (0-1000)',
    NET                     VARCHAR(10)     COMMENT 'ID of the preferred data contributor network',
    CODE                    VARCHAR(50)     COMMENT 'Identifying code assigned by the source network',
    IDS                     VARCHAR(256)    COMMENT 'Comma-separated list of event IDs associated with the event',
    SOURCES                 VARCHAR(256)    COMMENT 'Comma-separated list of network contributors',
    TYPES                   VARCHAR(512)    COMMENT 'Comma-separated list of product types associated with the event',
    NST                     INT             COMMENT 'Total number of seismic stations used to determine location',
    DMIN                    FLOAT           COMMENT 'Horizontal distance to nearest station (degrees)',
    RMS                     FLOAT           COMMENT 'Root-mean-square travel time residual (seconds)',
    GAP                     FLOAT           COMMENT 'Largest azimuthal gap between adjacent stations (degrees)',
    MAGTYPE                 VARCHAR(10)     COMMENT 'Method used to calculate the magnitude (e.g. ml, md, mb, mw)',
    TYPE                    VARCHAR(20)     COMMENT 'Type of seismic event (e.g. earthquake, quarry)',
    TITLE                   VARCHAR(256)    COMMENT 'Title generated from magnitude and place',

    -- Geometry (flattened from coordinates array: [longitude, latitude, depth])
    LONGITUDE               FLOAT           COMMENT 'Decimal degrees longitude (negative values for western longitudes)',
    LATITUDE                FLOAT           COMMENT 'Decimal degrees latitude (negative values for southern latitudes)',
    DEPTH                   FLOAT           COMMENT 'Depth of the event in kilometers',

    -- Data warehouse audit column
    DWH_CREATE_TIMESTAMP    TIMESTAMP_LTZ   DEFAULT CURRENT_TIMESTAMP() COMMENT 'Timestamp when the row was inserted into the table'
)
COMMENT = 'Staging table for USGS Earthquake FDSNWS GeoJSON API data (magnitude >= 5), containing all records from all previous batches.';