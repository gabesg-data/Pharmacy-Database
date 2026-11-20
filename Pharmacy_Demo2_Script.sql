USE PharmacyDB;
GO

-- extra test data
IF OBJECT_ID('dbo.BulkLoadLog') IS NULL
    CREATE TABLE dbo.BulkLoadLog (
        LogID       INT IDENTITY(1,1) PRIMARY KEY,
        FirstSaleID INT NOT NULL,
        LastSaleID  INT NOT NULL,
        LoadedAt    DATETIME NOT NULL DEFAULT GETDATE()
    );
GO

IF NOT EXISTS (SELECT 1 FROM dbo.BulkLoadLog)
BEGIN
    DECLARE @N INT = 20000;

    SELECT ROW_NUMBER() OVER (ORDER BY EmployeeID) AS rn, EmployeeID
    INTO #Emp FROM dbo.Employee;

    SELECT ROW_NUMBER() OVER (ORDER BY PaymentMethod) AS rn, PaymentMethod
    INTO #Pay FROM (SELECT DISTINCT PaymentMethod FROM dbo.Sale) AS x;

    SELECT ROW_NUMBER() OVER (ORDER BY MedicineID) AS rn, MedicineID, UnitPrice
    INTO #Med FROM dbo.Medicine WHERE RequiresPrescription = 0;

    DECLARE @EmpCount INT = (SELECT COUNT(*) FROM #Emp);
    DECLARE @PayCount INT = (SELECT COUNT(*) FROM #Pay);
    DECLARE @MedCount INT = (SELECT COUNT(*) FROM #Med);
    DECLARE @BaseSaleID INT = ISNULL((SELECT MAX(SaleID) FROM dbo.Sale), 0);

    ;WITH Nums AS (
        SELECT TOP (@N) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.Sale (SaleDate, EmployeeID, PrescriptionID, PaymentMethod)
    SELECT DATEADD(MINUTE, -(Nums.n * 50), GETDATE()), e.EmployeeID, NULL, p.PaymentMethod
    FROM Nums
    JOIN #Emp e ON e.rn = (Nums.n % @EmpCount) + 1
    JOIN #Pay p ON p.rn = (Nums.n % @PayCount) + 1
    ORDER BY Nums.n;

    ;WITH NewSales AS (
        SELECT SaleID, ROW_NUMBER() OVER (ORDER BY SaleID) AS rn
        FROM dbo.Sale WHERE SaleID > @BaseSaleID
    )
    INSERT INTO dbo.SaleItem (SaleID, MedicineID, Qty, UnitPrice)
    SELECT s.SaleID, m.MedicineID, (s.rn % 5) + 1, m.UnitPrice
    FROM NewSales s
    JOIN #Med m ON m.rn = (s.rn % @MedCount) + 1;

    ;WITH NewSales AS (
        SELECT SaleID, ROW_NUMBER() OVER (ORDER BY SaleID) AS rn
        FROM dbo.Sale WHERE SaleID > @BaseSaleID
    )
    INSERT INTO dbo.SaleItem (SaleID, MedicineID, Qty, UnitPrice)
    SELECT s.SaleID, m.MedicineID, (s.rn % 3) + 1, m.UnitPrice
    FROM NewSales s
    JOIN #Med m ON m.rn = ((s.rn + 1) % @MedCount) + 1;

    INSERT INTO dbo.BulkLoadLog (FirstSaleID, LastSaleID)
    SELECT MIN(SaleID), MAX(SaleID) FROM dbo.Sale WHERE SaleID > @BaseSaleID;

    DROP TABLE #Emp, #Pay, #Med;
END
GO

SELECT (SELECT COUNT(*) FROM Sale) AS Sales,
       (SELECT COUNT(*) FROM SaleItem) AS SaleLines;
GO

-- joins
SELECT TOP 20 s.SaleID, s.SaleDate,
       e.FirstName + ' ' + e.LastName AS Employee,
       m.MedicineName, si.Qty, si.UnitPrice,
       si.Qty * si.UnitPrice AS LineTotal
FROM Sale s
INNER JOIN Employee e  ON e.EmployeeID = s.EmployeeID
INNER JOIN SaleItem si ON si.SaleID = s.SaleID
INNER JOIN Medicine m  ON m.MedicineID = si.MedicineID
ORDER BY s.SaleDate DESC;

SELECT m.MedicineCode, m.MedicineName, c.CategoryName, su.SupplierName,
       m.UnitPrice, m.UnitPrice - m.UnitCost AS ProfitPerUnit
FROM Medicine m
INNER JOIN Category c  ON c.CategoryID = m.CategoryID
INNER JOIN Supplier su ON su.SupplierID = m.SupplierID
ORDER BY c.CategoryName, m.MedicineName;

SELECT su.SupplierName, COUNT(po.POID) AS OrdersPlaced
FROM Supplier su
LEFT JOIN PurchaseOrder po ON po.SupplierID = su.SupplierID
GROUP BY su.SupplierName
ORDER BY OrdersPlaced;

SELECT pr.PrescriptionID,
       pa.FirstName + ' ' + pa.LastName AS Patient,
       pr.IssueDate, s.SaleID, s.SaleDate,
       e.FirstName + ' ' + e.LastName AS DispensedBy,
       m.MedicineName, si.Qty
FROM Prescription pr
INNER JOIN Patient pa  ON pa.PatientID = pr.PatientID
INNER JOIN Sale s      ON s.PrescriptionID = pr.PrescriptionID
INNER JOIN Employee e  ON e.EmployeeID = s.EmployeeID
INNER JOIN SaleItem si ON si.SaleID = s.SaleID
INNER JOIN Medicine m  ON m.MedicineID = si.MedicineID
ORDER BY pr.IssueDate;
GO

-- subqueries
SELECT MedicineName, UnitPrice
FROM Medicine
WHERE UnitPrice > (SELECT AVG(UnitPrice) FROM Medicine)
ORDER BY UnitPrice DESC;

SELECT MedicineCode, MedicineName
FROM Medicine
WHERE MedicineID NOT IN (SELECT MedicineID FROM SaleItem);

SELECT e.FirstName + ' ' + e.LastName AS Employee, COUNT(*) AS SalesProcessed
FROM Sale s
INNER JOIN Employee e ON e.EmployeeID = s.EmployeeID
GROUP BY e.EmployeeID, e.FirstName, e.LastName
HAVING COUNT(*) > (SELECT COUNT(*) * 1.0 / COUNT(DISTINCT EmployeeID) FROM Sale);

SELECT m.MedicineName, m.ReorderLevel,
       (SELECT ISNULL(SUM(b.QtyOnHand), 0)
        FROM Batch b
        WHERE b.MedicineID = m.MedicineID
          AND b.ExpiryDate > CAST(GETDATE() AS DATE)) AS UsableStock
FROM Medicine m
ORDER BY m.MedicineName;

SELECT p.PatientID, p.FirstName, p.LastName
FROM Patient p
WHERE EXISTS (SELECT 1 FROM Prescription pr WHERE pr.PatientID = p.PatientID);
GO

-- views
CREATE OR ALTER VIEW vw_LowStock AS
SELECT m.MedicineID, m.MedicineCode, m.MedicineName, m.ReorderLevel,
       ISNULL(SUM(CASE WHEN b.ExpiryDate > CAST(GETDATE() AS DATE)
                       THEN b.QtyOnHand END), 0) AS UsableStock
FROM Medicine m
LEFT JOIN Batch b ON b.MedicineID = m.MedicineID
GROUP BY m.MedicineID, m.MedicineCode, m.MedicineName, m.ReorderLevel
HAVING ISNULL(SUM(CASE WHEN b.ExpiryDate > CAST(GETDATE() AS DATE)
                       THEN b.QtyOnHand END), 0) < m.ReorderLevel;
GO

CREATE OR ALTER VIEW vw_ExpiringBatches AS
SELECT b.BatchID, m.MedicineName, b.BatchNumber, b.ExpiryDate, b.QtyOnHand,
       DATEDIFF(DAY, GETDATE(), b.ExpiryDate) AS DaysLeft,
       CASE WHEN b.ExpiryDate < CAST(GETDATE() AS DATE)
            THEN 'Expired' ELSE 'Expiring soon' END AS ExpiryStatus
FROM Batch b
INNER JOIN Medicine m ON m.MedicineID = b.MedicineID
WHERE b.ExpiryDate <= DATEADD(DAY, 90, CAST(GETDATE() AS DATE));
GO

CREATE OR ALTER VIEW vw_MonthlySalesByEmployee AS
SELECT YEAR(s.SaleDate) AS SaleYear,
       MONTH(s.SaleDate) AS SaleMonth,
       e.EmployeeID,
       e.FirstName + ' ' + e.LastName AS Employee,
       COUNT(DISTINCT s.SaleID) AS SalesCount,
       SUM(si.Qty * si.UnitPrice) AS Revenue
FROM Sale s
INNER JOIN Employee e  ON e.EmployeeID = s.EmployeeID
INNER JOIN SaleItem si ON si.SaleID = s.SaleID
GROUP BY YEAR(s.SaleDate), MONTH(s.SaleDate), e.EmployeeID, e.FirstName, e.LastName;
GO

SELECT * FROM vw_LowStock ORDER BY UsableStock;
SELECT * FROM vw_ExpiringBatches ORDER BY ExpiryDate;
SELECT * FROM vw_MonthlySalesByEmployee WHERE SaleYear = 2026 AND SaleMonth = 3 ORDER BY Revenue DESC;
GO

-- stored procedures
CREATE OR ALTER PROCEDURE usp_GetSalesByDateRange
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SaleID, s.SaleDate,
           e.FirstName + ' ' + e.LastName AS Employee,
           s.PaymentMethod,
           SUM(si.Qty * si.UnitPrice) AS SaleTotal
    FROM Sale s
    INNER JOIN Employee e  ON e.EmployeeID = s.EmployeeID
    INNER JOIN SaleItem si ON si.SaleID = s.SaleID
    WHERE s.SaleDate >= @FromDate
      AND s.SaleDate < DATEADD(DAY, 1, @ToDate)
    GROUP BY s.SaleID, s.SaleDate, e.FirstName, e.LastName, s.PaymentMethod
    ORDER BY s.SaleDate;
END
GO

CREATE OR ALTER PROCEDURE usp_TopSellingMedicines
    @TopN INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@TopN) m.MedicineName,
           SUM(si.Qty) AS UnitsSold,
           SUM(si.Qty * si.UnitPrice) AS Revenue
    FROM SaleItem si
    INNER JOIN Medicine m ON m.MedicineID = si.MedicineID
    GROUP BY m.MedicineName
    ORDER BY UnitsSold DESC;
END
GO

CREATE OR ALTER PROCEDURE usp_DispenseMedicine
    @EmployeeID     INT,
    @MedicineID     INT,
    @Qty            INT,
    @PaymentMethod  NVARCHAR(30),
    @PrescriptionID INT = NULL,
    @SaleID         INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchID INT, @Price DECIMAL(10,2);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- earliest expiry first, row locked
        SELECT TOP 1 @BatchID = BatchID
        FROM Batch WITH (UPDLOCK, ROWLOCK)
        WHERE MedicineID = @MedicineID
          AND ExpiryDate > CAST(GETDATE() AS DATE)
          AND QtyOnHand >= @Qty
        ORDER BY ExpiryDate;

        IF @BatchID IS NULL
            THROW 50001, 'Not enough unexpired stock in a single batch.', 1;

        SELECT @Price = UnitPrice FROM Medicine WHERE MedicineID = @MedicineID;

        INSERT INTO Sale (SaleDate, EmployeeID, PrescriptionID, PaymentMethod)
        VALUES (GETDATE(), @EmployeeID, @PrescriptionID, @PaymentMethod);

        SET @SaleID = SCOPE_IDENTITY();

        INSERT INTO SaleItem (SaleID, MedicineID, Qty, UnitPrice)
        VALUES (@SaleID, @MedicineID, @Qty, @Price);

        UPDATE Batch SET QtyOnHand = QtyOnHand - @Qty WHERE BatchID = @BatchID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @SaleID = NULL;
        THROW;
    END CATCH
END
GO

EXEC usp_GetSalesByDateRange @FromDate = '2026-03-01', @ToDate = '2026-03-07';
EXEC usp_TopSellingMedicines;
EXEC usp_TopSellingMedicines @TopN = 10;
GO

-- triggers
CREATE OR ALTER TRIGGER trg_SaleItem_CheckPrescription
ON SaleItem
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1
               FROM inserted i
               INNER JOIN Medicine m ON m.MedicineID = i.MedicineID
               INNER JOIN Sale s     ON s.SaleID = i.SaleID
               WHERE m.RequiresPrescription = 1
                 AND s.PrescriptionID IS NULL)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50002, 'Prescription-only medicine cannot be sold without a prescription.', 1;
    END
END
GO

IF OBJECT_ID('dbo.MedicinePriceAudit') IS NULL
    CREATE TABLE dbo.MedicinePriceAudit (
        AuditID    INT IDENTITY(1,1) PRIMARY KEY,
        MedicineID INT NOT NULL REFERENCES dbo.Medicine(MedicineID),
        OldPrice   DECIMAL(10,2) NOT NULL,
        NewPrice   DECIMAL(10,2) NOT NULL,
        ChangedAt  DATETIME NOT NULL DEFAULT GETDATE(),
        ChangedBy  SYSNAME NOT NULL DEFAULT SUSER_SNAME()
    );
GO

CREATE OR ALTER TRIGGER trg_Medicine_PriceAudit
ON Medicine
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(UnitPrice)
        INSERT INTO MedicinePriceAudit (MedicineID, OldPrice, NewPrice)
        SELECT i.MedicineID, d.UnitPrice, i.UnitPrice
        FROM inserted i
        INNER JOIN deleted d ON d.MedicineID = i.MedicineID
        WHERE i.UnitPrice <> d.UnitPrice;
END
GO

-- test trigger 1
DECLARE @Emp INT = (SELECT TOP 1 EmployeeID FROM Employee);
DECLARE @Pay NVARCHAR(30) = (SELECT TOP 1 PaymentMethod FROM Sale);
DECLARE @RxMed INT = (SELECT TOP 1 MedicineID FROM Medicine WHERE RequiresPrescription = 1);

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO Sale (SaleDate, EmployeeID, PrescriptionID, PaymentMethod)
    VALUES (GETDATE(), @Emp, NULL, @Pay);

    INSERT INTO SaleItem (SaleID, MedicineID, Qty, UnitPrice)
    SELECT SCOPE_IDENTITY(), MedicineID, 1, UnitPrice
    FROM Medicine WHERE MedicineID = @RxMed;
    COMMIT TRANSACTION;
    PRINT 'Sale saved';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Blocked by trigger: ' + ERROR_MESSAGE();
END CATCH
GO

-- test trigger 2
BEGIN TRANSACTION;
    UPDATE Medicine SET UnitPrice = UnitPrice + 1.00 WHERE MedicineID = 1;
    SELECT * FROM MedicinePriceAudit;
ROLLBACK TRANSACTION;
GO

-- indexes and execution plans
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DROP INDEX IF EXISTS IX_Sale_SaleDate ON Sale;
DROP INDEX IF EXISTS IX_SaleItem_MedicineID ON SaleItem;
GO

-- query 1 before
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT SaleID, SaleDate, EmployeeID, PaymentMethod
FROM Sale
WHERE SaleDate >= '2026-01-01' AND SaleDate < '2026-04-01';
GO

CREATE NONCLUSTERED INDEX IX_Sale_SaleDate
ON Sale (SaleDate) INCLUDE (EmployeeID, PaymentMethod);
GO

-- query 1 after
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT SaleID, SaleDate, EmployeeID, PaymentMethod
FROM Sale
WHERE SaleDate >= '2026-01-01' AND SaleDate < '2026-04-01';
GO

-- query 2 before
DECLARE @Med INT = (SELECT TOP 1 MedicineID FROM Medicine WHERE RequiresPrescription = 0 ORDER BY MedicineID);
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT SUM(Qty) AS UnitsSold, SUM(Qty * UnitPrice) AS Revenue
FROM SaleItem
WHERE MedicineID = @Med;
GO

CREATE NONCLUSTERED INDEX IX_SaleItem_MedicineID
ON SaleItem (MedicineID) INCLUDE (Qty, UnitPrice);
GO

-- query 2 after
DECLARE @Med INT = (SELECT TOP 1 MedicineID FROM Medicine WHERE RequiresPrescription = 0 ORDER BY MedicineID);
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT SUM(Qty) AS UnitsSold, SUM(Qty * UnitPrice) AS Revenue
FROM SaleItem
WHERE MedicineID = @Med;
GO

-- query 3 (join plan)
SELECT m.MedicineName, c.CategoryName,
       SUM(si.Qty) AS UnitsSold,
       SUM(si.Qty * si.UnitPrice) AS Revenue
FROM SaleItem si
INNER JOIN Medicine m ON m.MedicineID = si.MedicineID
INNER JOIN Category c ON c.CategoryID = m.CategoryID
GROUP BY m.MedicineName, c.CategoryName
ORDER BY UnitsSold DESC;
GO

-- optimisation 1 original
SELECT SaleID, SaleDate, EmployeeID
FROM Sale
WHERE YEAR(SaleDate) = 2026 AND MONTH(SaleDate) = 3;

-- optimisation 1 improved
SELECT SaleID, SaleDate, EmployeeID
FROM Sale
WHERE SaleDate >= '2026-03-01' AND SaleDate < '2026-04-01';
GO

-- optimisation 2 original
DECLARE @Med INT = (SELECT TOP 1 MedicineID FROM Medicine WHERE RequiresPrescription = 0 ORDER BY MedicineID);
SELECT *
FROM SaleItem
WHERE MedicineID = @Med;

-- optimisation 2 improved
SELECT SaleItemID, Qty, UnitPrice
FROM SaleItem
WHERE MedicineID = @Med;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- transactions: rollback
SELECT MedicineID, MedicineName, UnitPrice FROM Medicine WHERE MedicineID <= 3;

BEGIN TRANSACTION;
    UPDATE Medicine SET UnitPrice = UnitPrice * 1.10 WHERE MedicineID <= 3;
    SELECT MedicineID, MedicineName, UnitPrice FROM Medicine WHERE MedicineID <= 3;
ROLLBACK TRANSACTION;

SELECT MedicineID, MedicineName, UnitPrice FROM Medicine WHERE MedicineID <= 3;
GO

-- transactions: commit
BEGIN TRANSACTION;
    UPDATE Medicine SET UnitPrice = UnitPrice + 0.50 WHERE MedicineID = 1;
COMMIT TRANSACTION;
SELECT * FROM MedicinePriceAudit;
GO

-- transactions: dispensing scenario
DECLARE @Emp INT = (SELECT TOP 1 EmployeeID FROM Employee);
DECLARE @Pay NVARCHAR(30) = (SELECT TOP 1 PaymentMethod FROM Sale);
DECLARE @Med INT = (SELECT TOP 1 b.MedicineID
                    FROM Batch b INNER JOIN Medicine m ON m.MedicineID = b.MedicineID
                    WHERE m.RequiresPrescription = 0
                      AND b.ExpiryDate > CAST(GETDATE() AS DATE)
                      AND b.QtyOnHand >= 5
                    ORDER BY b.QtyOnHand DESC);
DECLARE @NewSale INT;

SELECT BatchID, BatchNumber, ExpiryDate, QtyOnHand FROM Batch WHERE MedicineID = @Med;

EXEC usp_DispenseMedicine @EmployeeID = @Emp, @MedicineID = @Med, @Qty = 2,
                          @PaymentMethod = @Pay, @SaleID = @NewSale OUTPUT;
SELECT @NewSale AS NewSaleID;
SELECT BatchID, BatchNumber, ExpiryDate, QtyOnHand FROM Batch WHERE MedicineID = @Med;

DECLARE @CountBefore INT = (SELECT COUNT(*) FROM Sale);
BEGIN TRY
    EXEC usp_DispenseMedicine @EmployeeID = @Emp, @MedicineID = @Med, @Qty = 999999,
                              @PaymentMethod = @Pay, @SaleID = @NewSale OUTPUT;
END TRY
BEGIN CATCH
    PRINT 'Rolled back: ' + ERROR_MESSAGE();
END CATCH
SELECT @CountBefore AS SalesBefore, (SELECT COUNT(*) FROM Sale) AS SalesAfter;
GO

-- concurrency: lost update
SELECT TOP 1 BatchID, QtyOnHand FROM Batch WHERE QtyOnHand >= 20 ORDER BY BatchID;
GO

-- session 1
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
    DECLARE @Qty INT;
    SELECT @Qty = QtyOnHand FROM Batch WHERE BatchID = 1;
    WAITFOR DELAY '00:00:10';
    UPDATE Batch SET QtyOnHand = @Qty - 2 WHERE BatchID = 1;
COMMIT TRANSACTION;
SELECT BatchID, QtyOnHand FROM Batch WHERE BatchID = 1;
GO

-- session 2
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
    DECLARE @Qty INT;
    SELECT @Qty = QtyOnHand FROM Batch WHERE BatchID = 1;
    UPDATE Batch SET QtyOnHand = @Qty - 3 WHERE BatchID = 1;
COMMIT TRANSACTION;
GO

-- lost update fix (UPDLOCK), session 1
BEGIN TRANSACTION;
    DECLARE @Qty INT;
    SELECT @Qty = QtyOnHand FROM Batch WITH (UPDLOCK, ROWLOCK) WHERE BatchID = 1;
    WAITFOR DELAY '00:00:10';
    UPDATE Batch SET QtyOnHand = @Qty - 2 WHERE BatchID = 1;
COMMIT TRANSACTION;
SELECT BatchID, QtyOnHand FROM Batch WHERE BatchID = 1;
GO

-- lost update fix (UPDLOCK), session 2
BEGIN TRANSACTION;
    DECLARE @Qty INT;
    SELECT @Qty = QtyOnHand FROM Batch WITH (UPDLOCK, ROWLOCK) WHERE BatchID = 1;
    UPDATE Batch SET QtyOnHand = @Qty - 3 WHERE BatchID = 1;
COMMIT TRANSACTION;
SELECT BatchID, QtyOnHand FROM Batch WHERE BatchID = 1;
GO

-- remove test data
DECLARE @First INT = (SELECT MIN(FirstSaleID) FROM BulkLoadLog);
DECLARE @Last  INT = (SELECT MAX(LastSaleID) FROM BulkLoadLog);
DELETE FROM SaleItem WHERE SaleID BETWEEN @First AND @Last;
DELETE FROM Sale WHERE SaleID BETWEEN @First AND @Last;
DELETE FROM BulkLoadLog;
GO
