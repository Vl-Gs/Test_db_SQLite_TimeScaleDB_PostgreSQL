#!/bin/bash
set -x

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Set working directory
WORK_DIR="/vagrant"
cd "$WORK_DIR"

# Reference date (September 10, 2023)
REFERENCE_DATE="2023-09-10 00:00:00"

# Install SQLite
log "Starting SQLite installation..."
sudo apt-get update
sudo apt-get install -y sqlite3

# Verify installation
SQLITE_VERSION=$(sqlite3 --version)
log "SQLite installed: $SQLITE_VERSION"

# Import devices_sqlite.sql
log "Starting import of devices_sqlite.sql..."
sqlite3 sensor_data.db < devices_sqlite.sql
if [ $? -eq 0 ]; then
    log "devices_sqlite.sql imported successfully"
else
    log "Error importing devices_sqlite.sql"
    exit 1
fi

# Create script for performance testing
cat > test_queries.sql << EOF
.timer on
.mode column
.headers on

-- Test for fifteen_seconds
SELECT 'TEST FIFTEEN_SECONDS - 1 HOUR' as TEST;
SELECT count(*) 
FROM devices d
JOIN fifteen_seconds s ON d.id = s.device_id 
WHERE s.timestamp >= datetime('$REFERENCE_DATE', '-1 hour');

SELECT 'TEST FIFTEEN_SECONDS - 4 HOURS' as TEST;
SELECT count(*) 
FROM devices d
JOIN fifteen_seconds s ON d.id = s.device_id 
WHERE s.timestamp >= datetime('$REFERENCE_DATE', '-4 hours');

SELECT 'TEST FIFTEEN_SECONDS - 12 HOURS' as TEST;
SELECT count(*) 
FROM devices d
JOIN fifteen_seconds s ON d.id = s.device_id 
WHERE s.timestamp >= datetime('$REFERENCE_DATE', '-12 hours');

-- Test for one_hour
SELECT 'TEST ONE_HOUR - 1 DAY' as TEST;
SELECT count(*) 
FROM devices d
JOIN one_hour h ON d.id = h.device_id 
WHERE h.interval_start >= datetime('$REFERENCE_DATE', '-1 day');

SELECT 'TEST ONE_HOUR - 7 DAYS' as TEST;
SELECT count(*) 
FROM devices d
JOIN one_hour h ON d.id = h.device_id 
WHERE h.interval_start >= datetime('$REFERENCE_DATE', '-7 days');

SELECT 'TEST ONE_HOUR - 30 DAYS' as TEST;
SELECT count(*) 
FROM devices d
JOIN one_hour h ON d.id = h.device_id 
WHERE h.interval_start >= datetime('$REFERENCE_DATE', '-30 days');

-- Test for one_day
SELECT 'TEST ONE_DAY - 30 DAYS' as TEST;
SELECT count(*) 
FROM devices d
JOIN one_day od ON d.id = od.device_id 
WHERE od.interval_start >= datetime('$REFERENCE_DATE', '-30 days');

SELECT 'TEST ONE_DAY - 90 DAYS' as TEST;
SELECT count(*) 
FROM devices d
JOIN one_day od ON d.id = od.device_id 
WHERE od.interval_start >= datetime('$REFERENCE_DATE', '-90 days');

SELECT 'TEST ONE_DAY - 180 DAYS' as TEST;
SELECT count(*) 
FROM devices d
JOIN one_day od ON d.id = od.device_id 
WHERE od.interval_start >= datetime('$REFERENCE_DATE', '-180 days');

-- Test for five_minutes
SELECT 'TEST FIVE_MINUTES - 1 HOUR' as TEST;
SELECT count(*) 
FROM devices d
JOIN five_minutes fm ON d.id = fm.device_id 
WHERE fm.interval_start >= datetime('$REFERENCE_DATE', '-1 hour');

SELECT 'TEST FIVE_MINUTES - 4 HOURS' as TEST;
SELECT count(*) 
FROM devices d
JOIN five_minutes fm ON d.id = fm.device_id 
WHERE fm.interval_start >= datetime('$REFERENCE_DATE', '-4 hours');

SELECT 'TEST FIVE_MINUTES - 12 HOURS' as TEST;
SELECT count(*) 
FROM devices d
JOIN five_minutes fm ON d.id = fm.device_id 
WHERE fm.interval_start >= datetime('$REFERENCE_DATE', '-12 hours');
EOF

# Optimize SQLite
log "Applying SQLite optimizations..."
sqlite3 sensor_data.db << EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = DEFAULT;       
PRAGMA mmap_size = 268435456;
PRAGMA cache_size = -2000;

-- Indexes for time-based queries
CREATE INDEX IF NOT EXISTS idx_one_hour_interval_start ON one_hour(interval_start);
CREATE INDEX IF NOT EXISTS idx_one_hour_interval_end ON one_hour(interval_end);

CREATE INDEX IF NOT EXISTS idx_one_day_interval_start ON one_day(interval_start);
CREATE INDEX IF NOT EXISTS idx_one_day_interval_end ON one_day(interval_end);

CREATE INDEX IF NOT EXISTS idx_five_minutes_interval_start ON five_minutes(interval_start);
CREATE INDEX IF NOT EXISTS idx_five_minutes_interval_end ON five_minutes(interval_end);

-- Indexes for joins
CREATE INDEX IF NOT EXISTS idx_fifteen_seconds_device_id ON fifteen_seconds(device_id);
CREATE INDEX IF NOT EXISTS idx_one_hour_device_id ON one_hour(device_id);
CREATE INDEX IF NOT EXISTS idx_one_day_device_id ON one_day(device_id);
CREATE INDEX IF NOT EXISTS idx_five_minutes_device_id ON five_minutes(device_id);

ANALYZE;
EOF

# Run tests and save results
log "Running performance tests..."
RESULTS=$(sqlite3 sensor_data.db < test_queries.sql)

# Filter results to extract only "real" times
echo "$RESULTS" | grep "Run Time: real" | awk '{print $3}'

log "Testing complete. Real-time results have been displayed."
