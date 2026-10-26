# Ménage — conception

Petite app macOS (SwiftUI) pour surveiller l'espace disque et la mémoire, et faire le ménage
sans risque. Née du plantage du 2026-10-24 : swap plein (11,6 / 12 Go), disque à 93 %
(33 Go libres), arrêt forcé.

Nom de travail : **Ménage**. Dossier : `~/devapps/menage`. Usage personnel, hors App Store.

## Ce que l'app fait (V1)

### 1. Barre de menus et alertes

Une icône dans la barre de menus, toujours là :

- espace libre du disque de démarrage ;
- swap utilisé / total ;
- pression mémoire (normale, élevée, critique), comme dans le Moniteur d'activité ;
- les 5 apps qui consomment le plus de mémoire, **processus regroupés par app**
  (Firefox = la somme de ses `plugin-container`), avec un bouton « Quitter ».

L'icône change d'état (normal, attention, critique). Notifications macOS :

| Signal | Attention | Critique |
|---|---|---|
| Espace libre | < 40 Go | < 20 Go |
| Swap utilisé | > ¼ de la RAM (6 Go ici) | > ½ de la RAM (12 Go) |
| Pression mémoire | élevée | critique |

Le swap se juge en valeur absolue, pas en pourcentage : macOS agrandit et réduit son total à la
demande (12 Go le 2026-10-24, 7 Go le lendemain), donc « 90 % du total » ne veut rien dire.

Une notification quand un signal monte d'un palier. Le même palier d'un même signal n'est pas
renotifié avant 30 min (un disque qui oscille autour du seuil ne spamme pas). Le passage
d'attention à critique notifie tout de suite. Les seuils sont réglables.

Mesures, sans outil externe :
- espace libre : `volumeAvailableCapacity`, l'espace réellement libre comme `df`. On ne compte pas
  l'espace « purgeable » que le Finder ajoute : il ne sauve pas un swap qui grossit ;
- swap : `sysctl vm.swapusage` ;
- pression : `sysctl kern.memorystatus_vm_pressure_level` ;
- mémoire par processus : `proc_listpids` + `proc_pid_rusage` (`ri_phys_footprint`, la même valeur
  que le Moniteur d'activité), regroupée par app via `NSRunningApplication`.

Relevé toutes les 5 s, sans scan disque : coût négligeable.

### 2. Nettoyeur

La fenêtre principale. Chaque **règle** détecte des candidats, affiche leur taille, explique ce que
c'est et ce qui arrive si on les supprime. Trois niveaux de risque, affichés :

- **Sans risque** : se régénère tout seul, aucun travail perdu.
- **Régénérable** : se reconstruit, mais coûte un build ou un téléchargement.
- **À vérifier** : c'est peut-être à toi, l'app montre et ne pré-coche rien.

Règles de la V1 (chiffres relevés le 2026-10-25) :

| Règle | Exemple sur ce Mac | Risque |
|---|---|---|
| Xcode `DerivedData` | 6,8 Go | Sans risque |
| Simulateurs iOS indisponibles (`xcrun simctl delete unavailable`) | à mesurer | Sans risque |
| Caches applicatifs (`~/Library/Caches/*`, sauf ceux de macOS) | 9,3 Go | Sans risque |
| Installateurs `.dmg` / `.zip` / `.pkg` d'apps déjà dans `/Applications` | 9,3 Go (DaVinci ×2, FL Studio, ChatGPT) | Sans risque |
| Artefacts des **projets inactifs** (`node_modules`, `build`, `.next`, `.dart_tool`, `Pods`, `vendor`…) | jusqu'à 26 Go | Régénérable |
| Images système Android que plus aucun émulateur n'utilise | à mesurer | Régénérable |
| Anciennes versions du NDK (on garde la plus récente et celles citées par un projet) | 3 versions, 8,3 Go | Régénérable |
| Snapshots d'émulateur Android | 3,8 Go | Régénérable |
| Émulateur cassé : son image système n'est plus installée | `Pixel_7_API_36` (7,8 Go), pointe vers `android-36.1` absent | À vérifier |
| Docker : images orphelines, cache de build (`docker system df` puis `prune`) | 5,9 Go réels | Régénérable |
| Gros fichiers dans Téléchargements (vidéos, archives) | 2 vidéos « Challenge » ≈ 2 Go | À vérifier |

Précisions ajoutées en construisant l'étape 2 :
- **Caches** : tous les sous-dossiers de `~/Library/Caches` de plus de 50 Mo, sauf ceux de macOS
  (`com.apple.*`, `CloudKit`) et `ms-playwright*`, qui contient les navigateurs de Playwright et pas un
  cache.
- **Installateurs** (pré-cochés, donc la règle préfère en rater un que se tromper) : un `.dmg`,
  `.pkg` ou `.xip` dont le nom **commence** par celui d'une app installée, rangée à la racine de
  `/Applications` ou un niveau plus bas (`DaVinci Resolve/`). Les apps d'Apple sont écartées (Pages,
  Safari… ne s'installent jamais ainsi). Jamais de `.zip` : une archive peut contenir n'importe quoi,
  elle reste dans « Gros fichiers », à vérifier.
- **NDK** : on garde la plus récente, celles écrites dans un fichier Gradle, et celle du SDK Flutter
  quand un projet dit `ndkVersion = flutter.ndkVersion` (lue via `flutter.sdk` dans `local.properties`).
- **Émulateurs cassés** : si le SDK Android n'est pas là où on le cherche, la règle ne conclut rien.
- **Docker** : seulement le cache de build et les images orphelines (`builder prune --all`,
  `image prune`), jamais les conteneurs arrêtés ni les volumes. Si Docker n'est pas lancé, la règle le dit.
- Les commandes externes sont arrêtées au bout de 2 minutes.
- Seul le niveau **Sans risque** est pré-coché.

**Projets inactifs.** L'app parcourt les racines configurées (par défaut `~/devapps`, `~/develop`)
jusqu'à 4 niveaux et reconnaît un projet à ses marqueurs (`package.json`, `pubspec.yaml`,
`composer.json`, `build.gradle`, `Podfile`, `Cargo.toml`). La dernière activité, c'est la plus
récente entre le dernier commit git et la dernière modification d'un fichier source (artefacts
exclus) : un projet modifié hier sans commit depuis des mois est actif.
Inactif = rien depuis 60 jours, seuil réglable. Pour chaque projet : poids régénérable, dernière
activité, et la commande pour reconstruire (`npm install`, `flutter pub get`…).

