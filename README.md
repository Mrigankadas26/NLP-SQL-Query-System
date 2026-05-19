# NLP-SQL-Query-System
End-to-end FMCG Trade Promotion Analytics pipeline in R — ETL, gold table with ROTI/uplift metrics, and an NLP agent for natural language SQL queries via OpenRouter.

---

## What this does

Raw multi-sheet FMCG data (POS transactions, inventory snapshots, 
promo calendars, WMS SKU mapping) → cleaned, joined, aggregated 
weekly gold table → ask business questions in plain English, 
get live SQL results back.

---

## Pipeline overview

1. **ETL** — Loads 6 raw sheets, fixes SKU key formats, converts 
   Excel serial dates, maps WMS SKU codes to canonical IDs
2. **Gold table** — Weekly grain aggregation at region × SKU level
3. **Metrics** — ROTI, promo uplift %, incremental sales vs baseline, 
   gross margin per unit, inventory efficiency
4. **NLP Agent** — Sends natural language questions to GPT-4o-mini 
   via OpenRouter, generates SQLite queries, executes against gold table

---

## Key metrics computed

| Metric | Description |
|---|---|
| ROTI | Incremental sales / trade spend budget |
| Uplift % | (Promo sales − baseline) / baseline |
| Incremental sales | Promo week sales vs non-promo average |
| Gross margin per unit | List price − COGS |
| Inventory efficiency | Units sold / closing stock |

---

## How to run

**1. Install dependencies**
```r
install.packages(c("readxl", "dplyr", "DBI", 
                   "RSQLite", "httr", "jsonlite"))
```

**2. Set your OpenRouter API key**
```r
Sys.setenv(OPENROUTER_API_KEY = "your-key-here")
```
Get a free key at openrouter.ai

**3. Run ETL pipeline**

Run `etl_pipeline.R` with your dataset. Outputs `gold_table.csv`.

**4. Run the NLP agent**

Run `nlp_agent.R` — loads the gold table into SQLite and starts 
accepting natural language queries.

---

## Example queries

```r
run_agent("Which region has the highest total revenue?")
run_agent("Top 5 SKUs by uplift percentage")
run_agent("Total trade spend by region")
run_agent("Show revenue trend by region")
```

---

## Stack

- **Language** — R
- **Data layer** — RSQLite (in-memory), dplyr
- **NLP layer** — OpenRouter API (GPT-4o-mini)
- **Input** — Multi-sheet FMCG Excel dataset (not included, 
  proprietary)

---

## Notes

Dataset not included in this repo as it contains proprietary 
company data. The pipeline is designed to work with any similarly 
structured FMCG POS dataset.

Built as part of an analytics assignment — MBA, 
University of Delhi.
