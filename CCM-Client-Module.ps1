#using Add-Type instead of Enum because I want to group by namespace
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
          WaitForOrchestration = 23
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
<#
class ModuleInfoAttribute : System.Management.Automation.ArgumentTransformationAttribute {
    [object] Transform([System.Management.Automation.EngineIntrinsics]$engineIntrinsics, [object] $inputData) {
        $ModuleInfo = $null
        if ($inputData -is [string] -and -not [string]::IsNullOrWhiteSpace($inputData)) {
            $ModuleInfo = Get-Module $inputData -ErrorAction SilentlyContinue
            if (-not $ModuleInfo) {
                $ModuleInfo = @(Get-Module $inputData -ErrorAction SilentlyContinue -ListAvailable)[0]
            }
        }
        if (-not $ModuleInfo) {
            throw ([System.ArgumentException]"$inputData module could not be found, please try passing the output of 'Get-Module $InputData' instead")
        }
        return $ModuleInfo
    }
}
#>
function Clear-CCMClientCache {
    [cmdletbinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 0,
            Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [PSCredential]$Credential
    )

    Begin
    {
        $invokeParam = @{
            ScriptBlock = {
                $CMObject = new-object -com "UIResource.UIResourceMgr"
                $cacheInfo = $CMObject.GetCacheInfo()
                $objects = $cacheinfo.GetCacheElements()
                Write-Verbose ( "Removing {0:N2}gb of CCM Cache Files" -f (($objects | Measure-Object -Property contentsize -Sum).sum/1mb) )
                $objects | ForEach-Object {
                    $cacheInfo.DeleteCacheElement($_.CacheElementId)
                }
            }
        }

        $computerList = [System.Collections.Generic.List[String]]::new()

        if ($Credential){
            $invokeParam['Credential'] = $Credential
        }
    }

    Process {
        $computerList.AddRange([string[]]$ComputerName)
    }

    End {
        Invoke-Command @invokeParam -ComputerName $computerList
    }
}
function ConvertTo-CCMClientCimCredential {
   <#
   .Synopsis
      Short description
   .DESCRIPTION
      Long description
   .EXAMPLE
      Example of how to use this cmdlet
   .EXAMPLE
      Another example of how to use this cmdlet
   .INPUTS
      Inputs to this cmdlet (if any)
   .OUTPUTS
      Output from this cmdlet (if any)
   .NOTES
      General notes
   .COMPONENT
      The component this cmdlet belongs to
   .ROLE
      The role this cmdlet belongs to
   .FUNCTIONALITY
      The functionality that best describes this cmdlet
   #>
   
   [CmdletBinding()]
   [Alias()]
   [OutputType([Microsoft.Management.Infrastructure.Options.CimCredential])]
   Param
   (
       [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
       [PSCredential]$Credential
   )
       
   process {        
       $domain = $Credential.UserName -replace '.+@|\\.+'
       $UserName = $Credential.UserName -replace '.+\\|@.+'
       [Microsoft.Management.Infrastructure.Options.CimCredential]::new('Default', $domain, $UserName, $Credential.Password)        
   }
}
function Get-CCMClientComplianceSettings {
    [cmdletbinding(DefaultParameterSetName = 'ComputerName')]

    param (
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 0)]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            ParameterSetName = 'CimSession',
            Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimSession[]]$CimSession
    )

    Begin {
        $cimParam = @{
            NameSpace = 'root\ccm\dcm'
            ClassName = 'SMS_DesiredConfiguration'
        }
    }

    Process {
        Switch ($PSCmdlet.ParameterSetName) {
            'ComputerName' {
                $cimParam['ComputerName'] = $ComputerName
            }

            'CimSession' {
                $cimParam['CimSession'] = $CimSession
            }
        }
        Get-CimInstance @cimParam
    }
}
function Get-CCMClientExecutionRequest {
    param (

        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 0,
            Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [PSCredential]$Credential

    )

    Begin
    {}

    Process {
        if (-not $CimSession) {

            try {
                $CimSession = Get-CimSession -ComputerName $ComputerName -ErrorAction Stop
            }
            catch {

                $cimParm = @{
                    ComputerName = $ComputerName
                }
                if ($Credential) {
                    $cimParm['Credential'] = $Credential
                }

                $CimSession = New-CimSession @cimParm -ErrorAction Stop
            }

        }

        $cimParm = @{
            OutVariable = 'update'
            NameSpace   = 'root\ccm\SoftMgmtAgent'
            ClassName   = 'CCM_ExecutionRequestEx'
            CimSession  = $CimSession
        }

        Get-CimInstance @cimParm | ForEach-Object { $PSItem.PSObject.TypeNames.Insert(0, 'Microsoft.Management.Infrastructure.CimInstance.CCM_ExecutionRequestEx') ; $PSItem }

    }
}
function Get-CCMClientSoftwareUpdate {
    [cmdletbinding()]
    param (

        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 0,
            Mandatory = $true)]
        [alias('Name')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'CimSession')]
        [CimSession[]]$CimSession
    )

    begin {
        $cimParam = @{
            NameSpace = 'root/ccm/ClientSDK'
            ClassName = 'CCM_SoftwareUpdate'
        }
    }

    process {
        Switch ($PSCmdlet.ParameterSetName) {
            'ComputerName' {
                $cimParam['ComputerName'] = $ComputerName
            }

            'CimSession' {
                $cimParam['CimSession'] = $CimSession
            }
        }

        Get-CimInstance @cimParam
    }
    end {}
}
Function Install-CCMClientSoftwareUpdate {
    [cmdletbinding()]
    [alias('Install-CCMClientSoftwareUpdates')]
    param (

        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 1,
            Mandatory = $true)]
        #[alias('Name')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [PSCredential]$Credential
    )

    begin {}

    process {
        foreach ($a_ComputerName in $ComputerName){
            $cimSessionParam = @{
                ComputerName = $a_ComputerName
            }
            if ($Credential){
                $cimSessionParam['Credential'] = $Credential
            }

            $cimParam = @{
                CimSession = New-CCMClientCimSession @cimSessionParam
                NameSpace = 'root/ccm/clientsdk'
            }

            $updates = Get-CimInstance @cimParam -ClassName CCM_SoftwareUpdate

            $updates |
                Select-Object PSComputerName,ArticleID,Name |
                    Out-String |
                        Write-Verbose -Verbose

            $null = Invoke-CimMethod @cimParam -ClassName CCM_SoftwareUpdatesManager -MethodName InstallUpdates -Arguments @{ CCMUpdates = [ciminstance[]]$updates }

            $updates | Get-CimInstance
        }
    }
    end {}
}
Function Invoke-CCMClientPackageRerun
{
    [cmdletbinding()]

    param(
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential
    )

    Begin
    {
        $rerunSB = {
        
            Get-CimInstance -ClassName CCM_SoftwareDistribution -namespace root\ccm\policy\machine/ActualConfig -OutVariable Advertisements | Set-CimInstance -Property @{ 
                ADV_RepeatRunBehavior = 'RerunAlways'
                ADV_MandatoryAssignments = $True
            }

            foreach ($a_Advertisement in $Advertisements)
            {
                Write-Verbose -Message "Searching for schedule for package: $() - $($a_Advertisement.PKG_Name)"
                Get-CimInstance -ClassName CCM_Scheduler_ScheduledMessage -namespace "ROOT\ccm\policy\machine\actualconfig" -filter "ScheduledMessageID LIKE '$($a_Advertisement.ADV_AdvertisementID)%'" | 
                    ForEach-Object {

                        $null = Invoke-CimMethod -Namespace 'root\ccm' -ClassName SMS_CLIENT -MethodName TriggerSchedule @{ sScheduleID = $PSItem.ScheduledMessageID }

                        [pscustomobject]@{
                            PKG_Name = $a_Advertisement.PKG_Name
                            ADV_AdvertisementID = $a_Advertisement.ADV_AdvertisementID
                            sScheduleID = $PSItem.ScheduledMessageID
                        }
                    }
            }
            
        }

        $ComputerList = [System.Collections.Generic.List[string]]::new()
    }

    Process
    {
        $ComputerList.AddRange( ([string[]]$ComputerName) )
    }

    End
    {
        $invokeParm = @{
                ScriptBlock = $rerunSB                
        }

        $invokeParm['ComputerName'] = $ComputerList
        
        if ($Credential){
            $invokeParm['Credential'] = $Credential
        }

        if ($ComputerName -eq $env:COMPUTERNAME)
        {
            $invokeParm.Remove('Credential')
            $invokeParm.Remove('ComputerName')
        }

        $invokeParm | Out-String | Write-Verbose

        Invoke-Command @invokeParm
    }

}
function Invoke-CCMClientComplianceSettingsEvaluation {
    [cmdletbinding()]

    param (
        [Parameter(ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0,
            Mandatory
        )]
        [Microsoft.Management.Infrastructure.CimInstance[]]$CimInstance
    )

    process {
        foreach ($obj in $CimInstance) {
            Invoke-CimMethod -InputObject $obj -MethodName TriggerEvaluation -Arguments @{ Name = $obj.Name; version = $obj.Version }
        }
    }

}
Function Invoke-CCMClientScheduleUpdate
{
    [cmdletbinding()]
    param (
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 1,
            Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [PSCredential]$Credential
    )
    Begin
    {
        $taskHash = @{
            '{00000000-0000-0000-0000-000000000001}' = 'Hardware Inventory'
            '{00000000-0000-0000-0000-000000000002}' = 'Software Inventory '
            '{00000000-0000-0000-0000-000000000003}' = 'Discovery Inventory '
            '{00000000-0000-0000-0000-000000000010}' = 'File Collection '
            '{00000000-0000-0000-0000-000000000011}' = 'IDMIF Collection '
            '{00000000-0000-0000-0000-000000000012}' = 'Client Machine Authentication '
            '{00000000-0000-0000-0000-000000000021}' = 'Request Machine Assignments '
            '{00000000-0000-0000-0000-000000000022}' = 'Evaluate Machine Policies '
            '{00000000-0000-0000-0000-000000000023}' = 'Refresh Default MP Task '
            '{00000000-0000-0000-0000-000000000024}' = 'LS (Location Service) Refresh Locations Task '
            '{00000000-0000-0000-0000-000000000025}' = 'LS (Location Service) Timeout Refresh Task '
            '{00000000-0000-0000-0000-000000000026}' = 'Policy Agent Request Assignment (User) '
            '{00000000-0000-0000-0000-000000000027}' = 'Policy Agent Evaluate Assignment (User) '
            '{00000000-0000-0000-0000-000000000031}' = 'Software Metering Generating Usage Report '
            '{00000000-0000-0000-0000-000000000032}' = 'Source Update Message'
            '{00000000-0000-0000-0000-000000000037}' = 'Clearing proxy settings cache '
            '{00000000-0000-0000-0000-000000000040}' = 'Machine Policy Agent Cleanup '
            '{00000000-0000-0000-0000-000000000041}' = 'User Policy Agent Cleanup'
            '{00000000-0000-0000-0000-000000000042}' = 'Policy Agent Validate Machine Policy / Assignment '
            '{00000000-0000-0000-0000-000000000043}' = 'Policy Agent Validate User Policy / Assignment '
            '{00000000-0000-0000-0000-000000000051}' = 'Retrying/Refreshing certificates in AD on MP '
            '{00000000-0000-0000-0000-000000000061}' = 'Peer DP Status reporting '
            '{00000000-0000-0000-0000-000000000062}' = 'Peer DP Pending package check schedule '
            '{00000000-0000-0000-0000-000000000063}' = 'SUM Updates install schedule '
            '{00000000-0000-0000-0000-000000000071}' = 'NAP action '
            '{00000000-0000-0000-0000-000000000101}' = 'Hardware Inventory Collection Cycle '
            '{00000000-0000-0000-0000-000000000102}' = 'Software Inventory Collection Cycle '
            '{00000000-0000-0000-0000-000000000103}' = 'Discovery Data Collection Cycle '
            '{00000000-0000-0000-0000-000000000104}' = 'File Collection Cycle '
            '{00000000-0000-0000-0000-000000000105}' = 'IDMIF Collection Cycle '
            '{00000000-0000-0000-0000-000000000106}' = 'Software Metering Usage Report Cycle '
            '{00000000-0000-0000-0000-000000000107}' = 'Windows Installer Source List Update Cycle '
            '{00000000-0000-0000-0000-000000000108}' = 'Software Updates Assignments Evaluation Cycle '
            '{00000000-0000-0000-0000-000000000109}' = 'Branch Distribution Point Maintenance Task '
            '{00000000-0000-0000-0000-000000000110}' = 'DCM policy '
            '{00000000-0000-0000-0000-000000000111}' = 'Send Unsent State Message '
            '{00000000-0000-0000-0000-000000000112}' = 'State System policy cache cleanout '
            '{00000000-0000-0000-0000-000000000113}' = 'Scan by Update Source '
            '{00000000-0000-0000-0000-000000000114}' = 'Update Store Policy '
            '{00000000-0000-0000-0000-000000000115}' = 'State system policy bulk send high'
            '{00000000-0000-0000-0000-000000000116}' = 'State system policy bulk send low '
            '{00000000-0000-0000-0000-000000000120}' = 'AMT Status Check Policy '
            '{00000000-0000-0000-0000-000000000121}' = 'Application manager policy action '
            '{00000000-0000-0000-0000-000000000122}' = 'Application manager user policy action'
            '{00000000-0000-0000-0000-000000000123}' = 'Application manager global evaluation action '
            '{00000000-0000-0000-0000-000000000131}' = 'Power management start summarizer'
            '{00000000-0000-0000-0000-000000000221}' = 'Endpoint deployment reevaluate '
            '{00000000-0000-0000-0000-000000000222}' = 'Endpoint AM policy reevaluate '
            '{00000000-0000-0000-0000-000000000223}' = 'External event detection'

        }
    }
        
    Process
    {
        $cimSession = New-CCMClientCimSession @PSBoundParameters

        $cimParam = @{
            Namespace = 'root/ccm'
            Class = 'SMS_CLIENT'
            MethodName = 'TriggerSchedule'
            CimSession = $cimSession
        }
        $taskHash.Keys | ForEach-Object {
            Write-Verbose $PSItem
            try {$null = Invoke-CimMethod @cimParam -Arguments @{ sScheduleID = $PSItem } -ErrorAction Stop }
            catch {$PSItem}
        }
    }

}
Function Invoke-CCMCollectionRefresh {

    [cmdletbinding()]

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [CimInstance[]]$Collection,
        [switch]$Wait
    )

    Begin {}

    Process {
        foreach ($obj in $Collection) {
            $time = $obj.LastRefreshTime

            $null = $obj | Invoke-CimMethod -MethodName RequestRefresh

            '{0}: Collection "{1}" updated {2}' -f $MyInvocation.InvocationName, $obj.name, $obj.LastRefreshTime | Write-Verbose

            $obj = $obj | Get-CimInstance

            $x = $null

            While ( $Wait -and $obj.LastRefreshTime -eq $time -and $x -le 6000 ) {

                $x++
                Write-Progress -Activity 'Waiting for Collection Refresh' -Status "Collection $($obj.Name)"
                if ( ($x % 30) -eq 0 ) {
                    '{0}: waiting for "{1}", {2} seconds elapsed' -f $MyInvocation.InvocationName, $obj.Name, $x |
                        Write-Verbose
                }

                Start-Sleep -Seconds 1
                $obj = $obj | Get-CimInstance
            }

            '{0}: Collection "{1}" updated {2}' -f $MyInvocation.InvocationName, $obj.name, $obj.LastRefreshTime |
                Write-Verbose

            $obj

        }
    }

}
<#This function should be moved to the CCM client module
 
