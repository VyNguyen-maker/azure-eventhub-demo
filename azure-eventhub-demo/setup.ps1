Clear-Host
Write-Host "Starting script at $(Get-Date)"

# Đảm bảo PSGallery là trusted
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# --- Chọn subscription nếu có nhiều hơn 1 ---
$subs = Get-AzSubscription | Select-Object
if ($subs.Count -gt 1) {
    Write-Host "You have multiple Azure subscriptions - please select the one to use:"
    for ($i = 0; $i -lt $subs.Count; $i++) {
        Write-Host "[$i]: $($subs[$i].Name) (ID = $($subs[$i].Id))"
    }

    do {
        $input = Read-Host "Enter a number (0 to $($subs.Count - 1))"
    } while (-not ([int]::TryParse($input, [ref]$selectedIndex) -and $selectedIndex -ge 0 -and $selectedIndex -lt $subs.Count))

    $selectedSub = $subs[$selectedIndex].Id
    Select-AzSubscription -SubscriptionId $selectedSub
    az account set --subscription $selectedSub
} elseif ($subs.Count -eq 1) {
    $selectedSub = $subs[0].Id
    Select-AzSubscription -SubscriptionId $selectedSub
    az account set --subscription $selectedSub
}

# --- Đăng ký provider cần thiết ---
$providers = "Microsoft.EventHub", "Microsoft.StreamAnalytics"
foreach ($p in $providers) {
    $result = Register-AzResourceProvider -ProviderNamespace $p
    Write-Host "$p : $($result.RegistrationState)"
}

# --- Tạo suffix ngẫu nhiên cho tên resource ---
[string]$suffix = -join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})
Write-Host "Generated unique suffix: $suffix"
$resourceGroupName = "project-is402-$suffix"

# --- Lấy danh sách region và cho chọn ---
$locations = Get-AzLocation | Where-Object { $_.Providers -contains "Microsoft.EventHub" -and $_.Providers -contains "Microsoft.StreamAnalytics" }
Write-Host "Available Azure regions:"
for ($i = 0; $i -lt $locations.Count; $i++) { Write-Host "[$i] $($locations[$i].Location)" }

do {
    $input = Read-Host "Enter the number corresponding to the region you want"
} while (-not ([int]::TryParse($input, [ref]$selectedIndex) -and $selectedIndex -ge 0 -and $selectedIndex -lt $locations.Count))

$Region = $locations[$selectedIndex].Location
Write-Host "Selected region: $Region"

# --- Tạo resource group ---
Write-Host "Creating resource group $resourceGroupName in $Region ..."
New-AzResourceGroup -Name $resourceGroupName -Location $Region | Out-Null

# --- Tạo Event Hub ---
$eventNsName = "events$suffix"
$eventHubName = "eventhub$suffix"
Write-Host "Deploying Event Hub namespace: $eventNsName, Event Hub: $eventHubName ..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
    -TemplateFile "setup.json" `
    -Mode Complete `
    -uniqueSuffix $suffix `
    -eventNsName $eventNsName `
    -eventHubName $eventHubName `
    -Force

# --- Tạo JavaScript client ---
Write-Host "Preparing Event Hub client JS app ..."
npm install @azure/event-hubs@5.9.0 -s
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
$conStrings = Get-AzEventHubKey -ResourceGroupName $resourceGroupName -NamespaceName $eventNsName -AuthorizationRuleName "RootManageSharedAccessKey"
$conString = $conStrings.PrimaryConnectionString
$jsTemplate = Get-Content -Path "setup.txt" -Raw
$jsTemplate = $jsTemplate.Replace("EVENTHUBCONNECTIONSTRING", $conString).Replace("EVENTHUBNAME",$eventHubName)
Set-Content -Path "orderclient.js" -Value $jsTemplate

Write-Host "Script completed at $(Get-Date)"
