[CmdletBinding()]
param()
<#
	.SYNOPSIS
    Run all SQL Scripts in folder in SQLCMD mode, passing in an array of SQLCMD variables if supplied.

    .DESCRIPTION
    Run all SQL Scripts in folder in SQLCMD mode, passing in an array of SQLCMD variables if supplied.

    .NOTES
    Script written by (c) Dr. John Tunnicliffe, 2019 https://github.com/DrJohnT/AzureDevOpsExtensionsForSqlServer/tree/master/extensions/RunSqlCmdScripts
	This PowerShell script is released under the MIT license http://www.opensource.org/licenses/MIT
#>
    [string]$SqlCmdSciptFolderPath = Get-VstsInput -Name SqlCmdSciptFolderPath -Require;
    [string]$Server = Get-VstsInput -Name  Server -Require;
    [string]$Database = Get-VstsInput -Name Database -Require;
    [string]$SqlCmdVariableType = Get-VstsInput -Name SqlCmdVariableType;
    [string]$SqlCmdVariablesInJson = Get-VstsInput -Name SqlCmdVariablesInJson;
    [string]$SqlCmdVariablesInText = Get-VstsInput -Name SqlCmdVariablesInText;
    [string]$QueryTimeout = Get-VstsInput -Name QueryTimeout;
    [string]$Recursive = Get-VstsInput -Name Recursive;

    $global:ErrorActionPreference = 'Stop';

    if ($env:Processor_Architecture -eq 'x86') {
        Write-Error "The SQLSERVER PowerShell module will not run correctly in when the processor architecture = x86. Please use a 64-bit Azure DevOps agent. See https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops";
        exit 1;
    }

    Trace-VstsEnteringInvocation $MyInvocation;

    try {
        if (Test-Path -Path $SqlCmdSciptFolderPath)
        {
            Write-Host "==============================================================================";
            Write-Host "Calling Invoke-SqlCmd with the following parameters:";
            Write-Host "Server:                $Server";
            Write-Host "Database:              $Database";
            Write-Host "SqlCmdSciptFolderPath: $SqlCmdSciptFolderPath";
            Write-Host "Recursive:             $Recursive";
            Write-Host "SqlCmdVariableType:    $SqlCmdVariableType";
            Write-Host "Username:              $Username";

            [string[]]$SqlCmdVariables = @();
            switch ($SqlCmdVariableType) {
                'json' {
                    $jsonVariables = ConvertFrom-Json -InputObject $SqlCmdVariablesInJson;
                    $jsonVariables.PSObject.Properties | ForEach-Object {
                        $Name = $_.Name;
                        $Value = $_.Value;
                        $SqlCmdVariables += "$Name=$Value";
                    }
                }
                'text' {
                    $SqlCmdVariables = $SqlCmdVariablesInText -split "`n" | ForEach-Object { $_.trim() }
                }
            }

            if ($SqlCmdVariableType -ne 'none') {
                Write-Host "SqlCmdVariables:";
                foreach ($SqlCmdVariable in $SqlCmdVariables) {
                    Write-Host "                       $SqlCmdVariable";
                }
            }

            # ensure SqlServer module is installed
            $Name = 'SqlServer';
            if (!(Get-Module -ListAvailable -Name $Name)) {
                # if module is not installed
                Write-Output "Installing PowerShell module $Name for current user"
                Install-PackageProvider -Name NuGet -Force -Scope CurrentUser;
                Install-Module -Name $Name -Force -AllowClobber -Scope CurrentUser -Repository PSGallery -SkipPublisherCheck;
            }

            if (-not (Get-Module -Name $Name)) {
                # if module is not loaded
                Import-Module -Name $Name -DisableNameChecking;
            }


            Write-Host "SQLCMD folder:         $SqlCmdSciptFolderPath";
            if ($Recursive -eq 'true') {
                $SqlCmdFiles = Get-ChildItem -Path $SqlCmdSciptFolderPath -Recurse -Include *.sql;
            } else {
                $SqlCmdFiles = Get-ChildItem -Path "$SqlCmdSciptFolderPath\*" -Include *.sql;
            }

            # Now Invoke-Sqlcmd for each script in the folder
            foreach ($SqlCmdFile in $SqlCmdFiles) {
                Write-Host "Running SQLCMD file:   $(Split-Path -Leaf $SqlCmdFile)";

                $Command = "Invoke-Sqlcmd -Server $Server -Database $Database -InputFile '$SqlCmdFile' -ErrorAction Stop";
                if ("$QueryTimeout" -ne "") {
                    $Command += " -QueryTimeout $QueryTimeout";
                }
                if ("$Username" -ne "") {
                    $Command += " -Username '$Username' -Password '$Password'";
                }	
                if ($SqlCmdVariableType -ne 'none') {
                    #$Command += " -Variable '$SqlCmdVariables'";
                    $Command += ' -Variable $SqlCmdVariables';
                    Write-Host $Command;
                    $scriptBlock = [Scriptblock]::Create($Command);
                    Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $SqlCmdVariables;
                } else {
                    Write-Host $Command;            
                    $scriptBlock = [Scriptblock]::Create($Command);
                    Invoke-Command -ScriptBlock $scriptBlock;
                }

            }

            Write-Host "==============================================================================";
        } else {
            Write-Error "SQL Scripts Folder does not exist: $SqlCmdSciptFolderPath";
            exit 1;
        }
    } catch {
        Write-Error $_;
        exit 1;
    } finally {
        Trace-VstsLeavingInvocation $MyInvocation
    }




