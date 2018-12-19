[CmdletBinding()]
Param (
    [Parameter(Position=0)]
	$LoggEndPoint
,
    [Parameter(Position=1)]
    $NewRelicKey
,
   [Parameter()]
   [Switch]$Clear
)

function Setup
{
    Log -Message "Setup starting" -Level "INFO" -Logger "Setup";

    PrepareDisks;
    SetTimeZone;
    InstallCocolatey;
    ChocoInstall -Package "dotnet4.7.2";
    ChocoInstall -Package "dotnetcore-runtime";
    ChocoInstall -Package "nodejs-lts" -Version "10.14.2";
    SetupNewRelic -Version "8.6.45.0" -LicenseKey $NewRelicKey;

    Log -Message "Setup completed" -Level "INFO" -Logger "Setup";
}

function SetTimeZone
{
    $timeZone = "W. Europe Standard Time";
    $cmdOutPut = Set-TimeZone $timeZone *>&1 | Out-String;
    Log -Message "Setting timezone to $timeZone`r`n$cmdOutput" -Level "INFO" -Logger "SetTimeZone";
}

function InstallCocolatey
{
    choco.exe -v;
    $Output = $?;
    If (-Not $Output) {  
        $cmdOutput = iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')) *>&1 | Out-String;
        Log -Message "Installing Chocolatey`r`n$cmdOutput" -Level "WARN" -Logger "ChocolateySetup";
    }
    else {
        Log -Message "Chocolatey already installed, skipping." -Level "INFO" -Logger "ChocolateySetup";
    }
}

function ChocoInstall
{
    Param ([string] $Package,
    [string] $Version = "",
    [string] $Params = "",
    [string] $Flags = "")  

    $Command = "$env:ChocolateyInstall\bin\choco.exe";
    $Arguments = "install -y $Flags $Package --version=`"$Version`" --params=`"$Params`"";
    RunProcess -Command $Command -Arguments $Arguments -Logger "ChocoInstall" -Description "Installing $Package from Chocolatey";    
}

function PrepareDisks {
	$disks = Get-Disk | Where partitionstyle -eq 'raw' | sort number;

	$letters = 70..89 | ForEach-Object { [char]$_ };
	$count = 0;
	$label = "datadisk";

	foreach ($disk in $disks) {
		$driveLetter = $letters[$count].ToString();
		$disk | 
		Initialize-Disk -PartitionStyle MBR -PassThru |
		New-Partition -UseMaximumSize -DriveLetter $driveLetter |
		Format-Volume -FileSystem NTFS -NewFileSystemLabel $label.$count -Confirm:$false -Force;
		$count++;
	}
}

function SetupNewRelic
{
    Param ([string] $Version,
    [string] $LicenseKey)
    
    $CurrentFolder = $PSScriptRoot;
    $DotNetUrl = "https://download.newrelic.com/dot_net_agent/previous_releases/$Version/newrelic-agent-win-$Version-scriptable-installer.zip";
    $CoreUrl = "https://download.newrelic.com/dot_net_agent/previous_releases/$Version/newrelic-netcore20-agent-win-$Version-scriptable-installer.zip";
    $DotNetFile = "$PSScriptRoot\NewRelicDotNet-$Version.zip";
    $CoreNetFile = "$PSScriptRoot\NewReliCore-$Version.zip";
    $DotNetFolder = "$PSScriptRoot\NewRelicDotNet";
    $CoreFolder = "$PSScriptRoot\NewRelicCore";

    ResetNewRelicEnvironmentVariables;

    (New-Object System.Net.WebClient).DownloadFile($DotNetUrl, $DotNetFile);
    (New-Object System.Net.WebClient).DownloadFile($CoreUrl, $CoreNetFile);

    Expand-Archive -Force $DotNetFile -DestinationPath $DotNetFolder;
    Expand-Archive -Force $CoreNetFile -DestinationPath $CoreFolder;

    Set-Location -Path $DotNetFolder -PassThru;
    $OutPut = & "$DotNetFolder\install.cmd" -LicenseKey $LicenseKey -NoIISReset -InstrumentAll -ForceLicenseKey *>&1 | Out-String;;
    # RunProcess -Command "$DotNetFolder\install.cmd" -Arguments "-LicenseKey $LicenseKey -NoIISReset -InstrumentAll -ForceLicenseKey" -Logger "NewRelicDotNetInstall" -Description "Installing NewRelic .Net Agent $Version";    
    Log -Message "Installed NewRelic .Net Agent $Version`n$OutPut" -Level "INFO" -Logger "NewRelicDotNetInstall";

    Set-Location -Path $CoreFolder -PassThru
    $OutPut = & "$CoreFolder\installAgent.ps1" -destination "$Env:Programfiles\New Relic\.NetCore Agent" -installType global -licenseKey $LicenseKey -Force *>&1 | Out-String;
    Log -Message "Installed NewRelic .Net Core Agent $Version`n$OutPut" -Level "INFO" -Logger "NewRelicDotNetCoreInstall";

    Set-Location -Path $CurrentFolder -PassThru;

    # Cleanup
    Remove-Item $DotNetFile;
    Remove-Item $CoreNetFile;
    Remove-Item –path $DotNetFolder –recurse
    Remove-Item –path $CoreFolder –recurse
}

