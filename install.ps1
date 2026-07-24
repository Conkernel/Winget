#Requires -RunAsAdministrator
#Requires -Version 5.1


$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$WingetReleaseApi = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"

$WingetPackageName = "Microsoft.DesktopAppInstaller"

$WingetDependenciesZip =
    "DesktopAppInstaller_Dependencies.zip"



Write-Host "========================================="
Write-Host " Winget Installer"
Write-Host "========================================="


function Write-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host
    Write-Host "==> $Message"
}

function Write-Info {

    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[INFO] $Message" -ForegroundColor Cyan

}

function Write-Success {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[OK] $Message" -ForegroundColor Green
}


function Stop-Installation {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    throw $Message
}


function Wait-Command {

    param(
        [Parameter(Mandatory)]
        [scriptblock]$Script,

        [int]$Timeout = 120
    )

    $Stopwatch = [Diagnostics.Stopwatch]::StartNew()

    while ($Stopwatch.Elapsed.TotalSeconds -lt $Timeout) {

        try {

            if (& $Script) {
                return $true
            }

        }
        catch {
        }

        Start-Sleep -Seconds 1
    }

    return $false
}


function Download-File {

    param(

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Destination

    )

    if (Test-Path $Destination) {

        Write-Info "Ya existe: $Destination"

        return

    }

    Write-Info "Descargando $Url"

    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $Destination `
        -UseBasicParsing

}



function Test-AppxPackage {

    param(
        [Parameter(Mandatory)]
        [string]$Name
    )


    return [bool](
        Get-AppxPackage `
            -AllUsers `
            | Where-Object {
                $_.Name -like "$Name*"
            }
    )

}

function Get-TempDirectory {

    $Directory = Join-Path $env:TEMP "WinGetInstaller"

    if (-not (Test-Path $Directory)) {

        New-Item `
            -Path $Directory `
            -ItemType Directory | Out-Null

    }

    return $Directory

}
function Install-MSIX {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )


    if (-not (Test-Path $Path)) {

        Stop-Installation "No existe el archivo '$Path'."

    }


    Write-Info "Instalando $([IO.Path]::GetFileName($Path))"


    Add-AppxPackage `
        -Path $Path `
        -ForceApplicationShutdown `
        -ErrorAction Stop

}
function Install-WinGetDependencies {

    param(

        [Parameter(Mandatory)]
        [pscustomobject]$Winget

    )


    Write-Step "Instalando dependencias de WinGet"


    $Temp =
        Get-TempDirectory



    $Zip =
        Join-Path `
            $Temp `
            $Winget.DependenciesName



    Download-File `
        -Url $Winget.DependenciesUrl `
        -Destination $Zip



    $Extract =
        Join-Path `
            $Temp `
            "WinGetDependencies"



    if (Test-Path $Extract) {

        Remove-Item `
            $Extract `
            -Recurse `
            -Force

    }



    Expand-Archive `
        -Path $Zip `
        -DestinationPath $Extract `
        -Force




    $Packages =
        Get-ChildItem `
            -Path $Extract `
            -Recurse `
            -Include *.appx,*.msix,*.appxbundle,*.msixbundle



    foreach ($Package in $Packages) {


        Write-Info "Instalando dependencia $($Package.Name)"


        try {

            Add-AppxPackage `
                -Path $Package.FullName `
                -ErrorAction Stop


            Write-Success "$($Package.Name) instalado."

        }

        catch {

            Write-Info "$($Package.Name) ya instalado o no requerido."

        }


    }


}

function Wait-AppxPackage {

    param(

        [Parameter(Mandatory)]
        [string]$Name,

        [int]$Timeout = 120

    )

    return Wait-Command `
        -Timeout $Timeout `
        -Script {

            Test-AppxPackage $Name

        }

}

function Test-WinGet {

    try {

        $Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

        if ($Winget) {

            & winget.exe --version *> $null

            if ($LASTEXITCODE -eq 0) {
                return $true
            }

        }


        $WingetCmd = Get-Command winget.cmd -ErrorAction SilentlyContinue

        if ($WingetCmd) {

            & winget.cmd --version *> $null

            if ($LASTEXITCODE -eq 0) {
                return $true
            }

        }


        return $false

    }
    catch {

        return $false

    }

}
function Get-LatestWingetRelease {

    Write-Info "Obteniendo la última versión de WinGet..."


    $Release = Invoke-RestMethod `
        -Uri $WingetReleaseApi



    $Bundle = $Release.assets |
        Where-Object {
            $_.name -eq "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        } |
        Select-Object -First 1



    if (-not $Bundle) {

        Stop-Installation `
            "No se encontró Microsoft.DesktopAppInstaller."

    }



    $Dependencies = $Release.assets |
        Where-Object {
            $_.name -eq "DesktopAppInstaller_Dependencies.zip"
        } |
        Select-Object -First 1



    if (-not $Dependencies) {

        Stop-Installation `
            "No se encontró DesktopAppInstaller_Dependencies.zip."

    }



    return [PSCustomObject]@{


        Package =
            $WingetPackageName



        Version =
            $Release.tag_name



        Name =
            $Bundle.name



        Url =
            $Bundle.browser_download_url



        DependenciesName =
            $Dependencies.name



        DependenciesUrl =
            $Dependencies.browser_download_url


    }

}

function Install-WinGetPackage {

    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Winget
    )


    Install-WinGetDependencies `
        -Winget $Winget



    Write-Step "Instalando WinGet"


    $Temp =
        Get-TempDirectory


    $Installer =
        Join-Path `
            $Temp `
            $Winget.Name



    Download-File `
        -Url $Winget.Url `
        -Destination $Installer



    Install-MSIX `
        -Path $Installer

    if (-not (Wait-AppxPackage -Name $Winget.Package)) {

        Stop-Installation `
            "El paquete '$($Winget.Package)' no se registró correctamente."

    }

    Write-Success "Paquete WinGet instalado."

}

function Install-WinGetWrapper {

    Write-Step "Creando acceso global a WinGet"


    $Package = Get-AppxPackage `
        -AllUsers |
        Where-Object {
            $_.Name -like "Microsoft.DesktopAppInstaller*"
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1


    if (-not $Package) {

        Stop-Installation "No se encontró Microsoft Desktop App Installer."

    }


    $WingetExe = Join-Path `
        $Package.InstallLocation `
        "winget.exe"



    if (-not (Test-Path $WingetExe)) {

        Stop-Installation `
            "No existe winget.exe en $WingetExe"

    }


    $Wrapper = "C:\Windows\System32\winget.cmd"


    $Content = @"
@echo off
"$WingetExe" %*
"@



    Set-Content `
        -Path $Wrapper `
        -Value $Content `
        -Encoding ASCII



    Write-Success "Wrapper creado: $Wrapper"


}




function Install-WinGet {

    Write-Step "Comprobando WinGet"


    if (Test-WinGet) {

        Write-Success "WinGet ya está instalado."

        return

    }


    Write-Info "Instalando WinGet..."


    $Winget = Get-LatestWingetRelease


    Install-WinGetPackage `
        -Winget $Winget


    Install-WinGetWrapper


    Refresh-Environment


    if (-not (Wait-Command -Timeout 180 -Script { Test-WinGet })) {

        Stop-Installation "No ha sido posible validar WinGet."

    }


    Write-Success "WinGet instalado correctamente."

}

function Refresh-Environment {

    $MachinePath =
        [Environment]::GetEnvironmentVariable(
            "Path",
            "Machine"
        )


    $UserPath =
        [Environment]::GetEnvironmentVariable(
            "Path",
            "User"
        )


    $AliasPath =
        "$env:LOCALAPPDATA\Microsoft\WindowsApps"


    $env:PATH =
        "$MachinePath;$UserPath;$AliasPath"

}



try {

    Install-WinGet

}
catch {

    Write-Host
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}