import psycopg2
import sqlite3

# Configuration section: edit these variables to match your setup

# PostgreSQL connection parameters
PG_CONN_PARAMS = {
    'dbname': 'your_pg_dbname',   # PostgreSQL database name
    'user': 'your_pg_user',       # PostgreSQL user
    'password': 'your_pg_password', # PostgreSQL password
    'host': 'your_pg_host',       # PostgreSQL host (e.g., 'localhost')
    'port': '5432'        # PostgreSQL port (e.g., 5432)
}

# SQLite database file path
SQLITE_DB_PATH = 'output.sqlite'  # Output SQLite database file

# Optional: Customize the schema conversion rules (type mappings, etc.)
TYPE_MAPPING = {
    'character varying': 'TEXT',
    'character': 'TEXT',
    'integer': 'INTEGER',
    'boolean': 'BOOLEAN',
    'timestamp without time zone': 'TEXT',  # SQLite doesn't have timestamp type
}

# The function to convert PostgreSQL dump to SQLite
def convert_postgresql_to_sqlite(pg_conn_params, sqlite_db_path, type_mapping):
    # Connect to PostgreSQL
    pg_conn = psycopg2.connect(**pg_conn_params)
    pg_cursor = pg_conn.cursor()

    # Connect to SQLite
    sqlite_conn = sqlite3.connect(sqlite_db_path)
    sqlite_cursor = sqlite_conn.cursor()

    # Step 1: Fetch PostgreSQL schema and tables
    pg_cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
    tables = pg_cursor.fetchall()

    # Step 2: Create SQLite schema
    for table in tables:
        table_name = table[0]
        pg_cursor.execute(f"SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '{table_name}'")
        columns = pg_cursor.fetchall()
        
        column_defs = []
        for column in columns:
            column_name, data_type = column
            # Convert PostgreSQL types to SQLite types based on TYPE_MAPPING
            if data_type in type_mapping:
                data_type = type_mapping[data_type]
            column_defs.append(f"{column_name} {data_type}")
        
        # Construct CREATE TABLE query for SQLite
        create_table_sql = f"CREATE TABLE {table_name} ({', '.join(column_defs)});"
        sqlite_cursor.execute(create_table_sql)
        
        # Step 3: Fetch and insert data
        pg_cursor.execute(f"SELECT * FROM {table_name}")
        rows = pg_cursor.fetchall()
        
        for row in rows:
            placeholders = ', '.join('?' * len(row))
            insert_sql = f"INSERT INTO {table_name} VALUES ({placeholders})"
            sqlite_cursor.execute(insert_sql, row)

    # Step 4: Convert indexes
    pg_cursor.execute("SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'")
    indexes = pg_cursor.fetchall()

    for index in indexes:
        index_name, index_def = index
        if 'USING btree' in index_def:  # SQLite supports BTree indexes
            sqlite_cursor.execute(f"CREATE INDEX {index_name} ON {index_def.split('ON ')[1]}")
    
    # Commit changes to SQLite
    sqlite_conn.commit()

    # Close connections
    pg_cursor.close()
    pg_conn.close()
    sqlite_cursor.close()
    sqlite_conn.close()

# Example usage
convert_postgresql_to_sqlite(PG_CONN_PARAMS, SQLITE_DB_PATH, TYPE_MAPPING)
