# RetailMart Setup Script
# Usage: ./setup.ps1

$ErrorActionPreference = "Stop"

$DB_NAME = "retailmart"
$DB_USER = "postgres"
$DB_HOST = "localhost"
$DB_PORT = "5432"

# Helper function to run SQL
function Run-Sql {
    param([string]$sql, [string]$db = $DB_NAME)
    $env:PGPASSWORD = $env:PGPASSWORD # Ensure password is safe if set
    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $db -c "$sql"
    if ($LASTEXITCODE -ne 0) { throw "SQL execution failed" }
}

# Helper function to run SQL file
function Run-SqlFile {
    param([string]$file, [string]$db = $DB_NAME)
    Write-Host "Running $file..." -ForegroundColor Cyan
    $env:PGPASSWORD = $env:PGPASSWORD
    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $db -f "$file"
    if ($LASTEXITCODE -ne 0) { throw "SQL file execution failed: $file" }
}

# 1. Database Creation
Write-Host "Creating Database $DB_NAME..." -ForegroundColor Green
$killSql = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();"
Run-Sql $killSql "postgres"
Run-Sql "DROP DATABASE IF EXISTS $DB_NAME;" "postgres"
Run-Sql "CREATE DATABASE $DB_NAME;" "postgres"

# 2. Schema Creation (Core Tables)
Write-Host "Creating Core Schemas..." -ForegroundColor Green
$schemaFiles = @(
    "Retailmart_Data_Set/sql/core_schema.sql",
    "Retailmart_Data_Set/sql/customers_schema.sql",
    "Retailmart_Data_Set/sql/stores_schema.sql",
    "Retailmart_Data_Set/sql/products_schema.sql",
    "Retailmart_Data_Set/sql/sales_schema.sql",
    "Retailmart_Data_Set/sql/finance_schema.sql",
    "Retailmart_Data_Set/sql/hr_schema.sql",
    "Retailmart_Data_Set/sql/marketing_schema.sql"
)

foreach ($file in $schemaFiles) {
    if (Test-Path $file) {
        Run-SqlFile $file
    } else {
        Write-Warning "Schema file not found: $file"
    }
}

# 3. Data Loading
Write-Host "Loading Data from CSVs..." -ForegroundColor Green
# We need to use absolute paths for COPY command or \copy meta-command
$absPath = (Get-Location).Path
# Adjust path separators for psql (forward slashes usually work best even on Windows for paths in SQL)

# Function to load a CSV into a table
function Load-Csv {
    param($schema, $table, $csvFile)
    $fullPath = "$absPath/Retailmart_Data_Set/csv/$csvFile"
    if (Test-Path $fullPath) {
        Write-Host "  Loading $schema.$table from $csvFile"
        # Use meta-command \copy to handle client-side file reading, avoids permission issues
        $cmd = "\copy $schema.$table FROM '$fullPath' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');"
        $cmd | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME
    } else {
        Write-Warning "  CSV not found: $csvFile"
    }
}

# Core
Load-Csv "core" "dim_date" "core/dim_date.csv"
Load-Csv "core" "dim_region" "core/dim_region.csv"
Load-Csv "core" "dim_category" "core/dim_category.csv"
Load-Csv "core" "dim_brand" "core/dim_brand.csv"

# Customers
Load-Csv "customers" "customers" "customers/customers.csv"
Load-Csv "customers" "addresses" "customers/addresses.csv"
Load-Csv "customers" "loyalty_points" "customers/loyalty_points.csv"
Load-Csv "customers" "reviews" "customers/reviews.csv"

# Products
# Correct order: Suppliers -> Products -> Inventory
Load-Csv "products" "suppliers" "products/suppliers.csv"
Load-Csv "products" "products" "products/products.csv"
Load-Csv "products" "inventory" "products/inventory.csv"

# Stores
Load-Csv "stores" "departments" "stores/departments.csv"
Load-Csv "stores" "stores" "stores/stores.csv"
Load-Csv "stores" "employees" "stores/employees.csv"
Load-Csv "stores" "expenses" "stores/expenses.csv"

# Sales
# Note: Order matters due to FKs if enforced
Load-Csv "sales" "orders" "sales/orders.csv"
Load-Csv "sales" "order_items" "sales/order_items.csv"
Load-Csv "sales" "payments" "sales/payments.csv"
Load-Csv "sales" "returns" "sales/returns.csv"

# Marketing
Load-Csv "marketing" "campaigns" "marketing/campaigns.csv"
Load-Csv "marketing" "ads_spend" "marketing/ads_spend.csv"
Load-Csv "marketing" "email_clicks" "marketing/email_clicks.csv"

# Operations/supply chain (if any matching CSVs exist)
# Finance (if any matching CSVs exist)

# 4. Analytics Setup
Write-Host "Setting up Analytics Module..." -ForegroundColor Green
Run-SqlFile "retailmart_analytics/01_setup/01_create_analytics_schema.sql"
Run-SqlFile "retailmart_analytics/01_setup/02_create_metadata_tables.sql"
# Run-SqlFile "retailmart_analytics/01_setup/03_create_indexes.sql" # Optional, might take time

