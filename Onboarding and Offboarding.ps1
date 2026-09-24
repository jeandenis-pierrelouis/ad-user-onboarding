<#
.SYNOPSIS
    Employee onboarding and offboarding for an Active Directory lab domain.

.DESCRIPTION
    Start menu: choose Onboarding or Offboarding.

    ONBOARDING
    - Creates the department security groups if they don't exist yet
    - Prompts for first name, last name, department, and a temporary password
    - Builds the username as firstname.lastname (adds a number if it's already taken)
    - Creates the AD user and adds them to the department's security group

    OFFBOARDING
    - Creates an Offboarding OU if it doesn't exist yet
    - Prompts for a username and shows the user's first name, last name, and
      department so you can confirm it's the right person
    - Resets the password to a temporary one, disables the account,
      removes the user from their security groups, and moves them to the Offboarding OU
#>

[CmdletBinding()]
param(
    [string]$UserOU,
    [string]$OffboardingOUName = 'Offboarding'
)

# ---------------------------------------------------------------------------
# Department > security group mapping
# ---------------------------------------------------------------------------
$Departments = [ordered]@{
    '1' = @{ Name = 'Accounting';       Group = 'SG_Accounting' }
    '2' = @{ Name = 'ServiceDesk';      Group = 'SG_ServiceDesk' }
    '3' = @{ Name = 'HR';               Group = 'SG_HR' }
    '4' = @{ Name = 'Support Services'; Group = 'SG_SupportServices' }
}

# Accounts that should never be offboarded from this script
$ProtectedAccounts = @('Administrator', 'Guest', 'krbtgt')

# ===========================================================================
# Shared helpers
# ===========================================================================
function Read-ConfirmedPassword {
    param([string]$Prompt = 'Temporary password')

    while ($true) {
        $p1 = Read-Host $Prompt -AsSecureString
        $p2 = Read-Host "Confirm password" -AsSecureString

        $plain1 = [System.Net.NetworkCredential]::new('', $p1).Password
        $plain2 = [System.Net.NetworkCredential]::new('', $p2).Password

        if ($plain1 -eq $plain2 -and $plain1.Length -gt 0) {
            return $p1
        }
        Write-Host "  Passwords didn't match. Try again." -ForegroundColor Yellow
    }
}

# ===========================================================================
# Onboarding
# ===========================================================================
function Initialize-DepartmentGroups {
    foreach ($dept in $Departments.Values) {
        if (-not (Get-ADGroup -Filter "Name -eq '$($dept.Group)'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $dept.Group `
                        -GroupScope Global `
                        -GroupCategory Security `
                        -Description "File access for the $($dept.Name) department" `
                        -ErrorAction Stop
            Write-Host "Created group: $($dept.Group)" -ForegroundColor Green
        }
        else {
            Write-Verbose "Group already exists: $($dept.Group)"
        }
    }
}

function Read-ValidatedName {
    param([string]$Prompt)

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        # Letters plus spaces, hyphens, and apostrophes (e.g. Jolly Crew)
        if ($value -match "^[A-Za-z][A-Za-z '\-]*$") {
            return $value
        }
        Write-Host "  Please use letters only (spaces, hyphens, and apostrophes are OK)." -ForegroundColor Yellow
    }
}

function Read-DepartmentChoice {
    Write-Host "`nDepartments:"
    foreach ($key in $Departments.Keys) {
        Write-Host "  [$key] $($Departments[$key].Name)"
    }

    while ($true) {
        $choice = (Read-Host "Select department (number)").Trim()
        if ($Departments.Contains($choice)) {
            return $Departments[$choice]
        }
        Write-Host "  Enter a number from the list." -ForegroundColor Yellow
    }
}

function Get-UniqueUsername {
    param(
        [string]$FirstName,
        [string]$LastName
    )

    # firstname.lastname, lowercase, letters only in each part
    $first = ($FirstName -replace '[^A-Za-z]', '').ToLower()
    $last  = ($LastName  -replace '[^A-Za-z]', '').ToLower()
    $base  = "$first.$last"

    # SamAccountName is limited to 20 characters
    if ($base.Length -gt 20) { $base = $base.Substring(0, 20) }

    $candidate = $base
    $suffix    = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $suffix++
        $trimmed   = $base.Substring(0, [Math]::Min($base.Length, 20 - "$suffix".Length))
        $candidate = "$trimmed$suffix"
    }

    [pscustomobject]@{
        SamAccountName = $candidate
        Suffix         = if ($suffix -gt 1) { $suffix } else { $null }
    }
}

function Invoke-Onboarding {
    $firstName  = Read-ValidatedName "First name"
    $lastName   = Read-ValidatedName "Last name"
    $dept       = Read-DepartmentChoice
    $securePass = Read-ConfirmedPassword

    $username = Get-UniqueUsername -FirstName $firstName -LastName $lastName
    $sam      = $username.SamAccountName

    # Full name (CN) must be unique within the OU, so add the suffix if needed
    $fullName = "$firstName $lastName"
    if ($username.Suffix) { $fullName = "$fullName $($username.Suffix)" }

    $upnSuffix = (Get-ADDomain).DNSRoot

    Write-Host "`nAbout to create:" -ForegroundColor Cyan
    Write-Host "  Name       : $fullName"
    Write-Host "  Username   : $sam"
    Write-Host "  Department : $($dept.Name)"
    Write-Host "  Group      : $($dept.Group)"
    if ((Read-Host "Proceed? (Y/N)") -notmatch '^[Yy]') {
        Write-Host "Skipped." -ForegroundColor Yellow
        return
    }

    $newUserParams = @{
        Name                  = $fullName
        GivenName             = $firstName
        Surname               = $lastName
        DisplayName           = $fullName
        SamAccountName        = $sam
        UserPrincipalName     = "$sam@$upnSuffix"
        Department            = $dept.Name
        AccountPassword       = $securePass
        Enabled               = $true
        ChangePasswordAtLogon = $true
        ErrorAction           = 'Stop'
    }
    if ($UserOU) { $newUserParams.Path = $UserOU }

    try {
        New-ADUser @newUserParams
        Write-Host "User created: $sam" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not create user: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try {
        Add-ADGroupMember -Identity $dept.Group -Members $sam -ErrorAction Stop
        Write-Host "Added $sam to $($dept.Group)" -ForegroundColor Green
    }
    catch {
        Write-Host "User was created, but adding to $($dept.Group) failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "Sign-in: $upnSuffix\$sam  (password change required at first logon)`n" -ForegroundColor Cyan
}

function Start-Onboarding {
    Write-Host "`n--- Onboarding ---" -ForegroundColor Cyan

    try {
        Initialize-DepartmentGroups
    }
    catch {
        Write-Host "Failed to prepare department groups: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    do {
        Invoke-Onboarding
        $again = Read-Host "Onboard another user? (Y/N)"
    } while ($again -match '^[Yy]')
}

# ===========================================================================
# Offboarding
# ===========================================================================
function Initialize-OffboardingOU {
    # Creates the Offboarding OU at the domain root if it's missing and returns its DN
    $domainDN = (Get-ADDomain).DistinguishedName
    $ouDN     = "OU=$OffboardingOUName,$domainDN"

    try {
        Get-ADOrganizationalUnit -Identity $ouDN -ErrorAction Stop | Out-Null
        Write-Verbose "Offboarding OU already exists: $ouDN"
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        New-ADOrganizationalUnit -Name $OffboardingOUName `
                                 -Path $domainDN `
                                 -Description "Disabled accounts of offboarded employees" `
                                 -ErrorAction Stop
        Write-Host "Created OU: $ouDN" -ForegroundColor Green
    }

    return $ouDN
}

function Read-OffboardingTarget {
    # Prompts for a username, shows who it is, and asks for confirmation.
    # Returns the AD user object, or $null if the person cancels.
    while ($true) {
        $sam = (Read-Host "`nUsername to offboard (blank to cancel)").Trim()
        if (-not $sam) { return $null }

        if ($sam -notmatch '^[A-Za-z0-9._-]{1,20}$') {
            Write-Host "  That doesn't look like a valid username." -ForegroundColor Yellow
            continue
        }

        $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" `
                           -Properties Department, MemberOf `
                           -ErrorAction SilentlyContinue
        if (-not $user) {
            Write-Host "  No user found with username '$sam'." -ForegroundColor Yellow
            continue
        }

        if ($ProtectedAccounts -contains $user.SamAccountName -or
            $user.SamAccountName -eq $env:USERNAME) {
            Write-Host "  '$($user.SamAccountName)' is a protected account (built-in or the account you're running as)." -ForegroundColor Red
            continue
        }

        $groupNames = @($user.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name })
        $groupText  = if ($groupNames.Count) { $groupNames -join ', ' } else { '(none)' }
        $deptText   = if ($user.Department) { $user.Department } else { '(not set)' }

        Write-Host "`nUser found:" -ForegroundColor Cyan
        Write-Host "  First name : $($user.GivenName)"
        Write-Host "  Last name  : $($user.Surname)"
        Write-Host "  Department : $deptText"
        Write-Host "  Username   : $($user.SamAccountName)"
        Write-Host "  Groups     : $groupText"
        Write-Host "`nOffboarding will: reset the password, disable the account, remove all group memberships above, and move the user to the '$OffboardingOUName' OU." -ForegroundColor Cyan

        $answer = (Read-Host "Is this the correct user? (Y/N)").Trim()
        if ($answer -match '^[Yy]') {
            return $user
        }
        Write-Host "  OK, let's try again." -ForegroundColor Yellow
    }
}

function Invoke-Offboarding {
    param([string]$OffboardingOUDN)

    $user = Read-OffboardingTarget
    if (-not $user) {
        Write-Host "Offboarding cancelled." -ForegroundColor Yellow
        return
    }

    $sam        = $user.SamAccountName
    $securePass = Read-ConfirmedPassword -Prompt "Temporary password to reset to"

    # 1. Reset password to the temporary one
    try {
        Set-ADAccountPassword -Identity $user -Reset -NewPassword $securePass -ErrorAction Stop
        Write-Host "Password reset for $sam" -ForegroundColor Green
    }
    catch {
        Write-Host "Password reset failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stopping so the account isn't left half offboarded." -ForegroundColor Red
        return
    }

    # 2. Disable the account
    try {
        Disable-ADAccount -Identity $user -ErrorAction Stop
        Write-Host "Account disabled: $sam" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not disable account: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 3. Remove from security groups
    foreach ($groupDN in @($user.MemberOf)) {
        $groupName = (Get-ADGroup -Identity $groupDN).Name
        try {
            Remove-ADGroupMember -Identity $groupDN -Members $user -Confirm:$false -ErrorAction Stop
            Write-Host "Removed $sam from $groupName" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not remove $sam from ${groupName}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 4. Move to the Offboarding OU
    try {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $OffboardingOUDN -ErrorAction Stop
        Write-Host "Moved $sam to $OffboardingOUDN" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not move user to the Offboarding OU: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "Offboarding finished for $sam`n" -ForegroundColor Cyan
}

function Start-Offboarding {
    Write-Host "`n--- Offboarding ---" -ForegroundColor Cyan

    try {
        $ouDN = Initialize-OffboardingOU
    }
    catch {
        Write-Host "Failed to prepare the Offboarding OU: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    do {
        Invoke-Offboarding -OffboardingOUDN $ouDN
        $again = Read-Host "Offboard another user? (Y/N)"
    } while ($again -match '^[Yy]')
}

# ===========================================================================
# Main menu
# ===========================================================================
while ($true) {
    Write-Host "`n=== Employee Lifecycle ===" -ForegroundColor Cyan
    Write-Host "  [1] Onboard a new user"
    Write-Host "  [2] Offboard an existing user"
    Write-Host "  [Q] Quit"

    switch ((Read-Host "Select an option").Trim().ToUpper()) {
        '1'     { Start-Onboarding }
        '2'     { Start-Offboarding }
        'Q'     { return }
        default { Write-Host "Enter 1, 2, or Q." -ForegroundColor Yellow }
    }
}
