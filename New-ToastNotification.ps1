﻿#Region Help
<#
.SYNOPSIS
    Create nice Windows 10 toast notifications for the logged on user in Windows 10.

.DESCRIPTION
    Everything is customizeable through config-toast.xml.
    Config-toast.xml can be locally or set to an UNC path with the -Config parameter.
    This way you can quickly modify the configuration without the need to push new files to the computer running the toast.
    Can be used for improving the numbers in Windows Servicing as well as kindly reminding users of pending reboots.
    All actions are logged to a local log file in appdata\roaming\ToastNotification\New-Toastnotificaion.log.

.PARAMETER Config
    Specify the path for the config.xml. If none is specified, the script uses the local config.xml

.NOTES
    Filename: New-ToastNotification.ps1
    Version: 1.8.0
    Author: Martin Bengtsson
    Blog: www.imab.dk
    Twitter: @mwbengtsson

    Version history:

    1.0   -   Script created

    1.1   -   Separated checks for pending reboot in registry/WMI from OS uptime.
              More checks for conflicting options in config.xml.
              The content of the config.xml is now imported with UTF-8 encoding enabling other characters to be used in the text boxes.

    1.2   -   Added option for personal greeting using given name retrieved from Active Directory. If no AD available, the script will use a placeholder.
              Added ToastReboot protocol example, enabling the toast to carry out a potential reboot.

    1.3   -   All text elements in the toast notification is now customizeable through the config.xml
              Expanded the options for finding given name. Now also looking in WMI if no local AD is available. 
              Added Get-WindowsVersion function: Testing for supported Windows version
              Added Test-WindowsPushNotificationsEnabled function: Testing for OS toast blockers
              Added some more detailed logging
              Added contributions from @SuneThomsenDK @ https://www.osdsune.com
                - Date formatting in deadline group
                - Fixed a few script errors
                - More text options

    1.4   -   Added new feature for checking for local active directory password expiration. 
              If the password is about to expire (days configured in config.xml), the toast notification will display reminding the users to change their password

    1.4.1 -   Get-ADPasswordExpiration function modified to not requiring the AD Powershell module. Thank you @ Andrew Wells :-)
              Improved logging for when no toast notifications are displayed
              More commenting
              
    1.4.2 -   Bug fixes to the date formatting of ADPasswordExpiration now correctly supporting different cultures

    1.4.3 -   Some minor corrections to the get-givenname function when retreiving first name from WMI and registry
              Moved the default location for New-ToastNotification.log file to the user's profile
              Added contribution from @kevmjohnston @ https://ccmcache.wordpress.com
                - Added function for retrieving deadline date and time dynamically in WMI with ConfigMgr

    1.5   -   Added new option to run task sequences (PackageID) directly from the toast notification action button. Enable the option <RunPackageID> in the config.xml
              Fixed a few script errors when running the script on a device without ConfigMgr client

    1.6   -   Added new option to run applications (ApplicationID) directly from the toast notification action button. Enable the option <RunApplicationID> in the config.xml
              Created Display-ToastNotification function
                - Displaying the toast notification as been trimmed and merged into its own function
              Created Test-NTsystem function
                - Testing if the script is being run as SYSTEM. This is not supported  
              Converted all Get-WMIObject to Get-CimInstance
                - Get-WMIObject has been deprecated and is replaced with Get-CimInstance
    
    1.7   -   Added multilanguage support. Thank you Matt Benninge @matbe
                - Script and config files now support multiple languages
                - Note that old config xml files needs to be updated to support this
                - Moved text values from option to the text-section for consistency

    1.7.1 -   Added 2 new options (LogoImageName and HeroImageName) to the config file, allowing switching of images more easily and dynamically

    1.8.0 -   Added support for using Windows 10 Toast Notification Script with Endpoint Analytics Proactive Remediation
                - Added support for having config.xml file hosted online
                - Added support for having images used in the script hosted online
    2.0.0 -   Huge changes to how this script handles custom protocols
                - Added Support for Software Updates : Searches for an update (IPU) and will store in variable
                - Added Support for Custom Actions/Protocols within the script under user context removing the need for that to be run under SYSTEM/ADMIN : Only Supports SoftwareUpdate right now
                    <Option Name="Action" Value="ToastRunUpdateID:" />
                - Added Support to dynamically create Custom Action Scripts to support Custom Protocols : Only Supports Software Updates right now
                - Added New XML Types for SoftwareUpdates : 
                    <Option Name="RunUpdateTitle" Enabled="True" Value="Version 1909" />
                    <Option Name="RunUpdateID" Enabled="True" Value="3012973" />
                - Removed Custom Protocols Folder : Future Support for that will be within the script
                - Removed MSI / Zip files

.LINK
    https://www.imab.dk/windows-10-toast-notification-script/
#> 
#EndRegion Help

[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config
)

#Region Helper Functions 
######### FUNCTIONS #########

