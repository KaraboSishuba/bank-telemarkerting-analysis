CREATE DATABASE IF NOT EXISTS bank_marketing CHARACTER SET utf8mb4;
USE bank_marketing;

DROP TABLE IF EXISTS stg_bank_marketing_raw;
CREATE TABLE stg_bank_marketing_raw (
    row_id         INT AUTO_INCREMENT PRIMARY KEY,
    age            VARCHAR(10),
    job            VARCHAR(30),
    marital        VARCHAR(20),
    education      VARCHAR(30),
    `default`      VARCHAR(10),
    housing        VARCHAR(10),
    loan           VARCHAR(10),
    contact        VARCHAR(20),
    month          VARCHAR(10),
    day_of_week    VARCHAR(10),
    duration       VARCHAR(10),
    campaign       VARCHAR(10),
    pdays          VARCHAR(10),
    previous       VARCHAR(10),
    poutcome       VARCHAR(20),
    emp_var_rate   VARCHAR(10),
    cons_price_idx VARCHAR(10),
    cons_conf_idx  VARCHAR(10),
    euribor3m      VARCHAR(10),
    nr_employed    VARCHAR(10),
    y              VARCHAR(5)
) ENGINE=InnoDB;

LOAD DATA LOCAL INFILE 'bank-additional-full.csv'
INTO TABLE stg_bank_marketing_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(age, job, marital, education, `default`, housing, loan, contact, month,
 day_of_week, duration, campaign, pdays, previous, poutcome,
 emp_var_rate, cons_price_idx, cons_conf_idx, euribor3m, nr_employed, y);

SELECT COUNT(*) AS rows_loaded FROM stg_bank_marketing_raw;

DROP TABLE IF EXISTS bank_marketing_clean;
CREATE TABLE bank_marketing_clean (
    client_id                 INT AUTO_INCREMENT PRIMARY KEY,
    age                       TINYINT UNSIGNED,
    age_band                  VARCHAR(10),
    job                       VARCHAR(30),
    marital                   VARCHAR(20),
    education                 VARCHAR(30),
    has_credit_default        VARCHAR(10),
    housing_loan              VARCHAR(10),
    personal_loan             VARCHAR(10),
    contact_type              VARCHAR(20),
    contact_month             VARCHAR(10),
    contact_dow               VARCHAR(10),
    campaign                  TINYINT UNSIGNED,
    campaign_bucket           VARCHAR(10),
    pdays                     SMALLINT UNSIGNED,
    previously_contacted      TINYINT(1),
    previous                  TINYINT UNSIGNED,
    poutcome                  VARCHAR(20),
    emp_var_rate              DECIMAL(4,1),
    cons_price_idx            DECIMAL(6,3),
    cons_conf_idx             DECIMAL(4,1),
    euribor3m                 DECIMAL(5,3),
    nr_employed               DECIMAL(7,1),
    y                         VARCHAR(5),
    duration_sec_do_not_model SMALLINT UNSIGNED
) ENGINE=InnoDB;

INSERT INTO bank_marketing_clean
    (age, age_band, job, marital, education, has_credit_default, housing_loan,
     personal_loan, contact_type, contact_month, contact_dow, campaign,
     campaign_bucket, pdays, previously_contacted, previous, poutcome,
     emp_var_rate, cons_price_idx, cons_conf_idx, euribor3m, nr_employed,
     y, duration_sec_do_not_model)
WITH numbered AS (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY age, job, marital, education, `default`, housing, loan,
                            contact, month, day_of_week, duration, campaign, pdays,
                            previous, poutcome, emp_var_rate, cons_price_idx,
                            cons_conf_idx, euribor3m, nr_employed, y
               ORDER BY row_id
           ) AS copy_number
    FROM stg_bank_marketing_raw r
),
deduped AS (
    SELECT * FROM numbered WHERE copy_number = 1
)
SELECT
    CAST(age AS UNSIGNED),
    CASE
        WHEN CAST(age AS UNSIGNED) < 30 THEN 'under_30'
        WHEN CAST(age AS UNSIGNED) BETWEEN 30 AND 39 THEN '30_39'
        WHEN CAST(age AS UNSIGNED) BETWEEN 40 AND 49 THEN '40_49'
        WHEN CAST(age AS UNSIGNED) BETWEEN 50 AND 59 THEN '50_59'
        ELSE 'sixty_plus'
    END,
    job, marital, education,
    `default`, housing, loan,
    contact, month, day_of_week,
    CAST(campaign AS UNSIGNED),
    CASE
        WHEN CAST(campaign AS UNSIGNED) = 1 THEN '1'
        WHEN CAST(campaign AS UNSIGNED) = 2 THEN '2'
        WHEN CAST(campaign AS UNSIGNED) BETWEEN 3 AND 5 THEN '3_5'
        ELSE '6_plus'
    END,
    CAST(pdays AS UNSIGNED),
    CASE WHEN CAST(pdays AS UNSIGNED) = 999 THEN 0 ELSE 1 END,
    CAST(previous AS UNSIGNED),
    poutcome,
    CAST(emp_var_rate AS DECIMAL(4,1)),
    CAST(cons_price_idx AS DECIMAL(6,3)),
    CAST(cons_conf_idx AS DECIMAL(4,1)),
    CAST(euribor3m AS DECIMAL(5,3)),
    CAST(nr_employed AS DECIMAL(7,1)),
    y,
    CAST(duration AS UNSIGNED)
FROM deduped
ORDER BY row_id;

SELECT
    (SELECT COUNT(*) FROM stg_bank_marketing_raw) - COUNT(*) AS duplicate_rows_removed,
    COUNT(*) AS clients_after_cleaning
FROM bank_marketing_clean;

SELECT 'has_credit_default' AS column_name,
       SUM(has_credit_default = 'unknown') AS unknown_count,
       ROUND(SUM(has_credit_default = 'unknown') / COUNT(*) * 100, 2) AS pct_of_clients
FROM bank_marketing_clean
UNION ALL
SELECT 'education', SUM(education = 'unknown'),
       ROUND(SUM(education = 'unknown') / COUNT(*) * 100, 2) FROM bank_marketing_clean
UNION ALL
SELECT 'housing_loan', SUM(housing_loan = 'unknown'),
       ROUND(SUM(housing_loan = 'unknown') / COUNT(*) * 100, 2) FROM bank_marketing_clean
UNION ALL
SELECT 'personal_loan', SUM(personal_loan = 'unknown'),
       ROUND(SUM(personal_loan = 'unknown') / COUNT(*) * 100, 2) FROM bank_marketing_clean
UNION ALL
SELECT 'job', SUM(job = 'unknown'),
       ROUND(SUM(job = 'unknown') / COUNT(*) * 100, 2) FROM bank_marketing_clean
UNION ALL
SELECT 'marital', SUM(marital = 'unknown'),
       ROUND(SUM(marital = 'unknown') / COUNT(*) * 100, 2) FROM bank_marketing_clean;

SELECT
    COUNT(*)                                             AS clients,
    SUM(y = 'yes')                                       AS subscriptions,
    ROUND(SUM(y = 'yes') / COUNT(*) * 100, 2)            AS conversion_rate_pct,
    SUM(campaign)                                        AS total_calls,
    ROUND(SUM(campaign) / SUM(y = 'yes'), 1)             AS calls_per_subscription
FROM bank_marketing_clean;
