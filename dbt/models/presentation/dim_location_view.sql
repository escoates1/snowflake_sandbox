select 
    location_key,
    location,
    region,
    country,
    lat_hemisphere,
    lon_hemisphere
from {{ ref('dim_location') }}