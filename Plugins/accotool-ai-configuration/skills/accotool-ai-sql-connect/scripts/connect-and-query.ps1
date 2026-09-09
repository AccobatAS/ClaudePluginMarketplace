<#
.SYNOPSIS
    Signs in to Entra ID (device-code flow, MFA-capable) via Azure CLI and runs a T-SQL
    statement against an Azure SQL Database or Fabric SQL endpoint - no MCP server needed.

.DESCRIPTION
    Reuses the Azure CLI token cache, so interactive/MFA sign-in is only triggered when
    there is no cached session for the requested tenant. Output is a single JSON object
    on stdout: { ok, rows, rowCount, message } on success, or { ok:false, errorKind, message }
    on failure, so a caller can branch on errorKind without parsing free text.

.EXAMPLE
    ./connect-and-query.ps1 -TenantId <tenant-id> `
        -Server <server>.database.windows.net -Database <database> `
        -Query "SELECT TOP 10 * FROM sys.tables"
#>
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [Parameter(Mandatory, ParameterSetName = 'Query')] [string] $Query,
    [Parameter(Mandatory, ParameterSetName = 'File')] [string] $InputFile,
    [int] $QueryTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

function Write-JsonResult {
    param($Object)
    $Object | ConvertTo-Json -Depth 6 -Compress
    if ($Object.ok) { exit 0 } else { exit 1 }
}

# Must be the very first check, and must not itself use any PS7+-only syntax (ternary, etc.) -
# the whole point is to fail cleanly on PS 5.1 instead of a raw parser error.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-JsonResult @{
        ok        = $false
        errorKind = 'MissingTool'
        message   = "PowerShell $($PSVersionTable.PSVersion) is too old - this script requires PowerShell 7.0+. " +
                     "Install: winget install --id Microsoft.PowerShell --source winget -e (or https://aka.ms/PSWindows). " +
                     "No admin rights needed - installs side-by-side with Windows PowerShell 5.1, which stays untouched."
    }
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-JsonResult @{
        ok        = $false
        errorKind = 'MissingTool'
        message   = "Azure CLI ('az') not found on PATH. Install: winget install --id Microsoft.AzureCLI --source winget -e " +
                     "(this will likely prompt for admin elevation - it's a machine-wide MSI install). " +
                     "No admin rights? 'pip install azure-cli' works per-user inside a Python virtualenv as a fallback, " +
                     "just slower to install. Direct MSI: https://aka.ms/installazurecliwindows"
    }
}
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-JsonResult @{
        ok        = $false
        errorKind = 'MissingTool'
        message   = "PowerShell module 'SqlServer' not installed. Run: Install-Module SqlServer -Scope CurrentUser -Force " +
                     "No admin rights needed (installs to your user profile only); takes about a minute."
    }
}

# --- Ensure we're signed in to the right tenant; only prompt (device code) if we're not. ---
$currentTenant = az account show --query tenantId -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or $currentTenant -ne $TenantId) {
    Write-Host "Not signed in to tenant $TenantId - starting device-code sign-in..."
    az login --tenant $TenantId --use-device-code | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-JsonResult @{ ok = $false; errorKind = 'AuthFailed'; message = "az login failed or was not completed for tenant $TenantId." }
    }
}

# --- Acquire an access token scoped to Azure SQL / Fabric SQL (same audience for both). ---
$tokenJson = az account get-access-token --resource https://database.windows.net/ --tenant $TenantId -o json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-JsonResult @{ ok = $false; errorKind = 'AuthFailed'; message = 'Failed to acquire an access token for https://database.windows.net/ - the cached sign-in may have expired.' }
}
$accessToken = ($tokenJson | ConvertFrom-Json).accessToken

Import-Module SqlServer -ErrorAction Stop

$sqlParams = @{
    ServerInstance   = $Server
    Database         = $Database
    AccessToken      = $accessToken
    QueryTimeout     = $QueryTimeoutSeconds
    ErrorAction      = 'Stop'
}
if ($PSCmdlet.ParameterSetName -eq 'File') { $sqlParams['InputFile'] = $InputFile }
else { $sqlParams['Query'] = $Query }

try {
    $rawRows = @(Invoke-Sqlcmd @sqlParams)
    # Invoke-Sqlcmd returns DataRow objects whose properties include ADO.NET internals
    # (RowState, Table, ItemArray, ...) that serialize badly to JSON - this module version
    # has no '-As PSObject' option, so flatten each row to plain column:value pairs by hand.
    $cleanRows = @()
    if ($rawRows.Count -gt 0) {
        $columnNames = $rawRows[0].Table.Columns.ColumnName
        foreach ($row in $rawRows) {
            $obj = [ordered]@{}
            foreach ($col in $columnNames) { $obj[$col] = $row[$col] }
            $cleanRows += [PSCustomObject]$obj
        }
    }
    Write-JsonResult @{
        ok       = $true
        rowCount = $cleanRows.Count
        rows     = $cleanRows
        message  = if ($cleanRows.Count -eq 0) { 'Statement executed. No rows returned (expected for INSERT/UPDATE/DDL).' } else { "$($cleanRows.Count) row(s) returned." }
    }
}
catch {
    $msg = $_.Exception.Message
    $kind = switch -Regex ($msg) {
        'is not allowed to access the server' { 'FirewallBlocked'; break }
        'Login failed'                        { 'AuthRejected'; break }
        'Cannot open server'                  { 'NetworkOrFirewall'; break }
        default                               { 'SqlError' }
    }
    Write-JsonResult @{ ok = $false; errorKind = $kind; message = $msg }
}
