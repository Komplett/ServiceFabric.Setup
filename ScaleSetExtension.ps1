[CmdletBinding()]
Param (
	$LoggEndPoint,
	$NewRelicKey
)

function Setup
{
	PrepareDisks
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

function PrepareDisks {
	$disks = Get-Disk | Where partitionstyle -eq 'raw' | sort number

	$letters = 70..89 | ForEach-Object { [char]$_ }
	$count = 0
	$label = "datadisk"

	foreach ($disk in $disks) {
		$driveLetter = $letters[$count].ToString()
		$disk | 
		Initialize-Disk -PartitionStyle MBR -PassThru |
		New-Partition -UseMaximumSize -DriveLetter $driveLetter |
		Format-Volume -FileSystem NTFS -NewFileSystemLabel $label.$count -Confirm:$false -Force
		$count++
	}
}

function Send-UdpDatagram
{
      Param ([string] $EndPoint, 
      [int] $Port, 
      [string] $Message)

      $IP = [System.Net.Dns]::GetHostAddresses($EndPoint) 
      $Address = [System.Net.IPAddress]::Parse($IP) 
      $EndPoints = New-Object System.Net.IPEndPoint($Address, $Port) 
      $Socket = New-Object System.Net.Sockets.UDPClient 
      $EncodedText = [system.Text.Encoding]::UTF8.GetBytes($Message) 
      $SendMessage = $Socket.Send($EncodedText, $EncodedText.Length, $EndPoints) 
      $Socket.Close() 
} 

function Log
{
    Param ([string] $Message, 
    [string] $Level,
    [string] $Logger) 

    $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss,fff"
    $HostName = $env:computername
    $FormattedMessage = "$FormattedDate`r`napplication=Komplett.ServiceFabric.ScaleSet-Extension level=$Level logger=Komplett.ServiceFabric.ScaleSet-Extension.$Logger hostname=$HostName projectowner=Green`r`n$Message`r`n"
    Write-Output $FormattedMessage
    Send-UdpDatagram -EndPoint $LoggEndPoint -Port 666 -Message $FormattedMessage
}

Setup