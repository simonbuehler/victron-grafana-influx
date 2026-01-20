#!/bin/bash
# Backfill script for complete history in monthly blocks
# Usage: ./backfill_history.sh <start-date> <months>
# Example: ./backfill_history.sh 2024-01-01 12

set -e

START_DATE=${1:-"2024-01-01"}
MONTHS=${2:-6}
ORG="wolke"

echo "=== Victron Downsample Backfill ==="
echo "Start: $START_DATE"
echo "Months: $MONTHS"
echo "=================================="

# Function: Backfill for one month
backfill_month() {
    local start=$1
    local stop=$2
    
    echo ""
    echo ">>> Backfill period: $start to $stop"
    
    # Stage 1: victron -> victron_5m
    echo "  [1/2] victron -> victron_5m (5min aggregates)"
    influx query --org "$ORG" "
import \"date\"
src = \"victron\"
dst = \"victron_5m\"
org = \"$ORG\"
start = $start
stop = $stop

base = from(bucket: src) |> range(start: start, stop: stop) |> filter(fn:(r) => r._measurement == \"ve_direct_battery\" or r._measurement == \"ve_direct_panel\" or r._measurement == \"ve_direct_load\") |> filter(fn:(r) => r._field == \"voltage\" or r._field == \"current\" or r._field == \"power\")
lst = base |> aggregateWindow(every: 5m, fn: last, createEmpty: false) |> map(fn:(r) => ({ r with _field: r._field + \"_last\" }))

st = from(bucket: src) |> range(start: start, stop: stop) |> filter(fn:(r) => (r._measurement == \"ve_direct_victron\" and (r._field == \"CS_Status\" or r._field == \"ERR_Status\" or r._field == \"MPPT_Status\")) or (r._measurement == \"ve_direct_load\" and r._field == \"status\")) |> aggregateWindow(every: 5m, fn: last, createEmpty: false) |> map(fn:(r) => ({ r with _field: r._field + \"_last\" }))

tdy_y = from(bucket: src) |> range(start: start, stop: stop) |> filter(fn:(r) => r._measurement == \"ve_direct_today\" and r._field == \"yield\") |> aggregateWindow(every: 5m, fn: last, createEmpty: false) |> map(fn:(r) => ({ r with _field: \"yield_last\" }))

tdy_p = from(bucket: src) |> range(start: start, stop: stop) |> filter(fn:(r) => r._measurement == \"ve_direct_today\" and r._field == \"power\") |> aggregateWindow(every: 5m, fn: max, createEmpty: false) |> map(fn:(r) => ({ r with _field: \"power_max\" }))

union(tables: [lst, st, tdy_y, tdy_p]) |> to(bucket: dst, org: org)
" || { echo "ERROR during 5m backfill"; exit 1; }
    
    # Stage 2: victron_5m -> victron_1h
    echo "  [2/2] victron_5m -> victron_1h (1h aggregates)"
    influx query --org "$ORG" "
import \"date\"
src = \"victron_5m\"
dst = \"victron_1h\"
org = \"$ORG\"
start = $start
stop = $stop

base = from(bucket: src) |> range(start: start, stop: stop)

gauges = base |> filter(fn:(r) => r._measurement == \"ve_direct_battery\" or r._measurement == \"ve_direct_panel\" or r._measurement == \"ve_direct_load\") |> filter(fn:(r) => r._field == \"voltage_last\" or r._field == \"current_last\" or r._field == \"power_last\")
g_last = gauges |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

st = base |> filter(fn:(r) => (r._measurement == \"ve_direct_victron\" and (r._field == \"CS_Status_last\" or r._field == \"ERR_Status_last\" or r._field == \"MPPT_Status_last\")) or (r._measurement == \"ve_direct_load\" and r._field == \"status_last\")) |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

tdy_y = base |> filter(fn:(r) => r._measurement == \"ve_direct_today\" and r._field == \"yield_last\") |> aggregateWindow(every: 1h, fn: last, createEmpty: false)

tdy_p = base |> filter(fn:(r) => r._measurement == \"ve_direct_today\" and r._field == \"power_max\") |> aggregateWindow(every: 1h, fn: max, createEmpty: false)

union(tables: [g_last, st, tdy_y, tdy_p]) |> to(bucket: dst, org: org)
" || { echo "ERROR during 1h backfill"; exit 1; }
    
    echo "  ✓ Month completed"
}

# Loop through all months
current_date=$(date -d "$START_DATE" +%Y-%m-%d)
for ((i=0; i<$MONTHS; i++)); do
    start_ts="$(date -d "$current_date" --iso-8601=seconds)"
    next_month=$(date -d "$current_date + 1 month" +%Y-%m-%d)
    stop_ts="$(date -d "$next_month" --iso-8601=seconds)"
    
    backfill_month "$start_ts" "$stop_ts"
    
    current_date=$next_month
done

echo ""
echo "=================================="
echo "✓ Backfill completed!"
echo "  Period: $START_DATE to $(date -d "$current_date" +%Y-%m-%d)"
echo "  Months: $MONTHS"
echo "=================================="
