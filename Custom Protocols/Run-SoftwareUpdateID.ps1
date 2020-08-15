<#
.SYNOPSIS
    FORCE INSTALL OF SOFTWARE UPDATE THATS AVAILABLE ON CLIENT THROUGH WMI
    This scripts runs individual updates or all updates based using WMI methods. 

.DESCRIPTION
    To get the full list of States and more info about the WMI class follow the link to Microsofts MSDN 
    What I’ve noticed is that when the updates first gets available they don’t get value 1 but 0, 
    then after while some gets 1. The rest of the script just handles the actual process of calling 
    the WMI class for CCM_SoftwareUpdates to get available updates based on the parameters you feed into the script. 
    If something is found, it then feeds into a CCM_SoftwareUpdateManagement to call the InstallUpdates WMI method. 

.PARAMETER UpdateID
    Specify the article ID name you want to target

.PARAMETER ComputerName
    Defualts as the $env.computername

.PARAMETER Updatename
    Use as a LIKE operator in a WMI Query. Also as a fail safe for specifiying the right update is intalled.  

.EXAMPLE
    C:\PS>
    Run-SoftwareUpdateID.ps1 -UpdateID 34567 -UpdateName "Feature Update something"

.NOTES
          FileName: 
          Author: Chad Brower
          CO-Author: Tmmmy Anderson
          Contact: @TimmyITdotcom / @brower_chad
          Created: 2020.08.04
          Modified: 
          URL: https://timmyit.com/2016/08/01/sccm-and-powershell-force-install-of-software-updates-thats-available-on-client-through-wmi/
          Version - 0.0.0 - 
#>
# Convert the EvaluationState value to a readable valueenum EvaluationState 

[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, Position=1)]
    [String]
    $UpdateID = (Get-ItemProperty -Path "HKCU:\SOFTWARE\ToastNotificationScript" -Name "RunPackageID").RunUpdateID,
    [Parameter(Mandatory=$false, Position=2)]
    [String]
    $UpdateName = (Get-ItemProperty -Path "HKCU:\SOFTWARE\ToastNotificationScript" -Name "RunPackageID").RunUpdateName
)
enum EvaluationState {
    None = 0
    Available = 1
    Submitted = 2
    Detection = 3
    PreDownloading = 4
    Downloading = 5
    WaitInstall = 6
    Installing = 7
    PendingSoftReboot = 8
    PendingHardReboot = 9
    WaitReboot = 10
    Verifying = 11
    InstallComplete = 12
    Error = 13
    WaitServiceWindow = 14
    WaitUserLogon = 15
    WaitUserLogoff = 16
    WaitJobUserLogon = 17
    WaitUserReconnect = 18
    PendingUserLogoff = 19
    PendingUpdate = 20
    WaitingRetry = 21
    WaitPresModeOff = 22
    WaitForOrchestration = 23
}
    # Splatt CIM Instance parameters
    $parmwmi = @{
        Namespace = "root\ccm\clientSDK"
        Query = "SELECT * from CCM_SoftwareUpdate WHERE ArticleId='$($UpdateID)' AND Name LIKE '%$($UpdateName)%'"
        }
    try {

        $CMUpdateFound = Get-CimInstance @parmwmi
    }
    catch {

        Write-Error -Message "$($_.Exception.Message)" -Verbose
    }
    if(!($CMUpdateFound -eq $null)) {

            # Testing if you Just looking to return the info in var
            # Return $CMUpdateFound

        # Use the Enum to convert the Evaluation State to a readable format
        [EvaluationState]$EvaluationState = $CMUpdateFound.EvaluationState
        
        if ($EvaluationState -eq "None" -or $EvaluationState -eq "Available") {

            Write-Verbose -Message "Found a update that matches $($UpdateID) and $($CMUpdateFound.Name)" -Verbose

            # Convert the Update ID to a IDictionary System Type
            [System.Collections.IDictionary]$CMUpdateFound.UpdateID = $CCMUpdateID

            # Splatt CIM Method parameters
            $parmCIM = @{
            Namespace = "root\ccm\clientSDK"
            ClassName = "CCM_SoftwareUpdatesManager"
            MethodName = "InstallUpdates"
            }

            try {
                # TODO: Remove -whatif from here
                Invoke-CimMethod @parmCIM -Arguments $CCMUpdateID -WhatIf
            }
            catch {

                Write-Error -Message "$($_.Exception.Message)" -Verbose
            }
        }
        else  {

            Write-Warning -Message "Found a update that matches $($UpdateID) and $($CMUpdateFound.Name), but its status is not ready to trigger install." -Verbose
            Write-Warning -Message "Update Evaluation Status: $($Evaluation)" -Verbose
        }
    }
    else {

        Write-Warning -Message "Article ID $($UpdateID) was not found on $($ComputerName)" -Verbose
    }