# Bank Marketing Analytics: Who Should the Bank Call?

Goal: help a telemarketing team get more term deposit subscriptions from fewer calls.

Tools: MySQL, Tableau Public, R

Dataset: UCI Bank Marketing (bank-additional-full.csv). It has 41,188 calls from a Portuguese bank, from 2008 to 2010.
Link: https://archive.ics.uci.edu/dataset/222/bank+marketing

---

## Executive Summary

A Portuguese bank was calling clients to sell term deposits. About 1 in 9 clients subscribed (an 11.27% conversion rate) and it took 22.8 calls to win one subscription. I cleaned 41,188 call records in MySQL (41,176 after removing duplicates), built a Tableau dashboard, and fitted a logistic regression model in R to find out who the bank should call, how many times, and when.

What I found:

- Clients who said yes to an earlier campaign convert at 65.1%, compared to 9.4% for everyone else.
- Conversion drops as the number of calls to the same client goes up, from 13.0% at 1 call to 5.5% at 6 or more calls. Clients called 6+ times use 30.6% of all calls but only bring in 4.0% of subscriptions.
- Mobile converts at 14.74% and landline at 5.23%. A mobile sale takes 16.3 calls and a landline sale takes 54.5 calls.
- March, August and December are the best months. May, June and November are the worst. Day of the week makes almost no difference.
- The model has an AUC of 0.79. Calling only the top 10% of clients, ranked by the model, captures 42.3% of all subscriptions, which is 4.2 times better than calling at random.
---

## The Problem

A Portuguese bank phones clients to sell a term deposit. About 1 in 9 clients says yes, and every call costs the agents time. The campaign manager wants to know:

Who should we call, how many times, and when, so we get more subscriptions with fewer calls?

I used two numbers to answer this:

- Conversion rate: clients who subscribed divided by clients contacted
- Calls per subscription: total calls made divided by subscriptions won

At the start (the baseline), the conversion rate was 11.27% and it took 22.8 calls to get one subscription.

---

## What I Did

1. Clean the data in MySQL. I removed duplicates, fixed data types, dealt with the "unknown" values, and made age groups and call-count groups.
2. Explore the data in Tableau Public. I built a dashboard showing conversion by number of calls, month, channel and customer segment.
3. Build a model in R. I fitted a logistic regression to predict who is most likely to subscribe, then ranked the clients into deciles.
4. Wrote recommendations for the campaign manager.

---

## 1. Data Cleaning (MySQL)

Script: clean_data.sql

- Duplicates: I found and removed 12 exact duplicate rows. That took the data from 41,188 to 41,176 clients.
- Data types: I loaded everything as text first, then changed each column to the right type.
- Missing values: several columns have "unknown" in them. I kept "unknown" as its own category instead of deleting rows or guessing.
- New columns I made:
  - age_band: under 30, 30 to 39, 40 to 49, 50 to 59, 60+
  - campaign_bucket: 1, 2, 3 to 5, or 6+ calls per client
  - previously_contacted: turns the placeholder value 999 in pdays into a simple 0 or 1
- Column I left out: duration (how long the call lasted). We only know it after the call is done, so it can't help decide who to call. I did not use it in the model.

Unknown values by column:

- has_credit_default: 8,596 (20.88% of clients)
- education: 1,730 (4.20%)
- housing_loan: 990 (2.40%)
- personal_loan: 990 (2.40%)
- job: 330 (0.80%)
- marital: 80 (0.19%)

After cleaning I had 41,176 clients, 4,639 subscriptions, an 11.27% conversion rate and 105,735 calls.

Here are the main parts of the cleaning script, taken straight from clean_data.sql (shortened in a few places).

Load the raw file into a staging table. Every column is text at this stage:

```sql
CREATE TABLE stg_bank_marketing_raw (
    row_id         INT AUTO_INCREMENT PRIMARY KEY,
    age            VARCHAR(10),
    job            VARCHAR(30),
    -- ... other columns, all VARCHAR ...
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
```

Remove the exact duplicate rows by keeping only the first copy of each row:

```sql
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
```

Convert the data types and make the new columns (age_band, campaign_bucket and previously_contacted). The duration column is saved as duration_sec_do_not_model so I don't use it by mistake:

```sql
INSERT INTO bank_marketing_clean (...)
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
    -- ... other columns cast to the right type ...
    y,
    CAST(duration AS UNSIGNED)
FROM deduped
ORDER BY row_id;
```

Check how many duplicates were removed, then check the baseline numbers:

