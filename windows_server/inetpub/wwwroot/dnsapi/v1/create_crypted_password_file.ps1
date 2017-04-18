# In order for secure DNS to work as designed, the API must be invoked by an API user 
# because the API user's password needs to be stored in plain-text on the clients, the
# API users rights need to be limited to executing the API
# The API will perform DNS updates as a DNS Admin user account which must have rights
# to update DNS
#
# The purpose of this script is to generate an encrypted password file FOR the DNS Admin, but the file must be created BY the API user - otherwise the API user will be unable to decrypt it.


$apiusername="automation.dnsclient"
$dnsadminusername = "automation.dns"
$addomain = "ACME"
$runasapi = $addomain + "\" + $apiusername
$runasdnsadmin = $addomain + "\" + $dnsadminusername
$runaspassfile = $dnsadminusername + ".crypted"

# Get the name of the user currently running this script
$currentuser = whoami


# If this is not being invoked as the API user, we'll need to open a new shell as that user to create the password file 
if (( $runasapi.toupper() ).compareto( $currentuser.toupper() )) {
   write-host "You are running this script as '$currentuser'. In order to generate a usable file this script must be run as '$apiuser'"
   $password = read-host "Enter the AD password for the user '$runasapi': " -AsSecureString
   $runasapicred = New-Object System.Management.Automation.PSCredential -ArgumentList $runasapi, $password
   
   # Because of a limitation of powershell, the path to this script must be a literal string - it cannot be passed as a variable
   # This line will need to be edited if the script is placed in a different directory than what is shown below.
   Start-Process powershell -ArgumentList '-executionpolicy', 'bypass', '-file', 'C:\inetpub\wwwroot\dnsapi\v1\create_crypted_password_file.ps1' -Credential $runasapicred -redirectstandarderror c:\temp\pserrors.txt
   

   exit

}else {

   # When this script is run as the API user, prompt for the DNS Admin User's Password
   $password = read-host "Enter the AD password for the user '$runasdnsadmin': " -AsSecureString
   $secureStringText = $password | ConvertFrom-SecureString 
   Set-Content $runaspassfile $secureStringText
   write-host "$runaspassfile written"

}




