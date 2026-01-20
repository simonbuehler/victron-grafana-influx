// Backfill victron_5m -> victron_1h (1-hour aggregates)
// Parameterized for monthly blocks

import "date"

src = "victron_5m"
dst = "victron_1h"
org = "wolke"

// ====== PARAMETERS: Adjust time range ======
// IMPORTANT: Execute AFTER 5m backfill!
// Must be identical to backfill_5m_monthly.flux!
// ===========================================

// Time range (default: last month)
timeRange = duration(v: 30d)
stop = now()
start = date.sub(d: timeRange, from: stop)

// Alternative: Fixed time ranges (commented out)
// start = 2025-11-01T00:00:00Z
// stop = 2025-12-01T00:00:00Z

// ====== BACKFILL LOGIC ======

base =
  from(bucket: src)
    |> range(start: start, stop: stop)

// power/voltage/current *_last -> *_last
gauges =
  base
    |> filter(fn:(r) => r._measurement == "ve_direct_battery" or r._measurement == "ve_direct_panel" or r._measurement == "ve_direct_load")
    |> filter(fn:(r) => r._field == "voltage_last" or r._field == "current_last" or r._field == "power_last")

g_last =
  gauges
    |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

// Status *_last -> *_last
st =
  base
    |> filter(fn:(r) =>
      (r._measurement == "ve_direct_victron" and (r._field == "CS_Status_last" or r._field == "ERR_Status_last" or r._field == "MPPT_Status_last")) or
      (r._measurement == "ve_direct_load" and r._field == "status_last")
    )
    |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

// ve_direct_today: yield_last -> yield_last
tdy_y =
  base
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "yield_last")
    |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

// ve_direct_today: power_max -> power_max
tdy_p =
  base
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "power_max")
    |> aggregateWindow(every: 1h, fn: max, createEmpty: false)

union(tables: [g_last, st, tdy_y, tdy_p])
  |> to(bucket: dst, org: org)
