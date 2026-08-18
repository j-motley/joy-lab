<#

.EXAMPLE
    .\deploy.ps1 -Environment dev1 -DryRun
    .\deploy.ps1 -Environment test1
    .\deploy.ps1 -Environment uat -BuildFile NEW_XLAPS_Release_Application-Build-2026-08-13-68.zip
    .\deploy.ps1 -Environment dev1 -Only Database -DbMode Report
#>
 
[CmdletBinding()]
param(
    # Target environment(s), e.g. -Environment dev1  or  -Environment dev1,test1,uat
    # With multiple environments, each one gets a Proceed/skip/quit gate before its work starts.
    # (Required for deployments; not needed with -SetupToken.)
    [string[]]$Environment,
 
    # Application build zip name. If omitted, newest NEW_XLAPS_*Application-Build-*.zip
    # in today's date folder is offered for confirmation.
    [string]$BuildFile,
 
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'environments.json'),
 
    # Limit the run: any of WebComponents, Addin, Models, Database. Default: all.
    [ValidateSet('WebComponents','Addin','Models','Database')]
    [string[]]$Only = @('WebComponents','Addin','Models','Database'),
 
    # Database mode: Script (generate SQL, current team practice), Report (harmless
    # what-would-change preview), Publish (direct deploy - the original automated way).
    [ValidateSet('Script','Report','Publish')]
    [string]$DbMode = 'Script',
 
    # Folder containing PricingSystems.Database.dacpac + PublishProfiles\ for this deploy.
    # If omitted, newest PricingDB_*_Build-* folder under targetBasePath is offered.
    [string]$DbBuildFolder,
 
    # Folder containing the extracted model build output. Models are skipped if omitted.
    [string]$ModelBuildFolder,
 
    # Download the build zip from Artifactory instead of expecting it in the date folder.
    # Requires -BuildFile (the exact zip name). Auth: pass -ArtifactoryToken, or set the
    # ARTIFACTORY_TOKEN environment variable; omitted = anonymous request.
    [switch]$Download,
 
    [string]$ArtifactoryToken,
 
    # One-time (per user/machine) token setup: opens your browser at the Artifactory
    # profile page, you generate an identity token, paste it once, and it is stored
    # DPAPI-encrypted for all future -Download runs. Run again anytime to replace it.
    [switch]$SetupToken,
 
    # Walk through the deployment one logical step at a time:
    # each step is announced and waits for [Y]es / [s]kip / [q]uit.
    [switch]$Guided,
 
    [switch]$DryRun
)
 
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
 
# ---------------------------------------------------------------- helpers ----
 
$script:Results = New-Object System.Collections.Generic.List[object]
 
function Add-Result {
    param([string]$Step, [string]$Target, [string]$Status, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Step = $Step; Target = $Target; Status = $Status; Detail = $Detail })
    $color = switch ($Status) {
        'OK'      { 'Green' }
        'DRYRUN'  { 'Cyan' }
        'MANUAL'  { 'Yellow' }
        'SKIPPED' { 'DarkGray' }
        default   { 'Red' }
    }
    Write-Host ("[{0,-7}] {1} -> {2}  {3}" -f $Status, $Step, $Target, $Detail) -ForegroundColor $color
}
 
function Confirm-Step {
    <# Guided-mode gate. Returns $true to run the step, $false to skip it.
       'q' aborts the whole run. When -Guided is not set, always returns $true. #>
    param([string]$Title, [string]$Description = '', [switch]$Always)
    if (-not $Guided -and -not $Always) { return $true }
    Write-Host ""
    Write-Host ("STEP: " + $Title) -ForegroundColor White
    if ($Description) { Write-Host ("      " + $Description) -ForegroundColor DarkGray }
    while ($true) {
        $ans = (Read-Host "Proceed? [Y]es / [s]kip / [q]uit")
        switch ($ans.ToLower()) {
            ''  { return $true }
            'y' { return $true }
            's' { Add-Result 'Step' $Title 'SKIPPED' 'Skipped by operator (guided mode).'; return $false }
            'q' { throw "Aborted by operator at step: $Title" }
            default { Write-Host "Please answer Y, s, or q." -ForegroundColor Yellow }
        }
    }
}
 
