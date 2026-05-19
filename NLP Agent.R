#Location of the dataset in my computer
setwd('C:/Users/asus/Downloads')

#Setting API Keys


if (Sys.getenv("OPENROUTER_API_KEY") == "") {
  stop("API key not set properly.")
}



library(DBI)
library(RSQLite)

#Load gold table
gold <- read.csv("gold_table.csv")

cat("Gold table loaded successfully.\n")
cat("Rows:", nrow(gold), " Columns:", ncol(gold), "\n\n")

# Grain check
grain_check <- gold %>%
  count(week_start, region_code, sku_code) %>%
  filter(n > 1)

if (nrow(grain_check) == 0) {
  cat("Grain validation passed.\n\n")
} else {
  stop("Grain validation failed.")
}

# Create in-memory database
con <- dbConnect(SQLite(), ":memory:")

# Write gold table
dbWriteTable(con, "gold_table", gold, overwrite = TRUE)

# Confirm
dbListTables(con)

schema_info <- dbGetQuery(con, "PRAGMA table_info(gold_table)")
schema_columns <- paste(schema_info$name, collapse = ", ")

print(schema_columns)

install.packages("httr")
install.packages("jsonlite")

library(httr)
library(jsonlite)

#Forming the Agent
generate_sql <- function(question) {
  
  system_prompt <- paste0(
    "You are an FMCG Trade Promotion Analyst.\n",
    "You have access to a SQLite table called gold_table.\n",
    "Columns available: ", schema_columns, "\n",
    "Only generate valid SQLite SQL.\n",
    "Do NOT explain.\n"
  )
  
  response <- POST(
    url = "https://openrouter.ai/api/v1/chat/completions",
    add_headers(
      Authorization = paste("Bearer", Sys.getenv("OPENROUTER_API_KEY")),
      `Content-Type` = "application/json"
    ),
    body = toJSON(list(
      model = "openai/gpt-4o-mini",
      messages = list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = question)
      ),
      temperature = 0
    ), auto_unbox = TRUE),
    encode = "raw"
  )
  
  content_parsed <- content(response, as = "parsed")
  
  if (is.null(content_parsed$choices)) {
    print(content_parsed)
    stop("API did not return valid response")
  }
  
  sql_query <- content_parsed$choices[[1]]$message$content
  
  # Remove markdown formatting if present
  sql_query <- gsub("```sql", "", sql_query)
  sql_query <- gsub("```", "", sql_query)
  
  return(trimws(sql_query))
}

execute_sql <- function(query) {
  tryCatch({
    result <- dbGetQuery(con, query)
    return(result)
  }, error = function(e) {
    return(paste("SQL Error:", e$message))
  })
}

run_agent <- function(question) {
  
  cat("\n=============================\n")
  cat("User Question:\n", question, "\n")
  
  sql_query <- generate_sql(question)
  
  cat("\nGenerated SQL:\n", sql_query, "\n")
  
  result <- execute_sql(sql_query)
  
  cat("\nResult:\n")
  print(result)
  
  cat("\n=============================\n")
}

Sys.getenv("OPENROUTER_API_KEY")
run_agent("Which region has highest total revenue?")
run_agent("Top 5 SKUs by uplift percentage")
run_agent("Total trade spend by region")
run_agent("Show revenue trend by region")