# Create write log function
function Write-Log() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        # EDIT with your location for the local log file
        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path="$env:APPDATA\ToastNotificationScript\New-ToastNotification.log",
        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info"
    )
    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
		if ((Test-Path $Path)) {
			$LogSize = (Get-Item -Path $Path).Length/1MB
			$MaxLogSize = 5
		}
        # Check for file size of the log. If greater than 5MB, it will create a new one and delete the old.
        if ((Test-Path $Path) -AND $LogSize -gt $MaxLogSize) {
            Write-Error "Log file $Path already exists and file exceeds maximum file size. Deleting the log and starting fresh."
            Remove-Item $Path -Force
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (-NOT(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        else {
            # Nothing to see here yet.
        }
        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

# Create Pending Reboot function for registry
function Test-PendingRebootRegistry() {
    Write-Log -Message "Running Test-PendingRebootRegistry function"
    $CBSRebootKey = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction Ignore
    $WURebootKey = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Ignore
    $FileRebootKey = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Ignore
    if (($CBSRebootKey -ne $null) -OR ($WURebootKey -ne $null) -OR ($FileRebootKey -ne $null)) {
        Write-Log -Message "Check returned TRUE on ANY of the registry checks: Reboot is pending!"
        return $true
    }
    Write-Log -Message "Check returned FALSE on ANY of the registry checks: Reboot is NOT pending!"
    return $false
}
# Create Pending Reboot function for WMI via ConfigMgr client
function Test-PendingRebootWMI() {
    Write-Log -Message "Running Test-PendingRebootWMI function"   
    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
        Write-Log -Message "Computer has ConfigMgr client installed - checking for pending reboots in WMI"
        $Util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $Status = $Util.DetermineIfRebootPending()
        if(($Status -ne $null) -AND $Status.RebootPending) {
            Write-Log -Message "Check returned TRUE on checking WMI for pending reboot: Reboot is pending!"
            return $true
        }
        Write-Log -Message "Check returned FALSE on checking WMI for pending reboot: Reboot is NOT pending!"
        return $false
    }
    else {
        Write-Log -Message "Computer has no ConfigMgr client installed - skipping checking WMI for pending reboots" -Level Warn
        return $false
    }
}
# Create Get Device Uptime function
function Get-DeviceUptime() {
    Write-Log -Message "Running Get-DeviceUptime function"
    $OS = Get-CimInstance Win32_OperatingSystem
    $Uptime = (Get-Date) - ($OS.LastBootUpTime)
    $Uptime.Days
}
# Create Get GivenName function
function Get-GivenName() {
    Write-Log -Message "Running Get-GivenName function"
    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $PrincipalContext = [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Domain, [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain())
        $GivenName = ([System.DirectoryServices.AccountManagement.Principal]::FindByIdentity($PrincipalContext,[System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,[Environment]::UserName)).GivenName
        $PrincipalContext.Dispose()
    }
    catch [System.Exception] {
        Write-Log -Message "$_." -Level Warn
    }
    if ($GivenName) {
        Write-Log -Message "Given name retrieved from Active Directory"
        $GivenName
    }
    elseif (-NOT($GivenName)) {
        Write-Log -Message "Given name not found in AD or no local AD available. Continuing looking for given name elsewhere"
        if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
            Write-Log -Message "Looking for given name in WMI with CCM client"
            $LoggedOnSID = Get-CimInstance -Namespace ROOT\CCM -Class CCM_UserLogonEvents -Filter "LogoffTime=null" | Select -ExpandProperty UserSID
            if ($LoggedOnSID.GetType().IsArray) {
                Write-Log -Message "Multiple SID's found. Skipping"
                $GivenName = ""
                $GivenName
            }
            else {
	            $RegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\SessionData"
	            $DisplayName = (Get-ChildItem -Path $RegKey | Where-Object {$_.GetValue("LoggedOnUserSID") -eq $LoggedOnSID} | Select-Object -First 1).GetValue("LoggedOnDisplayName")
		        if ($DisplayName) {
                    Write-Log -Message "Given name found in WMI with the CCM client"
			        $GivenName = $DisplayName.Split()[0].Trim()
                    $GivenName
		        }
		        else {
			        $GivenName = ""
                    $GivenName
		        }
            }
        }
    }
    elseif (-NOT($GivenName)) {
        # More options for given name here
    }
    else {
        Write-Log -Message "No given name found. Using nothing as placeholder"
        $GivenName = ""
        $GivenName
    }
}
# Create Get-WindowsVersion function
# This is used to determine if the script is running on Windows 10 or not
function Get-WindowsVersion() {
    $OS = Get-CimInstance Win32_OperatingSystem
    if (($OS.Version -like "10.0.*") -AND ($OS.ProductType -eq 1)) {
        Write-Log -Message "Running supported version of Windows. Windows 10 and workstation OS detected"
        $true
    }
    elseif ($OS.Version -notlike "10.0.*") {
        Write-Log -Level Warn -Message "Not running supported version of Windows"
        $false
    }
    else {
        Write-Log -Level Warn -Message "Not running supported version of Windows"
        $false
    }
}
# Create Windows Push Notification function.
# This is testing if toast notifications generally are disabled within Windows 10
function Test-WindowsPushNotificationsEnabled() {
    $ToastEnabledKey = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -ErrorAction Ignore).ToastEnabled
    if ($ToastEnabledKey -eq "1") {
        Write-Log -Message "Toast notifications are enabled in Windows"
        $true
    }
    elseif ($ToastEnabledKey -eq "0") {
        Write-Log -Level Warn -Message "Toast notifications are not enabled in Windows. The script will run, but toasts might not be displayed"
        $false
    }
    else {
        Write-Log -Message "The registry key for determining if toast notifications are enabled does not exist. The script will run, but toasts might not be displayed"
        $false
    }
}
# Create function for testing for local Active Directory password expiration.
# Thank you @ Andrew Wells :-)
function Get-ADPasswordExpiration([string]$fADPasswordExpirationDays) {
    Write-Log -Message "Running Get-ADPasswordExpiration function"
    try {
        Write-Log -Message "Looking up SamAccountName and DomainName in local Active Directory"
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $PrincipalContext = [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Domain,[System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain())
        $SamAccountName = ([System.DirectoryServices.AccountManagement.Principal]::FindByIdentity($PrincipalContext,[System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,[Environment]::UserName)).SamAccountName
        $DomainName = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
        $PrincipalContext.Dispose()
    }
    catch [System.Exception] {
        Write-Log -Message "$_." -Level Warn
    }
    if (($SamAccountName) -AND ($DomainName)) {
        Write-Log -Message "SamAccountName found: $SamAccountName and DomainName found: $DomainName. Continuing looking for AD password expiration date"
        try {
            $Root = [ADSI] "LDAP://$($DomainName)"
            $Searcher = New-Object System.DirectoryServices.DirectorySearcher($Root, "(SamAccountName=$($SamAccountName))")
            $Searcher.PropertiesToLoad.Add("msDS-UserPasswordExpiryTimeComputed") | Out-Null
            $Result = $Searcher.FindOne();
            $ExpiryDate = [DateTime]::FromFileTime([Int64]::Parse((($Result.Properties["msDS-UserPasswordExpiryTimeComputed"])[0]).ToString()))
        }
        catch { 
            Write-Log -Message "Failed to retrieve password expiration date from Active Directory. Script is continuing, but without password expiration date" -Level Warn
            
        }
        if ($ExpiryDate) {
            Write-Log -Message "Password expiration date found. Password is expiring on $ExpiryDate. Calculating time to expiration"
            $LocalCulture = Get-Culture
            $RegionDateFormat = [System.Globalization.CultureInfo]::GetCultureInfo($LocalCulture.LCID).DateTimeFormat.LongDatePattern
            $ExpiryDate = Get-Date $ExpiryDate -f "$RegionDateFormat"
            $Today = Get-Date -f "$RegionDateFormat"
            $DateDiff = New-TimeSpan -Start $Today -End $ExpiryDate
            if ($DateDiff.Days -le $fADPasswordExpirationDays -AND $DateDiff.Days -ge 0) {
                Write-Log -Message "Password is expiring within the set period. Returning True"
                Write-Log -Message "ADPasswordExpirationDays is set to: $fADPasswordExpirationDays"
                # Return status, date and days until expiration
                $true
                $ExpiryDate
                $DateDiff
            }
            else {
                Write-Log -Message "Password is not expiring anytime soon. Returning False"
                Write-Log -Message "ADPasswordExpirationDays is set to: $fADPasswordExpirationDays"
                $false
            }
        }
        elseif (-NOT($ExpiryDate)) {
            Write-Log -Message "No password expiration date found. Returning False" -Level Warn
            $false
        }
    }
    elseif (-NOT($SamAccountName) -OR ($DomainName)) {
        Write-Log -Message "Failed to retrieve SamAccountName or DomainName from local Active Directory. Script is continuing, but password expiration date cannot be retrieved" -Level Warn
        $false
    }
}
# Create function for retrieving deadline directly from WMI based on the PackageID. 
# This works for Task Sequences and regular packages
# Thank you @kevmjohnston :-)
# TODO: Change this to support software updates
function Get-DynamicDeadline() {
    Write-Log -Message "Running Get-DynamicDeadline function. Trying to get deadline details from WMI and ConfigMgr"
    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
        try {
            # Get task sequence program information from WMI. This is the same location used by Software Center
            $PackageID = Get-CimInstance -Namespace root\ccm\clientsdk -Query "SELECT * FROM CCM_Program where PackageID = '$DynDeadlineValue'"
        }
        catch { 
            Write-Log -Message "Failed to get PackageID from WMI" -Level Warn
        }
        if ($PackageID) {
            # Get the deadline based on the package id
            # The Where-Object clause filters out any old/dummy deadline values
            # The Measure-Object clause returns only the earliest deadline if multiple program instances are found. In testing, I've only seen one instance
            # per package ID even if multiple deployments of the same task sequence with different deadlines are targeted, so this is more of a failsafe
            Write-Log -Message "PackageID retrieved. PackageID is: $DynDeadlineValue. Now getting deadline date and time"
            $Deadline = ($PackageID | Where-Object {$_.Deadline -gt (Get-Date).AddDays(-1)} | Measure-Object -Property Deadline -Minimum).Minimum
            if ($Deadline) {
                # Deadline date and time retrieved. I'm formatting the date later on in the actual toast xml
                Write-Log -Message "Deadline date and time successfully retrieved from WMI. Deadline is: $Deadline"
                $Deadline.ToUniversalTime()
            }
            else {
                Write-Log -Message "Failed to get deadline date and time from WMI" -Level Warn
                Write-Log -Message "Please check if there really is a deadline configured" -Level Warn
                Write-Log -Message "The script is continuing, but the toast is displayed without deadline date and time" -Level Warn
            }
        }
        else {
            Write-Log -Message "Appears that the specified package ID: $DynDeadlineValue is not deployed to the device."
            # Nothing to see here yet  
        }
    }
    else {
        Write-Log -Message "ConfigMgr service not found" -Level Warn
    }
}
# Create Write-PackageIDRegistry function
function Write-PackageIDRegistry() {
    Write-Log -Message "Running Write-PackageIDRegistry function"
    $RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
    $RegistryName = "RunPackageID"    
    # Making sure that the registry path being used exists
    if (-NOT(Test-Path -Path $RegistryPath)) {
        try {
            New-Item -Path $RegistryPath -Force
        }
        catch { 
            Write-Log -Message "Error. Could not create ToastNotificationScript registry path" -Level Warn
        }
    }
    # If the PackageID specified in the config.xml is picked up
    if ($RunPackageIDValue) {
        # If the ConfigMgr service exist
        if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
            # Testing if the PackageID specified in the config.xml actually is deployed to the device
            try {
                $TestPackageID = Get-CimInstance -Namespace root\ccm\clientsdk -Query "SELECT * FROM CCM_Program WHERE PackageID = '$RunPackageIDValue'"
            }
            catch { 
                Write-Log -Level Warn -Message "Failed to retrieve $RunPackageIDValue from WMI"
            }
            # If the PackageID is found in WMI with the ConfigMgr client, tattoo that PackageID into registry
            if ($TestPackageID) {
                Write-Log -Message "PackageID: $RunPackageIDValue was found in WMI as deployed to the client"
                Write-Log -Message "Writing the PackageID to registry"
                if ((Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -ne $RunPackageIDValue) {
                    try {
                        New-ItemProperty -Path $RegistryPath -Name $RegistryName -Value $RunPackageIDValue -PropertyType "String" -Force   
                    }
                    catch {
                        Write-Log -Level Warn -Message "Failed to write PackageID: $RunPackageIDValue to registry"
                    }
                }
            }
            else {
                Write-Log -Level Warn -Message "PackageID: $RunPackageIDValue was not found in WMI as deployed to the client. Please check the config.xml or deployment in ConfigMgr"
            }
        }
        else {
            Write-Log -Level Warn -Message "No ConfigMgr service found. This functon requires the ConfigMgr client to be installed"
        }
    }
}
# Create Write-ApplicationIDRegistry function
function Write-ApplicationIDRegistry() {
    Write-Log -Message "Running Write-ApplicationIDRegistry function"
    $RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
    $RegistryName = "RunApplicationID"    
    # Making sure that the registry path being used exists
    if (-NOT(Test-Path -Path $RegistryPath)) {
        try {
            New-Item -Path $RegistryPath -Force
        }
        catch { 
            Write-Log -Level Warn -Message "Error. Could not create ToastNotificationScript registry path"
        }
    }
    # If the ApplicationID specified in the config.xml is picked up
    if ($RunApplicationIDValue) {
        # If the ConfigMgr service exist
        if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
            # Testing if the ApplicationID specified in the config.xml actually is deployed to the device
            try {
                $TestApplicationID = Get-CimInstance -ClassName CCM_Application -Namespace "root\ccm\clientSDK" | Where-Object {$_.Id -eq $RunApplicationIDValue}
            }
            catch { 
                Write-Log -Level Warn -Message "Failed to retrieve $RunApplicationIDValue from WMI"
            }

            # If the ApplicationID is found in WMI with the ConfigMgr client, tattoo that ApplicationID into registry
            if ($TestApplicationID) {
                Write-Log -Message "ApplicationID: $RunApplicationIDValue was found in WMI as deployed to the client"
                Write-Log -Message "Writing the ApplicationID to registry"
                if ((Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -ne $RunApplicationIDValue) {
                    try {
                        New-ItemProperty -Path $RegistryPath -Name $RegistryName -Value $RunApplicationIDValue -PropertyType "String" -Force   
                    }
                    catch {
                        Write-Log -Level Warn -Message "Failed to write ApplicationID: $RunApplicationIDValue to registry"
                    }
                }
            }
            else {
                Write-Log -Level Warn -Message "ApplicationID: $RunApplicationIDValue was not found in WMI as deployed to the client. Please check the config.xml or deployment in ConfigMgr"
            }
        }
        else {
            Write-Log -Level Warn -Message "No ConfigMgr service found. This functon requires the ConfigMgr client to be installed"
        }
    }
}

# Create Display-ToastNotification function
function Display-ToastNotification() {
    $Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    # Load the notification into the required format
    $ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
    $ToastXml.LoadXml($Toast.OuterXml)
    # Display the toast notification
    try {
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($App).Show($ToastXml)
        Write-Log -Message "All good. Toast notification was displayed"
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "All good. Toast notification was displayed"
        Exit 0
    }
    catch { 
        Write-Log -Message "Something went wrong when displaying the toast notification" -Level Warn
        Write-Log -Message "Make sure the script is running as the logged on user" -Level Warn
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "Something went wrong when displaying the toast notification. Make sure the script is running as the logged on user"
        Exit 1  
    }
    if ($CustomAudio -eq "True") {
        Invoke-Command -ScriptBlock {
            Add-Type -AssemblyName System.Speech
            $speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $speak.Speak($CustomAudioTextToSpeech)
            $speak.Dispose()
        }    
    }
}
# Create Test-NTSystem function
# If the script is being run as SYSTEM, the toast notification won't display
function Test-NTSystem() {  
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($currentUser.IsSystem -eq $true) {
        Write-Log -Message "The script is being run as SYSTEM. This is not supported. The script needs the current user's context" -Level Warn
        $true  
    }
    elseif ($currentUser.IsSystem -eq $false) {
        $false
    }
}
######### GENERAL VARIABLES #########
# Getting executing directory
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Get running OS build
$RunningOS = Get-CimInstance -Class Win32_OperatingSystem | Select-Object BuildNumber
# Get user culture for multilanguage support
$userCulture = (Get-Culture).Name
# Setting the default culture to en-US. This will be the default language if MultiLanguageSupport is not enabled in the config
$defaultUserCulture = "en-US"
# Temporary location for images if images are hosted online on blob storage or similar
$LogoImageTemp = "$env:TEMP\ToastLogoImage.jpg"
$HeroImageTemp = "$env:TEMP\ToastHeroImage.jpg"
# Setting path to local images
$ImagesPath = "file:///$global:ScriptPath/Images"
# Getting custom action script location
$global:CustomScriptPath = "$($env:ProgramData)\ToastNotificationScript"

# Using Add-Type instead of Enum because we can group by namespace: ex [CCMClient.EvaluationState]
# Future considerations; adding DCM and App Eval states
try {
    Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
    namespace CCMClient
    {
        public enum EvalResult {
            Not_Yet_Evaluated = 1,
            Not_Applicable = 2,
            Evaluation_Failed = 3,
            Evaluated_Remediated_Failed = 4,
            Not_Evaluated_Dependency_Failed = 5,
            Evaluated_Remediated_Succeeded = 6,
            Evaluation_Succeeded = 7
        }
        public enum EvaluationState
        {
            None = 0,
            Available = 1,
            Submitted = 2,
            Detecting = 3,
            PreDownload = 4,
            Downloading = 5,
            WaitInstall = 6,
            Installing = 7,
            PendingSoftReboot = 8,
            PendingHardReboot = 9,
            WaitReboot = 10,
            Verifying = 11,
            InstallComplete = 12,
            Error = 13,
            WaitServiceWindow = 14,
            WaitUserLogon = 15,
            WaitUserLogoff = 16,
            WaitJobUserLogon = 17,
            WaitUserReconnect = 18,
            PendingUserLogoff = 19,
            PendingUpdate = 20,
            WaitingRetry = 21,
            WaitPresModeOff = 22,
            WaitForOrchestration = 23,
            ApplicationDownloadFailed = 24,
            ApplicationPredownloadingFailed = 25,
            DownloadSucess = 26,
            PostenforceEvaluation = 27,
            WaitingforNetwork = 28
        }
        public enum DCMEvaluationState {
            NonCompliant = 0,
            Compliant = 1,
            Submitted = 2,
            Unknown = 3,
            Detecting = 4,
            NotEvaluated = 5
        }
    }
'@
}
catch {
    $ErrorMessage = $_.Exception.Message
    if($ErrorMessage -match "already exists") {
        Write-Log -Message "Error, the type already is added...moving on" -Level Warn
    }
    else {
        Write-Log -Message "Error, could not Add-Type" -Level Warn
        Write-Log -Message "Error message: $ErrorMessage" -Level Warn
        Write-Output "Error, could not Add-Type. This parses information in WMI that needs to be loaded for the script to function. Error message: $ErrorMessage"
        Exit 1
    }
}    

# Testing for prerequisites
# Testing if script is being run as SYSTEM. This is not supported as the toast notification needs the current users context
$isSystem = Test-NTSystem
if ($isSystem -eq $True) {
    Write-Log -Message "Aborting script" -Level Warn
    Exit 1
}
# Test if the script is being run on a supported version of Windows. Windows 10 AND workstation OS is required
$SupportedWindowsVersion = Get-WindowsVersion
if ($SupportedWindowsVersion -eq $False) {
    Write-Log -Message "Aborting script" -Level Warn
    Exit 1
}
# Testing for blockers of toast notifications in Windows
$WindowsPushNotificationsEnabled = Test-WindowsPushNotificationsEnabled
# If no config file is set as parameter, use the default. 
# Default is executing directory. In this case, the config-toast.xml must exist in same directory as the New-ToastNotification.ps1 file
if (-NOT($Config)) {
    Write-Log -Message "No config file set as parameter. Using local config file"
    $Config = Join-Path ($global:ScriptPath) "config-toast-osupgrade_Servicing.xml"
}
# Load config.xml
# Catering for when config.xml is hosted online on blob storage or similar
# Loading the config.xml file here is relevant for when used with Endpoint Analytics in Intune
if (($Config.StartsWith("https://")) -OR ($Config.StartsWith("http://"))) {
    Write-Log -Message "Specified config file seems hosted [online]. Treating it accordingly"
    try { $testOnlineConfig = Invoke-WebRequest -Uri $Config -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineConfig.StatusDescription -eq "OK") {
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $Xml = [xml]$webClient.DownloadString($Config)
            Write-Log -Message "Successfully loaded $Config"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Log -Message "Error, could not read $Config" -Level Warn
            Write-Log -Message "Error message: $ErrorMessage" -Level Warn
            # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
            Write-Output "Error, could not read $Config. Error message: $ErrorMessage"
            Exit 1
        }
    }
    else {
        Write-Log -Level Warn -Message "The provided URL to the config does not reply or does not come back OK"
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "The provided URL to the config does not reply or does not come back OK"
        Exit 1
    }
}
# Catering for when config.xml is hosted locally or on fileshare
elseif (-NOT($Config.StartsWith("https://")) -OR (-NOT($Config.StartsWith("http://")))) {
    Write-Log -Message "Specified config file seems hosted [locally or fileshare]. Treating it accordingly"
    if (Test-Path -Path $Config) {
        try { 
            $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
            Write-Log -Message "Successfully loaded $Config"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Log -Message "Error, could not read $Config" -Level Warn
            Write-Log -Message "Error message: $ErrorMessage" -Level Warn
            Exit 1
        }
    }
    else {
        Write-Log -Level Warn -Message "No config file found on the specified location [locally or fileshare]"
        Exit 1
    }
}
else {
    Write-Log -Level Warn -Message "Something about the config file is completely off"
    # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
    Write-Output "Something about the config file is completely off"
    Exit 1
}

# TODO:  Write-CustomActionRegistry Updates
<#
    .DESCRIPTION
        If a user does not have Class URL Protocol added. This func adds it to the user context.

    .NOTES
        Author:     Chad Brower
        Contact:    @Brower_Chad
        Created:    2020.08.17

#>
function Write-CustomActionRegistry {
    [CmdletBinding()]
    param (
        [Parameter(Position="0")]
        [ValidateSet("ToastRunApplicationID","ToastRunPackageID","ToastRunUpdateID")]
        [string]
        $ActionType = "ToastRunUpdateID",
        [Parameter(Position="1")]
        [string]
        $RegCommandPath = $CustomScriptPath #Global Var can be changed

    )
    switch ($ActionType) {
        ToastRunUpdateID { 
            # Build out registry for custom action
            if((Test-Path -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command")  -ne $true) {
                try { 
                    New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ea SilentlyContinue | Out-Null
                        try {
                        New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ea SilentlyContinue | Out-Null
                        New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ea SilentlyContinue | Out-Null
                        $RegCommandValue = $RegCommandPath  + '\' + "Run-$($ActionType).cmd"
                        New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ea SilentlyContinue | Out-Null
                        }
                        catch {
                        $ErrorMessage = $_.Exception.Message
                        Write-Log -Level Error -Message "$($ErrorMessage)"
                        Write-Error -Message "$($ErrorMessage)"
                        # Exit because without this the toast action button does not work
                        Exit 1
                        }
                }
                catch {
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "$($ErrorMessage)"
                    Write-Error -Message "$($ErrorMessage)"
                    # Exit because without this the toast action button does not work
                    Exit 1
                }
                }
        #     # Build out registry for custom action
        #     if((Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\$($ActionType)\shell\open\command") -ne $true) {
        #         try { 
        #             New-Item "HKLM:\SOFTWARE\Classes\$($ActionType)\shell\open\command" -force -ea SilentlyContinue | Out-Null
        #               try {
        #                   New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ea SilentlyContinue | Out-Null
        #                   New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ea SilentlyContinue | Out-Null
        #                   # Build dynamic path for cmd file
        #                   $RegCommandValue = $RegCommandPath  + '\' + "Run-$($ActionType).cmd"
        #                   New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ea SilentlyContinue | Out-Null
        #               }
        #               catch {
        #                 $ErrorMessage = $_.Exception.Message
        #                 Write-Log -Level Error -Message "$($ErrorMessage)"
        #                 Write-Error -Message "$($ErrorMessage)"
        #               }
        #         }
        #         catch {
        #             $ErrorMessage = $_.Exception.Message
        #             Write-Log -Level Error -Message "$($ErrorMessage)"
        #             Write-Error -Message "$($ErrorMessage)"
        #         }
        #       }
        #   else {
        #     Write-Log -Level Info -Message "$($ActionType) Already exists in Registry"
        #   }
        }
        # TODO: Add other types "ToastRunApplicationID","ToastRunPackageID"
        Default {  
            Write-Log -Level Info -Message "Nothing to do here"
        }
    }
}
 # TODO: Write-UpdateIDRegistry
 <#
    .DESCRIPTION
        Adds the software update registry bit.  Uses another function to get update ID and writes to registry

    .NOTES
        Author:     Chad Brower
        Contact:    @Brower_Chad
        Created:    2020.08.17

#>
# TODO: Combine the other Write-reg functions and use a switch in 1 function
function Write-UpdateIDRegistry {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript",
        [Parameter()]
        [String]
        $RegistryName = "RunUpdateID" 

    )
    Write-Log -Message "Running Write-UpdateIDRegistry function"
    $RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
    $RegistryName = "RunUpdateID"    
    # Making sure that the registry path being used exists
    if (-NOT(Test-Path -Path $RegistryPath)) {
        try {
            New-Item -Path $RegistryPath -Force
        }
        catch { 
            Write-Log -Level Warn -Message "Error. Could not create ToastNotificationScript registry path"
        }
    }
    # If the ApplicationID specified in the config.xml is picked up
    if ($RunUpdateIDValue) {
        # If the ConfigMgr service exist
        if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
            # Testing if the UpdateID specified in the config.xml actually is deployed to the device
            try {
                $GetUpdateID = Get-CMUpdateAvailable
            }
            catch { 
                Write-Log -Level Warn -Message "Failed to retrieve $RunUpdateIDValue from WMI"
            }

            # If the Update ID is found in WMI with the ConfigMgr client, tattoo that ApplicationID into registry
            if ($GetUpdateID) {
                Write-Log -Message "Update ID: $RunUpdateIDValue was found in WMI as deployed to the client"
                Write-Log -Message "Writing the Update ID to registry"
                if ((Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -ne $GetUpdateID) {
                    try {
                        New-ItemProperty -Path $RegistryPath -Name $RegistryName -Value $GetUpdateID -PropertyType "String" -Force   
                    }
                    catch {
                        Write-Log -Level Warn -Message "Failed to write Update ID: $($GetUpdateID) to registry"
                    }
                }
            }
            else {
                Write-Log -Level Warn -Message "Update ID: $RunUpdateIDValue was not found in WMI as deployed to the client. Please check the config.xml or deployment in ConfigMgr"
            }
        }
        else {
            Write-Log -Level Warn -Message "No ConfigMgr service found. This functon requires the ConfigMgr client to be installed"
        }
    }
}
    
 # TODO: Write-CustomActionScript Updates
 <#
    .DESCRIPTION
        This func creates custom action scripts for action button

    .NOTES
        Author:     Chad Brower
        Contact:    @Brower_Chad
        Created:    2020.08.17

#>
 function Write-CustomActionScript {
    [CmdletBinding()]
    param (
        [Parameter(Position="0")]
        [ValidateSet("ToastRunApplicationID","ToastRunPackageID","ToastRunUpdateID")]
        [string]
        $Type,
        [Parameter(Position="1")]
        [String]
        $Path = $CustomScriptPath # Global var can be changed
    )
    # Create Path for custom scipts to live
    try {
        if(Test-Path -Path $Path) {
            Write-Log -Level Info -Message "Script Path Found"
        }
        else {
            New-item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Write-Log -Level Error -Message "$($ErrorMessage)"
        Write-Error -Message "$($ErrorMessage)"
    }
    switch ($Type) {
        ToastRunUpdateID {
            try {
                $CMDFileName = 'Run-' + $Type + '.cmd'
                New-item -Path $CustomScriptPath -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                    try {
                        $GetCustomScriptPath = $PathInfo.FullName
                        [String]$Script = @'
powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File "C:\ProgramData\ToastNotificationScript\Run-ToastRunUpdateID.ps1"                      
'@
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                    catch {
                        $ErrorMessage = $_.Exception.Message
                        Write-Log -Level Error -Message "$($ErrorMessage)"
                        Write-Error -Message "$($ErrorMessage)"
                    }
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "$($ErrorMessage)"
                Write-Error -Message "$($ErrorMessage)"
            }

            try {
                $CMDFileName = 'Run-' + $Type + '.ps1'
                New-item -Path $CustomScriptPath -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                    try {
                        $GetCustomScriptPath = $PathInfo.FullName
                        [String]$Script = @'
$registryPath = "HKCU:\SOFTWARE\ToastNotificationScript";
$UpdateID = (Get-ItemProperty -Path $RegistryPath -Name "RunUpdateID").RunUpdateID;
if(Test-Path -Path "C:\Windows\CCM\ClientUX\SCClient.exe") { Start-Process -FilePath "C:\Windows\CCM\ClientUX\SCClient.exe" -ArgumentList "SoftwareCenter:SoftwareID=$($UpdateID)" -WindowStyle Maximized };
exit 0                        
'@
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                    catch {
                        $ErrorMessage = $_.Exception.Message
                        Write-Log -Level Error -Message "$($ErrorMessage)"
                        Write-Error -Message "$($ErrorMessage)"
                    }
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "$($ErrorMessage)"
                Write-Error -Message "$($ErrorMessage)"
            }
            # Do not run another type; break
            Break
        }
        # TODO: Add other types: ToastApplicationID and ToastPackageID
        Default {
            Write-Verbose -Message "No Type Matched" -Verbose ; break
        }
    }
}

# TODO: Get-CMUpdateAvailable
<#
    .DESCRIPTION
        Get available updates based on the parameters you feed into the script

    .NOTES
        Author:     Chad Brower
        Contact:    @Brower_Chad
        Created:    2020.08.17

#>
function Get-CMUpdateAvailable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, Position=1)]
        [String]
        $UpdateID = $RunUpdateIDValue,
        [Parameter(Mandatory=$false, Position=2)]
        [String]
        $UpdateName = $RunUpdateTitleValue
    )
        # Splatt CIM Instance parameters
        $parmwmi = @{
            Namespace = "root\ccm\clientSDK"
            Query = "SELECT * from CCM_SoftwareUpdate WHERE ArticleId='$($UpdateID)' AND Name LIKE '%$($UpdateName)%'"
        }
        try {
            $GetCMUpdate = Get-CimInstance @parmwmi
        }
        catch {
            Write-Log -Level Error -Message "$($_.Exception.Message)"
            Write-Error -Message "$($_.Exception.Message)"
        }
        if(!($GetCMUpdate -eq $null)) {
            # Use the Enum to convert the Evaluation State to a readable format
            [CCMClient.EvaluationState]$EvaluationState = $GetCMUpdate.EvaluationState
            
            if ($EvaluationState -eq "None" -or $EvaluationState -eq "Available" -or $EvaluationState -eq "Submitted") {
                Write-Log -Level Info -Message "Found a update that matches ID: $($UpdateID) and Name: $($GetCMUpdate.Name)"
                # Write-Output "Found a update that matches $($UpdateID) and $($GetCMUpdate.Name)"
                Return $GetCMUpdate.UpdateID
            }
            else {
                Write-Log -Level Warn -Message "Update State is not set to available."
                Write-Log -Level Warn -Message "Update State: $($EvaluationState). Refer to notes in script for meaning of state."
                Write-Output "Update State is not set to available."
                Write-Output "Update State: $($EvaluationState). Refer to notes in script for meaning of state."
            }
        }
        else {
            Write-Log -Level Warn -Message "No Update was found on system. UpdateID: $($UpdateID) and Name: $($GetCMUpdate.Name)"
            Write-Output "No Update was found on system. UpdateID: $($UpdateID) and Name: $($GetCMUpdate.Name)"
            # if no update is found, then there is no point in running the toast
            Exit 1
        }
    }