function Test-Todo { param([string]$Value)
    return ([string]::IsNullOrWhiteSpace($Value) -or $Value -like 'TODO*')
}
 
function Resolve-EnvToken { param([string]$Template, [string]$EnvName)
    return $Template.Replace('{Env}', $EnvName)
}
 
function Confirm-Choice { param([string]$Message)
    if ($DryRun) { return $true }
    $answer = Read-Host "$Message [y/N]"
    return ($answer -eq 'y' -or $answer -eq 'Y')
}
 
function Copy-WithVerify {
    <# Copies Source\* to Destination recursively, then compares file counts.
       Returns $true on verified copy. #>
    param([string]$Source, [string]$Destination, [string]$Label)
 
    if ($DryRun) { Add-Result 'Copy' $Label 'DRYRUN' "$Source -> $Destination"; return $true }
 
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source path does not exist: $Source"
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
 
    $srcCount = (Get-ChildItem -LiteralPath $Source -Recurse -File | Measure-Object).Count
    $dstCount = (Get-ChildItem -LiteralPath $Destination -Recurse -File | Measure-Object).Count
    if ($dstCount -lt $srcCount) {
        throw "Verification FAILED for ${Label}: source has $srcCount files, destination has $dstCount."
    }
    return $true
}
 
function Get-TokenFilePath {
    return (Join-Path $env:USERPROFILE '.xlaps\artifactory.token.xml')
}
 
