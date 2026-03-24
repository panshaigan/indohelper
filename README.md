# Indohelper

Indohelper is a tool designed to help you download and update mods for Infinity Engine games (like Baldur's Gate, Baldur's Gate II, Icewind Dale, and Planescape: Torment). It automates the process of fetching the latest versions of mods from various sources and organizing them for use with Project Infinity.

## Installation

1.  **Project Infinity**: Extract or clone this repository as a subfolder in your **ProjectInfinity** directory.
2.  **PowerShell**: This tool uses PowerShell scripts. On the first launch, it will attempt to install the `7Zip4PowerShell` module to handle extractions.

## Usage

Run `update.bat` from the command line, providing the name of the CSV file containing your mod list (without the `.csv` extension).

### Basic usage:
```powershell
update.bat eet
```
This will process the mods listed in `eet.csv`.

### Using a custom CSV:
If you have a custom file named `my-mods.csv`:
```powershell
update.bat my-mods
```

### Filtering by Game:
You can provide an optional second parameter to filter mods by game (e.g., `BG2`, `BGEE`, `PSTEE`):
```powershell
update.bat eet IWD
```
```powershell
update.bat eet BG1-BG2
```

The mods will be downloaded to a folder (named the same as the csv list) in the main ProjectInfinity folder.

## GitHub Token

To avoid API rate limits when downloading from GitHub, a Personal Access Token is required.
- On the first run, the script will guide you through creating and saving a token.
- Alternatively, you can manually create a file at `scripts\token.txt` and paste your token there.

## CSV File Format

The mod list CSV files should use the following headers:
`Codename,Category,URL,Game,UseMaster,Release,Version`

- **Codename**: The folder name for the mod. It's taken automatically from the mod download URL, you can leave it blank
- **Category**: (Optional) For organizational purposes.
- **URL**: The link to the mod's repository or download page.
- **Game**: (Optional) Used for filtering with the second command-line parameter.
- **UseMaster**: (GitHub only) Set to `1` to download the master/main branch instead of the latest release. Useful for Artisan's mods

## Supported Mod Sources

Indohelper currently supports:
- **GitHub** (via API and Git clone)
- **WeaselMods** (`downloads.weaselmods.net`)
- **Morpheus-Mart** (`morpheus-mart.com`)
- **Baldur's Gate DE** (`baldurs-gate.de`)
- **Imoen Romance** (`imoen.blindmonkey.org`)
