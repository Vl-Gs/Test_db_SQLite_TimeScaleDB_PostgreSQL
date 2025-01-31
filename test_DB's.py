import sqlite3
import psycopg2
import time

# Variabile globale
POSTGRESQL_CONFIG = {
    "dbname": "your_dbname",   # Insert your database name
    "user": "your_user",     # Insert your database user
    "password": "your_password", # Insert your database password
    "host": "localhost",     # Insert your database host
    "port": "5432"  # Default port for PostgreSQL
}
TIMESCALEDB_CONFIG = POSTGRESQL_CONFIG  # TimescaleDB is a PostgreSQL extension, so using the same config
SQLITE_DB_PATH = "path/to/your/sqlite.db" # Insert the path to your SQLite database
TEST_RESULTS_FILE = "test_results_all.txt"
REFERENCE_DATE = "2023-09-10" # Insert a reference date in the format "YYYY-MM-DD"
TIME_PERIODS = ["1h", "4h", "12h", "1d", "7d", "30d", "60d", "90d", "120d"] # Time periods to test

def execute_postgresql_query(query, config):
    try:
        conn = psycopg2.connect(**config)
        cur = conn.cursor()
        start_time = time.time()
        cur.execute(query)
        cur.fetchall()
        execution_time = time.time() - start_time
        conn.close()
        return execution_time
    except Exception as e:
        print(f"PostgreSQL Error: {e}")
        return None

def execute_sqlite_query(query):
    try:
        conn = sqlite3.connect(SQLITE_DB_PATH)
        cur = conn.cursor()
        start_time = time.time()
        cur.execute(query)
        cur.fetchall()
        execution_time = time.time() - start_time
        conn.close()
        return execution_time
    except Exception as e:
        print(f"SQLite Error: {e}")
        return None

def run_tests():
    results = []
    for period in TIME_PERIODS:
        # PostgreSQL/TimescaleDB query with LIMIT 500
        if "h" in period:  # For hours
            interval = f"INTERVAL '{int(period[:-1])} hours'"
        elif "d" in period:  # For days
            interval = f"INTERVAL '{int(period[:-1])} days'"
        query_postgresql = f"""
            SELECT * FROM devices d
            JOIN fifteen_seconds f ON d.id = f.device_id
            WHERE f.timestamp >= '{REFERENCE_DATE} 00:00:00'::timestamp - {interval}
            LIMIT 500;
        """
        
        # SQLite query with LIMIT 500
        query_sqlite = f"""
            SELECT * FROM devices d
            JOIN fifteen_seconds f ON d.id = f.device_id
            WHERE f.timestamp >= datetime('{REFERENCE_DATE} 00:00:00', '-{period}')
            LIMIT 500;
        """
        
        # Execute queries
        postgres_time = execute_postgresql_query(query_postgresql, POSTGRESQL_CONFIG)
        timescaledb_time = execute_postgresql_query(query_postgresql, TIMESCALEDB_CONFIG)  # Same query for TimescaleDB
        sqlite_time = execute_sqlite_query(query_sqlite)
        
        # Avoid error if any query fails
        results.append((period, postgres_time if postgres_time is not None else "Error", 
                        timescaledb_time if timescaledb_time is not None else "Error",
                        sqlite_time if sqlite_time is not None else "Error"))
    
    with open(TEST_RESULTS_FILE, "w") as f:
        f.write("Time Period | PostgreSQL | TimescaleDB | SQLite\n")
        f.write("-----------------------------------------------\n")
        for row in results:
            # Write results even if there's an error
            f.write(f"{row[0]} | {row[1]} | {row[2]} | {row[3]}\n")
    
    print("Tests completed. Results saved.")

if __name__ == "__main__":
    run_tests()
