-- Cube-360 Employee Corporate Credit Card Expense Audit
-- 3 tables: Employee (self-referencing hierarchy via ManagerID), DepartmentBudget, Transactions
-- 275 employees, 9 departments, 3,634 transactions, H1 2026

CREATE DATABASE IF NOT EXISTS cube360;
USE cube360;

CREATE TABLE Employee (
    EmpID VARCHAR(10) PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Department VARCHAR(50) NOT NULL,
    Title VARCHAR(60) NOT NULL,
    ManagerID VARCHAR(10),
    CardIssued VARCHAR(1),
    FOREIGN KEY (ManagerID) REFERENCES Employee(EmpID)
);

DROP TABLE IF EXISTS DepartmentBudget;

CREATE TABLE DepartmentBudget (
    Department      VARCHAR(50) PRIMARY KEY,
    PeriodStart     DATE,
    PeriodEnd       DATE,
    AllocatedBudget DECIMAL(12,2),
    AnnualBudget    DECIMAL(12,2),
    HeadcountBasis  INT
);

INSERT INTO DepartmentBudget VALUES
('Actuarial & Risk', '2026-01-01', '2026-06-30', 22500, 45000, 25),
('Claims', '2026-01-01', '2026-06-30', 79000, 158000, 35),
('Customer Support', '2026-01-01', '2026-06-30', 19850, 39700, 30),
('Executive & Corporate', '2026-01-01', '2026-06-30', 31500, 63000, 7),
('Finance', '2026-01-01', '2026-06-30', 33000, 66000, 27),
('HR & Events', '2026-01-01', '2026-06-30', 36500, 73000, 15),
('IT & Platform Engineering', '2026-01-01', '2026-06-30', 16000, 32000, 21),
('Sales & Marketing', '2026-01-01', '2026-06-30', 196500, 393000, 70),
('Underwriting', '2026-01-01', '2026-06-30', 75000, 150000, 45);

CREATE TABLE Transactions (
    ExpID VARCHAR(15) PRIMARY KEY,
    EmpID VARCHAR(10) NOT NULL,
    TransactionID VARCHAR(15),
    ExpenseDate DATE,
    SubmissionDate DATE,
    Merchant VARCHAR(60),
    MCC VARCHAR(4),
    Category_SelfReported VARCHAR(30),
    FinalCategory VARCHAR(30),
    CategoryCheck VARCHAR(10),
    Amount DECIMAL(10,2),
    PaymentMethod VARCHAR(30),
    ReasonIfPersonal VARCHAR(60),
    ReceiptAttached VARCHAR(1),
    FOREIGN KEY (EmpID) REFERENCES Employee(EmpID)
);


-- ============================================
-- LOAD DATA
-- ============================================
SET FOREIGN_KEY_CHECKS = 0;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/employee_for_mysql.csv'
INTO TABLE Employee
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(EmpID, Name, Department, Title, ManagerID, CardIssued);

SET FOREIGN_KEY_CHECKS = 1;
SELECT COUNT(*) FROM Employee;
SELECT COUNT(*) FROM DepartmentBudget;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/transactions_for_mysql.csv'
INTO TABLE Transactions
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(ExpID, EmpID, TransactionID, ExpenseDate, SubmissionDate, Merchant, MCC,
 Category_SelfReported, Amount, PaymentMethod, ReasonIfPersonal,
 ReceiptAttached, FinalCategory, CategoryCheck);


-- ============================================
-- DATA QUALITY CHECKS
-- ============================================


SELECT COUNT(*) AS EmployeeCount
FROM Employee;

SELECT COUNT(*) AS DepartmentBudgetCount
FROM DepartmentBudget;

SELECT COUNT(*) AS TransactionCount
FROM Transactions;

SELECT
    e.EmpID,
    e.Name,
    e.ManagerID
FROM Employee e
LEFT JOIN Employee m
    ON e.ManagerID = m.EmpID
WHERE e.ManagerID IS NOT NULL
  AND m.EmpID IS NULL;

USE cube360;

SELECT *
FROM Employee
LIMIT 10;

UPDATE Employee SET ManagerID = NULL WHERE ManagerID = '';

SELECT
    EmpID,
    Name,
    Title,
    ManagerID
FROM Employee
WHERE ManagerID IS NULL;

-- Cube360 Overall Expense Summary
SELECT
SUM(Amount) AS TotalSpend,
COUNT(*) AS TransactionCount,
AVG(Amount) AS AverageTransaction
FROM Transactions;

-- Employee Corporate Card Spending by Department
SELECT
    e.Department,
    SUM(t.Amount) AS TotalSpending
FROM Transactions t
JOIN Employee e
    ON t.EmpID = e.EmpID
GROUP BY e.Department
ORDER BY e.Department;


-- Category breakdown within an over-budget department
SELECT t.FinalCategory, ROUND(SUM(t.Amount),2) AS TotalSpend
FROM Transactions t
JOIN Employee e ON t.EmpID = e.EmpID
WHERE e.Department = 'Sales & Marketing'
GROUP BY t.FinalCategory
ORDER BY TotalSpend DESC;


