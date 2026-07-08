WITH source AS (
    SELECT *
    FROM {{ source('usgs_earthquake', 'earthquakes') }}
),

refined as (
    select
        alert,
        status,
        tsunami,
        felt,
        time
    from source
)

select *
from refined