Function Invoke-CCMPackageRerun
{
    [cmdletbinding()]
 
    param(
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential
    )
 
    Begin
    {
        $rerunSB = {
 
            Get-CimInstance -ClassName CCM_SoftwareDistribution -namespace root\ccm\policy\machine/ActualConfig -OutVariable Advertisements | Set-CimInstance -Property @{
                ADV_RepeatRunBehavior = 'RerunAlways'
                ADV_MandatoryAssignments = $True
            }
 
            foreach ($a_Advertisement in $Advertisements)
            {
                Write-Verbose -Message "Searching for schedule for package: $() - $($a_Advertisement.PKG_Name)"
                Get-CimInstance -ClassName CCM_Scheduler_ScheduledMessage -namespace "ROOT\ccm\policy\machine\actualconfig" -filter "ScheduledMessageID LIKE '$($a_Advertisement.ADV_AdvertisementID)%'" |
                    ForEach-Object {
 
                        $null = Invoke-CimMethod -Namespace 'root\ccm' -ClassName SMS_CLIENT -MethodName TriggerSchedule @{ sScheduleID = $PSItem.ScheduledMessageID }
 
                        [pscustomobject]@{
                            PKG_Name = $a_Advertisement.PKG_Name
                            ADV_AdvertisementID = $a_Advertisement.ADV_AdvertisementID
                            sScheduleID = $PSItem.ScheduledMessageID
                        }
                    }
            }
 
        }
 
        $ComputerList = [System.Collections.Generic.List[string]]::new()
    }
 
    Process
    {
        $ComputerList.AddRange( ([string[]]$ComputerName) )
    }
 
    End
    {
        $invokeParm = @{
                ScriptBlock = $rerunSB
        }
 
        $invokeParm['ComputerName'] = $ComputerList
 
        if ($Credential){
            $invokeParm['Credential'] = $Credential
        }
 
        if ($ComputerName -eq $env:COMPUTERNAME)
        {
            $invokeParm.Remove('Credential')
            $invokeParm.Remove('ComputerName')
        }
 
        $invokeParm | Out-String | Write-Verbose
 
        Invoke-Command @invokeParm
    }
 
}
 
