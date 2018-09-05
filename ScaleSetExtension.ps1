function InstallDependencies
{
    SetTimeZone
    InstallCocolatey
    ChocoInstall -Package "dotnet4.7.2"
    ChocoInstall -Package "dotnetcore-runtime" -Version "2.0.7"
    ChocoInstall -Package "dotnetcore-runtime" -Version "2.1.3"
}

function SetTimeZone
{
    $timeZone = "W. Europe Standard Time"
    $cmdOutPut = Set-TimeZone $timeZone *>&1 | Out-String
    Log -Message "Setting timezone to $timeZone`r`n$cmdOutput" -Level "INFO" -Logger "SetTimeZone"
}

function InstallCocolatey
{
    choco.exe -v
    $Output = $?
    If (-Not $Output) {  
        $cmdOutput = iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')) *>&1 | Out-String        
        Log -Message "Installing Chocolatey`r`n$cmdOutput" -Level "WARN" -Logger "ChocolateySetup"
    }
    else {
        Log -Message "Chocolatey already installed, skipping." -Level "INFO" -Logger "ChocolateySetup"
    }
}

function ChocoInstall
{
    Param ([string] $Package,
    [string] $Version = "")    
    $cmdOutPut = & choco install -myv $Package --version="$Version" *>&1 | Out-String        
    Log -Message "Installing $Package from Chocolatey`r`n$cmdOutput" -Level "INFO" -Logger "ChocoInstall"
}

InstallDependencies