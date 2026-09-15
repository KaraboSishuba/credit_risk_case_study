## Project 1 of [N] — Data Analytics Portfolio
# Customer Data SQL Cleaning & Transformation Pipeline

---

## Executive Summary

| | |
|---|---|
| **Dataset** | Credit Card Customer Segmentation Data (Kaggle) |
| **Raw records** | 8,950 |
| **Environment** | PostgreSQL, hosted via Supabase |
| **Objective** | Stage, clean, transform, deduplicate, and verify raw customer data into a production-ready dataset for downstream analytics and machine learning |
| **Techniques used** | 12 core SQL functions across string cleaning, null handling, type casting, conditional segmentation, and window functions |

The raw dataset arrived with inconsistent ID formatting, missing financial values, and no built-in deduplication or segmentation logic. This pipeline transforms it into a clean, analysis-ready table (`customer_cleaned`) while preserving every original record.

---

## 12 Core SQL Functions Applied

| # | Function | Purpose |
|---|---|---|
| 1 | `TRIM` | Stripped leading/trailing whitespace from raw customer IDs |
| 2 | `UPPER` | Standardized customer identifier casing |
| 3 | `LOWER` | Standardized account status text for consistent reporting |
| 4 | `REPLACE` | Normalized ID prefixes (`'C'` → `'CUST_'`) |
| 5 | `COALESCE` | Filled missing `CREDIT_LIMIT` and `MINIMUM_PAYMENTS` values with `0.00` |
| 6 | `CAST` | Explicitly cast `TENURE` to a numeric type |
| 7 | `CASE WHEN` | Segmented customers into `High`, `Medium`, and `Low` balance tiers |
| 8 | `SUBSTRING` | Extracted the numeric suffix from each customer ID |
| 9 | `LENGTH` | Validated ID length consistency |
| 10 | `DATE_TRUNC` | Standardized the processing snapshot to the start of the month |
| 11 | `ROW_NUMBER() OVER (PARTITION BY ...)` | Deduplicated by customer ID, keeping the highest-balance record per ID |
| 12 | `RANK() OVER (PARTITION BY ...)` | Ranked purchase volume within each tenure group |

---

## Pipeline Implementation

