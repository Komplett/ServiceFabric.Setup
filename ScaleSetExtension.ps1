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

$global:errors = 0;
$global:logFile = "log.txt";

function Setup
{
	CleanLogfile;
	Start-Transcript -path $global:logFile;
    Write-Event "Setup starting";
	
    PrepareDisks;
    SetTimeZone;
    SetupNewRelic -Version "8.6.45.0" -LicenseKey $NewRelicKey;
	SetupNewRelicCore -Version "8.6.45.0" -LicenseKey $NewRelicKey;
	
	Write-Event "Setup Done";

	Stop-Transcript
	
	LogResults;
}

function CleanLogfile
{
	if (![System.IO.File]::Exists($global:logFile))
	{
		Remove-Item -path $global:logFile;
		Start-Sleep -s 1;
	}
}

function LogResults
{
	$level = "INFO";
	if($global:errors -gt 0)
	{
		$level = "ERROR";
	}
	
	$logData = Get-Content -Path $global:logFile -encoding UTF8 -Raw;
	
    Log -Message $logData -Level $level -Logger "ScaleSet-Extension";
}

function Write-Event
{
	Param ([string] $message)
	Write-Output "";
	Write-Output "------------------------------------------------------------------------";
	Write-Output "$message";
	Write-Output "------------------------------------------------------------------------";
	Write-Output "";
	
}

function SetTimeZone
{
    $timeZone = "W. Europe Standard Time";
    $cmdOutPut = Set-TimeZone $timeZone *>&1 | Out-String;
    Write-Event "Setting timezone to $timeZone`r`n$cmdOutput";
}

function PrepareDisks {
	Write-Event "Preparing disk if needed.";
	
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
	
	Write-Event "Installing New Relic Agent";
	
	$newRelicAgent = "$env:Programfiles\New Relic\.Net Agent\NewRelic.Agent.Core.dll";
	
	if (![System.IO.File]::Exists($newRelicAgent)) {
		Write-Output "New Relic Agent missing, installing.";
		InstallNewRelic -Version $Version -LicenseKey $LicenseKey;
	}
	else {
        Write-Output "New Relic Agent already installed, skipping.";
    }
}

function SetupNewRelicCore
{
    Param ([string] $Version,
    [string] $LicenseKey)
	
	Write-Event "Installing New Relic Core Agent";
	
	$newRelicCoreAgent = "$env:Programfiles\New Relic\.NetCore Agent\NewRelic.Agent.Core.dll";
	
	if (![System.IO.File]::Exists($newRelicCoreAgent)) {
		Write-Output "New Relic Core Agent missing, installing.";
		InstallNewRelicCore -Version $Version -LicenseKey $LicenseKey;
	}
	else {
        Write-Output "New Relic Core Agent already installed, skipping.";
    }
}

function InstallNewRelic
{
    Param ([string] $Version,
    [string] $LicenseKey)	
	
    $CurrentFolder = $PSScriptRoot;
    $DotNetUrl = "https://download.newrelic.com/dot_net_agent/previous_releases/$Version/newrelic-agent-win-$Version-scriptable-installer.zip";
    $DotNetFile = "$PSScriptRoot\NewRelicDotNet-$Version.zip";
    $DotNetFolder = "$PSScriptRoot\NewRelicDotNet";

    ResetNewRelicEnvironmentVariables;

    (New-Object System.Net.WebClient).DownloadFile($DotNetUrl, $DotNetFile);

    Expand-Archive -Force $DotNetFile -DestinationPath $DotNetFolder;

    Set-Location -Path $DotNetFolder -PassThru;
    $OutPut = & "$DotNetFolder\install.cmd" -LicenseKey $LicenseKey -NoIISReset -InstrumentAll -ForceLicenseKey *>&1 | Out-String;;
    Write-Output "Installed NewRelic .Net Agent $Version`n$OutPut";

    Set-Location -Path $CurrentFolder -PassThru;
    # Cleanup
    Remove-Item $DotNetFile;
    Remove-Item –path $DotNetFolder –recurse
}

function InstallNewRelicCore
{
    Param ([string] $Version,
    [string] $LicenseKey)	
	
    $CurrentFolder = $PSScriptRoot;
    $CoreUrl = "https://download.newrelic.com/dot_net_agent/previous_releases/$Version/newrelic-netcore20-agent-win-$Version-scriptable-installer.zip";
    $CoreNetFile = "$PSScriptRoot\NewReliCore-$Version.zip";
    $CoreFolder = "$PSScriptRoot\NewRelicCore";

    ResetNewRelicCoreEnvironmentVariables;

    (New-Object System.Net.WebClient).DownloadFile($CoreUrl, $CoreNetFile);

    Expand-Archive -Force $CoreNetFile -DestinationPath $CoreFolder;

    Set-Location -Path $CoreFolder -PassThru
    $OutPut = & "$CoreFolder\installAgent.ps1" -destination "$Env:Programfiles\New Relic\.NetCore Agent" -installType global -licenseKey $LicenseKey -Force *>&1 | Out-String;
    Write-Output "Installed NewRelic .Net Core Agent $Version`n$OutPut";

    Set-Location -Path $CurrentFolder -PassThru;

    # Cleanup
    Remove-Item $CoreNetFile;
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
}

function ResetNewRelicCoreEnvironmentVariables
{
    [Environment]::SetEnvironmentVariable("CORECLR_ENABLE_PROFILING", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_PROFILER", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_PROFILER_PATH", "", "Machine");
    [Environment]::SetEnvironmentVariable("CORECLR_NEWRELIC_HOME", "", "Machine");
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
	$messageBase = "$FormattedDate`r`napplication=Komplett.ServiceFabric.ScaleSet-Extension level=$Level logger=Komplett.ServiceFabric.ScaleSet-Extension.$Logger hostname=$HostName projectowner=Green`r`n";
    $FormattedMessage = $messageBase + $Message;
    Send-UdpDatagram -EndPoint $LoggEndPoint -Port 666 -Message $FormattedMessage;
}

Setup;
