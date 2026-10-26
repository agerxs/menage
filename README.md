# Ménage

App macOS de barre de menus : espace disque, swap et pression mémoire en direct, alertes avant
que le Mac sature. La conception complète et les étapes suivantes sont dans [CONCEPTION.md](CONCEPTION.md).

## Construire

```bash
swift test                    # logique de MenageCore
scripts/bundle.sh             # build/Menage.app
scripts/bundle.sh --install   # copie dans ~/Applications et lance
```

Outils de développement, build debug uniquement (ils ne suppriment rien, puis quittent) :

```bash
swift build
MENAGE_RENDER=/tmp/panel.png .build/debug/Menage          # panneau de la barre de menus en image
MENAGE_SCAN=1 .build/debug/Menage                         # analyse du nettoyeur dans le terminal
MENAGE_MAP=~ .build/debug/Menage                          # scan de la carte : durée, plus gros éléments
MENAGE_TREEMAP=/tmp/carte.png .build/debug/Menage         # carte du dossier perso en image
```

Les boutons apparaissent en jaune barré sur l'image : le moteur de rendu ne dessine pas les
contrôles AppKit. Ce n'est pas un bug de l'app.
