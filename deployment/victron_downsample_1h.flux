option task = {name: "victron_downsample_1h", every: 1h}

src = "victron_5m"
dst = "victron_1h"
org = "wolke"

// 3h overlap to prevent gaps
start = -3h

base =
  from(bucket: src)
    |> range(start: start)

// Only last aggregation for power/voltage/current
gauges =
  base
    |> filter(fn:(r) => r._measurement == "ve_direct_battery" or r._measurement == "ve_direct_panel" or r._measurement == "ve_direct_load")
    |> filter(fn:(r) => r._field == "voltage_last" or r._field == "current_last" or r._field == "power_last")

g_last =
  gauges
    |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

// Status stays discrete -> last
st =
  base
    |> filter(fn:(r) =>
      (r._measurement == "ve_direct_victron" and (r._field == "CS_Status_last" or r._field == "ERR_Status_last" or r._field == "MPPT_Status_last")) or
      (r._measurement == "ve_direct_load" and r._field == "status_last")
    )
    |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

// Today: yield_last stays last; power_max stays max
tdy_y =
  base
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "yield_last")
    |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

tdy_p =
  base
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "power_max")
    |> aggregateWindow(every: 1h, fn: max, createEmpty: false)

union(tables: [g_last, st, tdy_y, tdy_p])
  |> to(bucket: dst, org: org)
