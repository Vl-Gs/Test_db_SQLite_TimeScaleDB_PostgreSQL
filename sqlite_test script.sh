#!/bin/bash

# Database path
DB_PATH="/path/to/your/database.sqlite"

# Output file
OUTPUT_FILE="/tmp/query_performance_results.txt"

# Function to get the earliest and latest timestamp from the database
get_timestamp_range() {
  local table_name="$1"
  local timestamp_column
  
  # Select appropriate timestamp column based on table
  if [[ "$table_name" == "fifteen_seconds" ]]; then
      timestamp_column="timestamp"
  else
      timestamp_column="interval_start"
  fi

  # Query to get the earliest and latest timestamps
  local query="SELECT 
      MIN($timestamp_column) as earliest, 
      MAX($timestamp_column) as latest 
  FROM $table_name;"

  # Execute query and capture results
  sqlite3 "$DB_PATH" "$query"
}

# Function to run query and measure execution time
run_query() {
  local table_name="$1"
  local start_time="$2"
  local end_time="$3"
  local period_label="$4"
  local log_file="/tmp/${table_name}_${period_label// /_}_performance.log"
  local query

  # Construct query based on table type
  if [[ "$table_name" == "fifteen_seconds" ]]; then
      query="EXPLAIN QUERY PLAN
      SELECT d.device_type, d.device_number, 
             fs.timestamp, fs.value, 
             fs.min_value, fs.max_value, fs.avg_value
      FROM devices d
      JOIN $table_name fs ON d.id = fs.device_id
      WHERE fs.timestamp BETWEEN '$start_time' AND '$end_time';"
  else
      query="EXPLAIN QUERY PLAN
      SELECT d.device_type, d.device_number, 
             t.interval_start, t.interval_end,
             t.min_value, t.max_value, t.avg_value
      FROM devices d
      JOIN $table_name t ON d.id = t.device_id
      WHERE t.interval_start BETWEEN '$start_time' AND '$end_time';"
  fi

  # Measure execution time using time command
  local start_time_measure=$(date +%s.%N)
  
  # Execute query
  sqlite3 "$DB_PATH" "$query" > "$log_file" 2>&1
  
  local end_time_measure=$(date +%s.%N)
  
  # Calculate execution time
  local exec_time=$(echo "$end_time_measure - $start_time_measure" | bc)
  
  # Ensure we have a numeric value
  if [[ -z "$exec_time" ]]; then
      exec_time="N/A"
  fi

  echo "Interval: $period_label -> Timp execuție: ${exec_time} secunde" >> "$OUTPUT_FILE"
}

# Main performance testing function
test_performance() {
  local tables=("fifteen_seconds" "one_hour" "one_day")

  # Clear previous output file
  > "$OUTPUT_FILE"

  echo "Starting Performance Benchmarking..."
  echo "Results will be saved to $OUTPUT_FILE"
  
  for table in "${tables[@]}"; do
      # Get timestamp range for the table
      IFS='|' read -r earliest latest <<< $(get_timestamp_range "$table")
      
      echo "Table: $table" >> "$OUTPUT_FILE"
      echo "Data range: $earliest to $latest" >> "$OUTPUT_FILE"

      # Define periods 
      local periods=(
          "1 HOUR:1 hour"
          "4 HOURS:4 hours"
          "12 HOURS:12 hours"
          "1 DAY:1 day"
          "7 DAYS:7 days"
          "30 DAYS:30 days"
          "60 DAYS:60 days"
          "90 DAYS:90 days"
          "120 DAYS:120 days"
      )

      for period_info in "${periods[@]}"; do
          # Split period info
          IFS=':' read -r label interval <<< "$period_info"
          
          # Calculate end time based on earliest timestamp
          # Note: SQLite date calculations are slightly different
          local end_time="$latest"
          local start_time=$(sqlite3 "$DB_PATH" "SELECT datetime('$end_time', '-$interval')")
          
          # Run query and log results
          run_query "$table" "$start_time" "$end_time" "$label"
      done
      
      echo "" >> "$OUTPUT_FILE"
  done

  echo "Performance tests completed. Results in $OUTPUT_FILE"
  cat "$OUTPUT_FILE"
}

# Ensure sqlite3 is installed
if ! command -v sqlite3 &> /dev/null; then
  echo "SQLite3 is not installed. Please install it first."
  exit 1
fi

# Run performance tests
test_performance