```sql
-- CUSTOMER DATA SQL CLEANING & TRANSFORMATION PIPELINE 


-- 1. DROP EXISTING TABLES FOR A CLEAN RUN
DROP TABLE IF EXISTS customer_staging CASCADE;
DROP TABLE IF EXISTS customer_cleaned CASCADE;

-- 2. CREATE STAGING TABLE WITH EXACT UPPERCASE CSV HEADERS
CREATE TABLE customer_staging (
    "CUST_ID" VARCHAR(50),
    "BALANCE" NUMERIC(12, 6),
    "BALANCE_FREQUENCY" NUMERIC(6, 5),
    "PURCHASES" NUMERIC(12, 2),
    "ONEOFF_PURCHASES" NUMERIC(12, 2),
    "INSTALLMENTS_PURCHASES" NUMERIC(12, 2),
    "CASH_ADVANCE" NUMERIC(12, 2),
    "PURCHASES_FREQUENCY" NUMERIC(6, 5),
    "ONEOFF_PURCHASES_FREQUENCY" NUMERIC(6, 5),
    "PURCHASES_INSTALLMENTS_FREQUENCY" NUMERIC(6, 5),
    "CASH_ADVANCE_FREQUENCY" NUMERIC(6, 5),
    "CASH_ADVANCE_TRX" INT,
    "PURCHASES_TRX" INT,
    "CREDIT_LIMIT" NUMERIC(10, 2),
    "PAYMENTS" NUMERIC(12, 2),
    "MINIMUM_PAYMENTS" NUMERIC(12, 2),
    "PRC_FULL_PAYMENT" NUMERIC(6, 5),
    "TENURE" INT
);

-- 3. TRANSFORMATION, CLEANING & DEDUPLICATION PIPELINE
CREATE TABLE customer_cleaned AS
WITH cleaned_staging AS (
    SELECT
        REPLACE(UPPER(TRIM("CUST_ID")), 'C', 'CUST_') AS formatted_cust_id,
        SUBSTRING(TRIM("CUST_ID") FROM 2) AS cust_numeric_suffix,
        LENGTH(TRIM("CUST_ID")) AS cust_id_length,
        COALESCE("CREDIT_LIMIT", 0.00) AS clean_credit_limit,
        COALESCE("MINIMUM_PAYMENTS", 0.00) AS clean_minimum_payments,
        CAST("TENURE" AS NUMERIC) AS tenure_numeric,
        DATE_TRUNC('month', CURRENT_TIMESTAMP) AS snapshot_month,
        "BALANCE" AS balance,
        "BALANCE_FREQUENCY" AS balance_frequency,
        "PURCHASES" AS purchases,
        "ONEOFF_PURCHASES" AS oneoff_purchases,
        "INSTALLMENTS_PURCHASES" AS installments_purchases,
        "CASH_ADVANCE" AS cash_advance,
        "PURCHASES_FREQUENCY" AS purchases_frequency,
        "ONEOFF_PURCHASES_FREQUENCY" AS oneoff_purchases_frequency,
        "PURCHASES_INSTALLMENTS_FREQUENCY" AS purchases_installments_frequency,
        "CASH_ADVANCE_FREQUENCY" AS cash_advance_frequency,
        "CASH_ADVANCE_TRX" AS cash_advance_trx,
        "PURCHASES_TRX" AS purchases_trx,
        "PAYMENTS" AS payments,
        "PRC_FULL_PAYMENT" AS prc_full_payment,
        "TENURE" AS tenure,
        CASE
            WHEN "BALANCE" > 5000 THEN 'High Balance'
            WHEN "BALANCE" BETWEEN 1000 AND 5000 THEN 'Medium Balance'
            ELSE 'Low Balance'
        END AS balance_tier,
        LOWER('Active_Credit_Customer') AS account_status_desc
    FROM customer_staging
),
ranked_customers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY formatted_cust_id ORDER BY balance DESC) AS row_num,
        RANK() OVER (PARTITION BY tenure ORDER BY purchases DESC) AS purchase_rank
    FROM cleaned_staging
)
SELECT
    formatted_cust_id,
    cust_numeric_suffix,
    cust_id_length,
    balance,
    balance_frequency,
    purchases,
    oneoff_purchases,
    installments_purchases,
    cash_advance,
    purchases_frequency,
    oneoff_purchases_frequency,
    purchases_installments_frequency,
    cash_advance_frequency,
    cash_advance_trx,
    purchases_trx,
    clean_credit_limit AS credit_limit,
    payments,
    clean_minimum_payments AS minimum_payments,
    prc_full_payment,
    tenure,
    tenure_numeric,
    snapshot_month,
    balance_tier,
    account_status_desc,
    purchase_rank
FROM ranked_customers
WHERE row_num = 1;

-- 4. VERIFICATION & QUALITY ASSURANCE
SELECT
    balance_tier,
    COUNT(*) AS customer_count,
    ROUND(AVG(balance), 2) AS avg_balance,
    ROUND(AVG(credit_limit), 2) AS avg_credit_limit
FROM customer_cleaned
GROUP BY balance_tier
ORDER BY avg_balance DESC;
```

---

## Verification & Results

Verification queries confirmed full row reconciliation (8,950 total records processed) and correct segmentation logic:

| Balance Tier | Customer Count | % of Total | Avg. Balance | Avg. Credit Limit |
|---|---|---|---|---|
| **High Balance** | 682 | 7.62% | $7,225.23 | $10,286.80 |
| **Medium Balance** | 3,468 | 38.75% | $2,223.39 | $4,457.38 |
| **Low Balance** | 4,800 | 53.63% | $284.11 | $3,697.30 |

**Data quality checks:**
- **Zero nulls remaining** — 1 missing `CREDIT_LIMIT` value and 313 missing `MINIMUM_PAYMENTS` values in the raw data were successfully imputed to `0.00`.
- **No duplicate customer IDs** — the source data contained 8,950 unique IDs; the `ROW_NUMBER()` deduplication logic is retained in the pipeline as a safeguard for future batches that may contain duplicates.
- **Row count preserved** — 8,950 records in, 8,950 records out.

---

## Files in This Repository

| File | Description |
|---|---|
| `Customer_Data.csv` | Raw source data from Kaggle (8,950 records, 18 columns) |
| `customer_staging_rows.csv` | Staged data after loading into `customer_staging` |
| `customer_cleaned_rows.csv` | Final cleaned, transformed, and deduplicated output |
| `README.md` | This file |