```sql
SELECT
    (SELECT COUNT(*) FROM stg_bank_marketing_raw) - COUNT(*) AS duplicate_rows_removed,
    COUNT(*) AS clients_after_cleaning
FROM bank_marketing_clean;

SELECT
    COUNT(*)                                             AS clients,
    SUM(y = 'yes')                                       AS subscriptions,
    ROUND(SUM(y = 'yes') / COUNT(*) * 100, 2)            AS conversion_rate_pct,
    SUM(campaign)                                        AS total_calls,
    ROUND(SUM(campaign) / SUM(y = 'yes'), 1)             AS calls_per_subscription
FROM bank_marketing_clean;
```

The unknown-values check uses the same pattern for each column (this one is for has_credit_default):

```sql
SELECT 'has_credit_default' AS column_name,
       SUM(has_credit_default = 'unknown') AS unknown_count,
       ROUND(SUM(has_credit_default = 'unknown') / COUNT(*) * 100, 2) AS pct_of_clients
FROM bank_marketing_clean;
```

---

## 2. Dashboard (Tableau Public)

The dashboard has four pages: Campaign Overview, Customer Segments, Contact Volume and Timing, and Channel, Day and Model Insights.

The workbook (Bank_Marketing_Analysis.twbx) 

What I found:

More calls to the same client means a lower chance of success.

- 1 call: 17,634 clients, 13.0% conversion
- 2 calls: 10,568 clients, 11.5% conversion
- 3 to 5 calls: 9,589 clients, 9.8% conversion
- 6 or more calls: 3,385 clients, 5.5% conversion

Clients who got 6 or more calls use 30.6% of all calls but only bring in 4.0% of subscriptions.

Mobile does better than landline.

- Cellular: 14.74% conversion, 16.3 calls per subscription
- Telephone (landline): 5.23% conversion, 54.5 calls per subscription

Other things I noticed:

- Month matters. March, August and December convert best. May, June and November convert worst.
- Day of the week doesn't really matter. Monday to Friday look almost the same.
- Past success matters the most. Clients who said yes to an earlier campaign convert at 65.1%, compared to 9.4% for everyone else.

---

## 3. Predictive Model (R)

Script: analysis_model.R

I fitted a logistic regression to predict whether a client will subscribe. I only used information we know before the call: age, job, previous campaign outcome, contact channel, month and economic indicators. I used 70% of the data to train the model and 30% to test it.

What drives conversion (these are odds ratios). A number above 1 means more likely to subscribe and a number below 1 means less likely, compared to the reference category.

- Contacted in March: 4.40 (much more likely)
- Previously contacted: 2.76 (more likely)
- Previous campaign was a success: 2.39 (more likely)
- Contacted in December: 1.70 (more likely)
- Contacted in August: 1.58 (more likely)
- 6+ calls to the same client: 0.72 (less likely)
- Contacted in May: 0.65 (less likely)
- Contacted in November: 0.61 (less likely)
- Contacted in June: 0.53 (less likely)
- Landline instead of mobile: 0.47 (much less likely)

Model results on the test set (12,352 clients): AUC is 0.79. This means the model ranks likely subscribers well above random chance.

I then ranked the clients by their predicted chance of subscribing and split them into 10 equal groups (deciles). Lift means how many times better the group does compared to calling at random.

- Decile 1 (top): 10% of clients called, 42.3% of subscriptions captured, lift 4.2x
- Decile 2: 20% of clients called, 62.8% captured, lift 3.1x
- Decile 3: 30% of clients called, 70.8% captured, lift 2.4x
- Decile 4: 40% of clients called, 76.3% captured, lift 1.9x
- Decile 5: 50% of clients called, 81.6% captured, lift 1.6x
- Decile 10 (bottom): 100% of clients called, 100% captured, lift 1.0x

If we only call the top 10% of clients, we capture 42% of all subscriptions. That is over 4 times better than calling at random.

Here are the main parts of the R script, taken from analysis_model.R (script snippet).

Load the cleaned data from MySQL and check it against the baseline numbers:

```r
library(DBI)
library(RMariaDB)
library(dplyr)
library(broom)
library(pROC)
library(caret)

con <- dbConnect(
  RMariaDB::MariaDB(),
  dbname   = "bank_marketing",
  host     = "localhost",
  port     = 3306,
  user     = Sys.getenv("BANK_DB_USER"),
  password = Sys.getenv("BANK_DB_PASSWORD")
)
bank <- dbGetQuery(con, "SELECT * FROM bank_marketing_clean")
dbDisconnect(con)

bank <- bank %>%
  mutate(
    y_flag = ifelse(y == "yes", 1, 0),
    across(c(job, marital, education, has_credit_default, housing_loan,
             personal_loan, contact_type, contact_month, contact_dow,
             poutcome, age_band, campaign_bucket), as.factor)
  )

cat("Clients:", nrow(bank), "(expected 41,176)\n")
cat("Subscriptions:", sum(bank$y_flag), "(expected 4,639)\n")
```

