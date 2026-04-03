# R.E.P.O. Backup Scripts

This repository contains PowerShell and Batch scripts for backing up save files for the game R.E.P.O.

## Contents
- `Backup Repo.ps1`: The PowerShell script that handles the backup process, including automatic recovery if the source folder is missing.
- `Backup Repo.bat`: A simple batch wrapper to run the PowerShell script with the appropriate execution policy.

## Usage
Run `Backup Repo.bat` to start the backup process. The script will prompt for a folder to backup if not provided as an argument.
