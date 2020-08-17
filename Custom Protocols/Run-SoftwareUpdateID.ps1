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

          Evaluation States: (https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/core/clients/sdk/ccm_evaluationstate-client-wmi-class)
            Evaluation state. Possible values are:
            Value	Description
            0	No state information is available.
            1	Application is enforced to desired/resolved state.
            2	Application is not required on the client.
            3	Application is available for enforcement (install or uninstall based on resolved state). Content may/may not have been downloaded.
            4	Application last failed to enforce (install/uninstall).
            5	Application is currently waiting for content download to complete.
            6	Application is currently waiting for content download to complete.
            7	Application is currently waiting for its dependencies to download.
            8	Application is currently waiting for a service (maintenance) window.
            9	Application is currently waiting for a previously pending reboot.
            10	Application is currently waiting for serialized enforcement.
            11	Application is currently enforcing dependencies.
            12	Application is currently enforcing.
            13	Application install/uninstall enforced and soft reboot is pending.
            14	Application installed/uninstalled and hard reboot is pending.
            15	Update is available but pending installation.
            16	Application failed to evaluate.
            17	Application is currently waiting for an active user session to enforce.
            18	Application is currently waiting for all users to logoff.
            19	Application is currently waiting for a user logon.
            20	Application in progress, waiting for retry.
            21	Application is waiting for presentation mode to be switched off.
            22	Application is pre-downloading content (downloading outside of install job).
            23	Application is pre-downloading dependent content (downloading outside of install job).
            24	Application download failed (downloading during install job).
            25	Application pre-downloading failed (downloading outside of install job).
            26	Download success (downloading during install job).
            27	Post-enforce evaluation.
            28	Waiting for network connectivity.
#>

[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, Position=1)]
    [String]
    $UpdateID = (Get-ItemProperty -Path "HKCU:\SOFTWARE\ToastNotificationScript" -Name "RunPackageID").RunUpdateID,
    [Parameter(Mandatory=$false, Position=2)]
    [String]
    $UpdateName = (Get-ItemProperty -Path "HKCU:\SOFTWARE\ToastNotificationScript" -Name "RunPackageID").RunUpdateName
)
# Convert the EvaluationState value to a readable valueenum EvaluationState 

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
    ApplicationDownloadFailed = 24
    ApplicationPredownloadingFailed = 25
    DownloadSucess = 26
    PostenforceEvaluation = 27
    WaitingforNetwork = 28
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