Split the data 70/30 and fit the logistic regression. I dropped duration (only known after the call) and the raw pdays and campaign columns, because I use previously_contacted and campaign_bucket instead:

```r
model_data <- bank %>%
  select(-client_id, -y, -duration_sec_do_not_model, -pdays, -campaign) %>%
  na.omit()

set.seed(42)
train_idx <- createDataPartition(model_data$y_flag, p = 0.7, list = FALSE)
train <- model_data[train_idx, ]
test  <- model_data[-train_idx, ]

model <- glm(y_flag ~ ., data = train, family = binomial)
```

Get the odds ratios:

```r
odds_ratios <- tidy(model, exponentiate = TRUE, conf.int = TRUE) %>%
  filter(term != "(Intercept)") %>%
  arrange(desc(estimate))
```

Check the model on the test set (AUC) and build the decile lift table:

```r
test$pred_prob <- predict(model, newdata = test, type = "response")

roc_obj <- roc(test$y_flag, test$pred_prob)
cat("AUC:", round(auc(roc_obj), 2), "\n")

# Rank clients by predicted probability and split into 10 equal groups
test <- test %>%
  arrange(desc(pred_prob)) %>%
  mutate(decile = ntile(desc(pred_prob), 10))

gains <- test %>%
  group_by(decile) %>%
  summarise(clients = n(), subscriptions = sum(y_flag)) %>%
  arrange(decile) %>%
  mutate(
    cum_clients       = cumsum(clients),
    cum_subs          = cumsum(subscriptions),
    pct_clients       = cum_clients / sum(clients),
    pct_subs_captured = cum_subs / sum(subscriptions),
    lift              = pct_subs_captured / pct_clients
  )
```

---

## 4. Recommendations for the Campaign Manager

Each recommendation has a simple explanation and then the numbers behind it. All the tests were done on 41,176 clients. The "95% CI" is the range where the true value most likely falls.

### 1. Call past customers first

In simple terms: someone who said yes to an earlier campaign is very likely to say yes again. These clients should be at the top of every call list.

The numbers:

