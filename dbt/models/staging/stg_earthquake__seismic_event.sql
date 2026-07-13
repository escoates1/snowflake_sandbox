WITH source AS (
    SELECT *
    FROM {{ source('usgs_earthquake', 'earthquakes') }}
)

select
   id as event_id,
   time as unix_timestamp,
   url as event_url,
   detail as detail_url,
   latitude,
   longitude,
   depth as depth_in_km,
   mag as magnitude,
   place as location,
   felt,
   cdi,
   mmi,
   sig as significance,
   nst as num_stations,
   dmin as dmin_deg,
   rms as rms_sec,
   gap as azimuthal_gap_deg,
   type,
   magtype,
   alert,
   tsunami
from source