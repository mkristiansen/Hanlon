
#http://www.ingmarverheij.com/read-dhcp-options-received-by-the-client/

$HanlonDhcpOptionServer = 224;
$HanlonDhcpOptionPort = 225;
$HanlonDhcpOptionBaseuri = 226;
$HanlonShareName = "Hanlon";

$DebugPreference = "Continue";



Function Convert-SmbiosUuid {

Param (
	[Parameter(Mandatory=$True)]
	[String]
	$rawUUID
)

# Create an array of each half (hyphen delimiter)
$octets = $rawUUID.Split("-")
# Create an array of each two-charactere byte (space delimiter)
$bytes = $octets[0].Split(" ") + $octets[1].Split(" ")
# Build the final string, piecing together byte by byte
$prettyUUID = $bytes[0] + $bytes[1] + $bytes[2] + $bytes[3] + "-" + $bytes[4] + $bytes[5] + "-" + $bytes[6] + $bytes[7] + "-" + $bytes[8] + $bytes[9] + "-" + $bytes[10] + $bytes[11] + $bytes[12] + $bytes[13] + $bytes[14] + $bytes[15]
Return $prettyUUID

}

#When using VirtualBox and Fusion the UUID in the first three sections are "byte flipped".
#Converted the function in the comments http://intermediaware.com/blog/hack-of-the-day-byte-flipping
#To use for flipping the bits.

Function Flip-FourBytes {
Param (
    [Parameter(Mandatory=$True)]
    [uint64]
    $value)

    return (($value -band 0x000000FF) -shl 24) -bor (($value -band 0x0000FF00) -shl 8) -bor (($value -band 0x00FF0000) -shr 8) -bor (($value -band 0xFF000000) -shr 24)
}

Function Flip-TwoBytes {
Param (
    [Parameter(Mandatory=$True)]
    [int]
    $value)

    return (($value -band 0x000000FF) -shl 8) -bor (($value -band 0x0000FF00) -shr 8)
}


Function Get-HanlonDhcpOptionValue {
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[System.Array]$DhcpInterfaceOptions,
		[Parameter(Mandatory=$true)]
		[System.Int16]$Location
	)
	begin {
		$vendorLocation = $Location + 12;
		$lengthLocation = $Location + 8;
		$dataLocation = $Location + 20;
		$result = @();
	}
	process {
		try {
			if( $DhcpInterfaceOptions[$vendorLocation] -eq 1 ) {
				Write-Debug "Found Vendor Option";
				if( ($length = $DhcpInterfaceOptions[$lengthLocation]) -gt 0 ) {
					Write-Debug "Found Length: $length";
					$start = $Location + 20;
					$end = $dataLocation + $length;

					for( $newpos = $dataLocation; $newpos -lt $end; $newpos++ ) {
						$result += $DhcpInterfaceOptions[$newpos];
					}
				}
				else {
					throw "Length of Option Data is Zero, review DhcpInterfaceOptions";
				}

			} else {
				throw "Vendor Location Is Not 1";
			}
		}
		catch {
			write-host "Exception $($_.Exception.GetType().FullName), Message: $($_.Exception.Message), Line Number: $($_.InvocationInfo.ScriptLineNumber), Offset Inline: $($_.InvocationInfo.OffsetInLine)" -ForegroundColor Red
		}
	}
	end {return $result}
}

