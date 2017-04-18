Overview

Allows Linux systems to automatically update their own DNS information against Windows/AD DNS Servers when secure updates
are turned on.  It does not require that the Linux server be joined to an AD domain or use any form of Samba at all.


Prerequisites

- API User Account
    This AD account (automation.dnsclient) is used by the client script to send 
    commands to the API.  The password for this account will be stored in plain 
    text on the client systems, so it should not have ANY inherent permissions 
    beyond the ability to authenticate with the IIS server and execute the API 
    scripts, and this account should not be used for any other purpose.
    
- DNS Administration Account
    This AD account (automation.dns) is used by the API to perform DNS updates.
    Microsoft has gone back and forth on best practice for DNS update abilities.
    The simplest way to set this user up is to give it domain admin privileges.
    Trying to use a non-domain-admin account for this will be difficult and is 
    beyond the scope of this work.
    
- Windows Server running IIS and PHP
    This server does not have to be dedicated to this function - any server 
    running IIS and joined to the same domain as the DNS servers should work.
    
- Optional DB to track updates
    The c:\inetpub\wwwroot\dnsapi\v1\index_tracked.php contains logic that will
    save the output of every action to a tracking DB.  It was designed for use
    with Azure SQL, but can be adapted to any DB PHP has a connector for.
    
Setting Up IIS
  This document assumes you are familiar with the basics of setting up IIS for
  SSL and installing PHP.
  
  Create the AD service accounts for "automation.dns" and "automation.dnsclient".
  For simplicity, make automation.dns an AD Domain Admin account, make sure 
  automation.dnsclient has the absolute minmum access that will still allow it to
  authenticate to AD with a password.
  
  Copy the contents of "windows_server" to the root of the IIS server.  
  
  You can make this its own website or a use the default website. Either way the
  website authentication needs to have "Basic Authentication" Enabled.
  
  Make sure the API account (automation.dnsclient) has rights to read and 
  execute the whole "dnsapi" directory.
  
  If you used a path other than 'C:\inetpub\wwwroot\dnsapi\v1\' you'll need to 
  edit the 'create_crypted_password_file.ps1' script to the line beginning with 
  "Start-Process" to contain the new correct path to the ps1 script.
  
  Run the 'create_crypted_password_file.ps1' powershell script.  You will first 
  be prompted for the automation.dnsclient password, then for the automation.dns password.
  
  
Setting up the Linux Client

  Copy the scripts in "linux_client" to the relative paths on the client you wish to update.

/etc/init.d/dnscheck[edit]
  This script is a Sys-V init script that will run each time a Linux system starts 
  up and is essentially a wrapper for
      /opt/sa/scripts/check_my_dns.sh.
      
To verify that it is correctly configured issue the command:
  chkconfig --list dnscheck
  
Example Correct Output:
  # chkconfig --list dnscheck
  dnscheck        0:off   1:off   2:on    3:on    4:on    5:on    6:off

If the command comes back empty, or does not show the dnscheck script being "on"
for runlevels 3 and 5, then enable it with this command:
  chkconfig dnscheck on
  
/opt/sa/scripts/check_my_dns.sh
  This script checks to see if a DNS update is necessary. It does this by 
  determining the FQDN for the server.  If a domain name is not set, it will default 
  to acmeplaza.com for deciding FQDN.  If DNS does not resolve the FQDN to an IP 
  address, or resolves to an IP address which does not match the current primary IP
  address of the system, the script will trigger /opt/sa/scripts/update_dns.sh to 
  actually update the record.

/opt/sa/scripts/update_dns.sh
  This script will format and send a DNS update request for the current system
  whenever it is run.  FQDN will be determined by examining the system configuration.
  If a domain name is not found, it will default to acmeplaza.com.  Once the request 
  is formatted, it will be sent via curl to a web-based API on iisserver.acmeplaza.com, 
  using the AD service account "automation.dnsclient".


The DNS API location will be something like: https://iisserver.acmeplaza.com/dnsapi/v1/
  Its function requires the interaction of two scripts, the index.php PHP script that
  resides at the above location and the update_dns.ps1 PowerShell script located in 
  the same directory.

PHP Script
  The PHP script should be located at c:\inetpub\wwwroot\dnsapi\v1\index.php. The 
  function of the script is to pass post commands from the web server to the 
  PowerShell script as arguments.

PowerShell Script
  The PowerShell script should be located at c:\inetpub\wwwroot\dnsapi\v1\update_dns.ps1 
  and is responsible for performing the actual DNS update activity.

The following security precautions have been incorporated into the script:
  -The service account that starts the script (automation.dnsclient) has no 
    direct authority to update DNS
  -After the update request is validated, user context is switched to "automation.dns" 
    to perform the specific updates
  -Clients may not update IP addresses other than their own
  -Clients may not update hostnames which do not match the ACME naming standard
    for Linux
  -No updates may be made to top level domains (so the record for "acmeplaza.com"
    cannot be updated)
  -A blacklist of specifically disallowed updates is consulted
  -A dynamic blacklist of all same-as-domain servers (usually DC's) is generated 
    and checked.
  -The following logic is used when processing a validated DNS update request: 
      If a host record (A) exists with the name in the request, this record is deleted. 
      If a PTR record exists with the IP in the request, this record is deleted.
      If the hostname corresponding to the deleted PTR also matches an existing 
        A record, that A record is deleted as well
      Create the new A record 
      Create the new PTR record


