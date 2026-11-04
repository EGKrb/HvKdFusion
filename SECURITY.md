# Politique de sécurité

## Versions maintenues

Les correctifs vont dans la branche `main` et la dernière release. HvKdFusion est aussi livré dans [Fathom](https://github.com/EGKrb/Fathom) (`release\hvkdfusion\`), dont la dernière release reprend les mêmes scripts.

| Version | Maintenue |
| ------- | --------- |
| `main` et la dernière release (1.0.x) | ✅ |
| copies plus anciennes | ❌ (mettre à jour) |

## Usage prévu

**HvKdFusion** pilote le débogage noyau et l'analyse mémoire de **VM Hyper-V** (LiveCloudKd, WinDbg, MemProcFS, ntoseye, wineye). Il est destiné à un **usage légitime et autorisé** : débogage de vos propres systèmes et pilotes, forensic et réponse à incident, analyse de malware dans une VM, recherche en sécurité. N'inspectez que des VM et des images mémoire que vous avez le droit d'analyser : la mémoire d'une VM contient tout ce qui s'y trouvait, mots de passe et données personnelles compris.

## Surface d'attaque

Ce sont des propriétés de l'outil, pas des vulnérabilités :

- **Droits administrateur** : toutes les opérations mémoire en ont besoin (`hvkd.ps1` relance la commande via UAC). `setup`, `config` et `check` s'en passent.
- **Pilote noyau** : `hvlib.dll` charge `hvmm.sys` (LiveCloudKd), qui accède à la mémoire de toutes les VM de l'hôte. Le montage MemProcFS utilise le pilote Dokany (`dokan2.sys`), que HvKdFusion n'installe jamais lui-même.
- **Écriture** : `write` modifie la mémoire de la VM en cours d'exécution ; `debug --pause` met la VM en pause et `resume` la relance. Une mauvaise adresse peut faire planter l'invité.
- **Serveurs** : les modes `--serve mcp|dap|gdb` de wineye exposent la mémoire en lecture seule, sur stdio ou sur un port TCP lié par défaut à `127.0.0.1`. Tout programme local qui s'y connecte peut lire la mémoire de la VM : arrêtez-les après usage, et ne les liez pas à une autre interface.
- **`config.json`** contient les chemins locaux de votre machine (dossiers des composants, chemin des symboles) : ne le partagez pas tel quel.

## Signaler une vulnérabilité

Si vous trouvez un problème de sécurité dans le code d'HvKdFusion (`hvkdfusion.py`, `hvkd.ps1`, `wineye.py`, `plugin_build/`) — par exemple une commande lancée avec des arguments non échappés, un chemin mal contrôlé, ou un serveur qui traite ses entrées de façon dangereuse :

1. **N'ouvrez pas** d'issue publique décrivant l'exploitation.
2. Signalez-le en privé via [« Report a vulnerability »](https://github.com/EGKrb/HvKdFusion/security/advisories/new) (onglet Security → Advisories).
3. Indiquez la version (release ou commit), une description et les étapes de reproduction. Ne joignez pas de vraies images mémoire : elles contiennent des données sensibles.

Les vulnérabilités de **LiveCloudKd** (`hvlib.dll`, `hvmm.sys`), **WinDbg**, **MemProcFS / LeechCore**, **ntoseye** ou **Dokany** sont à signaler à leurs projets respectifs. Les problèmes propres à wineye peuvent aussi être signalés sur [wineye](https://github.com/EGKrb/wineye/security/advisories/new).

Pas de délai de réponse garanti, mais les signalements sont lus et pris au sérieux.
