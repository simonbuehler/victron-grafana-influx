# Backfill Scripts - Guide

## Overview

Two variants for backfill operations:

### 1. Monthly Scripts (parameterized)

- `backfill_5m_monthly.flux` - Adjustable time range
- `backfill_1h_monthly.flux` - Adjustable time range
- **Usage:** Flexible backfill for any time range

### 2. Automated Script (Linux/Bash)

- `backfill_history.sh` - Automatic backfill in monthly blocks
- **Usage:** Complete history on new server

---

## Scenario 1: Single Time Range (e.g., last month)

### Example: November 2025

1. Open `backfill_5m_monthly.flux`
2. Change lines 15-16:
   ```flux
   start = 2025-11-01T00:00:00Z
   stop = 2025-12-01T00:00:00Z
   ```
3. Execute in InfluxDB Data Explorer
4. Repeat with `backfill_1h_monthly.flux` (identical times!)

### Example: Last 60 Days

Change line 18:

```flux
timeRange = duration(v: 60d)
```

**Duration:** ~5-10 minutes (depending on data volume)

---

## Scenario 2: New Server / Complete History

### Variant A: Automated Script (Linux)

```bash
cd backfill/
chmod +x backfill_history.sh

# Backfill from January 2024, 12 months
./backfill_history.sh 2024-01-01 12

# Backfill from any date
./backfill_history.sh 2023-06-01 18
```

**Advantages:**

- Automatic loop through all months
- Error handling
- Progress display

**Duration:** ~1-2 hours for 12 months (depending on hardware)

### Variant B: Manual (Month by Month)

1. Create list of months:

   ```
   2024-01: 2024-01-01 to 2024-02-01
   2024-02: 2024-02-01 to 2024-03-01
   ...
   ```

2. For each month:
   - Adjust `backfill_5m_monthly.flux`
   - Execute
   - Adjust `backfill_1h_monthly.flux` (same times!)
   - Execute
   - Verify with `test_backfill.flux`

**Advantage:** More control, pausable

---

## Backup-Restore Workflow

### Export from old server

```bash
# Export raw data (last year)
influx backup --bucket victron --start 2024-01-01T00:00:00Z /backup/victron/

# Optional: Also downsampled buckets
influx backup --bucket victron_5m --start 2024-01-01T00:00:00Z /backup/victron_5m/
influx backup --bucket victron_1h --start 2024-01-01T00:00:00Z /backup/victron_1h/
```

### Import on new server

```bash
# Create buckets
influx bucket create -n victron -r 0
influx bucket create -n victron_5m -r 17520h
influx bucket create -n victron_1h -r 0

# Import raw data
influx restore --bucket victron /backup/victron/

# Option 1: Also import downsampled buckets (fast, more storage)
influx restore --bucket victron_5m /backup/victron_5m/
influx restore --bucket victron_1h /backup/victron_1h/

# Option 2: Recalculate downsampled buckets (slow, less storage)
cd backfill/
./backfill_history.sh 2024-01-01 12
```

**Recommendation:**

- **Small data volumes (<1GB):** Option 2 (recalculate)
- **Large data volumes (>1GB):** Option 1 (import with restore)

---

## Performance Notes

### Data Volume per Month (estimated)

- **victron** (Raw): ~50-100 MB/month (depending on sampling rate)
- **victron_5m**: ~5-10 MB/month
- **victron_1h**: ~0.5-1 MB/month

### Backfill Speed

- **5m Stage:** ~100,000 points/minute
- **1h Stage:** ~500,000 points/minute

### Optimization

- Run backfill outside peak hours
- For large time ranges: Split by month
- Memory: Minimum 2GB RAM for InfluxDB during backfill

---

## Troubleshooting

**Problem:** "Bucket not found"

```bash
influx bucket list --org wolke
# Create missing buckets
```

**Problem:** "Timeout" with large time ranges

```bash
# Choose smaller time ranges (max 3 months at once)
# Or increase --timeout parameter
```

**Problem:** Duplicates on repeated backfill

```bash
# Delete old data (careful!)
influx delete --bucket victron_5m --start 2024-11-01T00:00:00Z --stop 2024-12-01T00:00:00Z
```

**Problem:** Script hangs

```bash
# Check InfluxDB status
influx ping
systemctl status influxdb
# Check logs
journalctl -u influxdb -f
```
