# HvKdFusion

Outil unique qui **fusionne les fonctionnalités de LiveCloudKd et de windbg-master**
en un seul workflow / CLI / `config.json`.

| Projet | Rôle dans la fusion |
|---|---|
| **LiveCloudKd** | Le *moteur mémoire* des VM Hyper-V : `hvlib.dll` + `hvmm.sys`, pilotés via le wrapper `hvlib.py`. Énumération des VM, lecture/écriture mémoire physique & virtuelle du guest, dump, pause/resume. |
| **windbg-master** | Le *débogueur* : `windbg.exe`, extrait des parties `doc/windbg64.part*.rar`, attaché à la VM choisie. |
| **ntoseye** | *Analyseur hors-ligne* type-WinDbg (Rust, Linux/macOS → **WSL** sur Windows). HvKdFusion produit un crash dump de la VM, ntoseye l'analyse (REPL, MCP, DAP, serveur GDB). |
| **MemProcFS** | *Monte la mémoire comme système de fichiers* (lecteur M:) : processus, modules, handles, registre, mode forensic. Source : dump produit par HvKdFusion, ou VM Hyper-V live via le device LeechCore `hvmm`. |
| **Dokany** | Le *pilote de système de fichiers* en mode utilisateur dont MemProcFS a besoin pour monter (`dokan2.sys`). Fourni **signé** via `DokanSetup.exe`. |
| **LeechCore** | La *couche d'acquisition mémoire* de MemProcFS (`leechcore.dll`) : multiples backends `-device` (dump, `fpga`, `pmem`, `vmware://`, `hvmm`, …). C'est elle qui, via le plugin `hvmm`, lit une VM Hyper-V live. |

Plutôt que de recompiler deux arbres C/C++ hétérogènes (le source WinDbg est *legacy*
et le binaire vit dans un RAR), HvKdFusion relie les deux au bon niveau :
le moteur DLL fournit l'accès mémoire, WinDbg fournit l'UI de débogage, et un seul
front-end Python orchestre l'ensemble.

## Prérequis

- Windows + Hyper-V activé, une VM invité en cours d'exécution.
- **Droits administrateur** (toutes les opérations mémoire).
- Runtime Visual C++ 2022 x64 (requis par `hvlib.dll`).
- Python 3.11+ (testé sur 3.14).
- 7-Zip **ou** WinRAR sur le PATH (pour extraire WinDbg du RAR).

## Installation

```powershell
cd C:\Users\Elio\HvKdFusion
python hvkdfusion.py setup
```

`setup` :
1. localise `hvlib.dll`, `hvlib.py`, `hvmm.sys` dans le dossier LiveCloudKd ;
2. extrait `windbg64.part01.rar` (+ parties) → `windbg64\` et trouve `windbg.exe` ;
3. repère `LiveCloudKd.exe` s'il existe (sinon : mode moteur seul) ;
4. **copie `hvlib.dll` + `hvmm.sys` à côté de `windbg.exe`** (exigence du README LiveCloudKd) ;
5. écrit `config.json`.

Options utiles : `--windbg-dir <WinDbg installé>` (au lieu du RAR),
`--no-extract`, `--no-stage`, `--livecloudkd <dir>`, `--windbg-src <dir>`.

## Lancement rapide avec élévation UAC

`hvkd.ps1` relance la commande dans une fenêtre **administrateur** (prompt UAC) —
indispensable pour toute opération mémoire. Sans argument, il ouvre le **menu interactif**.

```powershell
.\hvkd.ps1                                   # menu interactif, élevé
.\hvkd.ps1 list
.\hvkd.ps1 debug --vm 0 --engine windbg
.\hvkd.ps1 dump --vm 0 --type linear --out guest.raw
```

Déjà dans une console admin ? Il exécute directement, sans nouvelle fenêtre.
`setup` n'a pas besoin d'admin : `python hvkdfusion.py setup`.

Sans prompt UAC, même hors console admin : `setup`, `config`, `check`, et
l'analyse d'un fichier existant (`wineye --dump`, `ntoseye --dump`, sans
`--vm`/`--from-vm`/`--live`). Les arguments qui ressemblent à des paramètres
PowerShell passent tels quels (`.\hvkd.ps1 wineye --dump x.raw -c "ps;lm"`).
Avec `HVKD_KEEP_OPEN=1` dans l'environnement, la fenêtre reste ouverte à la fin
(c'est ce que fait la commande `hvkd` du fork x64dbg EGKrb).

## Vérifier la préparation

```powershell
python hvkdfusion.py check          # tableau statique (sans admin, sans charger de DLL)
python hvkdfusion.py check --deep   # + exécute réellement MemProcFS.exe -h
```

`check` dresse l'état de chaque composant (moteur, WinDbg, LiveCloudKd.exe,
ntoseye, MemProcFS, plugin hvmm, Dokany, admin, Hyper-V, runtime VC++) en
vérifiant les fichiers **et leurs DLL co-localisées**, puis récapitule quelles
fonctionnalités sont prêtes. `[OK]` prêt · `[~~]` optionnel manquant · `[!!]`
bloquant manquant.

## Menu interactif

```powershell
python hvkdfusion.py menu        # (ou .\hvkd.ps1 sans argument)
```

Énumère les VM, demande laquelle choisir au clavier, puis propose : déboguer
(WinDbg / kd / EXDI), dump linéaire, lire, écrire (avec confirmation), resume,
analyser un dump avec ntoseye, et monter la mémoire avec MemProcFS.

## Utilisation (console admin)

```powershell
python hvkdfusion.py config                 # config résolue
python hvkdfusion.py list                   # énumère les VM Hyper-V

