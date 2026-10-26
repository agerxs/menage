# Ménage

App macOS de barre de menus : espace disque, swap et pression mémoire en direct, alertes avant
que le Mac sature. La conception complète et les étapes suivantes sont dans [CONCEPTION.md](CONCEPTION.md).

## Construire

```bash
swift test                    # logique de MenageCore
scripts/bundle.sh             # build/Menage.app
scripts/bundle.sh --install   # copie dans ~/Applications et lance
```

Vérifier le rendu du panneau sans cliquer dans la barre de menus (build debug) :

```bash
swift build && MENAGE_RENDER=/tmp/panel.png .build/debug/Menage
```

Les boutons apparaissent en jaune barré sur l'image : le moteur de rendu ne dessine pas les
contrôles AppKit. Ce n'est pas un bug de l'app.
