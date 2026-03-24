param (
    [string]$modFileName,
    [string]$preferredGames
)

if (-not $modFileName) {
    Write-Host "Error: No mod file name provided." -ForegroundColor Red
    exit 1
}

$modFileNameBase = [System.IO.Path]::GetFileNameWithoutExtension($modFileName)
$script:csvFile = "$modFileNameBase.csv"
$script:outputCsv = "$modFileNameBase-update.csv"

$tokenFilePath = Join-Path -Path $PSScriptRoot -ChildPath "token.txt"

function Get-GitHubToken {
    param ([string]$tokenFilePath)

    if (Test-Path $tokenFilePath) {
        $token = (Get-Content -Path $tokenFilePath -Raw).Trim()
        if ($token) { return $token }
    }

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Yellow
    Write-Host " GitHub Token Required" -ForegroundColor Yellow
    Write-Host "======================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "A GitHub personal access token is needed to use this script." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Steps to get one:" -ForegroundColor White
    Write-Host "  1. Sign in to GitHub (or create a free account at https://github.com/signup)"
    Write-Host "  2. Go to: https://github.com/settings/tokens/new"
    Write-Host "  3. Set a note (e.g. 'Indohelper'), set expiration, check 'public_repo' scope"
    Write-Host "  4. Click 'Generate token' and copy it"
    Write-Host ""

    # Auto-open the token page in the browser
    $openBrowser = Read-Host "Open the GitHub token page in your browser now? (Y/n)"
    if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
        Start-Process "https://github.com/settings/tokens/new"
    }

    Write-Host ""
    $token = Read-Host "Paste your GitHub token here"
    $token = $token.Trim()

    if (-not $token) {
        Write-Host "Error: No token provided. Exiting." -ForegroundColor Red
        exit 1
    }

    # Save token for future runs
    Set-Content -Path $tokenFilePath -Value $token -NoNewline
    Write-Host "Token saved to: $tokenFilePath" -ForegroundColor Green
    Write-Host ""

    return $token
}

$script:githubToken = Get-GitHubToken -tokenFilePath $tokenFilePath

$script:gitPath = Resolve-Path "..\Tools\Git\2.30.2\cmd\git.exe"
$script:modsFolder = "..\$modFileNameBase"
$script:scriptDir = (Get-Location).Path

if (-not (Test-Path -Path $script:modsFolder)) {
    New-Item -ItemType Directory -Path $script:modsFolder | Out-Null
}

if (-not (Get-Module -ListAvailable -Name 7Zip4PowerShell))
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Set-PSRepository -Name 'PSGallery' -SourceLocation "https://www.powershellgallery.com/api/v2" -InstallationPolicy Trusted
    Install-Module -Name 7Zip4PowerShell -Force
}

"Codename,Category,URL,Game,UseMaster,Release,Version" | Out-File -FilePath $script:outputCsv -Encoding UTF8

function DownloadGithub
{
    param (
        [string]$URL,
        [switch]$UseMaster
    )

    $Codename = $URL.Split('/')[-1]
    $modPath = Join-Path -Path $script:modsFolder -ChildPath $Codename

    if (Test-Path -Path $modPath) {
        Remove-Item -Path $modPath -Recurse -Force
    }

    Push-Location -Path $script:modsFolder
    & "$script:gitPath" clone --depth 1 $URL $modPath > $null 2>&1

    if ($UseMaster) {
        $branch = & "$script:gitPath" rev-parse --verify master 2>$null
        if ($branch) {
            & "$script:gitPath" checkout master > $null 2>&1
            Write-Host "Checked out branch: master"
        }
        else {
            & "$script:gitPath" checkout main > $null 2>&1
            Write-Host "Checked out branch: main (master not found)"
        }
    }
    else
    {
        Push-Location -Path $modPath
        & "$script:gitPath" fetch --tags > $null 2>&1
        $latestTag = & "$script:gitPath" describe --tags $( & "$script:gitPath" rev-list --tags --max-count=1 )
        & "$script:gitPath" checkout $latestTag > $null 2>&1
    }

    Set-Location -Path $script:scriptDir

    Remove-Item -Path "$modPath/.git" -Recurse -Force
    Get-ChildItem -Path "$modPath" -Filter ".git*" -Recurse | Remove-Item -Recurse -Force
}

