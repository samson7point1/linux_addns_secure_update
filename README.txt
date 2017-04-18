Overview[edit]

Linux systems will automatically update their own DNS information when deployed and at startup.
Because ACME uses Active Directory Integrated DNS, the process by which this happens is not straightforward.
This page describes the process and its dependencies.

Scripts on the Client (linux_client)

/etc/init.d/dnscheck[edit]
This script is a Sys-V init script that will run each time a Linux system starts up and is essentially a wrapper for /opt/sa/scripts/check_my_dns.sh.
To verify that it is correctly configured issue the command:
<script>chkconfig --list dnscheck</script>
Example Correct Output:
# chkconfig --list dnscheck
dnscheck        0:off   1:off   2:on    3:on    4:on    5:on    6:off

If the command comes back empty, or does not show the dnscheck script being "on" for runlevels 3 and 5, then enable it with this command:
chkconfig dnscheck on
/opt/sa/scripts/check_my_dns.sh[edit]
This script checks to see if a DNS update is necessary. It does this by determining the FQDN for the server.
If a domain name is not set, it will default to acmeplaza.com for deciding FQDN.
If DNS does not resolve the FQDN to an IP address, or resolves to an IP address which does not match the current primary IP address of the system, the script will trigger /opt/sa/scripts/update_dns.sh to actually update the record.

/opt/sa/scripts/update_dns.sh[edit]
This script will format and send a DNS update request for the current system whenever it is run.
FQDN will be determined by examining the system configuration. If a domain name is not found, it will default to acmeplaza.com.
Once the request is formatted, it will be sent via curl to a web-based API on iisserver.acmeplaza.com, using the AD service account "automation.dnsclient".
External Scripts (Web API)[edit]

The DNS API location is: https://iisserver.acmeplaza.com/dnsapi/v1/
Its function requires the interaction of two scripts, the index.php PHP script that resides at the above location and the update_dns.ps1 PowerShell script located in the same directory.

PHP Script
The PHP script should be located at c:\inetpub\wwwroot\dnsapi\v1\index.php. The function of the script is to pass post commands from the web server to the PowerShell script as arguments.

PowerShell Script
The PowerShell script should be located at c:\inetpub\wwwroot\dnsapi\v1\update_dns.ps1 and is responsible for performing the actual DNS update activity.

The following security precautions have been incorporated into the script:
The service account that starts the script (automation.dnsclient) has no direct authority to update DNS
After the update request is validated, user context is switched to "automation.dns" to perform the specific updates
Clients may not update IP addresses other than their own
Clients may not update hostnames which do not match the ACME naming standard for Linux
No updates may be made to top level domains (so the record for "acmeplaza.com" cannot be updated)
A blacklist of specifically disallowed updates is consulted
A dynamic blacklist of all same-as-domain servers is generated and checked.
The following logic is used when processing a validated DNS update request: If a host record (A) exists with the name in the request, this record is deleted. If a PTR record exists with the IP in the request, this record is deleted.
If the hostname corresponding to the deleted PTR also matches an existing A record, that A record is deleted as well
Create the new A record Create the new PTR record

Troubleshooting[edit]

Every attempt made against the API is logged to a DB and viewable from here: https://iisserver.acmeplaza.com/browse_db/get_table.php?db=DCOAutomation&table=ps1api
