# Project 1 - Credit Risk Case Study

**Author:** Karabo Sishuba

---

## Thesis

**Balance tier is a statistically valid and commercially actionable segmentation: a small High Balance segment (7.6% of customers) concentrates both the bank's credit exposure and its highest-value spending behavior, while the majority Low Balance segment (53.6% of customers) is high-volume but low-value. Credit policy, underwriting attention, and growth strategy should therefore be tier-differentiated rather than uniform.**

Every phase of this project — the SQL segmentation pipeline, the BI dashboard, and the hypothesis tests below — exists to test and support this statement: first by building the tiers, then by visualizing the gap between them, then by proving statistically that the gap is real and not due to chance.

---

## Executive Summary

| | |
|---|---|
| **Dataset** | Credit Card Customer Segmentation Data (Kaggle) |
| **Raw records** | 8,950 |
| **Environment** | PostgreSQL (Supabase), Power BI, R (Quarto) |
| **Objective** | Stage, clean, transform, deduplicate, and verify raw customer data; segment customers by balance tier; visualize the results in an interactive dashboard; and statistically test whether balance tier is a meaningful driver of credit limit and purchasing behavior |
| **Techniques used** | 12 core SQL functions (cleaning/transformation), Power BI dashboarding with DAX measures, one-way ANOVA, Tukey HSD post-hoc testing, Welch's t-test |

The raw dataset arrived with inconsistent ID formatting, missing financial values, and no built-in deduplication or segmentation logic. This project takes it through three phases: (1) a SQL pipeline that produces a clean, analysis-ready table (`customer_cleaned`), (2) a Power BI dashboard for exploratory and stakeholder-facing reporting, and (3) formal statistical testing to confirm the segmentation is meaningful and to quantify differences between customer tiers.

---

## Business Solutions

Each solution below is a direct response to the thesis, supported by the evidence in Phases 1–3.

1. **Move from a uniform credit policy to tier-based credit bands.** The ANOVA (F = 1254, p < 2e-16) and every pairwise Tukey comparison (p < 0.001) confirm credit limit differs significantly across all three tiers. A single blanket limit-setting rule is statistically unjustified — implement tier-specific (or balance-driven, model-based) limit bands instead.

2. **Route High Balance customers into a dedicated underwriting and relationship-management track.** This tier is only 7.6% of the base (682 customers) but holds the highest average credit limit ($10,287) and the highest average spend ($1,897). It carries a disproportionate share of total credit exposure and deserves closer, higher-touch review than the standard process.

3. **Build a targeted upsell and rewards program for the High Balance tier.** The Welch t-test confirms High Balance customers spend significantly more than Low Balance customers (p = 7.5e-11, 95% CI $739–$1,364 higher) — this is observed spending, not just unused capacity. Since spend is real and volatile (SD ≈ $4,126), a tiered rewards or limit-increase offer aimed at this group is likely to convert.

4. **Treat the Low Balance tier as a volume-engagement segment, not a risk-reduction one.** At 53.6% of customers (4,800) with the lowest average balance ($284) and credit limit ($3,697), this segment is best served by low-touch, automated products (entry-level cards, spend-triggered offers) rather than the manual review reserved for the High Balance tier. Its aggregate exposure should still be monitored, since volume can offset the low per-customer risk.

5. **Extend the analysis with a default/delinquency signal before making risk (not just value) claims.** The current tests measure credit limit and purchase differences, not default outcomes. Before using balance tier to set risk-based pricing or reserves, add a delinquency flag and re-run the tier comparison, and consider a regression using `balance`, `tenure`, and `cash_advance_frequency` as continuous predictors to sharpen the segmentation further.

---

## Phase 1 — SQL Cleaning & Transformation Pipeline

### 12 Core SQL Functions Applied

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

### Pipeline Implementation

```sql
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
```

### Verification & Results

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

## Phase 2 — Visualizations & BI Dashboard

**Tool:** Power BI (`Customer_Credit_Report_Dashboard.pbix`)

The cleaned `customer_cleaned` table feeds a Power BI report built for stakeholder-facing exploration of the customer base by balance tier. The report covers:

- **Segment overview** — customer counts and share of base by `balance_tier` (High / Medium / Low Balance).
- **Credit exposure** — average and total credit limit, balance, and payments by tier.
- **Purchasing behavior** — purchase volume and frequency (one-off vs. installment) broken out by tier and tenure.
- **Cash advance usage** — cash advance amount and frequency by tier, as an early indicator of liquidity stress.

*(Open `Customer_Credit_Report_Dashboard.pbix` in Power BI Desktop to interact with the live filters and drill-throughs.)*

### KPI Measures (DAX)

