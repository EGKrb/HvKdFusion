<#
    hvkd.ps1 - lanceur HvKdFusion avec élévation UAC automatique.

    Exécute hvkdfusion.py en administrateur (requis pour toute opération
    mémoire Hyper-V). Si la session n'est pas déjà élevée, relance une
    fenêtre PowerShell élevée (prompt UAC) et y exécute la commande.

    Exemples :
        .\hvkd.ps1                 # menu interactif, élevé
        .\hvkd.ps1 list
        .\hvkd.ps1 debug --vm 0 --engine windbg
        .\hvkd.ps1 dump --vm 0 --type linear --out guest.raw

    La commande 'setup' n'a pas besoin d'admin ; lance-la directement :
        python hvkdfusion.py setup
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Rest
)

$ErrorActionPreference = 'Stop'

$here   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script = Join-Path $here 'hvkdfusion.py'

if (-not (Test-Path $script)) {
    Write-Error "Introuvable : $script"
    exit 1
}

# Résoudre l'interpréteur Python (python.exe puis py.exe).
$py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command py.exe -ErrorAction SilentlyContinue).Source }
if (-not $py) {
    Write-Error 'Python introuvable sur le PATH (python.exe ou py.exe).'
    exit 1
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Sans argument -> menu interactif.
if (-not $Rest -or $Rest.Count -eq 0) {
    $Rest = @('menu')
}

# Aide/raccourcis.
if ($Rest[0] -in @('help', '-h', '--help', '/?')) {
    @'
hvkd.ps1 - lanceur HvKdFusion (élévation UAC auto)

  .\hvkd.ps1                      menu interactif (élevé)
  .\hvkd.ps1 list                 énumère les VM Hyper-V
  .\hvkd.ps1 debug --vm 0 --engine windbg
  .\hvkd.ps1 dump  --vm 0 --type linear --out guest.raw
  .\hvkd.ps1 read  --vm 0 --addr 0x10000 --size 0x1000

  Raccourcis ntoseye (analyse de dump) :
  .\hvkd.ps1 ntoseye --vm 0                 crash dump de la VM puis REPL ntoseye
  .\hvkd.ps1 ntoseye --dump C:\x\MEMORY.DMP analyse un .dmp existant (sans admin)
  .\hvkd.ps1 ntoseye --dump C:\x\MEMORY.DMP --mode mcp --http 127.0.0.1:8080

Toute sous-commande de hvkdfusion.py passe en direct. 'setup' n'a pas besoin d'admin.
'@
    exit 0
}

# L'analyse d'un dump ntoseye DÉJÀ existant n'a pas besoin de l'admin : on
# l'exécute directement, sans prompt UAC. (La génération d'un crash dump --vm,
# elle, passe par la branche élevée plus bas.)
$isNtoseyeDump = ($Rest[0] -eq 'ntoseye') -and ($Rest -contains '--dump') -and -not ($Rest -contains '--vm')

if ((Test-Admin) -or $isNtoseyeDump) {
    # Déjà administrateur (ou action sans besoin d'admin) : exécuter directement.
    & $py $script @Rest
    exit $LASTEXITCODE
}

# Pas administrateur : relancer une fenêtre élevée (prompt UAC).
# On garde la fenêtre ouverte à la fin pour lire la sortie.
$argline = ($Rest | ForEach-Object { '"' + ($_ -replace '"', '`"') + '"' }) -join ' '
$inner = @"
Set-Location "$here"
& "$py" "$script" $argline
Write-Host ''
Read-Host 'Terminé. Entree pour fermer'
"@

Write-Host '[*] élévation (UAC)...'
try {
    Start-Process -Verb RunAs -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $inner)
}
catch {
    Write-Error "Élévation refusée ou échouée : $($_.Exception.Message)"
    exit 1
}
