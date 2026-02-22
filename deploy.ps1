# Deploy RetailMart Analytics Dashboard
# Usage: ./deploy.ps1

Write-Host "Starting RetailMart Deployment..." -ForegroundColor Cyan

# 1. Update Data
Write-Host "Updating Analytics Data..." -ForegroundColor Yellow
./setup_retailmart.ps1

if ($LASTEXITCODE -eq 0) {
    # 2. Start Dashboard
    Write-Host "Starting Dashboard Server..." -ForegroundColor Green
    python start_dashboard.py
} else {
    Write-Error "Data update failed. Check setup_retailmart.ps1 logs."
}