```dax
-- Base counts

Total Customers =
DISTINCTCOUNT(customer_cleaned[formatted_cust_id])

Customers by Tier =
CALCULATE(
    [Total Customers],
    ALLEXCEPT(customer_cleaned, customer_cleaned[balance_tier])
)

% of Customer Base =
DIVIDE([Customers by Tier], [Total Customers])

-- Credit exposure

Total Credit Exposure =
SUM(customer_cleaned[credit_limit])

Avg Credit Limit =
AVERAGE(customer_cleaned[credit_limit])

Credit Exposure Share by Tier =
DIVIDE(
    CALCULATE([Total Credit Exposure], ALLEXCEPT(customer_cleaned, customer_cleaned[balance_tier])),
    CALCULATE([Total Credit Exposure], ALL(customer_cleaned))
)

Credit Utilization Rate =
AVERAGEX(
    customer_cleaned,
    DIVIDE(customer_cleaned[balance], customer_cleaned[credit_limit], 0)
)

-- Spend & liquidity risk signals

Avg Balance =
AVERAGE(customer_cleaned[balance])

Avg Purchases =
AVERAGE(customer_cleaned[purchases])

Avg Cash Advance Frequency =
AVERAGE(customer_cleaned[cash_advance_frequency])

Avg Full-Payment Rate =
AVERAGE(customer_cleaned[prc_full_payment])
```