#EndRegion Helper Functions

#Region Parse XML Config
# Load xml content into variables
if(-NOT[string]::IsNullOrEmpty($Xml)) {
    try {
        Write-Log -Message "Loading xml content from $Config into variables"
        # Load Toast Notification features 
        $ToastEnabled = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'Toast'} | Select-Object -ExpandProperty 'Enabled'
        $UpgradeOS = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'UpgradeOS'} | Select-Object -ExpandProperty 'Enabled'
        $PendingRebootUptime = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'PendingRebootUptime'} | Select-Object -ExpandProperty 'Enabled'
        $PendingRebootCheck = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'PendingRebootCheck'} | Select-Object -ExpandProperty 'Enabled'
        $ADPasswordExpiration = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'ADPasswordExpiration'} | Select-Object -ExpandProperty 'Enabled'
        # Load Toast Notification options   
        $PendingRebootUptimeTextEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'PendingRebootUptimeText'} | Select-Object -ExpandProperty 'Enabled'
        $MaxUptimeDays = $Xml.Configuration.Option | Where-Object {$_.Name -like 'MaxUptimeDays'} | Select-Object -ExpandProperty 'Value'
        $PendingRebootCheckTextEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'PendingRebootCheckText'} | Select-Object -ExpandProperty 'Enabled'
        $ADPasswordExpirationTextEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ADPasswordExpirationText'} | Select-Object -ExpandProperty 'Enabled'
        $ADPasswordExpirationDays = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ADPasswordExpirationDays'} | Select-Object -ExpandProperty 'Value'
        $TargetOS = $Xml.Configuration.Option | Where-Object {$_.Name -like 'TargetOS'} | Select-Object -ExpandProperty 'Build'
        $DeadlineEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Deadline'} | Select-Object -ExpandProperty 'Enabled'
        $DeadlineContent = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Deadline'} | Select-Object -ExpandProperty 'Value'
        $DynDeadlineEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'DynamicDeadline'} | Select-Object -ExpandProperty 'Enabled'
        $DynDeadlineValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'DynamicDeadline'} | Select-Object -ExpandProperty 'Value'
        $RunPackageIDEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunPackageID'} | Select-Object -ExpandProperty 'Enabled'
        $RunPackageIDValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunPackageID'} | Select-Object -ExpandProperty 'Value'
        $RunApplicationIDEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunApplicationID'} | Select-Object -ExpandProperty 'Enabled'
        $RunApplicationIDValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunApplicationID'} | Select-Object -ExpandProperty 'Value'
        # Servicing
        $RunUpdateIDEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunUpdateID'} | Select-Object -ExpandProperty 'Enabled'
        $RunUpdateIDValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunUpdateID'}| Select-Object -ExpandProperty 'Value'
        $RunUpdateTitleEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunUpdateTitle'} | Select-Object -ExpandProperty 'Enabled'
        $RunUpdateTitleValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'RunUpdateTitle'} | Select-Object -ExpandProperty 'Value'

        $SCAppName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UseSoftwareCenterApp'} | Select-Object -ExpandProperty 'Name'
        $SCAppStatus = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UseSoftwareCenterApp'} | Select-Object -ExpandProperty 'Enabled'
        $PSAppName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UsePowershellApp'} | Select-Object -ExpandProperty 'Name'
        $PSAppStatus = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UsePowershellApp'} | Select-Object -ExpandProperty 'Enabled'
        $CustomAudio = $Xml.Configuration.Option | Where-Object {$_.Name -like 'CustomAudio'} | Select-Object -ExpandProperty 'Enabled'
        $LogoImageFileName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'LogoImageName'} | Select-Object -ExpandProperty 'Value'
        $HeroImageFileName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'HeroImageName'} | Select-Object -ExpandProperty 'Value'
        # Rewriting image variables to cater for images being hosted online, as well as being hosted locally. 
        # Needed image including path in one variable
        if ((-NOT[string]::IsNullOrEmpty($LogoImageFileName)) -OR (-NOT[string]::IsNullOrEmpty($HeroImageFileName)))  {
            $LogoImage = $ImagesPath + "/" + $LogoImageFileName
            $HeroImage = $ImagesPath + "/" + $HeroImageFileName
        }
        $Scenario = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Scenario'} | Select-Object -ExpandProperty 'Type'
        $Action = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Action'} | Select-Object -ExpandProperty 'Value'
        $GreetGivenName = $Xml.Configuration.Text | Where-Object {$_.Option -like 'GreetGivenName'} | Select-Object -ExpandProperty 'Enabled'
        $MultiLanguageSupport = $Xml.Configuration.Text | Where-Object {$_.Option -like 'MultiLanguageSupport'} | Select-Object -ExpandProperty 'Enabled'
        # Load Toast Notification buttons
        $ActionButtonEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ActionButton'} | Select-Object -ExpandProperty 'Enabled'
        $DismissButtonEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'DismissButton'} | Select-Object -ExpandProperty 'Enabled'
        $SnoozeButtonEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'SnoozeButton'} | Select-Object -ExpandProperty 'Enabled'
        # Multi language support
        if ($MultiLanguageSupport -eq "True") {
            Write-Log "MultiLanguageSupport set to True. Current language culture is $userCulture. Checking for language support"
            # Check config xml if language support is added for the users culture
            if (-NOT[string]::IsNullOrEmpty($xml.Configuration.$userCulture)) {
                Write-Log -Message "Support for the users language culture found, localizing text using $userCulture"
                $XmlLang = $xml.Configuration.$userCulture
            }
            # Else fallback to using default language "en-US"
            elseif (-NOT[string]::IsNullOrEmpty($xml.Configuration.$defaultUserCulture)) {
                Write-Log -Message "No support for the users language culture found, using $defaultUserCulture as default fallback language"
                $XmlLang = $xml.Configuration.$defaultUserCulture
            }
        }
        # If multilanguagesupport is set to False use default language "en-US"
        elseif ($MultiLanguageSupport -eq "False") {
            $XmlLang = $xml.Configuration.$defaultUserCulture
        }
        # Regardless of whatever might happen, always use "en-US" as language
        else {
            $XmlLang = $xml.Configuration.$defaultUserCulture
        }
        # Load Toast Notification text
        $PendingRebootUptimeTextValue = $XmlLang.Text | Where-Object {$_.Name -like 'PendingRebootUptimeText'} | Select-Object -ExpandProperty '#text'
        $PendingRebootCheckTextValue = $XmlLang.Text | Where-Object {$_.Name -like 'PendingRebootCheckText'} | Select-Object -ExpandProperty '#text'
        $ADPasswordExpirationTextValue = $XmlLang.Text | Where-Object {$_.Name -like 'ADPasswordExpirationText'} | Select-Object -ExpandProperty '#text'
        $CustomAudioTextToSpeech = $XmlLang.Text | Where-Object {$_.Name -like 'CustomAudio'} | Select-Object -ExpandProperty '#text'
        $ActionButtonContent = $XmlLang.Text | Where-Object {$_.Name -like 'ActionButton'} | Select-Object -ExpandProperty '#text'
        $DismissButtonContent = $XmlLang.Text | Where-Object {$_.Name -like 'DismissButton'} | Select-Object -ExpandProperty '#text'
        $SnoozeButtonContent = $XmlLang.Text | Where-Object {$_.Name -like 'SnoozeButton'} | Select-Object -ExpandProperty '#text'
        $AttributionText = $XmlLang.Text | Where-Object {$_.Name -like 'AttributionText'} | Select-Object -ExpandProperty '#text'
        $HeaderText = $XmlLang.Text | Where-Object {$_.Name -like 'HeaderText'} | Select-Object -ExpandProperty '#text'
        $TitleText = $XmlLang.Text | Where-Object {$_.Name -like 'TitleText'} | Select-Object -ExpandProperty '#text'
        $BodyText1 = $XmlLang.Text | Where-Object {$_.Name -like 'BodyText1'} | Select-Object -ExpandProperty '#text'
        $BodyText2 = $XmlLang.Text | Where-Object {$_.Name -like 'BodyText2'} | Select-Object -ExpandProperty '#text'
        $SnoozeText = $XmlLang.Text | Where-Object {$_.Name -like 'SnoozeText'} | Select-Object -ExpandProperty '#text'
	    $DeadlineText = $XmlLang.Text | Where-Object {$_.Name -like 'DeadlineText'} | Select-Object -ExpandProperty '#text'
	    $GreetMorningText = $XmlLang.Text | Where-Object {$_.Name -like 'GreetMorningText'} | Select-Object -ExpandProperty '#text'
	    $GreetAfternoonText = $XmlLang.Text | Where-Object {$_.Name -like 'GreetAfternoonText'} | Select-Object -ExpandProperty '#text'
	    $GreetEveningText = $XmlLang.Text | Where-Object {$_.Name -like 'GreetEveningText'} | Select-Object -ExpandProperty '#text'
	    $MinutesText = $XmlLang.Text | Where-Object {$_.Name -like 'MinutesText'} | Select-Object -ExpandProperty '#text'
	    $HourText = $XmlLang.Text | Where-Object {$_.Name -like 'HourText'} | Select-Object -ExpandProperty '#text'
        $HoursText = $XmlLang.Text | Where-Object {$_.Name -like 'HoursText'} | Select-Object -ExpandProperty '#text'
	    $ComputerUptimeText = $XmlLang.Text | Where-Object {$_.Name -like 'ComputerUptimeText'} | Select-Object -ExpandProperty '#text'
        $ComputerUptimeDaysText = $XmlLang.Text | Where-Object {$_.Name -like 'ComputerUptimeDaysText'} | Select-Object -ExpandProperty '#text'
        Write-Log -Message "Successfully loaded xml content from $Config"     
    }
    catch {
        Write-Log -Message "Xml content from $Config was not loaded properly"
        Exit 1
    }
}
#EndRegion Parse XML Config