function Get-StoredArtifactoryToken {
    <# Returns the stored token as plain text, or $null if none is saved.
       The file is DPAPI-encrypted: only this user on this machine can decrypt it. #>
    $tokenFile = Get-TokenFilePath
    if (-not (Test-Path -LiteralPath $tokenFile)) { return $null }
    try {
        $secure = Import-Clixml -LiteralPath $tokenFile
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    catch {
        Write-Warning "Stored Artifactory token could not be read ($($_.Exception.Message)). Run deploy.ps1 -SetupToken to replace it."
        return $null
    }
}
 
function Invoke-TokenSetup {
    param($Artifactory)
 
    $uiBase = $Artifactory.baseUrl -replace '/artifactory/?$', ''
    $profileUrl = "$uiBase/ui/user_profile"
 
    Write-Host ""
    Write-Host "=== Artifactory token setup ===" -ForegroundColor White
    Write-Host "Your browser will now open to your Artifactory profile page."
    Write-Host "  1. Sign in via SSO if prompted."
    Write-Host "  2. Find 'Generate Identity Token' (under Edit Profile / Identity Tokens)."
    Write-Host "  3. Click Generate, copy the token, and paste it below."
    Write-Host "     (If there is no generate option, ask the Artifactory admins for a token.)"
    Write-Host ""
    Start-Process $profileUrl
 
    $secure = Read-Host -Prompt "Paste the identity token (input is hidden)" -AsSecureString
    if ($secure.Length -eq 0) { throw "No token entered - nothing saved." }
 
    # Optional validation: try an authenticated ping before saving.
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    try {
        Invoke-WebRequest -Uri "$($Artifactory.baseUrl)/api/system/ping" `
            -Headers @{ Authorization = "Bearer $plain" } -UseBasicParsing -TimeoutSec 15 | Out-Null
        Write-Host "Token verified against Artifactory." -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not verify the token against $($Artifactory.baseUrl) ($($_.Exception.Message)). Saving it anyway - if downloads fail, re-run -SetupToken."
    }
    finally { $plain = $null }
 
    $tokenFile = Get-TokenFilePath
    $tokenDir = Split-Path $tokenFile -Parent
    if (-not (Test-Path -LiteralPath $tokenDir)) { New-Item -Path $tokenDir -ItemType Directory -Force | Out-Null }
    $secure | Export-Clixml -LiteralPath $tokenFile
    Write-Host "Token saved (encrypted for this user on this machine): $tokenFile" -ForegroundColor Green
    Write-Host "You won't be asked again on this machine. Future runs of 'deploy.ps1 -Download' will use it automatically."
}
 
function Write-BuildStamp {
    param([string]$Destination, [hashtable]$Info)
    if ($DryRun) { return }
    $Info['deployedAtUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    $Info['deployedBy']    = $env:USERNAME
    ($Info | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $Destination 'deployed.buildinfo.json') -Encoding UTF8
}
 
# ---------------------------------------------------------- load manifest ----
 
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath  (copy environments.example.json to environments.json and fill it in)"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
 
# ---- one-time token setup mode: run and exit ----
if ($SetupToken) {
    Invoke-TokenSetup -Artifactory $manifest.artifactory
    return
}
if (-not $Environment) {
    throw "-Environment is required (or use -SetupToken for first-time Artifactory token setup)."
}
 
# Environment lookup - case-insensitive key match; ANY unknown name ABORTS before any work.
$envKeys = @()
$requestedList = @($Environment -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($requested in $requestedList) {
    $k = ($manifest.environments.PSObject.Properties.Name |
          Where-Object { $_ -ieq $requested -and $_ -notlike '_*' } |
          Select-Object -First 1)
    if (-not $k) {
        $valid = ($manifest.environments.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' }) -join ', '
        throw "Unknown environment '$requested'. Valid values: $valid"
    }
    if ($envKeys -notcontains $k) { $envKeys += $k }
}
$envLabel = $envKeys -join '+'
$script:StagedFinal = @{}   # components staged to final-output this run (stage once, reuse per environment)
 
# ------------------------------------------------------------- run set-up ----
 
$targetBasePath = $manifest.paths.targetBasePath
$currentDate    = (Get-Date).ToString('yyyy-MM-dd')
$targetPath     = Join-Path $targetBasePath $currentDate
 
$logDir = Join-Path $targetBasePath 'logs'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir ("deploy-{0}-{1}.log" -f $envLabel, (Get-Date).ToString('yyyyMMdd-HHmmss'))
Start-Transcript -Path $logFile | Out-Null
 
try {
    Write-Host ""
    Write-Host "=== XLAPS deploy ===" -ForegroundColor White
    Write-Host "Environments: $($envKeys -join ', ')"
    Write-Host "Sections    : $($Only -join ', ')"
    Write-Host "Dry run     : $DryRun"
    Write-Host "Manifest    : $ManifestPath"
    Write-Host "Log         : $logFile"
    Write-Host ""
 
    # ------------------------------------------------ resolve the app build ----
 
    $needsAppBuild = ($Only -contains 'WebComponents' -or $Only -contains 'Addin')
    $stagePath = $null
 
    if ($needsAppBuild) {
        if (-not (Test-Path -LiteralPath $targetPath)) {
            New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        }
 
        # ---- optional: download from Artifactory (replaces script 1's download branch) ----
        if ($Download -and (Confirm-Step 'Download build from Artifactory' "Fetch $BuildFile into $targetPath")) {
            if (-not $BuildFile) { throw "-Download requires -BuildFile (the exact zip name to fetch)." }
            if ($BuildFile -notmatch '^(.+?-Build)') { throw "Cannot derive the Artifactory build folder from '$BuildFile' (expected '<name>-Build-<date>-<n>.zip')." }
            $buildFolder = $Matches[1]
            $a = $manifest.artifactory
            $downloadUrl = "$($a.baseUrl)/$($a.repository)/$($a.application)/$buildFolder/$BuildFile"
 
            $headers = @{}
            $token = if ($ArtifactoryToken) { $ArtifactoryToken }
                     elseif ($env:ARTIFACTORY_TOKEN) { $env:ARTIFACTORY_TOKEN }
                     else { Get-StoredArtifactoryToken }   # saved via -SetupToken
            if ($token) { $headers['Authorization'] = "Bearer $token" }
            else { Write-Warning "No Artifactory token found (no -ArtifactoryToken, no ARTIFACTORY_TOKEN env var, no stored token). Trying anonymous - run 'deploy.ps1 -SetupToken' if this fails." }
 
            $downloadDest = Join-Path $targetPath $BuildFile
            if ($DryRun) {
                Add-Result 'Download' $BuildFile 'DRYRUN' $downloadUrl
            }
            else {
                Write-Host "Downloading: $downloadUrl"
                try {
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadDest -Headers $headers -UseBasicParsing
                }
                catch {
                    throw "Artifactory download failed: $($_.Exception.Message). If this is an auth error, supply -ArtifactoryToken or set ARTIFACTORY_TOKEN."
                }
                $dl = Get-Item -LiteralPath $downloadDest
                if ($dl.Length -lt 1MB) {
                    throw "Downloaded file is suspiciously small ($($dl.Length) bytes) - likely an error page, not the build. Check the URL and token."
                }
                Add-Result 'Download' $BuildFile 'OK' ("{0:N1} MB from Artifactory" -f ($dl.Length / 1MB))
            }
        }
 
        if (-not $BuildFile) {
            $candidate = Get-ChildItem -LiteralPath $targetPath -Filter '*Application-Build-*.zip' -File |
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $candidate) {
                throw "No application build zip found in $targetPath. Download it there (or pass -BuildFile / place the zip and re-run)."
            }
            if (-not (Confirm-Choice "Use newest build zip '$($candidate.Name)' (modified $($candidate.LastWriteTime))?")) {
                throw "Aborted by operator - pass -BuildFile to choose a specific zip."
            }
            $BuildFile = $candidate.Name
        }
        $buildZipPath = Join-Path $targetPath $BuildFile
        if (-not (Test-Path -LiteralPath $buildZipPath)) { throw "Build zip not found: $buildZipPath" }
 
        # ---- extract once (replaces script 2's extract section) ----
        $stagePath = Join-Path (Join-Path $targetPath 'stage-output') 'Components'
        if (-not (Confirm-Step 'Extract build zip' "Unzip $BuildFile to stage-output (skip if already extracted earlier today)")) {
            if (-not (Test-Path -LiteralPath $stagePath)) { throw "Extract was skipped but stage-output does not exist yet: $stagePath" }
        }
        elseif ($DryRun) {
            Add-Result 'Extract' $BuildFile 'DRYRUN' "-> $stagePath"
        } else {
            if (Test-Path -LiteralPath $stagePath) { Remove-Item -LiteralPath $stagePath -Recurse -Force }
            Write-Host "Extracting $BuildFile ..."
            Expand-Archive -Path $buildZipPath -DestinationPath $stagePath
            Add-Result 'Extract' $BuildFile 'OK' "-> $stagePath"
        }
    }
 
    # ------------------------------------- stage + environment output loop ----
    # (replaces script 2's five copy-paste blocks and both script 3 functions)
 
    function New-EnvironmentOutput {
        param($Component)
 
        $finalOutputPath = Join-Path (Join-Path $targetPath 'final-output') $Component.name
        $sourceInZip     = Join-Path $stagePath $Component.zipPath
 
        if ($script:StagedFinal.ContainsKey($Component.name)) {
            # already staged during this run (multi-environment) - reuse final-output as-is
        }
        elseif ($DryRun) {
            Add-Result 'Stage' $Component.name 'DRYRUN' "$sourceInZip -> $finalOutputPath"
            $script:StagedFinal[$Component.name] = $true
        } else {
            if (Test-Path -LiteralPath $finalOutputPath) { Remove-Item -LiteralPath $finalOutputPath -Recurse -Force }
            New-Item -Path $finalOutputPath -ItemType Directory -Force | Out-Null
            if (-not (Test-Path -LiteralPath $sourceInZip)) {
                throw "Expected path missing inside build zip for $($Component.name): $sourceInZip"
            }
            Copy-Item -Path (Join-Path $sourceInZip '*') -Destination $finalOutputPath -Recurse
            Add-Result 'Stage' $Component.name 'OK' $finalOutputPath
            $script:StagedFinal[$Component.name] = $true
        }
 
        # Add-in has no per-environment config work; it deploys from final-output.
        if ($Component.configStrategy -eq 'none') { return $finalOutputPath }
 
        $envOutputPath = Join-Path (Join-Path (Join-Path (Join-Path $targetPath 'environment-output') $Component.appFolder) $envName) $Component.name
 
        if ($DryRun) {
            Add-Result 'EnvOutput' $Component.name 'DRYRUN' "$envOutputPath ($($Component.configStrategy))"
            return $envOutputPath
        }
 
        if (Test-Path -LiteralPath $envOutputPath) { Remove-Item -LiteralPath $envOutputPath -Recurse -Force }
        New-Item -Path $envOutputPath -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $finalOutputPath '*') -Destination $envOutputPath -Recurse
 
        switch ($Component.configStrategy) {
 
            'renamePreTransformed' {
                # Original behavior: remove Web.*, then Web.config.<Env> becomes Web.config.
                Remove-Item -Path (Join-Path $envOutputPath 'Web.*') -Force
                $envSpecific = Join-Path $finalOutputPath ("Web.config." + $envName)
                if (-not (Test-Path -LiteralPath $envSpecific)) {
                    throw "Missing pre-transformed config for $($Component.name): $envSpecific"
                }
                Copy-Item -LiteralPath $envSpecific -Destination $envOutputPath
                Rename-Item -LiteralPath (Join-Path $envOutputPath ("Web.config." + $envName)) -NewName 'Web.config' -Force
            }
 
            'xdtTransform' {
                # Original PricingAdminUI behavior - but transform failure now ABORTS.
                Remove-Item -Path (Join-Path $envOutputPath 'Web.*') -Force
                Copy-Item -LiteralPath (Join-Path $finalOutputPath 'Web.config') -Destination $envOutputPath
                $transformSrc = Join-Path $finalOutputPath ("Web." + $envName + ".config")
                if (-not (Test-Path -LiteralPath $transformSrc)) {
                    throw "Missing XDT transform for $($Component.name): $transformSrc"
                }
                Copy-Item -LiteralPath $transformSrc -Destination $envOutputPath
 
                Add-Type -Path $manifest.paths.xmlTransformDll
                $baseConfigFile = Join-Path $envOutputPath 'Web.config'
                $doc = New-Object Microsoft.Web.XmlTransform.XmlTransformableDocument
                $doc.PreserveWhitespace = $true
                $doc.Load($baseConfigFile)
                $xf = New-Object Microsoft.Web.XmlTransform.XmlTransformation((Join-Path $envOutputPath ("Web." + $envName + ".config")))
                if (-not $xf.Apply($doc)) {
                    throw "XDT transformation FAILED for $($Component.name) / $envName - not saving."
                }
                $doc.Save($baseConfigFile)
                Remove-Item -LiteralPath (Join-Path $envOutputPath ("Web." + $envName + ".config")) -Force
            }
 
            default { throw "Unknown configStrategy '$($Component.configStrategy)' for $($Component.name)" }
        }
 
        Add-Result 'EnvOutput' $Component.name 'OK' $envOutputPath
        return $envOutputPath
    }
 
    # ============================ per-environment loop ==========================
 
    foreach ($envKey in $envKeys) {
        $envCfg  = $manifest.environments.$envKey
        $envName = $envCfg.envName
 
        # Gate each environment when deploying to several (or in guided mode).
        if ($envKeys.Count -gt 1 -or $Guided) {
            if (-not (Confirm-Step -Always "Deploy to $envName" "Sections: $($Only -join ', ')")) { continue }
        }
 
    # ------------------------------------------------------- web components ----
 
    if ($Only -contains 'WebComponents' -and (Confirm-Step 'Web components' "Stage, generate $envName environment output, and copy to app servers")) {
        $webComponents = @($manifest.components | Where-Object { $_.configStrategy -ne 'none' })
 
        foreach ($comp in $webComponents) {
            $envOutputPath = New-EnvironmentOutput -Component $comp
 
            foreach ($server in $envCfg.appServers) {
                $targetOnServer = Resolve-EnvToken $comp.serverTargetPath $envName
                $label = "$($comp.name) @ $($server.host)"
 
                if (Test-Todo $server.host) {
                    Add-Result 'DeployWeb' $comp.name 'MANUAL' "Manifest appServers.host is TODO. Copy $envOutputPath to <server>:$targetOnServer (CyberArk safe: $($server.cyberArkSafe))"
                    continue
                }
                if ($server.access -eq 'jump') {
                    Add-Result 'DeployWeb' $label 'MANUAL' "Jump-server route. Copy $envOutputPath via $($manifest.jumpServers.default) to $targetOnServer"
                    continue
                }
 
                # Direct: translate E:\WebApps\... to \\host\E$\WebApps\...
                $unc = '\\' + $server.host + '\' + ($targetOnServer -replace '^([A-Za-z]):', '$1$')
                if (-not (Confirm-Step "Copy $($comp.name) -> $($server.host)" $unc)) { continue }
                try {
                    Copy-WithVerify -Source $envOutputPath -Destination $unc -Label $label | Out-Null
                    Write-BuildStamp -Destination $unc -Info @{ component = $comp.name; environment = $envName; build = $BuildFile }
                    if (-not $DryRun) { Add-Result 'DeployWeb' $label 'OK' $unc }
                }
                catch {
                    Add-Result 'DeployWeb' $label 'FAILED' $_.Exception.Message
                }
            }
        }
    }
 
    # ---------------------------------------------------------------- addin ----
 
    if ($Only -contains 'Addin' -and (Confirm-Step 'Add-in (Addin0365)' 'Stage the add-in and copy to OneSpace shares (jump-server routes report as manual)')) {
        $addinComp = $manifest.components | Where-Object { $_.name -eq 'Addin0365' }
        $addinSource = New-EnvironmentOutput -Component $addinComp
 
        foreach ($share in $envCfg.addin.shares) {
            if (Test-Todo $share) {
                Add-Result 'DeployAddin' $share 'MANUAL' 'Share value is TODO in manifest.'
                continue
            }
            if ($envCfg.addin.access -eq 'jump') {
                Add-Result 'DeployAddin' $share 'MANUAL' "Jump-server route: copy $addinSource via $($manifest.jumpServers.default) to $share"
                continue
            }
            try {
                Copy-WithVerify -Source $addinSource -Destination $share -Label "Addin -> $share" | Out-Null
                if (-not $DryRun) { Add-Result 'DeployAddin' $share 'OK' '' }
            }
            catch {
                Add-Result 'DeployAddin' $share 'FAILED' $_.Exception.Message
            }
        }
    }
 
    # --------------------------------------------------------------- models ----
 
    if ($Only -contains 'Models' -and (Confirm-Step 'Models' "Copy model files to the $envName NetApp share")) {
        if (-not $ModelBuildFolder) {
            Add-Result 'DeployModels' $envName 'SKIPPED' 'Pass -ModelBuildFolder <extracted model build> to include models.'
        }
        elseif (Test-Todo $envCfg.modelShare) {
            Add-Result 'DeployModels' $envName 'MANUAL' "Manifest modelShare is TODO. Copy $ModelBuildFolder contents to the environment's NetApp share."
        }
        else {
            try {
                Copy-WithVerify -Source $ModelBuildFolder -Destination $envCfg.modelShare -Label "Models -> $($envCfg.modelShare)" | Out-Null
                if (-not $DryRun) { Add-Result 'DeployModels' $envCfg.modelShare 'OK' '' }
            }
            catch {
                Add-Result 'DeployModels' $envCfg.modelShare 'FAILED' $_.Exception.Message
            }
        }
    }
 
    # ------------------------------------------------------------- database ----
 
    if ($Only -contains 'Database' -and (Confirm-Step 'Database' "sqlpackage /Action:$DbMode against $envName")) {
        if (-not $DbBuildFolder) {
            $dbCandidate = Get-ChildItem -LiteralPath $targetBasePath -Directory -Filter 'PricingDB_*_Build-*' -ErrorAction SilentlyContinue |
                           Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($dbCandidate -and (Confirm-Choice "Use newest DB build folder '$($dbCandidate.Name)'?")) {
                $DbBuildFolder = $dbCandidate.FullName
            }
        }
 
        if (-not $DbBuildFolder) {
            Add-Result 'Database' $envName 'SKIPPED' 'No DB build folder found/selected. Pass -DbBuildFolder to include the database.'
        }
        else {
            $dacpac      = Join-Path $DbBuildFolder 'PricingSystems.Database.dacpac'
            $profileFile = Join-Path $DbBuildFolder (Resolve-EnvToken $envCfg.database.publishProfile $envName)
            if (-not (Test-Path -LiteralPath $dacpac))      { throw "dacpac not found: $dacpac" }
            if (-not (Test-Path -LiteralPath $profileFile)) { throw "publish profile not found: $profileFile" }
 
            $sqlpackage = $manifest.paths.sqlPackageExe
            $dbArgs = @("/SourceFile:$dacpac", "/Profile:$profileFile")
 
            # Manifest overrides beat whatever the profile says - this is the fix for
            # stale post-migration connection strings.
            $serverRef = $envCfg.database.serverRef
            $dbServer  = $null
            if ($serverRef -and -not (Test-Todo $serverRef)) { $dbServer = $manifest.databaseServers.$serverRef }
            if ($dbServer -and -not (Test-Todo $dbServer)) { $dbArgs += "/TargetServerName:$dbServer" }
            if (-not (Test-Todo $envCfg.database.databaseName)) { $dbArgs += "/TargetDatabaseName:$($envCfg.database.databaseName)" }
 
            $dbScriptDir = Join-Path $targetBasePath 'dbscript'
            if (-not (Test-Path $dbScriptDir)) { New-Item -Path $dbScriptDir -ItemType Directory -Force | Out-Null }
 
            switch ($DbMode) {
                'Script'  { $outFile = Join-Path $dbScriptDir ("output-{0}-{1}.sql" -f $envKey, (Get-Date).ToString('yyyyMMdd-HHmmss'))
                            $dbArgs = @('/Action:Script',  "/OutputPath:$outFile") + $dbArgs }
                'Report'  { $outFile = Join-Path $dbScriptDir ("report-{0}-{1}.xml" -f $envKey, (Get-Date).ToString('yyyyMMdd-HHmmss'))
                            $dbArgs = @('/Action:DeployReport', "/OutputPath:$outFile") + $dbArgs }
                'Publish' { $outFile = $null
                            $dbArgs = @('/Action:Publish') + $dbArgs }
            }
 
            if ($DryRun) {
                Add-Result 'Database' "$envName ($DbMode)" 'DRYRUN' "$sqlpackage $($dbArgs -join ' ')"
            }
            else {
                if ($DbMode -eq 'Publish' -and -not (Confirm-Choice "Publish database changes DIRECTLY to $envName ?")) {
                    Add-Result 'Database' $envName 'SKIPPED' 'Publish declined by operator.'
                }
                else {
                    Write-Host "Running sqlpackage /Action:$DbMode for $envName ..."
                    & $sqlpackage @dbArgs
                    if ($LASTEXITCODE -ne 0) {
                        Add-Result 'Database' "$envName ($DbMode)" 'FAILED' "sqlpackage exit code $LASTEXITCODE"
                    }
                    else {
                        Add-Result 'Database' "$envName ($DbMode)" 'OK' "$outFile"
 
                        # Script mode: also produce a clean file with the SQLCMD preamble
                        # stripped BY MARKER (never by line number), ready for SSMS.
                        if ($DbMode -eq 'Script' -and $outFile -and (Test-Path -LiteralPath $outFile)) {
                            $lines = Get-Content -LiteralPath $outFile
                            $markerMatch = $lines | Select-String -Pattern 'Pre.?deployment Script' | Select-Object -First 1
                            $markerIdx = if ($markerMatch) { $markerMatch.LineNumber } else { 0 }
                            if ($markerIdx) {
                                $cleanFile = $outFile -replace '\.sql$', '-clean.sql'
                                $lines[($markerIdx - 1)..($lines.Count - 1)] | Set-Content -LiteralPath $cleanFile -Encoding UTF8
                                Add-Result 'Database' 'preamble-strip' 'OK' "SSMS-ready file: $cleanFile"
                            }
                            else {
                                Add-Result 'Database' 'preamble-strip' 'MANUAL' "Marker 'Predeployment Script' not found in $outFile - review file before running."
                            }
                        }
                    }
                }
            }
        }
    }
 
    }   # ======================== end per-environment loop ======================
}
finally {
    # ------------------------------------------------------------- summary ----
    Write-Host ""
    Write-Host "=== Deployment summary: $envLabel ($currentDate) ===" -ForegroundColor White
    $script:Results | Format-Table Step, Target, Status, Detail -AutoSize | Out-String -Width 220 | Write-Host
    $failed = @($script:Results | Where-Object Status -eq 'FAILED')
    $manual = @($script:Results | Where-Object Status -eq 'MANUAL')
    Write-Host ("{0} OK, {1} manual step(s) remaining, {2} FAILED. Log: {3}" -f `
        @($script:Results | Where-Object Status -eq 'OK').Count, $manual.Count, $failed.Count, $logFile) `
        -ForegroundColor $(if ($failed.Count) { 'Red' } elseif ($manual.Count) { 'Yellow' } else { 'Green' })
    Stop-Transcript | Out-Null
    if ($failed.Count) { exit 1 }
}