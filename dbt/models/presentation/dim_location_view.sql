select 
    location_key,
    region,
    country,
    lat_hemisphere,
    lon_hemisphere
from {{ ref('dim_location') }}