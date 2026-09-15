-- =====================================================================
-- CUSTOMER DATA SQL CLEANING & TRANSFORMATION PIPELINE IN SUPABASE
-- =====================================================================

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