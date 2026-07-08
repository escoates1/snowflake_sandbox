WITH source AS (
    SELECT *
    FROM {{ source('usgs_earthquake', 'earthquakes') }}
),

refined as (
    select
        place,
        latitude,
        longitude,
        time
    from source
)

select *
from refined