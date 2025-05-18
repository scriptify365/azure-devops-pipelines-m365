# Azure DevOps Pipeline - Remove Mailbox Permissions

This pipeline is designed to remove **FullAccess** and **SendAs** permissions from a shared mailbox for a specified user using Exchange Online PowerShell.

## Prerequisites

Before running this pipeline, you must configure **app-only authentication** for Exchange Online PowerShell.  
Follow the instructions in the official Microsoft documentation:  
[Set up app-only authentication for unattended scripts in Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)

## Parameters

| Parameter      | Description                       | Type   | Default |
|-----------------|-----------------------------------|--------|---------|
| `userEmail`     | User email address               | string |         |
| `sharedMailbox` | Shared mailbox email address     | string |         |

## Pipeline Overview

1. **Retrieve GRAPH_CLIENT_SECRET from Azure Key Vault.**
2. **Store Graph Client Secret as Environment Variable.**
3. **Generate EXO Access Token using OAuth.**
4. **Remove FullAccess and SendAs permissions from the specified mailbox.**

## Need Help?

If you need assistance with configuring the app-only authentication or setting up the pipeline, feel free to reach out to me. 