function ResetNewRelicEnvironmentVariables
{
	[Environment]::SetEnvironmentVariable("NEWRELIC_INSTALL_PATH", "C:\Program Files\New Relic\.NET Agent", "Machine");
    [Environment]::SetEnvironmentVariable("NEW_RELIC_LICENSE_KEY", "", "Machine");
    [Environment]::SetEnvironmentVariable("NEW_RELIC_APP_NAME", "", "Machine");
    [Environment]::SetEnvironmentVariable("COR_ENABLE_PROFILING", "1", "Machine");
    [Environment]::SetEnvironmentVariable("COR_PROFILER", "{71DA0A04-7777-4EC6-9643-7D28B46A8A41}", "Machine");
    [Environment]::SetEnvironmentVariable("COR_PROFILER_PATH", "", "Machine");
    [Environment]::SetEnvironmentVariable("NEWRELIC_HOME", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_ENABLE_PROFILING", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_PROFILER", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_PROFILER_PATH", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_NEWRELIC_HOME", "", "Machine");
}

function RunProcess
{
    Param ([string] $Command,
    [string] $Arguments,
    [string] $Logger,
    [string] $Description)  
    
    $process = [System.Diagnostics.Process]::new();

     try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($Command, $Arguments);
        $process.StartInfo.RedirectStandardOutput = $true;
        $process.StartInfo.RedirectStandardError = $true;
        $process.StartInfo.UseShellExecute = $false;
        $process.StartInfo.CreateNoWindow = $false;
		$process.StartInfo.Verb = "runas";
        $null = $process.Start();
        $process.WaitForExit(1000 * 60 * 3);
        $stdOut = $process.StandardOutput.ReadToEnd();
        $stdErr = $process.StandardError.ReadToEnd();

        if ( $process.ExitCode -eq 0 ) {            
            Log -Message "Success: $Description`r`n$stdOut" -Level "INFO" -Logger $Logger
        } else {
            Log -Message "Error: $Descriptionr`n$stdErr`r`n$stdOut" -Level "ERROR" -Logger $Logger
        };
    } finally {
        $process.Dispose();
    };
}

function Send-UdpDatagram
{
      Param ([string] $EndPoint, 
      [int] $Port, 
      [string] $Message)

      $IP = [System.Net.Dns]::GetHostAddresses($EndPoint);
      $Address = [System.Net.IPAddress]::Parse($IP);
      $EndPoints = New-Object System.Net.IPEndPoint($Address, $Port);
      $Socket = New-Object System.Net.Sockets.UDPClient;
      $EncodedText = [system.Text.Encoding]::UTF8.GetBytes($Message);
      $SendMessage = $Socket.Send($EncodedText, $EncodedText.Length, $EndPoints);
      $Socket.Close();
} 

function Log
{
    Param ([string] $Message, 
    [string] $Level,
    [string] $Logger) 

    $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss,fff";
    $HostName = $env:computername;
    $FormattedMessage = "$FormattedDate`r`napplication=Komplett.ServiceFabric.ScaleSet-Extension level=$Level logger=Komplett.ServiceFabric.ScaleSet-Extension.$Logger hostname=$HostName projectowner=Green`r`n$Message`r`n";
    Write-Output $FormattedMessage;
    Send-UdpDatagram -EndPoint $LoggEndPoint -Port 666 -Message $FormattedMessage;
}

Setup;