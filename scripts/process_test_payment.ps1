# Process a test payment via the API (create customer, payment method, intent, authorize, capture).
# Usage:
#   1. Regenerate your API key from Dashboard > Account if needed
#   2. $env:API_KEY = "your-api-key-here"
#   3. .\scripts\process_test_payment.ps1 -AmountCents 20000
#
# Or run with inline key:
#   .\scripts\process_test_payment.ps1 -ApiKey "your-key" -AmountCents 20000

param(
    [string]$ApiKey = $env:API_KEY,
    [int]$AmountCents = 20000,
    [string]$BaseUrl = "http://127.0.0.1:3000"
)

$ErrorActionPreference = "Stop"

if (-not $ApiKey) {
    Write-Host "Error: API key required. Set `$env:API_KEY or pass -ApiKey 'your-key'" -ForegroundColor Red
    Write-Host "Regenerate from Dashboard > Account if needed." -ForegroundColor Yellow
    exit 1
}

$headers = @{
    "Content-Type" = "application/json"
    "X-API-KEY"   = $ApiKey
}

Write-Host "1. Creating customer..." -ForegroundColor Cyan
$customerBody = @{ customer = @{ email = "test@example.com"; name = "Test Customer" } } | ConvertTo-Json
$customer = Invoke-RestMethod -Uri "$BaseUrl/api/v1/customers" -Method Post -Headers $headers -Body $customerBody
$customerId = $customer.data.id
Write-Host "   Customer ID: $customerId" -ForegroundColor Green

Write-Host "2. Creating payment method..." -ForegroundColor Cyan
$pmBody = @{
    payment_method = @{
        method_type = "card"
        last4       = "4242"
        brand       = "Visa"
        exp_month   = 12
        exp_year    = 2026
    }
} | ConvertTo-Json
$pm = Invoke-RestMethod -Uri "$BaseUrl/api/v1/customers/$customerId/payment_methods" -Method Post -Headers $headers -Body $pmBody
$pmId = $pm.data.id
Write-Host "   Payment method ID: $pmId" -ForegroundColor Green

Write-Host "3. Creating payment intent ($($AmountCents / 100) USD)..." -ForegroundColor Cyan
$piBody = @{
    payment_intent = @{
        customer_id         = $customerId
        payment_method_id   = $pmId
        amount_cents        = $AmountCents
        currency            = "USD"
        idempotency_key     = "test_$(Get-Date -Format 'yyyyMMddHHmmss')"
    }
} | ConvertTo-Json
$pi = Invoke-RestMethod -Uri "$BaseUrl/api/v1/payment_intents" -Method Post -Headers $headers -Body $piBody
$piId = $pi.data.id
Write-Host "   Payment intent ID: $piId" -ForegroundColor Green

Write-Host "4. Authorizing..." -ForegroundColor Cyan
$auth = Invoke-RestMethod -Uri "$BaseUrl/api/v1/payment_intents/$piId/authorize" -Method Post -Headers $headers -Body "{}"
Write-Host "   Status: $($auth.data.status)" -ForegroundColor Green

Write-Host "5. Capturing..." -ForegroundColor Cyan
$capture = Invoke-RestMethod -Uri "$BaseUrl/api/v1/payment_intents/$piId/capture" -Method Post -Headers $headers -Body "{}"
Write-Host "   Status: $($capture.data.status)" -ForegroundColor Green

Write-Host "`nDone! Check Dashboard > Overview for Captured Volume and Net." -ForegroundColor Green
Write-Host "Amount: `$$($AmountCents / 100) USD" -ForegroundColor Green
