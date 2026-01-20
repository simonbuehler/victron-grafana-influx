// Backfill victron -> victron_5m (5-minute aggregates)
// Parameterized for monthly blocks

import "date"

src = "victron"
dst = "victron_5m"
org = "wolke"

// ====== PARAMETERS: Adjust time range ======
// Examples:
// 1 month:  start = date.sub(d: 30d, from: now())
// 3 months: start = date.sub(d: 90d, from: now())
// Specific: start = 2025-11-01T00:00:00Z, stop = 2025-12-01T00:00:00Z
// ===========================================

// Time range (default: last month)
timeRange = duration(v: 30d)
stop = now()
start = date.sub(d: timeRange, from: stop)

// Alternative: Fixed time ranges (commented out)
// start = 2025-11-01T00:00:00Z
// stop = 2025-12-01T00:00:00Z

// ====== BACKFILL LOGIC ======

// power/voltage/current -> *_last
base =
  from(bucket: src)
    |> range(start: start, stop: stop)
    |> filter(fn:(r) => r._measurement == "ve_direct_battery" or r._measurement == "ve_direct_panel" or r._measurement == "ve_direct_load")
    |> filter(fn:(r) => r._field == "voltage" or r._field == "current" or r._field == "power")

lst =
  base
    |> aggregateWindow(every: 5m, fn: last, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: r._field + "_last" }))

// Status-Felder -> *_last
st =
  from(bucket: src)
    |> range(start: start, stop: stop)
    |> filter(fn:(r) =>
      (r._measurement == "ve_direct_victron" and (r._field == "CS_Status" or r._field == "ERR_Status" or r._field == "MPPT_Status")) or
      (r._measurement == "ve_direct_load" and r._field == "status")
    )
    |> aggregateWindow(every: 5m, fn: last, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: r._field + "_last" }))

// ve_direct_today: yield -> yield_last
tdy_y =
  from(bucket: src)
    |> range(start: start, stop: stop)
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "yield")
    |> aggregateWindow(every: 5m, fn: last, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: "yield_last" }))

// ve_direct_today: power -> power_max
tdy_p =
  from(bucket: src)
    |> range(start: start, stop: stop)
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "power")
    |> aggregateWindow(every: 5m, fn: max, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: "power_max" }))

union(tables: [lst, st, tdy_y, tdy_p])
  |> to(bucket: dst, org: org)
