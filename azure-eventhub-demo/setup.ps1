Clear-Host
Write-Host "Starting script at $(Get-Date)"

# Trust PSGallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# 1️⃣ Login Azure
Write-Host "Logging in to Azure..."
Connect-AzAccount

# 2️⃣ Chọn subscription
$subs = Get-AzSubscription
if ($subs.Count -gt 1) {
    Write-Host "You have multiple subscriptions. Select one:"
    for ($i=0; $i -lt $subs.Count; $i++) {
        Write-Host "[$i] $($subs[$i].Name) (ID: $($subs[$i].Id))"
    }
    $selectedIndex = -1
    while ($selectedIndex -lt 0 -or $selectedIndex -ge $subs.Count) {
        $input = Read-Host "Enter subscription number"
        if ([int]::TryParse($input, [ref]$null)) {
            $selectedIndex = [int]$input
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $subs.Count) {
                Write-Host "Invalid number, try again."
            }
        } else {
            Write-Host "Please enter a valid number."
        }
    }
    $selectedSub = $subs[$selectedIndex].Id
    Select-AzSubscription -SubscriptionId $selectedSub
    az account set --subscription $selectedSub
} else {
    $selectedSub = $subs[0].Id
    Select-AzSubscription -SubscriptionId $selectedSub
}

Write-Host "Selected subscription: $selectedSub"

# 3️⃣ Resource providers (bỏ qua nếu account không có quyền đăng ký)
Write-Host "Check EventHub and StreamAnalytics providers (may require admin rights)..."
$providers = @("Microsoft.EventHub", "Microsoft.StreamAnalytics")
foreach ($p in $providers) {
    try {
        $result = Register-AzResourceProvider -ProviderNamespace $p -ErrorAction Stop
        Write-Host "$p : $($result.RegistrationState)"
    } catch {
        Write-Host "$p registration skipped or failed: $_"
    }
}

# 4️⃣ Generate unique suffix
$suffix = -join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})
Write-Host "Generated unique suffix: $suffix"

$resourceGroupName = "project-is402-$suffix"

# 5️⃣ List regions supporting EventHub + StreamAnalytics
$locations = Get-AzLocation | Where-Object {
    $_.Providers -contains "Microsoft.EventHub" -and
    $_.Providers -contains "Microsoft.StreamAnalytics"
}

Write-Host "Available Azure regions:"
for ($i=0; $i -lt $locations.Count; $i++) {
    Write-Host "[$i] $($locations[$i].Location)"
}

$selectedIndex = -1
while ($selectedIndex -lt 0 -or $selectedIndex -ge $locations.Count) {
    $input = Read-Host "Enter the number corresponding to the region you want to use"
    if ([int]::TryParse($input, [ref]$null)) {
        $selectedIndex = [int]$input
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $locations.Count) {
            Write-Host "Invalid selection, try again."
        }
    } else {
        Write-Host "Please enter a valid number."
    }
}
$Region = $locations[$selectedIndex].Location
Write-Host "Selected region: $Region"

# 6️⃣ Create resource group
Write-Host "Creating resource group $resourceGroupName in $Region..."
New-AzResourceGroup -Name $resourceGroupName -Location $Region | Out-Null

# 7️⃣ Create EventHub namespace and hub via template
$eventNsName = "events$suffix"
$eventHubName = "eventhub$suffix"

Write-Host "Deploying Azure resources..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
    -TemplateFile "setup.json" `
    -Mode Complete `
    -uniqueSuffix $suffix `
    -eventNsName $eventNsName `
    -eventHubName $eventHubName `
    -Force

# 8️⃣ Prepare JS client
Write-Host "Installing Event Hub SDK..."
npm install @azure/event-hubs@5.9.0 -s

$conStrings = Get-AzEventHubKey -ResourceGroupName $resourceGroupName -NamespaceName $eventNsName -AuthorizationRuleName "RootManageSharedAccessKey"
$conString = $conStrings.PrimaryConnectionString

$javascript = Get-Content -Path "setup.txt" -Raw
$javascript = $javascript.Replace("EVENTHUBCONNECTIONSTRING", $conString)
$javascript = $javascript.Replace("EVENTHUBNAME",$eventHubName)
Set-Content -Path "orderclient.js" -Value $javascript

Write-Host "Script completed at $(Get-Date)"