-- Tracking each employee's department and manager
-- Same anomaly flags, one join further -- adds each employee's direct manager
WITH EmpSpending AS (
    SELECT ExpID, EmpID, FinalCategory, Amount,
           AVG(Amount) OVER (PARTITION BY EmpID) AS EmpAvgAmount
    FROM Transactions
)
SELECT es.ExpID, e.Name AS Employee, e.Department, es.FinalCategory, es.Amount,
       ROUND(es.Amount/es.EmpAvgAmount,2) AS RatioToOwnAvg,
       mgr.Name AS Manager
FROM EmpSpending es
JOIN Employee e ON es.EmpID = e.EmpID
LEFT JOIN Employee mgr ON e.ManagerID = mgr.EmpID
WHERE es.Amount > 3*es.EmpAvgAmount
ORDER BY RatioToOwnAvg DESC;

-- Top 30 spenders company-wide, total spend per person with department and manager attached
SELECT e.Name AS Employee, e.Department, mgr.Name AS Manager,
       ROUND(SUM(t.Amount),2) AS TotalSpend,
       COUNT(t.ExpID) AS TransactionCount
FROM Transactions t
JOIN Employee e ON t.EmpID = e.EmpID
LEFT JOIN Employee mgr ON e.ManagerID = mgr.EmpID
GROUP BY e.EmpID, e.Name, e.Department, mgr.Name
ORDER BY TotalSpend DESC
LIMIT 30;


-- Total spend by category, company-wide -- mirrors the department breakdown, but by category instead
SELECT FinalCategory, ROUND(SUM(Amount),2) AS TotalSpend
FROM Transactions
GROUP BY FinalCategory
ORDER BY TotalSpend DESC;

SELECT COUNT(*) FROM Transactions;

SELECT e.Department, b.AllocatedBudget,
       ROUND(SUM(t.Amount),2) AS ActualSpending,
       ROUND(SUM(t.Amount) - b.AllocatedBudget,2) AS Variance,
       ROUND(100.0*SUM(t.Amount)/b.AllocatedBudget,1) AS PercentOfBudget
FROM Transactions t
JOIN Employee e ON t.EmpID = e.EmpID
JOIN DepartmentBudget b ON e.Department = b.Department
GROUP BY e.Department, b.AllocatedBudget
ORDER BY PercentOfBudget DESC;

-- A: How much spend bypassed the corporate card entirely, and why
SELECT ReasonIfPersonal, COUNT(*) AS TxnCount, ROUND(SUM(Amount),2) AS TotalAmount
FROM Transactions
WHERE PaymentMethod = 'Personal (Reimbursement)'
GROUP BY ReasonIfPersonal
ORDER BY TotalAmount DESC;

-- B: Transactions submitted more than 14 days after the expense date -- stale, hard to verify
SELECT ExpID, EmpID, ExpenseDate, SubmissionDate,
       DATEDIFF(SubmissionDate, ExpenseDate) AS DaysLate, Amount
FROM Transactions
WHERE DATEDIFF(SubmissionDate, ExpenseDate) > 14
ORDER BY DaysLate DESC;

-- C: High-dollar transactions with no receipt on file -- the real audit risk
SELECT ExpID, EmpID, FinalCategory, Amount, ReceiptAttached
FROM Transactions
WHERE ReceiptAttached = 'N' AND Amount > 300
ORDER BY Amount DESC;

-- Anomaly check, tightened to 3x own average -- 185/3634 (5.1%), a believable rare-exception rate
WITH ES AS (SELECT Amount, AVG(Amount) OVER (PARTITION BY EmpID) AS EA FROM Transactions)
SELECT COUNT(*) FROM ES WHERE Amount > 3*EA;

-- Events authorization scales by seniority level
WITH EventSpend AS (
SELECT t.ExpID, e.Name, e.Title, e.Department, t.Amount,
	CASE
WHEN e.Title LIKE '%VP%' OR e.Title LIKE '%Chief%' OR e.Title LIKE '%Director%' THEN 'Director/VP'
WHEN e.Title LIKE '%Manager%' THEN 'Manager'
WHEN e.Title LIKE 'Senior%' OR e.Title LIKE '%Event Coordinator%' THEN 'Senior'
ELSE 'IC'
END AS Level
FROM Transactions t JOIN Employee e ON t.EmpID = e.EmpID
WHERE t.FinalCategory = 'Events'
),
Threshold AS (
SELECT 'IC' AS Level, 465 AS Limit_ UNION ALL SELECT 'Senior', 620
UNION ALL SELECT 'Manager', 775 UNION ALL SELECT 'Director/VP', 1550
)
SELECT es.ExpID, es.Name, es.Level, es.Amount, th.Limit_
FROM EventSpend es JOIN Threshold th ON es.Level = th.Level
WHERE es.Amount > th.Limit_
ORDER BY es.Amount DESC;

-- Recursive CTE: walks any employee up through their manager chain to their Department Head
WITH RECURSIVE OrgChain AS (
    SELECT EmpID, Name, Title, ManagerID, 0 AS Level
    FROM Employee WHERE EmpID = 'E005'  -- swap in any EmpID

    UNION ALL

    SELECT e.EmpID, e.Name, e.Title, e.ManagerID, oc.Level + 1
    FROM Employee e
    JOIN OrgChain oc ON e.EmpID = oc.ManagerID
)
SELECT EmpID, Name, Title, Level
FROM OrgChain
ORDER BY Level;
