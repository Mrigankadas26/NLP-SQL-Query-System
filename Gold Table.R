install.packages("DBI")


library(readxl)
library(dplyr)
library(DBI)
library(RSQLite)

setwd('C:/Users/asus/Downloads')

file_path <- "Beverages Datasets.xlsx"

############################################################
# 1️⃣ LOAD DATA
############################################################

pos <- read_excel(file_path, sheet = "pos_transactions")
product <- read_excel(file_path, sheet = "product_master")
promo <- read_excel(file_path, sheet = "promo_master")
region <- read_excel(file_path, sheet = "region_master")
inventory <- read_excel(file_path, sheet = "inventory_snapshot")
wms_map <- read_excel(file_path, sheet = "wms_sku_mapping")

############################################################
# 2️⃣ FIX KEYS + DATES
############################################################

# Fix SKU format safely (avoid double dash)
pos <- pos %>%
  mutate(
    sku_code = gsub("-", "", sku_code),
    sku_code = gsub("SKU", "SKU-", sku_code),
    sku_code = as.character(sku_code),
    region_code = as.character(region_code),
    
    # FIX EXCEL DATE PROPERLY
    transaction_date = as.Date(transaction_date, origin = "1899-12-30"),
    
    # Monday week start
    week_start = transaction_date - 
      (as.numeric(format(transaction_date, "%u")) - 1)
  )

# Clean dimension tables
product <- product %>%
  mutate(sku_id = as.character(sku_id)) %>%
  distinct(sku_id, .keep_all = TRUE)

region <- region %>%
  mutate(sales_region_code = as.character(sales_region_code)) %>%
  distinct(sales_region_code, .keep_all = TRUE)

promo <- promo %>%
  distinct(promo_id, .keep_all = TRUE)

############################################################
# 3️⃣ BUILD WEEKLY SALES (CORRECT GRAIN)
############################################################

weekly_sales <- pos %>%
  group_by(week_start, region_code, sku_code) %>%
  summarise(
    total_units_sold = sum(units_sold, na.rm = TRUE),
    total_sales_gbp = sum(gross_sales_gbp, na.rm = TRUE),
    promo_flag = max(promo_flag, na.rm = TRUE),
    promo_sales = sum(gross_sales_gbp[promo_flag == "Y"], na.rm = TRUE),
    .groups = "drop"
  )

############################################################
# 4️⃣ JOIN DIMENSIONS
############################################################

gold <- weekly_sales %>%
  left_join(product, by = c("sku_code" = "sku_id")) %>%
  left_join(region, by = c("region_code" = "sales_region_code"))

############################################################
# 5️⃣ INVENTORY ALIGNMENT
############################################################

inventory <- inventory %>%
  mutate(
    wms_sku_code = as.character(wms_sku_code),
    snapshot_date = as.Date(snapshot_date, origin = "1899-12-30"),
    week_start = snapshot_date - 
      (as.numeric(format(snapshot_date, "%u")) - 1)
  )

wms_map <- wms_map %>%
  mutate(
    wms_sku_code = as.character(wms_sku_code),
    canonical_sku_id = as.character(canonical_sku_id)
  )

inventory <- inventory %>%
  left_join(wms_map, by = "wms_sku_code")

weekly_inventory <- inventory %>%
  group_by(week_start, canonical_sku_id) %>%
  summarise(
    closing_stock_units = mean(closing_stock_units, na.rm = TRUE),
    stockout_flag = max(stockout_flag, na.rm = TRUE),
    .groups = "drop"
  )

gold <- gold %>%
  left_join(
    weekly_inventory,
    by = c("week_start", "sku_code" = "canonical_sku_id")
  )

############################################################
# 6️⃣ DERIVED METRICS
############################################################

gold <- gold %>%
  mutate(
    gross_margin_per_unit = list_price_gbp - cogs_gbp,
    total_gross_margin = gross_margin_per_unit * total_units_sold,
    inventory_efficiency = total_units_sold / closing_stock_units
  )

############################################################
# 7️⃣ BASELINE + UPLIFT
############################################################

baseline <- gold %>%
  filter(promo_flag != "Y") %>%
  group_by(region_code, sku_code) %>%
  summarise(
    baseline_sales = mean(total_sales_gbp, na.rm = TRUE),
    .groups = "drop"
  )

gold <- gold %>%
  left_join(baseline, by = c("region_code", "sku_code")) %>%
  mutate(
    incremental_sales = total_sales_gbp - baseline_sales,
    uplift_pct = incremental_sales / baseline_sales
  )

############################################################
# 8️⃣ TRADE SPEND (FIXED PROPERLY)
############################################################

pos_with_spend <- pos %>%
  left_join(
    promo %>% select(promo_id, trade_spend_budget),
    by = "promo_id"
  )

weekly_spend <- pos_with_spend %>%
  filter(promo_flag == "Y") %>%
  group_by(week_start, region_code, sku_code) %>%
  summarise(
    trade_spend_budget = sum(trade_spend_budget, na.rm = TRUE),
    .groups = "drop"
  )

gold <- gold %>%
  left_join(
    weekly_spend,
    by = c("week_start", "region_code", "sku_code")
  )

############################################################
# 9️⃣ ROTI
############################################################

gold <- gold %>%
  mutate(
    trade_spend_budget = ifelse(is.na(trade_spend_budget), 0, trade_spend_budget),
    roti = incremental_sales / trade_spend_budget
  )

############################################################
# 🔟 CLEAN NUMERIC ONLY
############################################################

gold <- gold %>%
  mutate(
    across(where(is.numeric), ~ ifelse(is.na(.), 0, .)),
    across(where(is.numeric), ~ ifelse(is.infinite(.), 0, .))
  )

############################################################
# 1️⃣1️⃣ VALIDATION
############################################################

cat("Grain Check:\n")
print(
  gold %>%
    count(week_start, region_code, sku_code) %>%
    filter(n > 1)
)

cat("\nRevenue Check Difference:\n")
print(
  sum(gold$total_sales_gbp, na.rm = TRUE) -
    sum(pos$gross_sales_gbp, na.rm = TRUE)
)

cat("\nTrade Spend Summary:\n")
print(summary(gold$trade_spend_budget))

cat("\nROTI Summary:\n")
print(summary(gold$roti))

############################################################
# SAVE
############################################################

write.csv(gold, "gold_table.csv", row.names = FALSE)

############################################################
# END
############################################################

table(pos$promo_flag)