#https://kelleymd.wordpress.com/2015/02/08/run-local-advertisement-with-triggerschedule/
#>
function New-CCMClientCimSession {
   <#
.Synopsis
  Short description
.DESCRIPTION
  Long description
.EXAMPLE
  Example of how to use this cmdlet
.EXAMPLE
  Another example of how to use this cmdlet
.INPUTS
  Inputs to this cmdlet (if any)
.OUTPUTS
  Output from this cmdlet (if any)
.NOTES
  General notes
.COMPONENT
  The component this cmdlet belongs to
.ROLE
  The role this cmdlet belongs to
.FUNCTIONALITY
  The functionality that best describes this cmdlet
#>

   [CmdletBinding()]
   [Alias()]
   [OutputType([CimSession])]
   Param
   (
       [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
       $ComputerName,

       [Parameter()]
       [PSCredential]$Credential
   )

   Begin {
      $option = [Microsoft.Management.Infrastructure.Options.DComSessionOptions]::new()
      if ($Credential) {
         $option.AddDestinationCredentials( (ConvertTo-CCMClientCimCredential -Credential $Credential) )
      }
   }
   Process {
       ForEach ($a_ComputerName in $ComputerName) {
         [Microsoft.Management.Infrastructure.CimSession]::Create($a_ComputerName,$option)
       }
   }
   End {
   }
}
Function New-CCMCollection
{
    [cmdletbinding()]
    [Alias('New-SMS_Collection')]

    param(
        [Parameter(Mandatory)]
        [Alias('CollectionName')]
        [string]$Name,

        [ccm.CollectionType]$CollectionType,

        [Parameter(Mandatory,ParameterSetName='CollectionID')]
        [string]$LimitToCollectionID,

        [Parameter(Mandatory,ParameterSetName='Collection')]
        [ValidateScript({$PSItem.CimClass.CimClassName -eq 'SMS_Collection'})]
        [ciminstance]$LimitToCollection
    )

    Begin
    {
        $cimHash = $sbCCMGetCimParm.InvokeReturnAsIs()
    }

    Process
    {
        $newCollectionProperty = @{
            Name = $Name
            CollectionType = [int]$CollectionType
            LimitToCollectionID = $LimitToCollectionID
        }
        if ($LimitToCollection)
        {
            $newCollectionProperty['LimitToCollectionID'] = $LimitToCollection.CollectionID
        }

        $newCollectionProperty | Out-String | Write-Verbose

        New-CimInstance -OutVariable newCollection @cimHash -ClassName SMS_Collection -Property $newCollectionProperty
    }
}
function Wait-CCMClientSoftwareUpdate {
    [cmdletbinding()]
    param (
        [Alias('Wait-CCMClientSoftwareUpdateInstallation')]
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'ComputerName',
            Position = 0,
            Mandatory = $true)]
        [alias('Name')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [PSCredential]$Credential,

        [Parameter(ParameterSetName = 'CimSession')]
        [CimSession[]]$CimSession,

        [switch]$Quiet,

        [int]$Interval = 5
    )

    begin {
        $cimParam = @{
            NameSpace = 'root/ccm/ClientSDK'
            ClassName = 'CCM_SoftwareUpdate'
            Filter = 'EvaluationState < 8'
        }
    }
    process {
        Switch ($PSCmdlet.ParameterSetName) {
            'ComputerName' {
                $cimParam['ComputerName'] = $ComputerName

                if ($Credential) {
                    $cimParam['Credential'] = $Credential
                }
            }

            'CimSession' {
                $cimParam['CimSession'] = $CimSession
            }
        }

        While (($updates = Get-CimInstance @cimParam)) {
            $updates | ForEach-Object {
                Write-Progress -Activity 'Waiting for patch installation' -CurrentOperation $PSItem.PSComputerName -Status ('{0}: {1}' -f [CCM.EvaluationState]$PSItem.EvaluationState,$PSItem.Name)
            }
            if (-not $Quiet.IsPresent){
                $updates | Out-String | Write-Host -ForegroundColor Green
            }
            Start-Sleep -Seconds $Interval
        }
    }
    end {}
}