# 5. KPI Queries (Views & Functions)
Write-Host "Creating KPI Views..." -ForegroundColor Green
$kpiFiles = Get-ChildItem "retailmart_analytics/03_kpi_queries/*.sql" | Sort-Object Name
foreach ($file in $kpiFiles) {
    Run-SqlFile $file.FullName
}

# 6. Alerts & Refresh Logic
Write-Host "Setting up Alerts & Refresh..." -ForegroundColor Green
Run-SqlFile "retailmart_analytics/04_alerts/business_alerts.sql"
Run-SqlFile "retailmart_analytics/05_refresh/refresh_all_analytics.sql"

# 7. Initial Refresh & Export
Write-Host "Refreshing Materialized Views..." -ForegroundColor Green
Run-Sql "SELECT * FROM analytics.fn_refresh_all_analytics();"

Write-Host "Exporting JSON Data..." -ForegroundColor Green
$outputDir = "retailmart_analytics/06_dashboard/data"

# Create directories
New-Item -ItemType Directory -Force -Path "$outputDir/sales" | Out-Null
New-Item -ItemType Directory -Force -Path "$outputDir/customers" | Out-Null
New-Item -ItemType Directory -Force -Path "$outputDir/products" | Out-Null
New-Item -ItemType Directory -Force -Path "$outputDir/stores" | Out-Null
New-Item -ItemType Directory -Force -Path "$outputDir/operations" | Out-Null
New-Item -ItemType Directory -Force -Path "$outputDir/marketing" | Out-Null

function Export-Json {
    param($func, $outfile, $desc)
    Write-Host "  Exporting $desc..."
    $outPath = "$outputDir/$outfile"
    $cmd = "COPY (SELECT $func()) TO STDOUT;"
    # Capture output, careful with encoding
    $json = psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -A -c "SELECT $func();"
    if ($LASTEXITCODE -eq 0 -and $json) {
        $json | Out-File -FilePath $outPath -Encoding utf8
    } else {
        Write-Warning "  Failed to export $desc"
    }
}

# Sales
Export-Json "analytics.get_executive_summary_json" "sales/executive_summary.json" "Executive Summary"
Export-Json "analytics.get_monthly_trend_json" "sales/monthly_trend.json" "Monthly Trend"
Export-Json "analytics.get_recent_trend_json" "sales/recent_trend.json" "Recent Trend"
Export-Json "analytics.get_dayofweek_json" "sales/dayofweek.json" "Day of Week"
Export-Json "analytics.get_payment_mode_json" "sales/payment_modes.json" "Payment Modes"
Export-Json "analytics.get_quarterly_sales_json" "sales/quarterly_sales.json" "Quarterly"
Export-Json "analytics.get_weekend_weekday_json" "sales/weekend_weekday.json" "Weekend vs Weekday"
Export-Json "analytics.get_hourly_pattern_json" "sales/hourly_pattern.json" "Hourly Pattern"

# Customers
Export-Json "analytics.get_top_customers_json" "customers/top_customers.json" "Top Customers"
Export-Json "analytics.get_clv_tier_distribution_json" "customers/clv_tiers.json" "CLV Tiers"
Export-Json "analytics.get_rfm_segments_json" "customers/rfm_segments.json" "RFM Segments"
Export-Json "analytics.get_churn_risk_json" "customers/churn_risk.json" "Churn Risk"
Export-Json "analytics.get_demographics_json" "customers/demographics.json" "Demographics"
Export-Json "analytics.get_geography_json" "customers/geography.json" "Geography"

# Products
Export-Json "analytics.get_top_products_json" "products/top_products.json" "Top Products"
Export-Json "analytics.get_inventory_status_json" "products/inventory_status.json" "Inventory Status"
Export-Json "analytics.get_abc_analysis_json" "products/abc_analysis.json" "ABC Analysis"
Export-Json "analytics.get_category_performance_json" "products/categories.json" "Category Performance"
Export-Json "analytics.get_brand_performance_json" "products/brands.json" "Brand Performance"

# Stores
Export-Json "analytics.get_top_stores_json" "stores/top_stores.json" "Top Stores"
Export-Json "analytics.get_regional_performance_json" "stores/regional.json" "Regional Performance"
Export-Json "analytics.get_store_inventory_json" "stores/inventory.json" "Store Inventory"
Export-Json "analytics.get_employee_distribution_json" "stores/employees.json" "Employee Performance"

# Operations
Export-Json "analytics.get_delivery_performance_json" "operations/delivery.json" "Delivery Performance"
Export-Json "analytics.get_return_analysis_json" "operations/returns.json" "Return Analysis"
Export-Json "analytics.get_courier_comparison_json" "operations/couriers.json" "Courier Performance"
Export-Json "analytics.get_pending_shipments_json" "operations/pending.json" "Pending Orders"

# Marketing
Export-Json "analytics.get_campaign_performance_json" "marketing/campaigns.json" "Campaign Performance"
Export-Json "analytics.get_channel_performance_json" "marketing/channels.json" "Channel Performance"
Export-Json "analytics.get_email_engagement_json" "marketing/email.json" "Email Performance"

Write-Host "Setup Completed Successfully!" -ForegroundColor Green