- Conversion is 65.1% for clients with a successful earlier campaign, compared to 9.4% for everyone else.
- That is a gap of 55.7 percentage points (95% CI: 53.2 to 58.2). This is too big to be chance (p < 0.001).
- Previous campaign outcome is the strongest single factor in the data (Cramér's V = 0.32, which is a medium to large effect).

```r
# Conversion: success vs everyone else, with 95% CI on the difference
print(prop.test(c(x_success, x_rest), c(n_success, n_rest), correct = FALSE))

# Strength of the effect (Cramer's V)
tab_poutcome <- table(bank$poutcome, bank$y)
print(chisq.test(tab_poutcome))
print(cramerV(tab_poutcome))
```

### 2. Call clients in the order the model ranks them

In simple terms: the model gives every client a score for how likely they are to subscribe. If the team calls from the top of the list down, a small number of calls brings in most of the sales.

The numbers (tested on 12,352 clients the model had never seen):

- Calling the top 10% of clients captures 42.3% of all subscriptions, which is 4.2 times better than calling at random.
- Calling the top 20% captures 62.8% of subscriptions.
- The model AUC is 0.79. A score of 0.5 is random guessing and 1.0 is perfect, so the model is good at ranking clients but not perfect.

### 3. Stop after 5 calls per client

In simple terms: every extra call to the same person is less likely to work. After 5 calls, the time is better spent on someone new.

The numbers:

- Conversion goes from 13.0% (1 call) to 11.5% (2 calls), then 9.8% (3 to 5 calls) and 5.5% (6+ calls).
- The drop from 3 to 5 calls down to 6+ calls is statistically significant (p < 0.001). So is the drop from 1 call to 2 calls (p = 0.0001).
- Clients called 6+ times use 30.6% of all calls but only produce 4.0% of subscriptions.

```r
h2_summary <- bank %>%
  group_by(campaign_bucket) %>%
  summarise(clients = n(),
            subscriptions = sum(y_flag),
            conversion_rate = subscriptions / clients,
            calls = sum(campaign)) %>%
  mutate(share_of_calls         = calls / sum(calls),
         share_of_subscriptions = subscriptions / sum(subscriptions)) %>%
  arrange(campaign_bucket)

# 1 call vs 2 calls, and 3-5 calls vs 6+ calls
print(prop.test(x = h2_summary$subscriptions[1:2], n = h2_summary$clients[1:2]))
print(prop.test(x = h2_summary$subscriptions[3:4], n = h2_summary$clients[3:4]))
```

### 4. Use mobile numbers first

In simple terms: clients reached on a mobile phone are almost three times as likely to subscribe as clients reached on a landline, and it takes far fewer calls to get each sale.

The numbers:

- Conversion is 14.74% on mobile and 5.23% on landline. That is a gap of about 9.5 percentage points (95% CI: 8.9 to 10.1).
- A mobile sale takes 16.3 calls on average, compared to 54.5 calls on a landline.
- The model agrees. Landline contact roughly halves the odds of subscribing (odds ratio 0.47), even after taking the other factors into account.

```r
chan_summary <- bank %>%
  group_by(contact_type) %>%
  summarise(clients = n(),
            subscriptions = sum(y_flag),
            conversion_rate = subscriptions / clients,
            calls_per_subscription = sum(campaign) / subscriptions)

print(prop.test(c(x_cell, x_tel), c(n_cell, n_tel), correct = FALSE))
```

### 5. Focus campaigns on March, August and December

In simple terms: timing matters. Clients are more open to the offer in some months than others, so campaigns should be planned around those months.

The numbers (odds of subscribing compared to the reference month, with other factors kept equal):

- March: odds ratio 4.40 (over 4 times the odds)
- December: 1.70 (70% higher odds)
- August: 1.58 (58% higher odds)
- November: 0.61 (39% lower odds)
- May: 0.65 (35% lower odds)
- June: 0.53 (47% lower odds)

Month is the second strongest factor in the data (Cramér's V = 0.275). It is stronger than contact channel.

### 6. Don't plan the calling schedule around the day of the week

In simple terms: Monday to Friday perform almost the same, so there is nothing to gain from moving calls between weekdays.

The numbers: the effect of weekday is close to zero (Cramér's V = 0.025). The result can be detected because the dataset is large, but the difference is too small to matter in real life.

```r
cat("Month:      ", round(cramerV(table(bank$contact_month, bank$y)), 3), "\n")
cat("Day of week:", round(cramerV(table(bank$contact_dow,   bank$y)), 3), "\n")
```

### Summary

- Call past customers first: 65.1% vs 9.4% conversion
- Work down the ranked list: the top 10% of clients captures 42.3% of sales
- Cap calls at 5: 6+ calls make up 30.6% of calls but only 4.0% of sales
- Prefer mobile: 14.74% vs 5.23% conversion
- Focus on March, August and December: March odds are 4.4 times higher
- Ignore day of week: effect size is 0.025 (very small)

These results come from past data. Before changing the whole operation, I recommend testing the ranked list and the 5-call cap on a small batch of future calls and comparing the results with the current way of doing things.

---

## Limitations

- The data is from one Portuguese bank during 2008 to 2010, which includes the financial crisis. Results may be different today or in other countries.
- These are patterns in past data, not proven causes. Testing on real future calls is what would confirm them.
- Call counts are partly shaped by the outcome, because clients who subscribe stop being called. So the call cap finding should be used as a guide, not a guarantee.

---

## Repository


bank-additional-full.csv   - the dataset
clean_data.sql             - data cleaning and feature preparation (MySQL)
analysis_model.R           - logistic regression, odds ratios, decile lift
dashboard.twb (or images/) - Tableau dashboard workbook or screenshots

### Get the data

The dataset is from the UCI Machine Learning Repository (Bank Marketing): https://archive.ics.uci.edu/dataset/222/bank+marketing

Download it and use the file bank-additional/bank-additional-full.csv. It is separated by semicolons and has 41,188 rows and 21 columns.

### How to reproduce

1. Clean: load bank-additional-full.csv into MySQL and run clean_data.sql. This makes the cleaned table used in the later steps (41,176 clients, 4,639 subscriptions).
2. Model: run analysis_model.R. It connects to MySQL (set the BANK_DB_USER and BANK_DB_PASSWORD environment variables first), reads the cleaned table, fits the logistic regression, and prints the odds ratios and the decile lift table.
3. Dashboard: open dashboard.twb in Tableau, or look at the screenshots in images/.

Citation: S. Moro, P. Cortez and P. Rita. A Data-Driven Approach to Predict the Success of Bank Telemarketing. Decision Support Systems, 2014. doi:10.1016/j.dss.2014.03.001
