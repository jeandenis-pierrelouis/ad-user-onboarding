# Active Directory Employee On/Offboarding Automation

Utilizes PowerShell for onboarding and offboarding users in an Active Directory lab domain. It brings common accounts into one interactive workflow: onboarding an account assigned to a security groups, or offboarding an existing account and move it into an offboarding organizational unit.

This project demonstrates hands-on Windows infrastructure administration with PowerShell and Active Directory, including user and group management, OU, input validation, confirmation prompts, and error handling.

## Project objectives

- Automate repeatable onboarding and offboarding tasks
- Apply department-based security group membership during onboarding.
- Reduce human error by showing the target user's details before completion of onboarding & offboarding.
- Demonstrate practical Active Directory administration through PowerShell.

## Environment and architecture

The script runs interactively in a PowerShell session on DC but can run on any device that stores Active Directory. 

Administrator workstation or Windows Server
  └── PowerShell + ActiveDirectory module
        └── Lifecycle Script
              └── Active Directory domain
                    ├── User accounts
                    ├── Department security groups
                    └── Offboarding OU
```

The domain name is discovered at runtime through `Get-ADDomain`. Onboarding creates users in the default Users container. Offboarding creates the configured offboarding OU at the domain root if it does not already exist.

## Technologies

- PowerShell
- Active Directory
- Windows Server or a Windows administration workstation with the required AD tools

## Prerequisites

- An Active Directory lab domain that the machine can reach.
- PowerShell with the Active Directory module available in the session.
- Credentials with delegated rights
- Permission to run scripts under the machine's PowerShell execution policy.

The script does not install the module, create the domain, or configure permissions. Prepare those separately in the lab.

## Repository structure

The project artifact available for this README is one PowerShell script under the name of " Onboarding and Offboarding.ps1 ". 
```

## How it works

### Onboarding

1. Ensures these global security groups exist, creating any that are missing:
   - `SG_Accounting`
   - `SG_ServiceDesk`
   - `SG_HR`
   - `SG_SupportServices`
2. Prompts for first name, last name, department, and a temporary password entered as a secure string and confirmed a second time.
3. Validates names and department selection.
4. Builds a lowercase `firstname.lastname` username, removes non-letter characters from the name parts, enforces the 20-character `SamAccountName` limit, and adds a numeric suffix when needed to avoid a username collision.
5. Displays the proposed account and asks for confirmation before creating it.
6. Creates the enabled user with a UPN based on the domain DNS root, records the department, and requires a password change at first sign-in.
7. Adds the user to the selected department group and reports any error.

### Offboarding

1. Ensures an `Offboarding` OU exists at the domain root (or uses the name supplied through `-OffboardingOUName`).
2. Prompts for a `SamAccountName`, looks up the user, and displays their name, department, username, and current direct group memberships for confirmation.
3. Refuses the built-in `Administrator`, `Guest`, and `krbtgt` accounts, as well as the account running the script.
4. Prompts for and confirms a temporary password, resets the user's password, and stops if that reset fails.
5. Disables the account, attempts to remove its listed group memberships, and attempts to move the account to the offboarding OU.
6. Reports each successful or failed operation in the console.

The main menu lets the operator repeat either workflow or quit. The script is interactive and does not accept a user record or password through command-line arguments.

## Setup and usage

1. Copy Onboarding and Offboarding.ps1 script
2. Open PowerShell on a domain-connected administration machine where the Active Directory module is available.
3. Sign in using an account authorized for the intended AD operations.
4. Run the script

Replace the example distinguished name with an OU in your lab.
Choose `[1]` to onboard, `[2]` to offboard, or `[Q]` to exit. Follow the prompts and review the displayed account details before confirming.

## Example operator workflow

For a new lab employee, select onboarding, enter the employee's name, choose a department, and enter and confirm a temporary password. Review the proposed name, username, department, and group; confirm to create the account. The employee is enabled and must change the password at first logon.

For a departing lab employee, select offboarding and enter their username. Verify the displayed identity and groups before confirming. Enter and confirm a temporary password for the reset. The script then disables the account, removes listed group memberships, and moves the user into the offboarding OU, reporting the outcome of each step.

## Security considerations

- Use this script only in an authorized lab or environment where you have approval to administer the domain.
- Run it with a least-privilege account that has only the delegated rights required for the workflow.
- Password prompts use `Read-Host -AsSecureString`; do not hard-code or pass passwords as command-line arguments. The script briefly converts entered secure strings to plaintext in memory to compare the confirmation entries.
- Review the identity and department/group details before confirming onboarding or offboarding.
- The offboarding password is operator-supplied and temporary. Handle it according to the lab's credential-handling process; the script does not generate or communicate a password automatically.
- Offboarding removes the memberships returned on the user's `MemberOf` property. Review the account and environment requirements before using this behavior in a real directory.
  
## Troubleshooting and limitations

| Symptom | What to check |
| --- | --- |
| An AD cmdlet is not recognized | Make sure the Active Directory PowerShell module is installed and available in the current session. |
| Access denied or an AD operation fails | Check domain connectivity and confirm the signed-in account has the required delegated permissions on the relevant users, groups, and OUs. |
| User creation fails | Check that the target OU exists and that the account values meet domain policy. If using `-UserOU`, verify its distinguished name. |
| Group membership fails after user creation | The account may already exist while group assignment did not complete. Check the user and department group in AD, then correct membership manually or rerun an appropriate administrative action. |
| Offboarding stops after password reset failure | The script deliberately stops at that point. Verify the account state in AD before retrying. |
 |

Additional implementation limits:

- The department list and group names are defined in the script but can be added manually in script ( Not as interactive but another version will be implemented to be more interacrtive adding pop up if need to add a security group ).
- The script does not collect job title, manager, email address, licensing, home directory, or other organization-specific attributes.
- Offboarding is not transactional: later failures can leave some steps complete and others incomplete.
- There is no persistent logging, reporting export, automated test suite, or WhatIf support in the supplied script.
- This is a lab/portfolio automation example; production use would need review against the organization's identity lifecycle, access control, audit, and recovery requirements.

## Future improvements

- Adding structured audit logging
- Configurable department mappings
- Clearer post-failure recovery checks


