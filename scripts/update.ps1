param (
    [string]$modFileName
)

if (-not $modFileName) {
    Write-Host "Error: No mod file name provided." -ForegroundColor Red
    exit 1
}

$modFileNameBase = [System.IO.Path]::GetFileNameWithoutExtension($modFileName)
$script:csvFile = "$modFileNameBase.csv"
$script:outputCsv = "$modFileNameBase-update.csv"

$tokenFilePath = Join-Path -Path $PSScriptRoot -ChildPath "token.txt"
$script:githubToken = Get-Content -Path $tokenFilePath -Raw
$script:gitPath = Resolve-Path "..\Tools\Git\2.30.2\cmd\git.exe"
$script:modsFolder = "..\$modFileNameBase"
$script:scriptDir = (Get-Location).Path

if (-not (Get-Module -ListAvailable -Name 7Zip4PowerShell))
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Set-PSRepository -Name 'PSGallery' -SourceLocation "https://www.powershellgallery.com/api/v2" -InstallationPolicy Trusted
    Install-Module -Name 7Zip4PowerShell -Force
}

"Name,Codename,Category,URL,Version,Release" | Out-File -FilePath $script:outputCsv -Encoding UTF8

function DownloadGithub
{
    param (
        [string]$URL
    )

    $Codename = $URL.Split('/')[-1]
    $modPath = Join-Path -Path $script:modsFolder -ChildPath $Codename

    if (Test-Path -Path $modPath) {
        Remove-Item -Path $modPath -Recurse -Force
    }

    Push-Location -Path $script:modsFolder
    & "$script:gitPath" clone --depth 1 $URL $modPath > $null 2>&1

    Push-Location -Path $modPath
    & "$script:gitPath" fetch --tags > $null 2>&1
    $latestTag = & "$script:gitPath" describe --tags $( & "$script:gitPath" rev-list --tags --max-count=1 )
    & "$script:gitPath" checkout $latestTag > $null 2>&1

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


Import-Csv -Path $script:csvFile | ForEach-Object {

    foreach ($property in @('URL', 'Category', 'Name', 'Codename', 'Version', 'Release')) {
        if ($_.PSObject.Properties[$property] -and $_.$property) {
            Set-Variable -Name $property -Value ($_.($property).Trim('"').Trim().TrimEnd('/'))
        } else {
            Set-Variable -Name $property -Value $null
        }
    }

    $formattedDate = $Release

    Write-Host -NoNewline $Name": "

	if (-not $URL) {
        Write-Host "[FAIL] No download URL"
    }

    if ($URL -match "github\.com" -or $URL -match "baldurs-gate\.de" -or $URL -match "downloads\.weaselmods\.net")
    {
        try
        {
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

            $modPath = Join-Path -Path $script:modsFolder -ChildPath $Codename

            if (Test-Path $modPath)
            {
                Write-Host -NoNewline "[OK] Repo already cloned, checking for latest version..."

                if ($currentVersion -ne $Version)
                {
                    Write-Host -NoNewline "updating [$Version -> $currentVersion] "

                    if ($URL -match "github\.com")
                    {
                        DownloadGithub -url $URL
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
                Write-Host -NoNewline "Downloading..."

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

            Write-Host "[OK]"
        }
        catch
        {
            Write-Host "[FAIL] An error occurred: $_"
            Write-Host "Error Details: $( $Error[0].Exception.Message )"
            Write-Host "Error occurred at line: $( $Error[0].InvocationInfo.ScriptLineNumber )"
        }
    }

    "`"$Name`",$Codename,$Category,`"$URL`",`"$Version`",$Release" | Out-File -FilePath $script:outputCsv -Append -Encoding UTF8

    Write-Host ""
}

Remove-Item -Path $script:csvFile -Force
Rename-Item -Path $script:outputCsv -NewName "$script:csvFile"