# Cube-360 — Employee Corporate Credit Card Expense Audit

I built this because I wanted a project that actually resembled corporate finance work — not a typical tutorial dataset. Cube-360 is a made-up company, a fictional insurer of digital assets like Instagram and YouTube accounts, with 275 employees across 9 departments and 3,688 corporate card transactions from the first two quarters of 2026 (January through June).

Real corporate card data isn't public, so I generated this myself and made it intentionally messy — inconsistent date formats, dollar amounts stored as text, missing or wrong expense categories, some duplicate entries. The goal was to make the cleaning and validation part of the actual work, not skip straight to analysis with clean data handed to me.

## Data model

Three tables. **Employee** has a self-referencing ManagerID column, so the org hierarchy lives inside the same table instead of a separate one. **DepartmentBudget** is built bottom-up from per-role expense allowances, weighted higher for travel-intensive, client-facing departments like Sales & Marketing than for back-office functions. **Transactions** holds both what the employee typed as the category and the card network's MCC code, used as an independent reference field for validating the employee-reported category.

## Cleaning it up (Excel)

The original file had 3,688 rows. I standardized the date formats, converted currency-as-text amounts into real numbers, and checked every self-reported category against its MCC code using INDEX/MATCH and IF/TRIM logic. That check came back 90.4% match, 3.8% mismatch, 5.8% blank. I also found and removed 54 duplicate transactions (matched on employee, merchant, and amount via COUNTIFS) before running any analysis on top of it, leaving 3,634 clean rows.

Two things worth mentioning. First, partway through, almost every "Travel" transaction was getting flagged as a mismatch while every other category looked normal — turned out to be a typo in my own lookup table, not a data problem. Second, I noticed the Events category was averaging more per transaction than Travel or Lodging despite happening just as often, which didn't make sense for this kind of company — traced it to how I'd priced Events merchants when generating the data, and corrected it. Both are documented in the Data Cleaning Log tab in the workbook.

The workbook also has a Dashboard tab — department-level Actual vs. Budget with variance and percent of budget, built from a PivotTable, plus a comparison chart.

## SQL

Schema, data load, and full analysis are in `cube360_full_project.sql`, loaded into MySQL. It covers:

- Total spend and department-level breakdowns
- Budget vs. actual by department, with variance and percent of budget
- Category drill-downs, both within a department and company-wide
- An anomaly check using a window function (`AVG(Amount) OVER (PARTITION BY EmpID)`) — transactions over 3x an employee's own average get flagged. Started at 2x, which flagged too much to mean anything, so I tightened it.
- A **recursive CTE** (`WITH RECURSIVE`) that walks any employee up through their manager chain to their Department Head — this is what a flagged transaction would actually route to for review, not just a flat list of anomalies
- Compliance checks: a flat cap on meals, event authorization that scales by seniority level (since a big event booking is often one person spending on behalf of a team), personal reimbursements, late submissions, and missing receipts on high-dollar transactions

## Key Findings

Sales & Marketing used approximately 157% of its allocated budget — about 57% above budget — with Travel and Lodging as the main drivers. HR & Events used approximately 71% of its allocated budget, or about 29% below budget. 185 transactions (5.1%) were flagged under the 3x employee-average exception rule. 97 high-dollar transactions had no receipt on file, providing a more targeted subset for review than the 429 transactions with missing receipts overall.

## Tools

Excel (formulas — INDEX/MATCH, IF/TRIM, COUNTIFS, ISNUMBER, VALUE/SUBSTITUTE; PivotTables), MySQL, SQL (window functions, recursive CTEs, self-referencing foreign keys, CASE expressions)