### 3. Carte du disque et gros fichiers

- Carte en rectangles proportionnels (*treemap squarified*), dessinée avec `Canvas` : clic pour
  entrer dans un dossier, fil d'Ariane pour remonter, couleur par type (code, médias, apps,
  système, caches).
- Liste des fichiers de plus de 500 Mo, triable, avec « Afficher dans le Finder » et « Mettre à la
  Corbeille ».
- Les tailles affichées sont la **place réellement occupée** (`totalFileAllocatedSize`), pas la
  taille apparente. Sinon `Docker.raw` afficherait 494 Go alors qu'il en occupe 5,9.

### 4. Historique : « Qu'est-ce qui a grossi ? »

- Après chaque scan, on enregistre la taille de chaque dossier **jusqu'à 3 niveaux sous la racine**,
  pas fichier par fichier, pour que l'historique reste petit.
- Vue « Depuis le dernier scan » et « Sur 30 jours » : les dossiers qui ont le plus grossi, avec le
  delta.
- Courbe de l'espace libre au fil du temps.
- Scan automatique une fois par jour quand l'app tourne (lancement à l'ouverture de session via
  `SMAppService`).

## Sécurité : règles non négociables

1. **Rien n'est supprimé définitivement.** Tout passe par `FileManager.trashItem`, donc la Corbeille.
   Pas de `removeItem`.
2. Les seules exceptions sont les règles qui passent par un outil (Docker `prune`, `simctl delete`) :
   elles sont marquées « Commande », et la commande exacte est affichée avant de la lancer.
3. **Aperçu obligatoire** : liste exacte des chemins et taille totale, puis confirmation.
4. **Chemins protégés**, vérifiés à l'analyse puis de nouveau juste avant la Corbeille :
   - les *sanctuaires*, ni eux ni leur contenu : `~/ai-brain`, `~/.ssh`, `~/.gnupg`, `~/Documents`,
     `~/Desktop`, `~/Pictures`, `~/Library/Keychains`, `~/Library/Mobile Documents` (iCloud), Mail,
     Messages, `/System`, `/usr`, `/private` ;
   - les *ancres*, dont on peut vider le contenu mais jamais supprimer le dossier lui-même :
     `~`, `~/Library`, `~/Library/Caches`, `~/Downloads`, `/Applications`, les racines de projets…
   - supprimer le parent d'un sanctuaire ou d'une ancre est refusé aussi.

   L'idée de départ, « tout dépôt git avec des modifications non commitées », visait mal : ces
   modifications sont dans le code, que l'app ne touche jamais. Le vrai risque est un dossier au nom
   d'artefact qui contient du code (un `build/` ou un `vendor/` commité). D'où la règle suivante.