#Region Checks and Conflicts
# Check if toast is enabled in config.xml
if ($ToastEnabled -ne "True") {
    Write-Log -Message "Toast notification is not enabled. Please check $Config file"
    Exit 1
}

# Checking for conflicts in config. Some combinations makes no sense, thus trying to prevent those from happening
if (($UpgradeOS -eq "True") -AND ($PendingRebootCheck -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have both ÜpgradeOS feature set to True AND PendingRebootCheck feature set to True at the same time"
    Exit 1
}
if (($UpgradeOS -eq "True") -AND ($PendingRebootUptime -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have both ÜpgradeOS feature set to True AND PendingRebootUptime feature set to True at the same time"
    Exit 1
}
if (($PendingRebootCheck -eq "True") -AND ($PendingRebootUptime -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You currently can't have both PendingReboot features set to True. Please use them seperately"
    Exit 1
}
if (($ADPasswordExpiration -eq "True") -AND ($UpgradeOS -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have both ADPasswordExpiration AND UpgradeOS set to True at the same time"
    Exit 1
}
if (($ADPasswordExpiration -eq "True") -AND ($PendingRebootCheck -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have both ADPasswordExpiration AND PendingRebootCheck set to True at the same time"
    Exit 1
}
if (($ADPasswordExpiration -eq "True") -AND ($PendingRebootUptime -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have both ADPasswordExpiration AND PendingRebootUptime set to True at the same time"
    Exit 1
}
if (($SCAppStatus -eq "True") -AND (-NOT(Get-Service -Name ccmexec))) {
    Write-Log -Level Warn -Message "Error. Using Software Center app for the notification requires the ConfigMgr client installed"
    Write-Log -Level Warn -Message "Error. Please install the ConfigMgr cient or use Powershell as app doing the notification"
    Exit 1
}
if (($SCAppStatus -eq "True") -AND ($PSAppStatus -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have both SoftwareCenter app set to True AND PowershellApp set to True at the same time"
    Exit 1
}
if (($SCAppStatus -ne "True") -AND ($PSAppStatus -ne "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You need to enable at least 1 app in the config doing the notification. ie. Software Center or Powershell"
    Exit 1
}
if (($UpgradeOS -eq "True") -AND ($PendingRebootUptimeTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have UpgradeOS set to True and PendingRebootUptimeText set to True at the same time"
    Exit 1
}
if (($UpgradeOS -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have UpgradeOS set to True and PendingRebootCheckText set to True at the same time"
    Exit 1
}
if (($PendingRebootUptimeTextEnabled -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have PendingRebootUptimeText set to True and PendingRebootCheckText set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the text options"
    Exit 1
}
if (($PendingRebootCheck -eq "True") -AND ($PendingRebootUptimeTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have PendingRebootCheck set to True and PendingRebootUptimeText set to True at the same time"
    Write-Log -Level Warn -Message "You should use PendingRebootCheck with the PendingRebootCheckText option instead"
    Exit 1
}
if (($PendingRebootUptime -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have PendingRebootUptime set to True and PendingRebootCheckText set to True at the same time"
    Write-Log -Level Warn -Message "You should use PendingRebootUptime with the PendingRebootUptimeText option instead"
    Exit 1
}
if (($ADPasswordExpirationTextEnabled -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have ADPasswordExpirationTextEnabled set to True and PendingRebootCheckText set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the text options"
    Exit 1
}
if (($ADPasswordExpirationTextEnabled -eq "True") -AND ($PendingRebootUptimeTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have ADPasswordExpirationTextEnabled set to True and PendingRebootUptimeTextEnabled set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the text options"
    Exit 1
}
if (($DeadlineEnabled -eq "True") -AND ($DynDeadlineEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have DeadlineEnabled set to True and DynamicDeadlineEnabled set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the deadline options"
    Exit 1
}
if (($RunApplicationIDEnabled -eq "True") -AND ($RunPackageIDEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have RunApplicationIDEnabled set to True and RunPackageIDEnabled set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the options"
    Exit 1
}
if (($RunApplicationIDEnabled -eq "True") -AND ($RunUpdateIDEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have RunApplicationIDEnabled set to True and RunUpdateIDEnabled set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the options"
    Exit 1
}
if (($RunUpdateIDEnabled -eq "True") -AND ($RunPackageIDEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Warn -Message "Error. You can't have RunUpdateIDEnabled set to True and RunPackageIDEnabled set to True at the same time"
    Write-Log -Level Warn -Message "You should only enable one of the options"
    Exit 1
}
#EndRegion Checks and Conflicts

#Region Script Building Blocks
# Downloading images into user's temp folder if images are hosted online
if (($LogoImageFileName.StartsWith("https://")) -OR ($LogoImageFileName.StartsWith("http://"))) {
    Write-Log -Message "ToastLogoImage appears to be hosted online. Will need to download the file"
    # Testing to see if image at the provided URL indeed is available
    try { $testOnlineLogoImage = Invoke-WebRequest -Uri $LogoImageFileName -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineLogoImage.StatusDescription -eq "OK") {
        try {
            Invoke-WebRequest -Uri $LogoImageFileName -OutFile $LogoImageTemp
            # Replacing image variable with the image downloaded locally
            $LogoImage = $LogoImageTemp
            Write-Log -Message "Successfully downloaded $LogoImageTemp from $LogoImageFileName"
        }
        catch { 
            Write-Log -Level Warn -Message "Failed to download the $LogoImageTemp from $LogoImageFileName"
        }
    }
    else {
        Write-Log -Level Warn -Message "The image supposedly located on $LogoImageFileName is not available"
    }
}
if (($HeroImageFileName.StartsWith("https://")) -OR ($HeroImageFileName.StartsWith("http://"))) {
    Write-Log -Message "ToastHeroImage appears to be hosted online. Will need to download the file"
    # Testing to see if image at the provided URL indeed is available
    try { $testOnlineHeroImage = Invoke-WebRequest -Uri $HeroImageFileName -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineHeroImage.StatusDescription -eq "OK") {
        try {
            Invoke-WebRequest -Uri $HeroImageFileName -OutFile $HeroImageTemp
            # Replacing image variable with the image downloaded locally
            $HeroImage = $HeroImageTemp
            Write-Log -Message "Successfully downloaded $HeroImageTemp from $HeroImageFileName"
        }
        catch { 
            Write-Log -Level Warn -Message "Failed to download the $HeroImageTemp from $HeroImageFileName"
        }
    }
    else {
        Write-Log -Level Warn -Message "The image supposedly located on $HeroImageFileName is not available"
    }
}

# Running RunApplicationID function
if ($RunApplicationIDEnabled -eq "True") {
    Write-Log -Message "RunApplicationID set to True. Will allow execution of ApplicationID directly from the toast action button"
    Write-ApplicationIDRegistry
}

# Running RunPackageID function
if ($RunPackageIDEnabled -eq "True") {
    Write-Log -Message "RunPackageID set to True. Will allow execution of PackageID directly from the toast action button"
    Write-PackageIDRegistry
}

# Running RunUpdateID function
if ($RunUpdateIDEnabled -eq "True") {
    Write-Log -Message "RunUpdateID set to True. Will allow execution of Software Update ID directly from the toast action button"
    Write-UpdateIDRegistry
    Write-CustomActionScript -Type ToastRunUpdateID
    Write-CustomActionRegistry -ActionType ToastRunUpdateID    
}


# Running DynamicDeadline function
if ($DynDeadlineEnabled -eq "True") {
    Write-Log -Message "DynDeadlineEnabled set to True. Overriding deadline details using date and time from WMI"
    $DeadlineContent = Get-DynamicDeadline
}

# Running ADPasswordExpiration Check
if ($ADPasswordExpiration -eq "True") {
    Write-Log -Message "ADPasswordExpiration set to True. Checking for expiring AD password"
    $TestADPasswordExpiration = Get-ADPasswordExpiration $ADPasswordExpirationDays
    $ADPasswordExpirationResult = $TestADPasswordExpiration[0]
    $ADPasswordExpirationDate = $TestADPasswordExpiration[1]
    $ADPasswordExpirationDiff = $TestADPasswordExpiration[2]
}

# Running Pending Reboot Checks
if ($PendingRebootCheck -eq "True") {
    Write-Log -Message "PendingRebootCheck set to True. Checking for pending reboots"
    $TestPendingRebootRegistry = Test-PendingRebootRegistry
    $TestPendingRebootWMI = Test-PendingRebootWMI
}
if ($PendingRebootUptime -eq "True") {
    $Uptime = Get-DeviceUptime
    Write-Log -Message "PendingRebootUptime set to True. Checking for device uptime. Current uptime is: $Uptime days"
}

# Check for required entries in registry for when using Software Center as application for the toast
if ($SCAppStatus -eq "True") {
    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
        # Path to the notification app doing the actual toast
        $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
        $App = "Microsoft.SoftwareCenter.DesktopToasts"
        # Creating registry entries if they don't exists
        if (-NOT(Test-Path -Path $RegPath\$App)) {
            New-Item -Path $RegPath\$App -Force
            New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force
            New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
        }
        # Make sure the app used with the action center is enabled
        if ((Get-ItemProperty -Path $RegPath\$App -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -ne "1") {
            New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
        }
    }
    else {
        Write-Log -Message "No ConfigMgr client thus cannot use Software Center as notifying app" -Level Warn
    }
}

# Check for required entries in registry for when using Powershell as application for the toast
if ($PSAppStatus -eq "True") {

    # Register the AppID in the registry for use with the Action Center, if required
    $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    $App =  "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
    
    # Creating registry entries if they don't exists
    if (-NOT(Test-Path -Path $RegPath\$App)) {
        New-Item -Path $RegPath\$App -Force
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD"
    }
    
    # Make sure the app used with the action center is enabled
    if ((Get-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -ErrorAction SilentlyContinue).ShowInActionCenter -ne "1") {
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force
    }
}

# Checking if running toast with personal greeting with given name
if ($GreetGivenName -eq "True") {
    Write-Log -Message "Greeting with given name selected. Replacing HeaderText"
    $Hour = (Get-Date).TimeOfDay.Hours
    if (($Hour -ge 0) -AND ($Hour -lt 12)) {
        $Greeting = $GreetMorningText
    }
    elseif (($Hour -ge 12) -AND ($Hour -lt 16)) {
        $Greeting = $GreetAfternoonText
    }
    else {
        $Greeting = $GreetEveningText
    }
    $GivenName = Get-GivenName
    $HeaderText = "$Greeting $GivenName"
}
#EndRegion Script Building Blocks

#Region Build XML for Notfication
# Formatting the toast notification XML
# Create the default toast notification XML with action button and dismiss button
if (($ActionButtonEnabled -eq "True") -AND ($DismissButtonEnabled -eq "True")) {
    Write-Log -Message "Creating the xml for displaying both action button and dismiss button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action" content="$ActionButtonContent" />
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# NO action button and NO dismiss button
if (($ActionButtonEnabled -ne "True") -AND ($DismissButtonEnabled -ne "True")) {
    Write-Log -Message "Creating the xml for no action button and no dismiss button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
    </actions>
</toast>
"@
}

# Action button and NO dismiss button
if (($ActionButtonEnabled -eq "True") -AND ($DismissButtonEnabled -ne "True")) {
    Write-Log -Message "Creating the xml for no dismiss button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action" content="$ActionButtonContent" />
    </actions>
</toast>
"@
}

# Dismiss button and NO action button
if (($ActionButtonEnabled -ne "True") -AND ($DismissButtonEnabled -eq "True")) {
    Write-Log -Message "Creating the xml for no action button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Snooze button - this option will always enable both action button and dismiss button regardless of config settings
if ($SnoozeButtonEnabled -eq "True") {
    Write-Log -Message "Creating the xml for snooze button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <input id="snoozeTime" type="selection" title="$SnoozeText" defaultInput="60">
            <selection id="15" content="15 $MinutesText"/>
            <selection id="30" content="30 $MinutesText"/>
            <selection id="60" content="1 $HourText"/>
            <selection id="240" content="4 $HoursText"/>
            <selection id="480" content="8 $HoursText"/>
        </input>
        <action activationType="protocol" arguments="$Action" content="$ActionButtonContent" />
        <action activationType="system" arguments="snooze" hint-inputId="snoozeTime" content="$SnoozeButtonContent"/>
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Add an additional group and text to the toast xml used for notifying about possible deadline.
if (($DeadlineEnabled -eq "True") -OR ($DynDeadlineEnabled -eq "True")) {
    
    if ($DeadlineContent) {
        # Format the date time to match local culture of the running OS. Thanks @osdsune.com
        $LocalCulture = Get-Culture
        $RegionDateFormat = [System.Globalization.CultureInfo]::GetCultureInfo($LocalCulture.LCID).DateTimeFormat.LongDatePattern
        $RegionTimeFormat = [System.Globalization.CultureInfo]::GetCultureInfo($LocalCulture.LCID).DateTimeFormat.ShortTimePattern
        $LocalDateFormat = $DeadlineContent
        $LocalDateFormat = Get-Date $LocalDateFormat -f "$RegionDateFormat $RegionTimeFormat"

$DeadlineGroup = @"
        <group>
            <subgroup>
                <text hint-style="base" hint-align="left">$DeadlineText</text>
                 <text hint-style="caption" hint-align="left">$LocalDateFormat</text>
            </subgroup>
        </group>
"@
        $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $DeadlineGroup
    }
}

# Add an additional group and text to the toast xml for PendingRebootCheck
if ($PendingRebootCheckTextEnabled -eq "True") {
$PendingRebootGroup = @"
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$PendingRebootCheckTextValue</text>
            </subgroup>
        </group>
"@
    $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $PendingRebootGroup
}

# Add an additional group and text to the toast xml for ADpasswordExpiration
if ($ADPasswordExpirationTextEnabled -eq "True") {
$ADPasswordExpirationGroup = @"
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$ADPasswordExpirationTextValue $ADPasswordExpirationDate</text>
            </subgroup>
        </group>
"@
    $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $ADPasswordExpirationGroup
}

# Add an additional group and text to the toast xml used for notifying about computer uptime. Only add this if the computer uptime exceeds MaxUptimeDays.
if (($PendingRebootUptimeTextEnabled -eq "True") -AND ($Uptime -gt $MaxUptimeDays)) {
$UptimeGroup = @"
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$PendingRebootUptimeTextValue</text>
            </subgroup>
        </group>
        <group>
            <subgroup>
                <text hint-style="base" hint-align="left">$ComputerUptimeText $Uptime $ComputerUptimeDaysText</text>
            </subgroup>
        </group>
"@
    $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $UptimeGroup
}
#EndRegion Build XML for Notfication

#Region Display Notification IF Statements
# Running the Display-notification function depending on selections and variables
# Toast used for upgrading OS. Checking running OS buildnumber. No need to display toast, if the OS is already running on TargetOS
if (($UpgradeOS -eq "True") -AND ($RunningOS.BuildNumber -lt $TargetOS)) {
    Write-Log -Message "Toast notification is used in regards to OS upgrade. Taking running OS build into account"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
# TODO: Add in for servicing
else {
    Write-Log -Level Warn -Message "Conditions for displaying toast notifications for UpgradeOS are not fulfilled"
}

# Toast used for PendingReboot check and considering OS uptime
if (($PendingRebootUptime -eq "True") -AND ($Uptime -gt $MaxUptimeDays)) {
    Write-Log -Message "Toast notification is used in regards to pending reboot. Uptime count is greater than $MaxUptimeDays"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying toast notifications for pending reboot uptime are not fulfilled"
}

# Toast used for pendingReboot check and considering checks in registry
if (($PendingRebootCheck -eq "True") -AND ($TestPendingRebootRegistry -eq $True)) {
    Write-Log -Message "Toast notification is used in regards to pending reboot registry. TestPendingRebootRegistry returned $TestPendingRebootRegistry"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying toast notifications for pending reboot registry are not fulfilled"
}

# Toast used for pendingReboot check and considering checks in WMI
if (($PendingRebootCheck -eq "True") -AND ($TestPendingRebootWMI -eq $True)) {
    Write-Log -Message "Toast notification is used in regards to pending reboot WMI. TestPendingRebootWMI returned $TestPendingRebootWMI"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying toast notifications for pending reboot WMI are not fulfilled"
}

# Toast used for ADPasswordExpiration
if (($ADPasswordExpiration -eq "True") -AND ($ADPasswordExpirationResult -eq $True)) {
    Write-Log -Message "Toast notification is used in regards to ADPasswordExpiration. ADPasswordExpirationResult returned $ADPasswordExpirationResult"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying toast notification for ADPasswordExpiration are not fulfilled"
}

# Toast not used for either OS upgrade or Pending reboot OR ADPasswordExpiration. Run this if all features are set to false in config.xml
if (($UpgradeOS -ne "True") -AND ($PendingRebootCheck -ne "True") -AND ($PendingRebootUptime -ne "True") -AND ($ADPasswordExpiration -ne "True")) {
    Write-Log -Message "Toast notification is not used in regards to OS upgrade OR Pending Reboots OR ADPasswordExpiration. Displaying default toast"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying default toast notification are not fulfilled"
}
#EndRegion Display Notifications IF Statements