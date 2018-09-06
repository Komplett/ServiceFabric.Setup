﻿[CmdletBinding()]
Param (
	$LoggEndPoint,
	$NewRelicKey
)

function Setup
{
	PrepareDisks;
    SetTimeZone;
    InstallCocolatey;
    ChocoInstall -Package "dotnet4.7.2";
    ChocoInstall -Package "dotnetcore-runtime" -Version "2.0.7" -Flags "-m";
    ChocoInstall -Package "dotnetcore-runtime" -Version "2.1.3" -Flags "-m";
    ChocoInstall -Package "newrelic-dotnet" -Params "'license_key=$NewRelicKey'";
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
    
    $process = [System.Diagnostics.Process]::new();

     try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new("$env:ChocolateyInstall\bin\choco.exe", "install -yv $Flags $Package --version=`"$Version`" --params=`"$Params`"");
        $process.StartInfo.RedirectStandardOutput = $true;
        $process.StartInfo.RedirectStandardError = $true;
        $process.StartInfo.UseShellExecute = $false;
        $null = $process.Start();
        $process.WaitForExit();
        $stdOut = $process.StandardOutput.ReadToEnd();
        $stdErr = $process.StandardError.ReadToEnd();

        if ( $process.ExitCode -eq 0 ) {            
            Log -Message "Installed $Package from Chocolatey`r`n$stdOut" -Level "INFO" -Logger "ChocoInstall"
        } else {
            Log -Message "Error trying to install $Package from Chocolatey`r`n$stdErr`r`n$stdOut" -Level "ERROR" -Logger "ChocoInstall"
        };
    } finally {
        $process.Dispose();
    };
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