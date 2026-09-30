# install.packages(c("DBI", "RMariaDB", "dplyr", "tidyr", "broom",
#                    "pROC", "rcompanion", "caret"))
library(DBI)
library(RMariaDB)
library(dplyr)
library(tidyr)
library(broom)
library(pROC)
library(rcompanion)   
library(caret)        



# 1. Load the cleaned data
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

# check against the baseline
cat("Clients:", nrow(bank), "(expected 41,176)\n")
cat("Subscriptions:", sum(bank$y_flag), "(expected 4,639)\n")
cat("Conversion rate:", round(mean(bank$y_flag) * 100, 2), "% (expected 11.27%)\n")
cat("Total calls:", sum(bank$campaign), "(expected 105,735)\n")
cat("Calls per subscription:",
    round(sum(bank$campaign) / sum(bank$y_flag), 1), "(expected 22.8)\n\n")



# 2. Logistic regression
model_data <- bank %>%
  select(-client_id, -y, -duration_sec_do_not_model, -pdays, -campaign) %>%
  na.omit()

set.seed(42)
train_idx <- createDataPartition(model_data$y_flag, p = 0.7, list = FALSE)
train <- model_data[train_idx, ]
test  <- model_data[-train_idx, ]

model <- glm(y_flag ~ ., data = train, family = binomial)


# 3. What drives conversion: odds ratios 

odds_ratios <- tidy(model, exponentiate = TRUE, conf.int = TRUE) %>%
  filter(term != "(Intercept)") %>%
  arrange(desc(estimate))

readme_factors <- c(
  contact_monthmar      = "Contacted in March",
  previously_contacted  = "Previously contacted",
  poutcomesuccess       = "Previous campaign was a success",
  contact_monthdec      = "Contacted in December",
  contact_monthaug      = "Contacted in August",
  campaign_bucket6_plus = "6+ calls to the same client",
  contact_monthmay      = "Contacted in May",
  contact_monthnov      = "Contacted in November",
  contact_monthjun      = "Contacted in June",
  contact_typetelephone = "Landline instead of mobile"
)

odds_table <- odds_ratios %>%
  filter(term %in% names(readme_factors)) %>%
  mutate(factor = readme_factors[term],
         odds_ratio = round(estimate, 2),
         p_value = signif(p.value, 2)) %>%
  select(factor, odds_ratio, p_value)

cat("Odds ratios for the key factors:\n")
print(as.data.frame(odds_table), row.names = FALSE)
cat("\n")


# -----------------------------------------------------------------------------
test$pred_prob <- predict(model, newdata = test, type = "response")

roc_obj <- roc(test$y_flag, test$pred_prob)
cat("Test set size:", nrow(test), "clients\n")
cat("AUC:", round(auc(roc_obj), 2), "\n\n")

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

cat("Decile lift table:\n")
print(
  gains %>%
    transmute(decile,
              cum_pct_clients       = paste0(round(pct_clients * 100), "%"),
              cum_pct_subscriptions = paste0(round(pct_subs_captured * 100, 1), "%"),
              lift                  = round(lift, 1)),
  n = 10
)
cat("\nTop 10% of clients capture",
    round(gains$pct_subs_captured[1] * 100, 1), "% of subscriptions (",
    round(gains$lift[1], 1), "x random ).\n")
cat("Top 20% of clients capture",
    round(gains$pct_subs_captured[2] * 100, 1), "% of subscriptions.\n\n")



# --- Recommendation 1: Call past customers first ---------------------------
cat("---- Rec 1: Previous campaign outcome ----\n")
success_tab <- bank %>%
  mutate(is_success = poutcome == "success") %>%
  count(is_success, y_flag) %>%
  pivot_wider(names_from = y_flag, values_from = n, values_fill = 0)

x_success <- success_tab$`1`[success_tab$is_success]
n_success <- sum(success_tab[success_tab$is_success,  c("0", "1")])
x_rest    <- success_tab$`1`[!success_tab$is_success]
n_rest    <- sum(success_tab[!success_tab$is_success, c("0", "1")])

# Conversion: success vs everyone else, with 95% CI on the difference
print(prop.test(c(x_success, x_rest), c(n_success, n_rest), correct = FALSE))

# Strength of the effect (Cramer's V)
tab_poutcome <- table(bank$poutcome, bank$y)
print(chisq.test(tab_poutcome))
print(cramerV(tab_poutcome))


# --- Recommendation 3: Stop after 5 calls per client -----------------------
cat("\n---- Rec 3: Contacts per client ----\n")
h2_summary <- bank %>%
  group_by(campaign_bucket) %>%
  summarise(clients = n(),
            subscriptions = sum(y_flag),
            conversion_rate = subscriptions / clients,
            calls = sum(campaign)) %>%
  mutate(share_of_calls         = calls / sum(calls),
         share_of_subscriptions = subscriptions / sum(subscriptions)) %>%
  arrange(campaign_bucket)
print(as.data.frame(h2_summary))

# 1 call vs 2 calls, and 3-5 calls vs 6+ calls
print(prop.test(x = h2_summary$subscriptions[1:2], n = h2_summary$clients[1:2]))
print(prop.test(x = h2_summary$subscriptions[3:4], n = h2_summary$clients[3:4]))


# --- Recommendation 4: Use mobile numbers first ----------------------------
cat("\n---- Rec 4: Contact channel ----\n")
chan_summary <- bank %>%
  group_by(contact_type) %>%
  summarise(clients = n(),
            subscriptions = sum(y_flag),
            conversion_rate = subscriptions / clients,
            calls_per_subscription = sum(campaign) / subscriptions)
print(as.data.frame(chan_summary))

x_cell <- chan_summary$subscriptions[chan_summary$contact_type == "cellular"]
n_cell <- chan_summary$clients[chan_summary$contact_type == "cellular"]
x_tel  <- chan_summary$subscriptions[chan_summary$contact_type == "telephone"]
n_tel  <- chan_summary$clients[chan_summary$contact_type == "telephone"]
print(prop.test(c(x_cell, x_tel), c(n_cell, n_tel), correct = FALSE))


# --- Recommendations 5 and 6: Month and day of week ------------------------
cat("\n---- Rec 5 and 6: Strength of month and weekday effects (Cramer's V) ----\n")
cat("Month:      ", round(cramerV(table(bank$contact_month, bank$y)), 3), "\n")
cat("Day of week:", round(cramerV(table(bank$contact_dow,   bank$y)), 3), "\n")
# The month odds ratios (with other factors held equal) are in section 3 above.