- **`Credit Exposure Share by Tier`** is the KPI that most directly supports the thesis — it quantifies how much of total credit exposure sits with the small High Balance tier versus the much larger Low Balance tier.
- **`Credit Utilization Rate`** and **`Avg Cash Advance Frequency`** are early-warning KPIs worth tracking per tier as a proxy for risk until a true delinquency field is available (see Business Solution #5).

A companion interactive R/Quarto dashboard (`Credit_Risk_Stats_Analysis.qmd`, rendered to `Credit_Risk_Stats_Analysis.html`) supplements the Power BI report with a balance-distribution boxplot by tier and a purchases-vs-balance scatter plot, alongside the statistical outputs below.

### Quarto Dashboard Source

`````qmd
---
title: "Credit Risk Analysis Dashboard"
author: "Karabo Sishuba"
format: dashboard
scrolling: true
---

```{r}
#| include: false
library(tidyverse)
library(rstatix)
library(car)
library(DT)
library(ggplot2)
library(plotly)

# Load data
customer_data <- read_csv("C:/Users/Dell/Downloads/customer_cleaned_rows.csv")

# ANOVA & Post-Hoc Analysis
anova_model <- aov(balance ~ balance_tier, data = customer_data)
anova_summary <- summary(anova_model)
tukey_results <- TukeyHSD(anova_model)

# Summary Table Data
credit_summary <- customer_data %>%
  group_by(balance_tier) %>%
  summarise(
    Total_Customers = n(),
    Mean_Balance = mean(balance, na.rm = TRUE),
    Median_Balance = median(balance, na.rm = TRUE),
    .groups = "drop"
  )

# Graph 1: Balance Distribution by Tier
p1 <- ggplot(customer_data, aes(x = balance_tier, y = balance, fill = balance_tier)) +
  geom_boxplot(alpha = 0.7) +
  theme_minimal() +
  labs(title = "Balance Distribution by Tier", x = "Balance Tier", y = "Balance") +
  theme(legend.position = "none")

# Graph 2: Purchases vs. Balance Scatter Plot
p2 <- ggplot(customer_data, aes(x = purchases, y = balance, color = balance_tier)) +
  geom_point(alpha = 0.5, size = 1.5) +
  theme_minimal() +
  labs(title = "Purchases vs. Balance", x = "Purchases", y = "Balance", color = "Balance Tier")
```

Row
ANOVA Model Summary
```{r}
#| echo: false
print(anova_summary)
```

Tukey HSD Post-Hoc Results
```{r}
#| echo: false
print(tukey_results)
```

Row
Balance Distribution
```{r}
#| echo: false
#| warning: false
ggplotly(p1)
```

Purchases vs. Balance
```{r}
#| echo: false
#| warning: false
ggplotly(p2)
```

Row
Interactive Credit Summary Table
```{r}
#| echo: false
#| warning: false
datatable(credit_summary, options = list(pageLength = 5, scrollX = TRUE))
```
`````

> **Note:** the Quarto dashboard's ANOVA model (`balance ~ balance_tier`) differs from the ANOVA reported below (`credit_limit ~ balance_tier`, from `Credit_Risk_Analysis.pdf`). Since `balance_tier` is itself derived directly from `balance`, testing `balance ~ balance_tier` is close to tautological (it will always be highly significant) and mainly useful as a sanity check that the tiers were cut correctly. The `credit_limit ~ balance_tier` model below is the more meaningful test of the thesis, since it asks whether a variable *not* used to define the tiers still differs significantly across them.

---

## Phase 3 — Statistical Analysis (Hypothesis Testing & ANOVA)

**Tool:** R (`Credit_Risk_Analysis.pdf` / `Credit_Risk_Stats_Analysis.qmd`)

The goal of Phase 3 was to confirm, statistically, that the `balance_tier` segmentation built in Phase 1 corresponds to real, significant differences in customer behavior — the direct evidence base for the thesis above.

### R Script

```r
library(tidyverse)

customer_data <- read_csv("C:/Users/Dell/Downloads/customer_cleaned_rows.csv")

anova_model <- aov(credit_limit ~ balance_tier, data = customer_data)
summary(anova_model)

tukey_results <- TukeyHSD(anova_model)
print(tukey_results)

credit_summary <- customer_data %>%
  group_by(balance_tier) %>%
  summarise(
    count = n(),
    mean_credit = mean(credit_limit, na.rm = TRUE),
    sd_credit = sd(credit_limit, na.rm = TRUE),
    median_credit = median(credit_limit, na.rm = TRUE)
  )
print(credit_summary)

t_test_subset <- customer_data %>%
  filter(balance_tier %in% c("Low Balance", "High Balance"))

t_test_result <- t.test(purchases ~ balance_tier, data = t_test_subset, var.equal = FALSE)
print(t_test_result)

purchases_summary <- t_test_subset %>%
  group_by(balance_tier) %>%
  summarise(
    count = n(),
    mean_purchases = mean(purchases, na.rm = TRUE),
    sd_purchases = sd(purchases, na.rm = TRUE),
    median_purchases = median(purchases, na.rm = TRUE)
  )
print(purchases_summary)
```

### One-way ANOVA — Credit Limit by Balance Tier

```
                Df    Sum Sq   Mean Sq F value  Pr(>F)
balance_tier     2 2.594e+10 1.297e+10    1254  <2e-16 ***
Residuals     8947 9.256e+10 1.035e+07
```

- **Result:** F(2, 8947) = 1254, p < 2e-16 — highly statistically significant.
- **Supports the thesis by:** proving balance tier explains a large, significant share of the variation in credit limit — the segmentation carries real financial signal, not noise.

### Tukey HSD Post-Hoc Comparison

| Comparison | Mean Diff | 95% CI | Adj. p-value |
|---|---|---|---|
| Low Balance − High Balance | −$6,589.51 | [−6,898.05, −6,280.97] | < 0.001 |
| Medium Balance − High Balance | −$5,829.42 | [−6,145.25, −5,513.59] | < 0.001 |
| Medium Balance − Low Balance | +$760.09 | [592.05, 928.12] | < 0.001 |

- **Supports the thesis by:** confirming every pair of tiers differs significantly, not just High vs. Low — High Balance customers are extended roughly double the credit of Medium Balance customers, and more than 2.5x that of Low Balance customers.

### Credit Limit Summary by Tier

| Balance Tier | n | Mean | SD | Median |
|---|---|---|---|---|
| High Balance | 682 | $10,287 | $3,494 | $9,500 |
| Medium Balance | 3,468 | $4,457 | $3,135 | $3,500 |
| Low Balance | 4,800 | $3,697 | $3,234 | $2,500 |

### Welch Two-Sample t-test — Purchases, High vs. Low Balance

```
t = 6.6119, df = 699.17, p-value = 7.533e-11
95% CI on the difference in means: [739.31, 1363.82]
Mean (High Balance): 1,897.22   Mean (Low Balance): 845.65
```

| Balance Tier | n | Mean Purchases | SD | Median |
|---|---|---|---|---|
| High Balance | 682 | 1,897 | 4,126 | 409 |
| Low Balance | 4,800 | 846 | 1,261 | 402 |

- **Result:** t(699.17) = 6.61, p = 7.5e-11 — highly statistically significant.
- **Supports the thesis by:** showing High Balance customers spend significantly more, not just hold higher limits — the "high-value" half of the thesis is a behavioral fact, not a paper credit assumption. The large SD in the High Balance group also shows this value is unevenly distributed, driven by a subset of high-volume spenders within the tier.

---

## Files in This Repository

| File | Description |
|---|---|
| `Customer_Data.csv` | Raw source data from Kaggle (8,950 records, 18 columns) |
| `customer_staging_rows.csv` | Staged data after loading into `customer_staging` |
| `customer_cleaned_rows.csv` | Final cleaned, transformed, and deduplicated output |
| `Customer_Credit_Report_Dashboard.pbix` | Power BI dashboard (Phase 2) |
| `Credit_Risk_Stats_Analysis.qmd` | Quarto/R source for the statistical dashboard (Phase 3) |
| `Credit_Risk_Stats_Analysis.html` | Rendered interactive Quarto dashboard (Phase 3) |
| `Credit_Risk_Analysis.pdf` | Rendered ANOVA / Tukey HSD / t-test output (Phase 3) |
| `README.md` | This file |
