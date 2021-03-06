##############################################################################
#
#   SCOM2012AlertOwnerReport.ps1
#
#   Author: Natascia Heil
#
#   Version: 1.1
#
#	This script checks if SCOM alerts have an owner entry which contains "@". 
#   Then it sends an email to each owner with a table of the open alerts.
#   The script is intended to run daily on a management server through a scheduled task.
#
#	Requirements: Quest AD Module http://www.quest.com/powershell/activeroles-server.aspx
#
#   Used some parts of the SCOM2012Health-Check.ps1 from Jason Rydstrand:
#   http://blogs.technet.com/b/jasonrydstrand/archive/2013/03/27/daily-scom-health-check-with-powershell.aspx
#
#   Please change the values of the following variables:
#   Domains to search
#   For Mailing: SMTPServer, SMTPPort, From, To
#   
##############################################################################

#Importing the SCOM PowerShell module
Import-module OperationsManager
#Connect to localhost when running on the management server
$connect = New-SCOMManagementGroupConnection –ComputerName localhost

# Or enable the two lines below and of course enter the FQDN of the management server in the first line.
#$MS = "enter.fqdn.name.here"
#$connect = New-SCOMManagementGroupConnection –ComputerName $MS

# Retrieve open critical/warning alerts with owners
$alerts=get-scomalert | where{$_.resolutionstate -ne 255 -and $_.severity -ne 0 -and $_.owner -like '*@*'}

if ($alerts -is [Object])
{
$owners= $alerts | group-object owner
$resstate= get-scomalertresolutionstate

foreach ($owner in $owners)
{
$ownedalerts=$alerts| where {$_.owner -eq $owner.name}

# Create header for HTML Report
$Head = "<style>"
$Head +="BODY{background-color:white;font-family:Verdana,sans-serif; font-size: x-small;}"
$Head +="TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; width: 100%;}"
$Head +="TH{border-width: 1px;padding: 0px;border-style: solid;border-color: black;background-color:grey;color:black;padding: 5px; font-weight: bold;text-align:left;}"
$Head +="TD{border-width: 1px;padding: 0px;border-style: solid;border-color: black;background-color:#F0F0F0; padding: 2px;}"
$Head +="</style>"

$ReportOutput = "To enable HTML view, click on `"This message was converted to plain text.`" and select `"Display as HTML`""
$ReportOutput += "<p><H2>SCOM alerts assigned to owner: "+ $owner.name +"</H2></p>"

$AgentTable = New-Object System.Data.DataTable "$AvailableTable"
$AgentTable.Columns.Add((New-Object System.Data.DataColumn CreationDate,([string])))
$AgentTable.Columns.Add((New-Object System.Data.DataColumn Severity,([string])))
$AgentTable.Columns.Add((New-Object System.Data.DataColumn Computername,([string])))
$AgentTable.Columns.Add((New-Object System.Data.DataColumn MonitoringObjectName,([string])))
$AgentTable.Columns.Add((New-Object System.Data.DataColumn Name,([string])))
$AgentTable.Columns.Add((New-Object System.Data.DataColumn Description,([string])))
$AgentTable.Columns.Add((New-Object System.Data.DataColumn ResolutionState,([string])))

foreach ($ownedalert in $ownedalerts)
{
$NewRow = $AgentTable.NewRow()
$NewRow.CreationDate = $ownedalert.TimeRaised
$NewRow.Severity = $ownedalert.Severity
$NewRow.Computername = $ownedalert.Netbioscomputername
$NewRow.MonitoringObjectName = $ownedalert.Monitoringobjectfullname
$NewRow.Name = $ownedalert.Name
$NewRow.Description = $ownedalert.Description
$NewRow.ResolutionState = ($resstate | where {$_.ResolutionState -eq $ownedalert.ResolutionState}).Name
$AgentTable.Rows.Add($NewRow)
}
$ReportOutput += $AgentTable  |select * -ExcludeProperty RowError, RowState, HasErrors, Name, Table, ItemArray | ConvertTo-HTML

$Body = ConvertTo-HTML -head $Head -body "$ReportOutput"

#$file = 'C:\Temp\'+$owner.name+'.html'
#$Body | Out-File $file

# get email address
add-PSSnapin -name 'Quest.ActiveRoles.ADManagement' -ErrorAction SilentlyContinue
$UPN=$owner.name
$foundmail=$false

# try DomainAFQDN - change domain name here
Connect-QADService -Service DomainAFQDN
$mail=get-qaduser $UPN |select mail
 
if ($mail -is [object])
{
$mail
$foundmail=$true
}
else
# try DomainBFQDN - change domain name here
{
Connect-QADService -Service DomainBFQDN
$mail=get-qaduser $UPN |select mail
if ($mail -is [object])
{
$mail
$foundmail=$true
}

# Setup and send output as email message - change SMTPServer, SMTPPort and From address here
$SMTPServer =  "SMTPServer address"
$SMTPPort = "25"
$SmtpClient = New-Object system.net.mail.smtpClient($SMTPServer, $SMTPPort);
$MailMessage = New-Object system.net.mail.mailmessage
$mailmessage.Subject = "Information: SCOM Daily Alert Report"
$mailmessage.from = "From address"

if ($foundmail)
{
$Body = ConvertTo-HTML -head $Head -body "$ReportOutput"
$mailmessage.To.add($mail.mail)
$MailMessage.IsBodyHtml = $true
$mailmessage.Body = $Body
$smtpclient.Send($mailmessage)
}
else
{
# Setup and send error email message - change To address here
$body="Email Address not found for User: " +$owner.name
# if you want to notify your SCOM admins
$mailmessage.To.add("To Address")
$mailmessage.Body = $body
$smtpclient.Send($mailmessage)
}
}
}