# Débogage (nécessite LiveCloudKd.exe compilé) :
python hvkdfusion.py debug --vm 0 --engine windbg   # attache WinDbg
python hvkdfusion.py debug --vm 0 --engine kd       # attache kd
python hvkdfusion.py debug --vm 0 --engine exdi     # plugin EXDI

# Mémoire (moteur DLL, toujours dispo) :
python hvkdfusion.py read  --vm 0 --addr 0x10000 --size 0x1000
python hvkdfusion.py read  --vm 0 --addr 0xfffff80000000000 --size 0x200 --virtual
python hvkdfusion.py write --vm 0 --addr 0x10000 --data 9090cc --virtual
python hvkdfusion.py dump  --vm 0 --type linear --out guest.raw
python hvkdfusion.py resume --vm 0
```

## Modes

- **Mode moteur** (`list`, `read`, `write`, `dump --type linear`, `resume`) :
  n'utilise que `hvlib.dll`, **déjà livré prébuild** dans `LiveCloudKdSdk\files`.
  Fonctionne sans compiler quoi que ce soit.
- **Mode lanceur** (`debug`, `dump --type crash|raw`) : requiert `LiveCloudKd.exe`.
  Le **premier** arbre (`LiveCloudKd-master`) ne compile pas (header
  `LiveCloudKdSdkPublic.h` et `LiveCloudKdSdk.lib` absents). Le **second**
  (`LiveCloudKd-master2`) **se compile** (voir plus bas), et son `LiveCloudKd.exe`
  est déjà câblé. En l'absence d'exe, l'outil bascule sur le moteur quand c'est
  possible (`list`, `read`, `write`, `dump --type linear`, `resume`), car
  `hvlib.dll` est livré compilé.

## Compiler LiveCloudKd.exe (arbre master2)

Le projet `LiveCloudKd-master2` lie `hvlib.lib` (fourni) en toolset v143 et
n'exige ni `LiveCloudKdSdkPublic.h` ni `LiveCloudKdSdk.lib`. Il attend seulement
une disposition de dossiers. Préparer puis compiler (VS 2022/2026, SDK 10.0.26100) :

```powershell
$m2 = "C:\Users\Elio\Downloads\LiveCloudKd-master2\LiveCloudKd-master"
Copy-Item "$m2\LiveCloudKdSdk\public" "$m2\public" -Recurse -Force    # includes
New-Item -ItemType Directory -Force "$m2\files" | Out-Null
Copy-Item "$m2\LiveCloudKdSdk\files\hvlib.lib" "$m2\files\" -Force    # lib liée
New-Item -ItemType Directory -Force "$m2\LiveCloudKd\files" | Out-Null # postbuild
# hvlib.dll + hvmm.sys à côté de l'exe produit, pour l'exécution
Copy-Item "$m2\LiveCloudKdSdk\files\hvlib.dll","$m2\LiveCloudKdSdk\files\hvmm.sys" "$m2\LiveCloudKd\x64\Release\" -Force -ErrorAction SilentlyContinue

msbuild "$m2\LiveCloudKd\LiveCloudKd.sln" /p:Configuration=Release /p:Platform=x64 /p:SpectreMitigation=false

