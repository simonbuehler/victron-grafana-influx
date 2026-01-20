option task = {name: "victron_downsample_5m", every: 5m}

src = "victron"
dst = "victron_5m"
org = "wolke"

// 15m overlap to prevent gaps from brief outages
start = -15m

// Only last aggregation for power/voltage/current
base =
  from(bucket: src)
    |> range(start: start)
    |> filter(fn:(r) => r._measurement == "ve_direct_battery" or r._measurement == "ve_direct_panel" or r._measurement == "ve_direct_load")
    |> filter(fn:(r) => r._field == "voltage" or r._field == "current" or r._field == "power")

lst =
  base
    |> aggregateWindow(every: 5m, fn: last, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: r._field + "_last" }))

// Status fields: last
st =
  from(bucket: src)
    |> range(start: start)
    |> filter(fn:(r) =>
      (r._measurement == "ve_direct_victron" and (r._field == "CS_Status" or r._field == "ERR_Status" or r._field == "MPPT_Status")) or
      (r._measurement == "ve_direct_load" and r._field == "status")
    )
    |> aggregateWindow(every: 5m, fn: last, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: r._field + "_last" }))

// ve_direct_today: yield (absoluter Counter) und power (Peak-Wert)
tdy_y =
  from(bucket: src)
    |> range(start: start)
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "yield")
    |> aggregateWindow(every: 5m, fn: last, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: "yield_last" }))

tdy_p =
  from(bucket: src)
    |> range(start: start)
    |> filter(fn:(r) => r._measurement == "ve_direct_today" and r._field == "power")
    |> aggregateWindow(every: 5m, fn: max, createEmpty: false)
    |> map(fn:(r) => ({ r with _field: "power_max" }))

union(tables: [lst, st, tdy_y, tdy_p])
  |> to(bucket: dst, org: org)