function DownloadWeb {
    param (
        [string]$downloadLink,
        [string]$Codename,
        [string]$extension
    )

    $modPath = Join-Path -Path $script:modsFolder -ChildPath $Codename

    $downloadsDir = Join-Path $script:scriptDir "downloads"
    $tempDir = Join-Path $script:scriptDir "temp"

    if (-not (Test-Path -Path $downloadsDir)) {
        New-Item -ItemType Directory -Path $downloadsDir | Out-Null
    }

    if (Test-Path -Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
    if (Test-Path -Path $modPath)
    {
        Remove-Item -Path $modPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    New-Item -ItemType Directory -Path $modPath | Out-Null

    $downloadedFile = Join-Path $downloadsDir "$Codename.$extension"
    Invoke-WebRequest -Uri $downloadLink -OutFile $downloadedFile

    if ($extension -eq "zip") {
        Expand-Archive -Path $downloadedFile -DestinationPath $tempDir
    } elseif ($extension -eq "rar") {
        Expand-7Zip -ArchiveFileName $downloadedFile -TargetPath $tempDir
    } else {
        throw "Unsupported archive format: $extension"
    }

    Get-ChildItem -Path "$tempDir/" -Filter "setup-*.exe" -File | Remove-Item -Force
    Copy-Item -Path "$tempDir/*" -Destination $modPath -Recurse

    Remove-Item -Path $tempDir -Recurse -Force
    Remove-Item -Path $downloadedFile -Force
}

$esc = [char]27
$blue = "${esc}[34m"
$bold = "${esc}[1m"
$reset = "${esc}[0m"

Import-Csv -Path $script:csvFile | ForEach-Object {

    foreach ($property in @('URL', 'Category', 'Codename', 'Version', 'Release', 'UseMaster', 'Game')) {
        if ($_.PSObject.Properties[$property] -and $_.$property) {
            Set-Variable -Name $property -Value ($_.($property).Trim('"').Trim().TrimEnd('/'))
        } else {
            Set-Variable -Name $property -Value $null
        }
    }

    # Skip if Game doesn't match any of the preferred games
    if ($preferredGames -and $Game) {
        $preferredList = $preferredGames -split '-'  | ForEach-Object { $_.Trim() }
        $gameList      = $Game -split '-' | ForEach-Object { $_.Trim() }

        $hasMatch = $false
        foreach ($pg in $preferredList) {
            if ($gameList -icontains $pg) {
                $hasMatch = $true
                break
            }
        }
        if (-not $hasMatch) {
            "$Codename,$Category,`"$URL`",$Game,$UseMaster,$Release,`"$Version`"" | Out-File -FilePath $script:outputCsv -Append -Encoding UTF8
            return
        }
    }

    $formattedDate = $Release

    Write-Host -NoNewline $Codename": "

	if (-not $URL) {
        Write-Host "[FAIL] No download URL"
    }

    if ($URL -match "github\.com" -or $URL -match "baldurs-gate\.de" -or $URL -match "downloads\.weaselmods\.net" -or $URL -match "morpheus-mart\.com" -or $URL -match "imoen\.blindmonkey\.org")
    {
        try
        {
            $modPath = Join-Path -Path $script:modsFolder -ChildPath $Codename

            if ($URL -match "downloads\.weaselmods\.net")
            {
                $Codename = $URL.Split('/')[-1]

                $response = Invoke-WebRequest -Uri $URL
                $html = $response.Content

                $currentVersion = [regex]::Match($html, '(?<=<strong>Version</strong><br/>)([^<]+)').Value
                $downloadLink = [regex]::Match($html, 'data-downloadurl=\"([^\"]+)\"').Groups[1].Value
                $lastUpdated = [regex]::Match($html, '(?<=<strong>Last Updated</strong><br/>)([^<]+)').Value
                $lastUpdatedDate = Get-Date -Date $lastUpdated
                $Release = $lastUpdatedDate.ToString("yyyy-MM-dd")
                $extension = "zip"
            }

            if ($URL -match "morpheus-mart\.com")
            {
                $Codename = $URL.Split('/')[-1]

                $response = Invoke-WebRequest -Uri $URL
                $html = $response.Content

                $currentVersion = [regex]::Match($html, '<strong>Version\s+([^<]+)</strong>').Groups[1].Value
                $downloadLink = [regex]::Match($html, 'href="(https://www\.dropbox\.com/[^"]+)"').Groups[1].Value -replace 'www\.dropbox\.com', 'dl.dropboxusercontent.com' ` -replace 'dl=0', 'dl=1'
                $lastUpdated = [regex]::Match($html, '(?i)(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},\s+\d{4}').Value

                if ($Codename -eq "fight-the-heavens")
                {
                    if ([string]::IsNullOrEmpty($currentVersion)) { $currentVersion = "v1.2" }
                    if ([string]::IsNullOrEmpty($lastUpdated))    { $lastUpdated = "2025-10-11" }
                }

                $lastUpdatedDate = Get-Date -Date $lastUpdated
                $Release = $lastUpdatedDate.ToString("yyyy-MM-dd")

                $extension = "zip"
            }

            if ($URL -match "imoen\.blindmonkey\.org")
            {
                $Codename = 'imoenRomance'

                $response = Invoke-WebRequest -Uri $URL
                $html = $response.Content

                $downloadLink  = [regex]::Match($html, 'href="(http://www\.blindmonkey\.org/imoen/files/[^"]+)"').Groups[1].Value
                $currentVersion = [regex]::Match($html, 'DOWNLOAD</a>\s*-\s*v([\d.]+)').Groups[1].Value
                $lastUpdated    = [regex]::Match($html, 'DOWNLOAD</a>\s*-\s*v[\d.]+\s+([A-Za-z]+\s+\d+\w*\s+\d{4})').Groups[1].Value -replace '(\d+)(st|nd|rd|th)', '$1'

                $lastUpdatedDate = Get-Date -Date $lastUpdated
                $Release = $lastUpdatedDate.ToString("yyyy-MM-dd")

                $extension = "zip"
            }

            if ($URL -match "baldurs-gate\.de")
            {
                $Codename = $URL.Split('/')[-1]

                $response = Invoke-WebRequest -Uri $URL
                $html = $response.Content

                if ($html -match '<h1 class="p-title-value">\s*(.*?)\s*<span class="u-muted">\s*(.*?)\s*</span>')
                {
                    $currentVersion = $matches[2].Trim()
                }


                if ($html -match '<dt>Letzte Bearbeitung</dt>\s*<dd><time[^>]*data-date-string="([^"]+)"')
                {
                    $dateObject = Get-Date -Date $matches[1]
                    $Release = $dateObject.ToString("yyyy-MM-dd")
                }

                $downloadLink = if ($URL -notlike '*/')
                {
                    "$URL/"
                }
                else
                {
                    $URL
                }
                $downloadLink = "$downloadLink" + "download"

                $extension = "rar"
            }

            if ($URL -match "github\.com")
            {
                $Codename = $URL.Split('/')[-1]
                $author = $URL.Split('/')[-2]
                $apiUrl = "https://api.github.com/repos/$author/$Codename"
                $auth = @{ Authorization = "token $script:githubToken" }

                if ($UseMaster) {
                    $response = Invoke-RestMethod -Uri "$apiUrl/commits" -Headers $auth -UseBasicParsing
                    $currentVersion = $response[0].sha.Substring(0, 7) # short hash
                    $Release = $response[0].commit.author.date.Substring(0, 10)
                } else
                {
                    try
                    {
                        $response = Invoke-RestMethod -Uri "$apiUrl/releases/latest" -Headers $auth -UseBasicParsing
                        $currentVersion = $response.tag_name
                        $Release = $response.published_at.Substring(0, 10)
                    }
                    catch
                    {
                        # take the data from the last commit if there is no release
                        $response = Invoke-RestMethod -Uri "$apiUrl/commits" -Headers $auth -UseBasicParsing
                        $currentVersion = $response[0].sha.Substring(0, 7) # short hash
                        $Release = $response[0].commit.author.date.Substring(0, 10)
                    }
                }
            }

            if (Test-Path $modPath)
            {
                Write-Host -NoNewline "[OK] Repo already cloned, checking for latest version..."

                if ($currentVersion -ne $Version)
                {
                    Write-Host -NoNewline "${bold}${blue}updating [$Version -> $currentVersion] "

                    if ($URL -match "github\.com")
                    {
                        if ($UseMaster)
                        {
                            DownloadGithub -url $URL -UseMaster
                        } else {
                            DownloadGithub -url $URL
                        }
                    }
                    else
                    {
                        DownloadWeb -downloadLink $downloadLink -codeName $Codename -extension $extension
                    }

                }
                else
                {
                    Write-Host -NoNewline "up to date [$currentVersion] "
                }
            }
            else
            {
                Write-Host -NoNewline "${bold}${blue}Downloading..."

                if ($URL -match "github\.com")
                {
                    DownloadGithub -url $URL
                }
                else
                {
                    DownloadWeb -downloadLink $downloadLink -codeName $Codename -extension $extension
                }
            }

            $Version = $currentVersion

            Write-Host "[OK] ${reset}"
        }
        catch
        {
            Write-Host "[FAIL] An error occurred: $_ ${reset}"
            Write-Host "Error Details: $( $Error[0].Exception.Message )"
            Write-Host "Error occurred at line: $( $Error[0].InvocationInfo.ScriptLineNumber )"
        }
    } else {
        Write-Host "[SKIPPING] ${reset}"
    }

    "$Codename,$Category,`"$URL`",$Game,$UseMaster,$Release,`"$Version`"" | Out-File -FilePath $script:outputCsv -Append -Encoding UTF8

    Write-Host ""
}

Remove-Item -Path $script:csvFile -Force
Rename-Item -Path $script:outputCsv -NewName "$script:csvFile"