5. **Journal** de chaque action (date, chemins, taille libérée) dans
   `~/Library/Application Support/Menage/journal.jsonl`, consultable dans l'app.
6. La règle « artefacts de projets » ne touche que les noms de dossiers connus, **dans** un projet
   reconnu. Jamais un `build/` isolé. **Un dossier qui contient un seul fichier suivi par git n'est
   jamais un artefact.** Les noms ambigus (`build`, `dist`, `vendor`, `venv`) doivent en plus être
   ignorés par git (`git check-ignore`) ; hors dépôt git, on ne peut pas le prouver, donc on s'abstient.
   Les noms sans ambiguïté (`node_modules`, `.dart_tool`, `Pods`, `.gradle`, `target`, `.venv`) passent.

## Architecture

```
menage/
  Package.swift
  Sources/
    MenageCore/          ← logique pure, testée avec `swift test`
      System/            SystemMonitor (disque, swap, pression, processus)
      Scan/              Scanner (arbre de tailles, parallèle par sous-dossier)
      Rules/             CleanupRule (protocole) + une règle par fichier
      Projects/          ProjectDetector (marqueurs, dernière activité)
      History/           SnapshotStore (JSON par scan, comparaison)
      Safety/            ProtectedPaths, Trash, ActionJournal
      Treemap/           Layout squarified (pur calcul, testable)
    Menage/              ← app SwiftUI
      MenageApp.swift    MenuBarExtra + Window
      MenuBar/  Cleaner/  DiskMap/  History/  Settings/
  Tests/MenageCoreTests/
  scripts/bundle.sh      ← build release + assemblage de Menage.app + signature
```

Choix :
- **Swift Package, sans `.xcodeproj` ni dépendance.** `scripts/bundle.sh` compile et construit
  `Menage.app` (Info.plist avec `LSUIElement`, bundle id `dev.ager.menage`). Les notifications ont
  besoin d'un vrai bundle, d'où ce script.
- **Pas d'App Sandbox.** Il interdirait de scanner le dossier perso, c'est pour ça que l'app ne
  passera pas par l'App Store. Signature ad hoc pour commencer, puis le certificat Developer ID
  d'ager si on veut la distribuer.
- **Accès complet au disque** : sans lui, certains dossiers (Mail, Messages, Safari) sont illisibles.
  L'app le détecte, le signale (« X dossiers ignorés ») et ouvre le bon panneau des Réglages.
  Elle fonctionne sans.
- Scanner : `FileManager.enumerator` avec les clés de taille préchargées, un `TaskGroup` par
  sous-dossier de premier niveau, sans suivre les liens symboliques et sans sortir du volume. On ne
  passe à `getattrlistbulk` que si le scan complet de `~` (~4 M fichiers) dépasse 2 minutes.
- macOS 14 minimum (`MenuBarExtra`, `Observation`). Ce Mac est en macOS 26.4.

## Plan de construction

Chaque étape est livrable seule et vérifiée avant de passer à la suivante.

| Étape | Contenu | Vérification |
|---|---|---|
| 1 | Squelette du package, `bundle.sh`, barre de menus, SystemMonitor, alertes | `swift test` (parsing sysctl, regroupement des processus, seuils et délai entre alertes) ; l'app lancée affiche les mêmes valeurs que `vm_stat` / `df` |
| 2 | Scanner, sécurité (Corbeille, chemins protégés, journal), nettoyeur et ses règles | Tests sur une arborescence factice dans un dossier temporaire : tailles exactes, chemins protégés jamais proposés, rien hors Corbeille |
| 3 | Carte du disque et gros fichiers | Tests du layout (aires proportionnelles, pas de chevauchement) ; vérification visuelle |
| 4 | Historique et scan quotidien | Tests de comparaison de deux snapshots |

## Hors V1 (idées notées)

- Doublons de fichiers (empreinte par taille, puis hash).
- Tri des médias WhatsApp (18 Go dans iCloud) : c'est du contenu personnel, à traiter à part.
- Nettoyage des caches de gestionnaires de paquets (`~/.gradle`, `~/.pub-cache`, `~/.npm`) :
  régénérables, mais leur suppression casse le travail hors ligne.
- Widget pour le bureau.
