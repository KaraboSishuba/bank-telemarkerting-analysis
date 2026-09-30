# Bank Marketing Analytics: Who Should the Bank Call?

**Goal: help a telemarketing team get more term-deposit subscriptions from fewer calls.**

**Tools:** MySQL · Tableau Public · R  
**Dataset:** [UCI Bank Marketing](https://archive.ics.uci.edu/dataset/222/bank+marketing) (`bank-additional-full.csv`, 41,188 calls from a Portuguese bank, 2008–2010)

---

## The Problem

A Portuguese bank phones clients to sell a **term deposit**. Roughly 1 in 9 clients subscribes, and every call costs agent time. The campaign manager wants to know:

> **Who should we call, how many times, and when, to get more subscriptions with fewer calls?**

**Two metrics drive the whole project:**

| Metric | Definition |
|---|---|
| **Conversion rate** | Clients who subscribed ÷ clients contacted |
| **Calls per subscription** | Total calls made ÷ subscriptions won |

**Baseline:** 11.27% conversion and 22.8 calls per subscription.

---

## Project Workflow

| Step | What I did | Tool |
|---|---|---|
| 1. Clean | Removed duplicates, fixed data types, handled `unknown` values, created age groups and call-count buckets | MySQL |
| 2. Explore | Built an interactive dashboard of conversion by contact count, month, channel and segment | Tableau Public |
| 3. Model | Fitted a logistic regression to predict who is most likely to subscribe, then ranked clients into deciles | R |
| 4. Recommend | Turned the findings into clear actions for the campaign manager | This README |

---

## 1. Data Cleaning (MySQL)

Script: `bank_marketing_clean.sql`

- **Duplicates:** found and removed 12 exact duplicate rows (41,188 → 41,176 clients).
- **Data types:** loaded everything as text first, then converted each column to its proper type.
- **Missing values:** `unknown` appears in several columns. I kept it as its own category rather than deleting or guessing values.
- **New columns:**
  - `age_band`: under 30, 30–39, 40–49, 50–59, 60+
  - `campaign_bucket`: 1, 2, 3–5, 6+ calls per client
  - `previously_contacted`: turns the placeholder value `999` in `pdays` into a simple 0/1 flag
- **Excluded column:** `duration` (call length) is only known *after* the call, so it cannot be used to decide who to call. I left it out of the model.

**Unknown values by column:**

| Column | Unknown | % of clients |
|---|---|---|
| `has_credit_default` | 8,596 | 20.88% |
| `education` | 1,730 | 4.20% |
| `housing_loan` | 990 | 2.40% |
| `personal_loan` | 990 | 2.40% |
| `job` | 330 | 0.80% |
| `marital` | 80 | 0.19% |

After cleaning: **41,176 clients, 4,639 subscriptions, 11.27% conversion, 105,735 calls.**

---

## 2. Dashboard (Tableau Public)

Four dashboard pages: Campaign Overview, Customer Segments, Contact Volume & Timing, and Channel, Day & Model Insights.

**Live dashboard:** *add your Tableau Public URL here*  
The workbook (`dashboard.twb`) or screenshots (`images/`) are included in this repo.

**Key findings:**

**More calls to the same client means a lower chance of success**

| Calls to a client | Clients | Conversion rate |
|---|---|---|
| 1 | 17,634 | 13.0% |
| 2 | 10,568 | 11.5% |
| 3–5 | 9,589 | 9.8% |
| 6+ | 3,385 | 5.5% |

Clients who received 6 or more calls take up **30.6% of all calls** but produce only **4.0% of subscriptions**.

**Mobile beats landline**

| Channel | Conversion rate | Calls per subscription |
|---|---|---|
| Cellular | 14.74% | 16.3 |
| Telephone (landline) | 5.23% | 54.5 |

**Other patterns**
- **Month matters:** March, August and December convert best. May, June and November convert worst.
- **Day of week doesn't matter:** Monday to Friday look almost identical.
- **Past success matters most:** clients who said yes to an earlier campaign convert at **65.1%**, versus **9.4%** for everyone else.

---

## 3. Predictive Model (R)

Script: `analysis_model.R`

I fitted a **logistic regression** to predict whether a client will subscribe, using only information known *before* the call (age, job, previous campaign outcome, contact channel, month, economic indicators). The data was split 70% for training and 30% for testing.

**What drives conversion** (odds ratios; above 1 means more likely to subscribe, below 1 means less likely, compared with the reference category):

| Factor | Odds ratio | Meaning |
|---|---|---|
| Contacted in March | 4.40 | Much more likely to subscribe |
| Previously contacted | 2.76 | More likely |
| Previous campaign was a success | 2.39 | More likely |
| Contacted in December | 1.70 | More likely |
| Contacted in August | 1.58 | More likely |
| 6+ calls to the same client | 0.72 | Less likely |
| Contacted in May | 0.65 | Less likely |
| Contacted in November | 0.61 | Less likely |
| Contacted in June | 0.53 | Less likely |
| Landline instead of mobile | 0.47 | Much less likely |

**Model results on the test set (12,352 clients):** **AUC = 0.79**, meaning the model ranks likely subscribers well above random chance.

Clients were ranked by predicted probability and split into 10 equal groups (deciles):

| Decile | Cumulative % of clients called | Cumulative % of subscriptions captured | Lift |
|---|---|---|---|
| 1 (top) | 10% | 42.3% | 4.2× |
| 2 | 20% | 62.8% | 3.1× |
| 3 | 30% | 70.8% | 2.4× |
| 4 | 40% | 76.3% | 1.9× |
| 5 | 50% | 81.6% | 1.6× |
| 10 (bottom) | 100% | 100% | 1.0× |

**Calling only the top 10% of clients captures 42% of all subscriptions. That is over 4× better than calling at random.**

---

## 4. Recommendations for the Campaign Manager

Each recommendation has a plain-English version for the team and the statistical evidence behind it. All differences below are tested on 41,176 clients, and "95% CI" is the range the true value most likely falls in.

### 1. Call past customers first

**Clarified:** Someone who said yes to an earlier campaign is very likely to say yes again. These clients should go to the top of every call list.

**Evidence:**
- Conversion is **65.1%** for clients with a successful earlier campaign, versus **9.4%** for everyone else.
- That is a gap of **55.7 percentage points (95% CI: 53.2 to 58.2)**, far too large to be chance (p < 0.001).
- Previous campaign outcome is the strongest single factor in the data (Cramér's V = 0.32, a medium-to-large effect).

### 2. Call clients in the order the model ranks them

**Clarified:** The model gives every client a score for how likely they are to subscribe. If the team calls from the top of that list, a small share of the calls brings in most of the sales.

**Evidence (on 12,352 clients the model had never seen):**
- Calling the **top 10%** of clients captures **42.3%** of all subscriptions, which is **4.2× better than calling at random**.
- Calling the **top 20%** captures **62.8%** of subscriptions.
- Model AUC is **0.79**. A score of 0.5 is random guessing and 1.0 is perfect, so the model ranks clients well but not perfectly.

### 3. Stop after 5 calls per client

**Clarified:** Every extra call to the same person is less likely to work. After 5 calls, the time is better spent on someone new.

**Evidence:**
- Conversion falls from **13.0%** (1 call) to **11.5%** (2 calls), **9.8%** (3 to 5 calls) and **5.5%** (6+ calls).
- The drop from 3 to 5 calls down to 6+ calls is statistically significant (p < 0.001), as is the drop from 1 call to 2 calls (p = 0.0001).
- Clients called 6+ times use **30.6% of all calls** but produce only **4.0% of subscriptions**.

### 4. Use mobile numbers first

**Clarified:** Clients reached on a mobile phone are almost three times as likely to subscribe as clients reached on a landline, and it takes far fewer calls to win each sale.

**Evidence:**
- Conversion is **14.74%** on mobile versus **5.23%** on landline, a gap of about **9.5 percentage points (95% CI: 8.9 to 10.1)**.
- A mobile sale takes **16.3 calls** on average, versus **54.5 calls** on a landline.
- The model agrees: landline contact roughly halves the odds of subscribing (odds ratio 0.47), even after accounting for the other factors.

### 5. Concentrate campaigns in March, August and December

**Clarified:** Timing matters. Clients are noticeably more receptive in some months than others, so campaign pushes should be planned around those months.

**Evidence (odds of subscribing versus the reference month, with other factors held equal):**

| Month | Odds ratio | Meaning |
|---|---|---|
| March | 4.40 | Over 4× the odds |
| December | 1.70 | 70% higher odds |
| August | 1.58 | 58% higher odds |
| November | 0.61 | 39% lower odds |
| May | 0.65 | 35% lower odds |
| June | 0.53 | 47% lower odds |

Month is the second-strongest factor in the data (Cramér's V = 0.275), stronger than contact channel.

### 6. Don't plan the calling schedule around the day of the week

**Clarified:** Monday to Friday perform almost the same, so there is nothing to gain from moving calls between weekdays.

**Evidence:** The effect of weekday is close to zero (Cramér's V = 0.025). The result is technically detectable because the dataset is large, but the difference is too small to matter in practice.

### Summary

| Action | Key number |
|---|---|
| Call past customers first | 65.1% vs 9.4% conversion |
| Work down the ranked list | Top 10% of clients captures 42.3% of sales |
| Cap calls at 5 | 6+ calls: 30.6% of calls, 4.0% of sales |
| Prefer mobile | 14.74% vs 5.23% conversion |
| Focus on March, August, December | March odds 4.4× higher |
| Ignore day of week | Effect size 0.025 (negligible) |

**Next step:** these results come from past data, so before changing the whole operation we recommend testing the ranked list and the 5-call cap on a small batch of future calls and comparing the results with the current approach.

---

## Limitations

- The data comes from **one Portuguese bank during 2008–2010**, including the financial crisis. Results may differ today or in other markets.
- These are **patterns in past data, not proven causes.** Testing on real future calls is what would confirm them.
- Call counts are partly shaped by outcomes, because clients who subscribe stop being called. Treat the call-cap finding as a guide, not a guarantee.

---

## Repository

```
├── bank-additional-full.csv   # The dataset 
├── clean_data.sql             # Data cleaning and feature preparation (MySQL)
├── analysis_model.R           # Logistic regression, feature importance (odds ratios), decile lift
└── dashboard.twb (or images/) # Tableau dashboard workbook or screenshots
```

### Get the data

The dataset is from the UCI Machine Learning Repository: [Bank Marketing](https://archive.ics.uci.edu/dataset/222/bank+marketing). Download it and use the file `bank-additional/bank-additional-full.csv` (semicolon-separated, 41,188 rows, 21 columns).

### How to reproduce

1. **Clean:** load `bank-additional-full.csv` into MySQL and run `clean_data.sql`. This produces the cleaned table used in every later step (41,176 clients, 4,639 subscriptions).
2. **Model:** run `analysis_model.R`. It reads the cleaned data, fits the logistic regression, and prints the odds ratios and the decile lift table.
3. **Dashboard:** open `dashboard.twb` in Tableau, or view the screenshots in `images/`.

**Citation:** S. Moro, P. Cortez and P. Rita. *A Data-Driven Approach to Predict the Success of Bank Telemarketing.* Decision Support Systems, 2014. doi:10.1016/j.dss.2014.03.001