Function Get-HanlonServerParameters {
	[CmdletBinding()]
	param()
	begin {
		$HanlonObject = New-Object System.Object;
	}
	process {
		try {
			$networkAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True' AND DHCPEnabled ='True'";
			foreach ( $na in $networkAdapters ) {
				$interfaceRegPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\Tcpip\Parameters\Interfaces\$($na.SettingID)\"
				Write-Debug $interfaceRegPath;
				$dhcpInterfaceOptions = (Get-ItemProperty -Path $interfaceRegPath -Name DhcpInterfaceOptions).DhcpInterfaceOptions

				for( $pos = 0; $pos -lt $dhcpInterfaceOptions.Length; $pos++ ) {

					switch ($dhcpInterfaceOptions[$pos]) {
						$HanlonDhcpOptionServer {
							Write-Debug "Found $HanlonDhcpOptionServer";
							$result = Get-HanlonDhcpOptionValue -DhcpInterfaceOptions $dhcpInterfaceOptions -Location $pos
							if( $result.Length -eq 4 ) {
								$ipaddress = "{0}.{1}.{2}.{3}" -f $result[0], $result[1], $result[2], $result[3];
								Write-Debug $ipaddress
								$HanlonObject | Add-Member -Name IPAddress -Value $ipaddress -MemberType NoteProperty
							}
							else {
								throw "Result Length Exception";
							}

						}
						$HanlonDhcpOptionPort {
							Write-Debug "Found $HanlonDhcpOptionPort";

							$result = Get-HanlonDhcpOptionValue -DhcpInterfaceOptions $dhcpInterfaceOptions -Location $pos
							if( $result.Length -eq 2 ) {
								$port = (([int]$result[0]) -shl 8) + ([int]$result[1]);
								Write-Debug $port
								$HanlonObject | Add-Member -Name Port -Value $port -MemberType NoteProperty
							}
							else {
								throw "Result Length Exception";
							}

						}
						$HanlonDhcpOptionBaseuri {
							Write-Debug "Found $HanlonDhcpOptionBaseuri";
							$result = Get-HanlonDhcpOptionValue -DhcpInterfaceOptions $dhcpInterfaceOptions -Location $pos
							$baseuri = "";
							foreach ( $res in $result ) {
								$baseuri += ([char]$res);
							}
							$HanlonObject | Add-Member -Name BaseUri -Value $baseuri -MemberType NoteProperty
							Write-Debug "Base Uri: $baseuri";
						}
					}
				}
			}
			#confirm members
			if( ($HanlonObject | Get-Member -Name IPAddress) -eq $null ) {
				throw "Missing Member IPAddress";
			}
			if( ($HanlonObject | Get-Member -Name BaseUri) -eq $null ) {
				throw "Missing Member BaseUri";
			}
			if( ($HanlonObject | Get-Member -Name Port) -eq $null ) {
				throw "Missing Member Port";
			}
		}
		catch {
			write-host "Exception $($_.Exception.GetType().FullName), Message: $($_.Exception.Message), Line Number: $($_.InvocationInfo.ScriptLineNumber), Offset Inline: $($_.InvocationInfo.OffsetInLine)" -ForegroundColor Red
		}

	}
	end {
		return $HanlonObject;
	}
}


Function Invoke-Main {
	[CmdletBinding()]
	param()

	begin {}
	process {
		try {
			$HanlonServerSettings = Get-HanlonServerParameters 

            $ComputerSystemProduct = Get-WmiObject Win32_ComputerSystemProduct

            if( $ComputerSystemProduct.Name -like "*virtual*" ) {
                $uuidArray = $ComputerSystemProduct.UUID.split("-")

                $first = [uint64]("0x"+$uuidArray[0])
                $firstFlip = [Convert]::ToString($(Flip-FourBytes -value $first), 16)
                $second = [int]("0x"+$uuidArray[1])
                $secondFlip =  [Convert]::ToString($(Flip-TwoBytes -value $second), 16)
                $third = [int]("0x"+$uuidArray[2])
                $thirdFlip =  [Convert]::ToString($(Flip-TwoBytes -value $third), 16)

                $SmbiosUuid = $firstFlip + "-" + $secondFlip + "-" + $thirdFlip + "-" + $uuidArray[3] + "-" + $uuidArray[4]
            }
            else {
                $SmbiosUuid = $ComputerSystemProduct.UUID
            }

			Write-Debug $SmbiosUuid

            $hanlonBaseUri = "http://$($HanlonServerSettings.IPAddress):$($HanlonServerSettings.port)/$($HanlonServerSettings.baseuri)"

            Write-Debug $hanlonBaseUri
            $queryActiveModel = "$hanlonBaseUri/active_model?hw_id=$SmbiosUuid"

            Write-Debug $queryActiveModel
            $activeModel = Invoke-WebRequest -Uri $queryActiveModel -UseBasicParsing | ConvertFrom-Json

            #$activeModelUuid = Invoke-WebRequest -Uri $activeModel.response."@uri" -UseBasicParsing | ConvertFrom-Json
            $uuid = $activeModel.response."@uuid"

            iex ((new-object net.webclient).DownloadString("$hanlonBaseUri/policy/callback/$uuid/install/file")) 

	    }
		catch {
			write-host "Exception $($_.Exception.GetType().FullName), Message: $($_.Exception.Message), Line Number: $($_.InvocationInfo.ScriptLineNumber), Offset Inline: $($_.InvocationInfo.OffsetInLine)" -ForegroundColor Red
		}
	}
	end {}

}

Invoke-Main
