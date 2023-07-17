
function Test-Module {
    [cmdletbinding()]
    param()
    write-Host "Test Successful"
}

function Add-GroupMemberships {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]$group,
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]$TMID
    )
    
    process {
        $creds = Get-Credential
        try {
            $GroupObject = Get-ADGroup -Filter "Name -eq '$group'"
            $UserObject = Get-ADUser -Filter "EmployeeID -eq '$TMID'"

            if(!$GroupObject) {
                throw "$group invalid"
            }
            if(!$UserObject) {
                throw "$TMID invalid"
            } elseif($GroupObject -and $UserObject) {
                Write-Host "Adding $($UserObject.SamAccountName) to $($GroupObect.Name)" 
                Add-AdGroupMember -Identity $GroupObject.SamAccountName -Members $UserObject.SamAccountName -Credential $creds
                Write-Output "Added $($UserObject.SamAccountName) to $($GroupObject.Name) successfully"
            }     
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Error $errorMessage
        }
    }  
}

function Remove-GroupMemberships {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]$group,
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]$TMID
    )
    
    process {
        $creds = Get-Credential
        try {
            $GroupObject = Get-ADGroup -Filter "Name -eq '$group'"
            $UserObject = Get-ADUser -Filter "EmployeeID -eq '$TMID'"

            if(!$GroupObject) {
                throw "$group invalid"
            }
            if(!$UserObject) {
                throw "$TMID invalid"
            } elseif($GroupObject -and $UserObject) {
                Write-Host "Removing $($UserObject.SamAccountName) from $($GroupObect.Name)" 
                Remove-AdGroupMember -Identity $GroupObject.SamAccountName -Members $UserObject.SamAccountName -Credential $creds
                Write-Output "Removed $($UserObject.SamAccountName) from $($GroupObject.Name) successfully"
            }     
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Error $errorMessage
        }
    }  
}

function Invoke-ModifyGroupsFromCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$CSVFILE
    )
    
    process {
        $creds = Get-Credential
        try {
            $csvData = Import-CSV -Path $CSVFILE
        }
        catch {
            throw "Failed to import CSV file: $CSVFILE"
        }

        $invalidActions = @()
        foreach ($row in $csvData) {
            try {
                $user = Get-ADUser -Filter "EmployeeID -eq '$($row.TMID.trim())'" -ErrorAction Stop
                $group = Get-ADGroup -Filter "Name -eq '$($row.GroupName.trim())'" -ErrorAction Stop

                if (!$user) {
                    throw "User $($row.TMID) not found"
                }
                if (!$group) {
                    throw "Group $($row.GroupName) not found"
                }

                $validAction = [PSCustomObject]@{
                    GroupName = $row.GroupName.trim()
                    TMID = $row.TMID.trim()
                    User = $user.SamAccountName
                    Group = $group.SamAccountName
                    Action = $row.Action.trim()
                }

                if ($user -and $group) {
                    switch ($validAction.Action) {
                        "Add" {
                            Write-Host "Adding $($validAction.User) to $($validAction.Group)"
                            $parameters = @{
                                Identity = $validAction.Group
                                Members = $validAction.User
                            }
                            Add-ADGroupMember @parameters -Credential $creds
                            Write-Output "Added $($validAction.User) to $($validAction.Group) successfully" 
                        }
                        "Remove" {
                            Write-Host "Removing $($validAction.User) from $($validAction.Group)"
                            $parameters = @{
                                Identity = $validAction.Group
                                Members = $validAction.User
                                Confirm = $false
                            }
                            Remove-ADGroupMember @parameters -credential $creds
                            Write-Output "Removed $($validAction.User) from $($validAction.Group) successfully" 
                        }
                        default {
                            throw "Invalid action: $($validAction.Action)"
                        }
                    }
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error $errorMessage
                $invalidActions += $validAction
                continue
            }
        }
        
        if ($invalidActions.Count -eq 0) {
            Write-Host "Script Completed Successfully with no errors" -ForegroundColor Green
        }
        else {
            Write-Host "Script Completed" -ForegroundColor Green
            Write-Warning "The following actions were unsuccessful:"
            $invalidActions | Format-Table
        }
    }
}

function Remove-Accounts {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]
        $DeviceName
    )
    
    process {
        Invoke-Command -ComputerName $DeviceName {
            #variable for system accounts (which should never be deleted)
            $systemaccounts = @('administrator', 'Public', 'default', 'DOMAIN\administrator', 'NetworkService', 'LocalService', 'systemprofile') 

            #variable for user profiles (excluding any system profiles)
            $onharddrive = Get-CimInstance win32_userprofile | Where-Object { $_.LocalPath.split('\')[-1] -notin $systemaccounts }

            #Run the command stored in $onharddrive and send each object down the pipeline through the scriptblock
            $onharddrive | ForEach-Object {
                
                ##Within the loop save profile to a variable called p##
                $p = $_

                ##Try the following
                try {
                    #create a new object for SID and set error action preference to stop so that the catch block is triggered
                    $pSID = New-Object System.Security.Principal.SecurityIdentifier($p.SID) -ErrorAction Stop

                    ##Translate the SID we just created for each profile to NTAccountName
                    $pSID.Translate([System.Security.Principal.NTAccount]) | Out-Null

                    ##create a PSCustom Object called user with attributes of AccountName, Path, and Localpath
                    $knownuser = [PSCustomObject]@{
                        AccountName = $ntAccount.Value
                        Path        = $p.LocalPath
                        SID         = $p.SID
                    } 
                }
                ##Catch exceptions thrown when the script attempts to translate the SID to the NTAccount Name
                catch {
                    $unknownuser = [PSCustomObject]@{
                        AccountName = "Unknown"
                        Path        = $p.LocalPath
                        SID         = $p.SID
                    }
                    ##Save these results to a variable called UnknownAccounts##
                    Write-Host "Removing Account $($p.LocalPath)" 
                    Remove-CimInstance -InputObject $p 
                    Write-Output "Account $($p.LocalPath) removed successfully..."
                }
            } 
        } 
    }
}