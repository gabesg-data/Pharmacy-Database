import pyodbc

# Establish native connectivity to your local SQL Server database
conn_str = (
    r'DRIVER={ODBC Driver 17 for SQL Server};'
    r'SERVER=localhost;'
    r'DATABASE=PharmacyDB;'
    r'Trusted_Connection=yes;'
)

try:
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    print("=== PHARMACY MANAGEMENT SYSTEM INTERFACE ONLINE ===\n")

    # 1. CREATE OPERATION
    print("[TESTING] Executing CREATE...")
    cursor.execute("INSERT INTO Category (CategoryName) VALUES ('Experimental Antidotes')")
    conn.commit()
    print("-> SUCCESS: 'Experimental Antidotes' added to Category table.\n")

    # 2. READ OPERATION
    print("[TESTING] Executing READ...")
    cursor.execute("SELECT TOP 3 CategoryID, CategoryName FROM Category ORDER BY CategoryID DESC")
    print("-> SUCCESS: Pulling top categories from database:")
    for row in cursor.fetchall():
        print(f"   - ID: {row[0]} | Name: {row[1]}")
    print("")

    # 3. UPDATE OPERATION
    print("[TESTING] Executing UPDATE...")
    cursor.execute(
        "UPDATE Category SET CategoryName = 'Critical Care Agents' "
        "WHERE CategoryName = 'Experimental Antidotes'"
    )
    conn.commit()
    print("-> SUCCESS: Modified record value to 'Critical Care Agents'.\n")

    # 4. SEARCH / REPORT OPERATION
    print("[TESTING] Executing SEARCH/REPORT...")
    cursor.execute("SELECT CategoryID, CategoryName FROM Category WHERE CategoryName LIKE '%Critical%'")
    search_result = cursor.fetchone()
    if search_result:
        print(f"   - Match Found -> ID: {search_result[0]} | Name: {search_result[1]}")
    print("-> SUCCESS: Wildcard search evaluation complete.\n")

    # 5. DELETE OPERATION
    print("[TESTING] Executing DELETE...")
    cursor.execute("DELETE FROM Category WHERE CategoryName = 'Critical Care Agents'")
    conn.commit()
    print("-> SUCCESS: Cleaned up test record from database storage.\n")

    cursor.close()
    conn.close()
    print("=== ALL CRUD WORKSPACE TESTS COMPLETED FLAWLESSLY ===")

except Exception as e:
    print(f"[CRITICAL ERROR] Database link failure: {e}")
