param(
		[Parameter(mandatory=$true)]
		[string]$sourceIP,
		[Parameter(mandatory=$true)]
		[string]$domain,
		[Parameter(mandatory=$true)]
		[string]$recType,
		[Parameter(mandatory=$true)]
		[string]$recName,
		[Parameter(mandatory=$true)]
		[string]$recValue,
		[switch]$debug2
		);
try
{
	$RESULTS=@{};
    # The expectation is that this API is going to be invoked by an API user account (automation.dnsclient) via Windows/Kerberos auth through IIS.
    # the crypted password file with the DNS admin's password needs to be generated by this API user because the encryption is tied to the user
    # account that encrypts the file.
    $runasuser = "ACME\automation.dns"
    $runaspassfile = "automation.dns.crypted"
    $runascred = new-object -typename system.management.automation.pscredential -argumentlist $runasuser, (get-content $runaspassfile | convertto-securestring)
    $primaryDNSIP = "10.25.131.134"


    switch ($recType) {
        "A" {
            # This should be the default record update type

            $validated = $true

            # Safety check 1 - verify that the sourceIP and recValue match - otherwise the actor is trying to update someone else's IP
            if ($sourceIP -ne $recValue) {
                $errorlist += "Invalid Request - a server is only allowed to update its own DNS information. Your IP: [$sourceIP] the record IP [$recValue]"
                $validated = $false
            }

            # Safety check 2 - verify the record name is valid
            
            # Sanitize record name - remove domain name if it was accidentally included
            $recName = $recName.split(".") | select -first 1

            # This could be done more elegantly with regex but whatever
            # Extract characters at known positions
            $fourthc = $recName.toLower().Substring(3,1)
            $eighthc = $recName.toLower().Substring(7,1)
            $ninthc = $recName.toLower().Substring(8,1)

            # Check for "l" in the correct position to indicate it's a Linux host
            if ( $eighthc -ne "l" ) {

                # Additional check to see if it's using the legacy SAP naming standard
                if (!(($fourthc -eq "-") -and ($ninthc -eq "l"))) {
                    $errorlist += "Invalid Requiest - the hostname provided does not meet naming standard for Linux servers"
                    $validated = $false
                }
            }

            # Safety check 3 - verify the record name is not in the blacklist
            # begin with a literal blacklist
            $blacklisted = @("knerhsilp001")
            # add all of the domain controllers for acme.com to the blacklist
            $blacklisted += $(foreach ($ip in $(resolve-dnsname -type A acme.com -server $primaryDNSIP ).ipaddress) { resolve-dnsname -type ptr $ip -erroraction Ignore }).namehost.tolower().replace(".${domain}","")
            

            if ($blacklisted.Contains($recName)) {
                $errorlist += "Invalid Request - the hostname [$recName] is blacklisted from automatic updates"
                $validated = $false
            }

            # Safety check 4 - verify the provided domain is dot-notated.  We won't be updating any top-level host records!
            if ( $domain.split(".").count -lt 2 ) {
                $errorlist += "Invalid domain name [ $domain ] provided by request"
                $validated = $false
            }

            
            if ($validated -eq $true) {
                
                # Get the authoritative DNS server from the SOA record.
                $forwardSOA = ( Resolve-DnsName -type SOA $domain -server $primaryDNSIP ).PrimaryServer

                # Check the SOA for an existing record.
                $existingA = ( resolve-dnsname -type A "$recName.$domain" -server $forwardSOA 2>&1 )

                # Check for and remove any existing A records with the same name
                if ( $existingA.IP4Address ) {

                    # Create a new CimSession connection to the SOA as the privileged service account
                    $CS = new-cimsession -computername $forwardSOA -credential $runascred

                    # Delete the existing record
                    $OUTPUT = Remove-DnsServerResourceRecord -CimSession $CS -ZoneName $domain -ComputerName $forwardSOA -RRType "A" -name "$recName" -Force -ErrorAction Stop

                    # Close the session
                    $CS.Close()


                    # Output should be empty unless there was an error
                    if ($OUTPUT) {
                        $OUTPUT.psobject.properties | Foreach { $RESULTS[$_.Name] = $_.Value }
                        $RESULTS.removedExistingA = $false
                        break
                    } else {
	                    $RESULTS.removedExistingA = $true
                        $RESULTS.removedA = $existingA | select IP4Address,Name,TTL
                    }
            
                } else {
                    $RESULTS.removedExistingA = $false
                }

                ## PTR records are a little more involved but we're going to do basically the same thing

                # Generate the fully qualified PTR record name from the IP
                $FQPtr = ( $recValue -replace '^(\d+)\.(\d+)\.(\d+)\.(\d+)$','$4.$3.$2.$1.in-addr.arpa' )

                # We know we're likely to have lookup failures and they don't matter, so keep them out of the output.
                $ErrorActionPreference = 'SilentlyContinue'

                # Walk the reverse zone hierarchy until we find the actual reverse zone 
                $PtrRange = ( $recValue -replace '^(\d+)\.(\d+)\.(\d+)\.(\d+)$','$3.$2.$1.in-addr.arpa' )
                $revZone = ((resolve-dnsname -type SOA $PtrRange).Name | select-object -first 1)
                if (!$revZone) {
                    $PtrRange = ( $recValue -replace '^(\d+)\.(\d+)\.(\d+)\.(\d+)$','$2.$1.in-addr.arpa' )
                    $revZone = ((resolve-dnsname -type SOA $PtrRange).Name | select-object -first 1)
                    if (!$revZone){
                        # Default to class A (usually 10.in-addr.arpa)
                        $revZone = ( $recValue -replace '^(\d+)\.(\d+)\.(\d+)\.(\d+)$','$1.in-addr.arpa' )
                    }

                }
                # Resume normal error action
                $ErrorActionPreference = 'Continue'

                # Set the unqualified value of the PTR by subtracting the reverse zone name from the FQ record name
                $unqualPtr = ( $FQPtr -replace ".$revZone$","" )

                # Set the SOA for the reverse zone ( it will probably be the same as the forward, but we don't want to assume that )
                $reverseSOA = ( Resolve-DnsName -type SOA $PtrRange ).PrimaryServer

                # Look for an existing PTR
                $existingPtr = ( resolve-dnsname -type PTR $FQPtr -server $reverseSOA 2>&1 )

                # Check for and remove any existing PTR record with the same IP
                if ($existingPtr.NameHost) {

                    # Open a new CIM session to the SOA 
                    $CS = new-cimsession -computername $reverseSOA -credential $runascred

                    # Delete the record
                    $OUTPUT = Remove-DnsServerResourceRecord -CimSession $CS -ZoneName $revZone -ComputerName $reverseSOA -RRType "PTR" -name "$unqualPtr" -Force -ErrorAction Stop
                    
                    # Close the session
                    $CS.Close()

                     # Output should be empty unless there was an error
                    if ($OUTPUT) {
                        $OUTPUT.psobject.properties | Foreach { $RESULTS[$_.Name] = $_.Value }
                        $RESULTS.removedExistingPTR = $false
                        break
                    } else {
	                    $RESULTS.removedExistingPTR = $true
                        $RESULTS.removedPtr = $existingPtr | select NameHost,Name,TTL
                    }

                    ## If we removed an existing PTR, we also want to check for and remove the corresponding A record, IF that A record points to our same IP

                    if ( $existingPtr.NameHost -ne "${recName}.${domain}" ) {
                        # If the existing PTR's "NameHost" doesn't match then the hostname of the client probably changed
                        
                        # Query for an A record matcching the PTR record's "NameHost"
                        $ErrorActionPreference = 'SilentlyContinue'
                        $oldPtrHostRec = ( resolve-dnsname -type A $existingPtr.NameHost -server $primaryDNSIP )
                        $ErrorActionPreference = 'Continue'

                        # If the A record exists...
                        if ( $oldPtrHostRec.ip4address ) {

                            # ...and it matches the IP address of the system requesting the update
                            if ( $oldPtrHostRec.ip4address -eq $recValue ) {
                                # Delete it

                                # Extract the "record name" from "NameHost"
                                $oldPtrHostName = $oldPtrHostRec.Name.Split(".",2) | select -first 1

                                # Extract domain name from "NameHost"
                                $oldPtrHostDom = $oldPtrHostRec.Name.Split(".",2) | select -last 1

                                # Find the SOA for the old domain (don't take anything for granted!)
                                $oldPtrHostSOA = ( Resolve-DnsName -type SOA $oldPtrHostDom -server $primaryDNSIP ).PrimaryServer

                                # Create a new CimSession connection to the SOA as the privileged service account
                                $CS = new-cimsession -computername $oldPtrHostSOA -credential $runascred

                                # Delete the existing record
                                $OUTPUT = Remove-DnsServerResourceRecord -CimSession $CS -ZoneName $oldPtrHostDom -ComputerName $oldPtrHostSOA -RRType "A" -name "$oldPtrHostName" -Force -ErrorAction Stop

                                # Close the session
                                $CS.Close()


                                # Output should be empty unless there was an error
                                if ($OUTPUT) {
                                    $OUTPUT.psobject.properties | Foreach { $RESULTS[$_.Name] = $_.Value }
                                    $RESULTS.removedOrphanedA = $false
                                    break
                                } else {
	                                $RESULTS.removedOrphanedA = $true
                                    $RESULTS.orphanedA = $oldPtrHostRec | select IP4Address,Name,TTL
                                }

                                

                            }
                        }


                    }

                   
                } else {
                    $RESULTS.removedExistingPTR = $false
                }

                

 

                ## Create the new resource record ##

                # Open a new CIM session to the forward SOa
                $CS = new-cimsession -computername $forwardSOA -Credential $runascred

                # Add the new A record
                $OUTPUT = Add-DnsServerResourceRecord -Cimsession $CS -ZoneName "$domain" -ComputerName $forwardSOA -A -Name "$recName" -IPv4Address "$recValue" -ErrorAction Stop

                # Close the session
                $CS.Close()


                $OUTPUT.psobject.properties | Foreach { $RESULTS[$_.Name] = $_.Value }
	            $RESULTS.createdNewA = $true
                $newA = ( resolve-dnsname -type A "$recName.$domain" -server $forwardSOA 2>&1 )
                $RESULTS.newA = $newA | select IP4Address,Name,TTL
                

                # Create the new PTR record
                $CS = new-cimsession -computername $reverseSOA -Credential $runascred
                $OUTPUT = Add-DnsServerResourceRecord -CimSession $CS -ZoneName "$revZone" -ComputerName ( Resolve-DnsName -type SOA $revZone ).PrimaryServer -PTR -name "$unqualPtr" -PtrDomainName "$recName.$domain" -ErrorAction Stop
                $CS.Close()
                $OUTPUT.psobject.properties | Foreach { $RESULTS[$_.Name] = $_.Value }
	            $RESULTS.createdNewPTR = $true
                $newPTR = ( resolve-dnsname -type PTR $FQPtr -server $reverseSOA 2>&1 )
                $RESULTS.newPTR = $existingPtr = $newPTR | select NameHost,Name,TTL
                
                if (($newA.IP4Address -eq "$recValue" ) -and ($newPTR.NameHost -eq "$recName.$domain")) {
                    $RESULTS.success = $true
                } else {
                    $RESULTS.success = $false
                    $RESULTS.error = "One or more new records could not be created."
                }

            } else {
               
               $RESULTS.success = $false
               $RESULTS.error = $errorlist
            }
        }


        default {
            $RESULTS.success = $false
            $RESULTS.error = "Record Type [$recType] is unsupported in this version."
        }

    }

}
catch
{
	foreach ($objName in $_.exception.ErrorData.CimInstanceProperties)
	{
		if ($objName.Name -eq "error_WindowsErrorMessage")
		{
			$RESULTS.error = $objName.Value
			$RESULTS.success = $false
		}
	}
	if ($debug2)
	{
		$RESULTS.debug = $_
	}
}
$RESULTS | convertto-json -depth 5