python hvkdfusion.py setup --livecloudkd $m2 --livecloudkd-exe "$m2\LiveCloudKd\x64\Release\LiveCloudKd.exe"
```

> `/p:SpectreMitigation=false` car les libs Spectre ne sont pas installées.
> L'exe exige l'élévation (manifeste `RequireAdministrator`) et charge `hvlib.dll`.

## wineye — équivalent natif Windows de ntoseye (mémoire passive)

`wineye` est un **REPL natif Windows façon WinDbg**, l'équivalent du *backend
mémoire* de ntoseye **sans WSL** : il inspecte Windows à partir de la seule
mémoire (dump ou VM Hyper-V live), cible non consciente d'être observée. Il
pilote `vmm.dll` (MemProcFS) directement en **ctypes** — ni pip, ni extension,
ni Dokany (il ne monte rien, il lit la mémoire).

```powershell
python hvkdfusion.py wineye --dump C:\dumps\vm0.raw      # analyser un dump
python hvkdfusion.py wineye --from-vm 0                   # dump moteur puis analyse
python hvkdfusion.py wineye --live                        # VM Hyper-V live (admin)
python hvkdfusion.py wineye --dump x.raw -c "ps;lm" --batch --json
```

Commandes (façon WinDbg) : `ps`, `!process [pid]`, `.pid <n|-1>`, `lm [pid]`,
`x <mod>!<sym>`, `db|dw|dd|dq <addr|mod!sym> [L<n>]`, `dt <mod>!<type> [champ]
[addr]`, `!vad [pid]`, `!handle [pid]`, `s <addr> <len> <hex>`, `info`, `help`,
`q`. Les adresses acceptent `0x..`, décimal et `module!symbole`.

### Lever la limite « pas de contrôle d'exécution »

La mémoire passive lit la RAM mais ne contrôle pas les VCPU. On lève ça en
ajoutant un **canal de contrôle** : `hvlib` (LiveCloudKd) expose
`SdkControlVmState` et `SdkReadVpRegister`. wineye l'utilise pour une **VM
Hyper-V live** (admin requis) :

```powershell
python hvkdfusion.py wineye --live --vm 0      # lie le canal de contrôle à la VM 0
# puis dans le REPL :
freeze            # suspend la VM
r                 # lit rip/rsp/rax/.../rflags du VP0
r rip rsp         # registres choisis
resume            # (ou 'g') relance la VM
```

Ce qui est **réellement levé** : lecture des **registres** des processeurs
virtuels et **gel/reprise** de la VM. Ce qui ne l'est **pas** : breakpoints
matériels/logiciels et **pas-à-pas** — `hvlib` ne délivre pas d'événements de
trap, donc on ne peut pas « attraper » un hit passivement. Pour ça, il faut un
transport de debug : **WinDbg/kd** via `hvkdfusion.py debug` (EXDI/live-kd), qui
donne le contrôle d'exécution complet. wineye couvre donc le cœur passif + le
contrôle d'état/registres ; le run-control fin reste le domaine de WinDbg.

## Analyse avec ntoseye (hors-ligne)

`ntoseye` est un débogueur type-WinDbg pour **Linux/macOS** : sur Windows il tourne
sous **WSL2**. Il lit les crash dumps Windows `.dmp` (full / kernel / triage). La
fusion : HvKdFusion génère un **crash dump Microsoft** de la VM Hyper-V live
(action LiveCloudKd 3), puis ntoseye l'analyse.

> Le dump `linear` du moteur est *RAW* (pas un `.dmp`) et n'est **pas** lisible
> par ntoseye — pour ntoseye, utilise le crash dump.

Installation (dans WSL) : `uv tool install ntoseye` (ou `pipx`, `cargo`, ou le
script d'install du dépôt). `setup` le détecte automatiquement (PATH natif, sinon
dans WSL) et l'enregistre dans `config.json`. Pour que `setup` tente l'installation
lui-même dans WSL quand ntoseye manque :

```powershell
python hvkdfusion.py setup --install-ntoseye
```

```powershell
# analyser un .dmp existant dans le REPL ntoseye
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP

# produire un crash dump de la VM 0 (LiveCloudKd.exe requis) puis l'analyser
python hvkdfusion.py ntoseye --vm 0

# exécuter des commandes puis quitter (mode batch)
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP -c "analyze" -c "lm" --batch

# serveur MCP (intégration agent) / DAP (éditeur) / GDB (IDA, Ghidra, Binja)
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP --mode mcp --http 127.0.0.1:8080
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP --mode dap --port 4000
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP --mode gdbserver

# override manuel de l'exécutable
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP --ntoseye /home/elio/.local/bin/ntoseye --wsl

# voir la commande construite sans l'exécuter
python hvkdfusion.py ntoseye --dump C:\dumps\MEMORY.DMP --print-cmd
```

Les chemins Windows (`C:\…`) sont traduits automatiquement en chemins WSL
(`/mnt/c/…`) quand l'invocation passe par WSL. Arguments ntoseye supplémentaires :
après `--`, p. ex. `... --print-cmd -- --sympath-append /sym`.

## Montage mémoire (MemProcFS + Dokany)

MemProcFS monte la mémoire comme un système de fichiers (lecteur M: par défaut) :
arborescence des processus, modules, handles, registre, mode forensic, etc.
**Pré-requis** : le pilote **Dokany v2** (`DokanSetup.exe` signé,
github.com/dokan-dev/dokany/releases — à installer, pilote kernel signé) et
**MemProcFS.exe**. Ce dernier **a été compilé depuis les sources** ici (voir plus
bas) ; `setup` le câble :

```powershell
python hvkdfusion.py setup --memprocfs-exe C:\...\MemProcFS-master\files\memprocfs.exe
```

Sources de montage — elles relient le moteur LiveCloudKd / LeechCore à MemProcFS :

```powershell
# 1. dump existant (.raw/.dmp)
python hvkdfusion.py mount --dump C:\dumps\vm0.raw --letter M -v

