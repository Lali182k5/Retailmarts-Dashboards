# Finish RetailMart Setup
# Usage: ./finish_setup.ps1

$ErrorActionPreference = "Stop"

$DB_NAME = "retailmart"
$DB_USER = "postgres"
$DB_HOST = "localhost"
$DB_PORT = "5432"

function Run-SqlFile {
    param([string]$file, [string]$db = $DB_NAME)
    Write-Host "Running $file..." -ForegroundColor Cyan
    $env:PGPASSWORD = $env:PGPASSWORD
    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $db -f "$file"
    if ($LASTEXITCODE -ne 0) { throw "SQL file execution failed: $file" }
}

function Run-Sql {
    param([string]$sql, [string]$db = $DB_NAME)
    $env:PGPASSWORD = $env:PGPASSWORD
    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $db -c "$sql"
    if ($LASTEXITCODE -ne 0) { throw "SQL execution failed" }
}

# 4. Analytics Setup (Assuming Schema is already created, but we can re-run safely if idempotent)
# But let's start from where it seemed to stop or just re-run all SQLs.
# 01_create_analytics_schema.sql handles Drop Schema, so it resets correctly.

Write-Host "Setting up Analytics Module..." -ForegroundColor Green
Run-SqlFile "retailmart_analytics/01_setup/01_create_analytics_schema.sql"
Run-SqlFile "retailmart_analytics/01_setup/02_create_metadata_tables.sql"
# Run-SqlFile "retailmart_analytics/01_setup/03_create_indexes.sql"

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

function Export-Json {
    param($func, $outfile, $desc)
    Write-Host "  Exporting $desc..."
    $outPath = "$outputDir/$outfile"
    $cmd = "COPY (SELECT $func()) TO STDOUT;"
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

# Alerts
Export-Json "analytics.get_all_alerts_json" "alerts.json" "Active Alerts"

Write-Host "Finish Setup Completed!" -ForegroundColor Green