# 2. dump linéaire de la VM via le moteur, puis montage (aucun plugin requis)
python hvkdfusion.py mount --from-vm 0 --forensic

# 3. VM Hyper-V LIVE via le device LeechCore 'hvmm'  (plugin compilé + en place)
python hvkdfusion.py mount --live

# 4. n'importe quel device LeechCore brut
python hvkdfusion.py mount --device FPGA
python hvkdfusion.py mount --device "PMEM://c:\temp\winpmem_x64.sys"
```

- **Option 2** (`--from-vm`) : moteur `hvlib.dll` seul + MemProcFS + Dokany.
- **Option 3** (`--live`) : `leechcore_device_hvmm.dll` **a été compilé** (grâce à
  l'arbre LeechCore) et mis en place à côté de `MemProcFS.exe` avec `hvlib.dll` +
  `hvmm.sys`. `setup` le détecte et le stage automatiquement.
- **Option 4** (`--device`) expose tout backend LeechCore.

Fermer MemProcFS (Ctrl+C dans sa fenêtre) pour démonter.

## Compiler MemProcFS + le plugin hvmm (avec LeechCore)

`MemProcFS.sln` attend **LeechCore comme dossier frère** (`..\LeechCore`). Les
projets lient `leechcore.lib`/`vmm.lib` depuis `files\` ; on bâtit donc dans
l'ordre leechcore → vmm → memprocfs, via la `.sln` (pour que `$(SolutionDir)`
soit correct). Toolset v143, SDK 10.0.26100.

```powershell
$mp = "C:\Users\Elio\Downloads\MemProcFS-master\MemProcFS-master"
$lc = "C:\Users\Elio\Downloads\LeechCore-master\LeechCore-master"
New-Item -ItemType Junction -Path (Join-Path (Split-Path $mp) LeechCore) -Target $lc   # ..\LeechCore
foreach ($t in 'leechcore','vmm','memprocfs') {
  msbuild "$mp\MemProcFS.sln" /t:$t /p:Configuration=Release /p:Platform=x64 /p:SpectreMitigation=false
}
# -> $mp\files\{leechcore.dll, vmm.dll, memprocfs.exe}
```

Plugin **leechcore_device_hvmm.dll** (device `hvmm`) : son projet (dans
`LiveCloudKd-master2`) compile `..\LeechCore\leechcore\util.c` et exige
`..\LeechCore` frère + les headers hvlib + `charutil.c` (ajouté car `util.c`
appelle `CharUtil_WtoU`, non exporté par `leechcore.lib`) :

```powershell
$m2 = "C:\Users\Elio\Downloads\LiveCloudKd-master2\LiveCloudKd-master"
New-Item -ItemType Junction -Path "$m2\LeechCore" -Target $lc | Out-Null
New-Item -ItemType Directory -Force "$m2\hvlib\hvlib\include\public","$m2\files" | Out-Null
Copy-Item "$m2\LiveCloudKdSdk\public\*" "$m2\hvlib\hvlib\include\public\" -Recurse -Force
Copy-Item "$m2\LiveCloudKdSdk\files\hvlib.lib" "$m2\files\" -Force
# ajouter <ClCompile Include="..\LeechCore\leechcore\charutil.c" /> au .vcxproj, puis :
msbuild "$m2\leechcore_device_hvmm\leechcore_device_hvmm.vcxproj" /p:Configuration=Release /p:Platform=x64 /p:SolutionDir="$m2\" /p:SpectreMitigation=false
```

Puis câbler : `setup --memprocfs-exe $mp\files\memprocfs.exe` copie le plugin +
`hvlib.dll` + `hvmm.sys` à côté de `MemProcFS.exe`.

## Symboles

```powershell
setx /m _NT_SYMBOL_PATH "SRV*C:\Symbols*https://msdl.microsoft.com/download/symbols"
```

Le chemin est aussi mémorisé dans `config.json` (`symbol_path`).

## Notes

- Les opérations mémoire échouent proprement (message, pas de *traceback*) sans
  admin / Hyper-V / VM.
- Méthodes d'accès : `read_method` / `write_method` dans `config.json` —
  `0` = hypercall WinHv (lent, robuste), `1` = pilote brut `hvmm.sys` (rapide, défaut).
- Le `dump --type linear` du moteur lit la plage physique jusqu'à
  `HvddMmMaximumPhysicalPage` et met à zéro les plages illisibles.
