# Diffusion d'écran Mac vers Linux

Utilisez les moniteurs d'un PC Linux comme écrans d'un Mac : chaque écran virtuel BetterDisplay est diffusé via Sunshine/Moonlight, et la souris et le clavier du Linux pilotent le Mac. Un seul écran par défaut, tout un bureau multi-écrans avec un peu de configuration. Le dépôt contient les fichiers sources des deux plateformes, les définitions de services et les modèles de configuration sans secret.

La vidéo utilise une instance Sunshine par écran sur le Mac et une fenêtre Moonlight par écran sur Linux. La saisie clavier passe par le flux de l'écran principal. Un pont Python sous Linux convertit le pointeur du bureau en coordonnées macOS et envoie les événements souris en UDP à un pont Swift sur le Mac. Le son reste sur le Mac.

## Organisation du dépôt

```text
config.example                        Modèle de réglages (un seul écran)
examples/three-screens.config         Réglages pour un bureau à trois écrans
common/mac-three-screens-config       Lecteur de configuration partagé par les deux plateformes
macos/
  install.sh                          Compile/installe le côté Mac
  bin/
    mac-sunshine-three                Superviseur BetterDisplay/Sunshine
    mac-sunshine-session              Leases d'écran et restauration de la luminosité
    mac-keyboard-backlight.m          Assistant natif de luminosité du clavier
    mac-mouse-bridge.swift            Récepteur natif d'événements souris
  launchagents/                       Modèles de démarrage à l'ouverture de session
  sunshine/
    apps.json                         Définition de l'application Bureau
    sunshine.conf.in                  Modèle de configuration Sunshine par écran
linux/
  install.sh                          Lie le côté Linux et démarre son pont
  bin/
    mac-three-screens                 Démarre/arrête/redémarre tous les flux
    moonlight-mac-display             Lance/place une fenêtre Moonlight
    mac-mouse-bridge                  Émetteur de pointeur et de touches spéciales
    mac-screens-wake                  Client de réveil/heartbeat/release
    moonlight-show-cursor.c           Garde le curseur Linux visible
  systemd/                            Définitions des services utilisateur
  kde/moonlight.kwinrule              Exception de raccourci KDE pour Moonlight
tests/                                Vérifications de régression indépendantes du bureau
```

Gardez ce dépôt à un emplacement permanent, par exemple `~/Documents/mac-three-screens`. Les scripts et unités utilisateur Linux sont des liens symboliques vers cet emplacement ; les scripts de session du Mac sont copiés dans `~/.local/bin` pour que launchd puisse les lancer hors de Documents. Si vous déplacez le dépôt, relancez l'installeur de la plateforme pour rafraîchir les fichiers installés.

## Configuration

Les deux machines lisent `~/.config/mac-three-screens/config`. Les installeurs le créent depuis `config.example` s'il manque. Le même fichier fonctionne des deux côtés ; chaque côté utilise les clés dont il a besoin. Rien sur vos machines n'est stocké dans le dépôt.

```ini
MAC_HOST=my-mac.local          # Linux : nom Bonjour ou IP filaire du Mac (obligatoire)
SCREENS=main                   # un flux par nom
SCREEN_MAIN_TAG=1              # Mac : tag BetterDisplay de cet écran virtuel (obligatoire)
```

Avec ces trois lignes seulement, vous obtenez un flux 1920 × 1080 à 60 i/s en haut à gauche du bureau Linux. Toutes les autres clés sont optionnelles :

| Clé | Défaut | Utilisée par | Signification |
| --- | --- | --- | --- |
| `MAC_HOST` | aucune (obligatoire) | Linux | Nom d'hôte ou IP du Mac. Préférez une adresse filaire réservée. |
| `MAC_JITTER_SECONDS` | `60` | Linux | Décale le pointeur du Mac de 1 px et le remet à cette fréquence pendant la diffusion ; `0` désactive. |
| `SCREENS` | `main` | les deux | Noms d'écran séparés par des espaces (lettres minuscules, chiffres, tirets). L'ordre fixe le port : le premier est 47989, chaque suivant +200. |
| `PRIMARY_SCREEN` | premier écran | les deux | L'écran qui garde le focus clavier et reçoit la frappe ; les autres sont en lecture seule. |
| `SCREEN_<NAME>_TAG` | aucune (obligatoire) | Mac | Tag BetterDisplay de l'écran virtuel. |
| `SCREEN_<NAME>_WIDTH` / `_HEIGHT` | `1920` / `1080` | les deux | Taille du flux en pixels. |
| `SCREEN_<NAME>_FPS` / `_BITRATE` | `60` / `20` | les deux | Fréquence d'images et débit (Mbps). |
| `SCREEN_<NAME>_WINDOW_X` / `_WINDOW_Y` | `0` / `0` | Linux | Coin haut gauche de la fenêtre sur le bureau Linux. |
| `SCREEN_<NAME>_MAC_X` / `_MAC_Y` | `0` / `0` | Linux | Coin haut gauche de l'écran dans les coordonnées logiques du bureau du Mac (négatif pour un écran à gauche ou au-dessus du principal). |
| `SCREEN_<NAME>_MAC_WIDTH` / `_MAC_HEIGHT` | taille du flux | Linux | Taille logique de l'écran, utilisée pour mapper le pointeur. Diffère de la taille du flux quand l'écran du Mac est HiDPI ou que le flux est mis à l'échelle. |
| `INTERNAL_SCREEN_TAG` | non défini | Mac | Tag BetterDisplay de la dalle intégrée ; éteinte pendant la diffusion et restaurée ensuite. |
| `UNMIRROR_FROM` | `Color LCD` | Mac | Noms d'écran (séparés par des virgules) dont l'écran principal est démarqué après extinction des écrans virtuels. |

`<NAME>` est le nom d'écran en majuscules avec les tirets remplacés par des underscores (`left-2` → `SCREEN_LEFT_2_TAG`). Les titres de fenêtre et les noms Sunshine sont `Mac-<name>`.

`examples/three-screens.config` est une disposition complète à trois écrans (portrait, ultralarge, paysage) avec l'agencement Mac et les origines de fenêtres qui vont avec ; copiez-la et remplacez `MAC_HOST` et les tags. Après avoir modifié le fichier, relancez l'installeur Mac (il régénère les réglages Sunshine et redémarre le superviseur) et `mac-three-screens restart` sous Linux.

Pour obtenir les tags, utilisez la CLI de BetterDisplay. Les tags appartiennent à votre installation BetterDisplay ; les identifiants de capture de macOS changent après une reconnexion ou un redémarrage, et le superviseur les résout à partir des tags et met Sunshine à jour automatiquement.

```sh
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay get -identifiers
```

## Dépendances

Développé sur macOS 27 avec BetterDisplay 5.0.6 et Sunshine 2026.922, et sur Arch Linux avec KDE Plasma/KWin 6.7 sous Wayland/XWayland avec Moonlight Qt 6. Les autres versions ne sont pas vérifiées.

Sur le Mac, installez [BetterDisplay](https://github.com/waydabber/BetterDisplay) et [Sunshine](https://github.com/LizardByte/Sunshine/releases) dans `/Applications`. Installez les outils en ligne de commande d'Apple pour `swiftc` et `clang`, et rendez Python 3 disponible :

```sh
xcode-select --install
```

Sous Linux, installez Moonlight Qt, Python 3, un compilateur C, `xdotool`, `xinput`, XWayland, `libX11`, les outils Avahi et `iproute2`. `nmap` sert de solution de repli pour la découverte des hôtes filaires. Sur Arch :

```sh
sudo pacman -S moonlight-qt python gcc xdotool xorg-xinput xorg-xwayland libx11 avahi iproute2 nmap
```

Le pont actif utilise l'entrée brute X11 et XQueryPointer via XWayland. Les lanceurs sélectionnent explicitement les backends `xcb` de Qt et `x11` de SDL.

## Installation du Mac

1. Ouvrez BetterDisplay et créez/activez un écran virtuel par écran, avec les tailles et fréquences de rafraîchissement voulues. Utilisez le mode non HiDPI à la taille du flux (`BetterDisplay set -tagID=N -resolution=WxH -hiDPI=off`) : le flux est en 1× de toute façon, et le HiDPI fait rendre et capturer quatre fois plus de pixels au Mac, ce qui coûte du GPU et de la latence. Disposez-les dans Réglages d'écrans de macOS pour correspondre aux valeurs `MAC_X`/`MAC_Y` que vous configurerez, et faites de l'écran virtuel principal l'écran principal. BetterDisplay doit tourner à l'ouverture de session.
2. Créez la configuration (voir [Configuration](#configuration)) avec vos tags, soit en copiant `config.example` vers `~/.config/mac-three-screens/config`, soit en lançant l'installeur une fois, qui la crée puis s'arrête pour que vous la remplissiez.
3. Depuis le dépôt, installez le côté Mac :

   ```sh
   cd ~/Documents/mac-three-screens
   ./macos/install.sh
   ```

   Cela compile le récepteur Swift, génère les modèles Sunshine/LaunchAgent pour votre dossier personnel et vos écrans, et démarre les deux tâches de session. Il redémarre les instances Sunshine et le récepteur souris de cette installation ; reconnectez les flux Linux ensuite s'ils tournaient.
4. Dans **Confidentialité et sécurité** de macOS, autorisez l'enregistrement d'écran et l'entrée pour Sunshine, et autorisez le contrôle d'accessibilité/entrée pour `~/.local/bin/mac-mouse-bridge`. Le récepteur tourne directement sous launchd avec `KeepAlive` : fermer le Terminal ne peut donc pas l'arrêter, et un récepteur planté redémarre automatiquement. Gardez le binaire à `~/.local/bin/mac-mouse-bridge`. macOS retire l'autorisation à chaque recompilation du binaire : si le pointeur bouge mais que les clics ne font rien, retirez-le et rajoutez-le, puis redémarrez la tâche avec `launchctl kickstart -k gui/$(id -u)/com.mac-three-screens.mouse-bridge`.
5. Ouvrez chaque interface web Sunshine et créez son compte local s'il s'agit d'une installation neuve. L'écran *n* (en comptant à partir de 0) diffuse sur le port `47989 + 200·n` ; son interface web est sur le port immédiatement supérieur, à `https://localhost:<port>`.

   | Écran (dans l'ordre de `SCREENS`) | Adresse du flux | Interface web du Mac |
   | --- | --- | --- |
   | 1er | `MAC_HOST:47989` | `https://localhost:47990` |
   | 2e | `MAC_HOST:48189` | `https://localhost:48190` |
   | 3e | `MAC_HOST:48389` | `https://localhost:48390` |

   Laissez chaque instance générer ses propres certificats et son état. L'installeur préserve les identités et fichiers d'appairage existants.
6. Le pont transmet spécialement deux touches pour un clavier français AZERTY ISO (la touche ISO à côté du Maj gauche et la touche `²`). Si c'est votre disposition, ajoutez la source d'entrée **Français – PC** dans les réglages clavier de macOS et basculez manuellement entre elle (pour la saisie Linux) et la disposition propre au Mac. Les autres dispositions peuvent demander de petites modifications dans `linux/bin/mac-mouse-bridge` et `macos/bin/mac-mouse-bridge.swift`.
7. Choisissez les haut-parleurs du Mac ou un casque comme sortie audio de macOS. Toutes les configurations Sunshine ont `stream_audio = false` ; l'audio Moonlight ne fait pas partie de cette installation.

Le superviseur rafraîchit les identifiants de capture de Sunshine chaque fois que les écrans virtuels se connectent. Le lanceur Linux réveille le Mac via le pont souris toujours actif avant de démarrer Moonlight, les écrans virtuels peuvent donc rester déconnectés pendant l'usage normal du Mac.

Chaque flux détient un lease sur le Mac pendant qu'il tourne. Sunshine exécute l'`acquire` d'un lease quand un client se connecte (ce hook ne fait qu'enregistrer le lease ; la mise en place des écrans est faite par la demande de réveil Linux), et chaque flux Moonlight actif le rafraîchit toutes les 45 secondes via le pont souris. Quand un flux se termine volontairement, il envoie aussi un release, donc `mac-three-screens stop` éteint les écrans en quelques secondes ; le premier flux à se connecter efface le maintien de réveil, et une demande de réveil tardive d'un client qui a trop réessayé est ignorée dès qu'un flux possède les écrans. Si le Mac n'entend plus rien du tout (plantage, coupure réseau, câble arraché), le lease expire simplement après 150 secondes et le superviseur éteint les écrans de lui-même.

Les leases sont renouvelés par les processus Moonlight actifs, indépendamment de l'activité clavier ou souris. Le pont Mac ferme chaque flux UDP de réveil/heartbeat/release après avoir répondu ; sinon les ports clients qui s'accumulent peuvent saturer la table de flux UDP, arrêter les renouvellements et bloquer les démarrages suivants. Les renouvellements échoués apparaissent dans les logs des flux Linux.

Une demande de réveil écrit son propre lease court. C'est ce qui empêche le superviseur de rééteindre les écrans pendant que Sunshine redémarre autour des nouveaux identifiants de capture.

Le superviseur utilise `lockf` de macOS avec `~/.config/sunshine-three-supervisor.lock` ; le noyau libère le verrou à la fin du processus ou au redémarrage, même si le fichier reste. Un démarrage échoué efface son lease de réveil et restaure le Mac ; Linux signale une erreur de préparation au lieu de lancer Moonlight vers un hôte non résolu. La dernière IP qui fonctionnait est aussi essayée quand mDNS tarde.

Le LaunchAgent `com.mac-three-screens.supervisor` a `KeepAlive`, car un superviseur qui meurt en silence fait la différence entre "ça marche" et "tous les flux renvoient 503". Si vous voyez des 503, vérifiez d'abord que l'agent tourne : `launchctl list | grep mac-three-screens` et `mac-sunshine-session has-active`.

Sur un portable Apple silicon, la dalle intégrée ne peut pas toujours être déconnectée via BetterDisplay. Définir `INTERNAL_SCREEN_TAG` l'éteint en mettant sa luminosité à zéro pendant la diffusion, et remet la luminosité précédente à la fin de la session ; la valeur est enregistrée dans `~/.config/sunshine-three-internal-brightness` pour la durée de la session.

Le rétroéclairage du clavier intégré est coupé par le petit assistant natif `mac-keyboard-backlight`, compilé par l'installeur Mac. Il utilise CoreBrightness directement ; les touches de luminosité simulées et `hidutil` ne fonctionnent pas sur les macOS actuels. La session enregistre la luminosité actuelle du clavier et le réglage de luminosité automatique, désactive la luminosité automatique pendant la diffusion, puis restaure les deux à l'arrêt. Si le clavier était déjà éteint, `~/.config/sunshine-three-keyboard-backlight` fournit le niveau de restauration (`0`–`1`, par défaut `1.0`). CoreBrightness est une interface privée de macOS : l'assistant signale une erreur si une future version de macOS la change.

Le pont Linux suit l'adresse choisie par le lanceur de diffusion, enregistrée dans `~/.local/state/mac-three-screens/host`, au lieu de conserver l'adresse devinée à la connexion. Les heartbeats et les releases utilisent aussi cette même adresse.

## Installation Linux et appairage

1. Placez le même dépôt à `~/Documents/mac-three-screens` sous Linux. Lancez l'installeur depuis un terminal dans votre session KDE :

   ```sh
   cd ~/Documents/mac-three-screens
   ./linux/install.sh
   ```

   Il crée les liens vers les commandes et les unités utilisateur systemd, compile le shim de curseur, crée le dossier de logs, et active/démarre le pont souris. Si `~/.config/mac-three-screens/config` n'existe pas encore, il le crée depuis `config.example` et s'arrête ; renseignez `MAC_HOST` (et vos écrans) puis relancez-le. Il laisse intactes les données d'appairage Sunshine/Moonlight. KDE crée un nouveau fichier d'autorisation XWayland à chaque connexion ; le pont le découvre au lieu de figer un ancien nom de fichier.
2. Importez `linux/kde/moonlight.kwinrule` dans **Paramètres système → Gestion des fenêtres → Règles de fenêtres**. La règle désactive les raccourcis globaux de KDE quand une fenêtre Moonlight a le focus, pour que les combinaisons Super/Meta arrivent au Mac comme des combinaisons Command.
3. Dans les actions souris de fenêtre de KDE, mettez l'action modificateur + bouton gauche sur **Rien**. Le réglage dans `~/.config/kwinrc` est :

   ```ini
   [MouseBindings]
   CommandAll1=Nothing
   ```

   Cela permet la sélection par Command-clic au lieu que KDE capture la fenêtre. C'est une liaison souris valable pour tout le bureau. L'installeur ne réécrit pas votre configuration KDE.
4. Appairez chaque profil Moonlight isolé avec l'instance Sunshine correspondante. Chaque écran a son propre dossier de profil, `~/.config/moonlight-<name>`. Ouvrez une interface à la fois depuis le terminal KDE, ajoutez `MAC_HOST:<port>` pour cet écran, et saisissez le PIN affiché par Moonlight dans l'interface web Sunshine de cet écran :

   ```sh
   XDG_CONFIG_HOME="$HOME/.config/moonlight-main" QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 moonlight
   ```

   Appairez chaque profil d'écran séparément puis fermez les interfaces.
5. Vérifiez que `~/.local/bin` est dans le PATH de votre shell, puis démarrez :

   ```sh
   mac-three-screens start
   ```

Le pont et les lanceurs vidéo cherchent des adresses Sunshine joignables et préfèrent le chemin le plus rapide quand le Mac annonce des adresses Wi-Fi et Ethernet. La découverte réseau peut prendre plusieurs secondes. L'Ethernet filaire est la connexion prévue. Après avoir changé `MAC_HOST` :

```sh
systemctl --user restart mac-mouse-bridge
mac-three-screens restart
```

## Usage quotidien

```sh
mac-three-screens start          # Lance et place toutes les fenêtres
mac-three-screens status
mac-three-screens restart
mac-three-screens stop
```

La fenêtre Moonlight de l'écran principal possède le focus clavier. Le pont souris envoie les événements globaux du pointeur du Mac sur tous les écrans. Les autres flux sont des visionneuses : Sunshine refuse leur souris et leur clavier. Le pont libère leur capture après les clics et rend le focus clavier au principal.

Réduisez le flux principal avec **Ctrl+Shift+Alt+D** pour utiliser le bureau Linux. Tant qu'il est réduit, le pont suspend la transmission souris et touches spéciales sur tous les écrans et relâche les boutons/modificateurs maintenus. Les clics sur les fenêtres latérales ne peuvent pas restaurer le flux principal. Restaurez sa fenêtre pour reprendre le contrôle ; les fenêtres latérales réduites ne reçoivent jamais d'entrée souris.

`mac-three-screens stop` libère explicitement toutes les sessions d'affichage après avoir fermé Moonlight, y compris en fenêtre réduite. Il signale une erreur si le Mac n'accuse pas réception d'un release. Le démarrage revérifie le plein écran pendant les dix premières secondes, le temps que Moonlight initialise sa surface vidéo.

Pour un usage normal du Mac, arrêtez les flux sous Linux. En deux minutes et demie environ, les leases expirent et le Mac déconnecte les écrans virtuels. Lancer `mac-three-screens` les réveille avant que Moonlight ne se connecte.

Pour désactiver complètement l'entrée souris distante, `systemctl --user stop mac-mouse-bridge` ; pour la rétablir, `systemctl --user start mac-mouse-bridge`.

## Modification et mise à jour

Modifiez les fichiers dans le dépôt. Les scripts Linux sont liés directement ; redémarrez le service souris après avoir changé son code Python, et redémarrez les flux après avoir changé le lanceur. Lancez `systemctl --user daemon-reload` après avoir modifié les définitions de services Linux.

Les changements de source Swift du Mac demandent une recompilation avec `./macos/install.sh`. Les réglages Sunshine et les modèles de LaunchAgent sont générés par cet installeur. Modifiez `macos/sunshine/sunshine.conf.in` plutôt que de compter sur la conservation de modifications faites à chaud.

Les deux installeurs acceptent `--no-start` pour installer les liens de sources et la configuration sans redémarrer les services. Sur le Mac, ce mode préserve un binaire de pont existant ; il n'en compile un que s'il manque.

Pour une autre disposition de bureau, modifiez la configuration : taille du flux, FPS, débit et origines de fenêtres sont par écran, et les clés `MAC_*` sont les coordonnées **logiques** d'écran vers lesquelles le pointeur est mappé. Changer seulement la taille du flux ne change pas la carte des coordonnées souris. Gardez la fréquence de rafraîchissement de BetterDisplay en phase avec `FPS`.

## Vérifications et dépannage

Lancez la petite vérification de régression depuis l'un ou l'autre dépôt :

```sh
python3 tests/check.py
```

Elle vérifie le mapping du pointeur, la distinction entre clic ordinaire et vrai glisser, le lecteur de configuration, la syntaxe des scripts et modèles, et l'isolation des entrées des flux secondaires. Sur le Mac, vous pouvez aussi vérifier les types du récepteur :

```sh
swiftc -typecheck macos/bin/mac-mouse-bridge.swift
```

Pour tester le pont de contrôle depuis Linux avec un Mac actif ou inactif (aucun événement souris ou clavier n'est envoyé) :

```sh
python3 tests/check-bridge.py MAC_IP
```

Cela ouvre 1 100 sockets clients UDP pour détecter l'ancienne panne d'accumulation de flux.

Diagnostics Linux :

```sh
systemctl --user status mac-mouse-bridge
journalctl --user -u mac-mouse-bridge -n 50
tail -n 50 ~/.local/state/mac-three-screens/<name>.log
mac-three-screens-config check linux
```

Les logs du Mac sont `~/.config/mac-mouse-bridge.log`, `~/.config/sunshine-three-autostart.log` et `~/.config/sunshine-<name>/sunshine.log` ; `mac-three-screens-config check mac` valide la configuration.

- **La vidéo se connecte mais les clics souris échouent :** vérifiez le service du pont Linux et la permission d'accessibilité macOS du pont souris. Vérifiez le port UDP 45991 et les coordonnées `MAC_*`.
- **Le curseur Linux est invisible sur un flux :** Moonlight le cache pendant la capture. Le lanceur précharge `~/.local/lib/moonlight-show-cursor.so` pour le garder visible ; relancez `linux/install.sh` si ce fichier manque.
- **Le rechargement de Chromium ouvre son menu :** les clics ordinaires ne doivent pas envoyer un nouvel échantillon de pointeur au relâchement du bouton. Cela crée un glisser synthétique quand Moonlight décale le pointeur. La vérification de régression protège ce correctif. Gardez l'entrée clavier Sunshine désactivée sur les écrans secondaires pour que les raccourcis de capture locaux ne puissent pas injecter de modificateurs.
- **Command-clic déplace une fenêtre Linux ou Command-V ouvre le presse-papiers KDE :** vérifiez la règle de fenêtre importée, la liaison souris avec modificateur de KDE, et le focus de Moonlight principal.
- **Un écran se reconnecte incorrectement :** vérifiez les tags et l'agencement BetterDisplay, puis les logs Sunshine. Redémarrez les flux Linux une fois que les hôtes écoutent de nouveau.
- **Pas de son du Mac :** vérifiez la sortie choisie dans macOS et que `stream_audio = false` est toujours dans la configuration de chaque hôte.

## Fichiers volontairement laissés hors de Git

L'état d'exécution reste aux emplacements habituels du système :

- Mac : `~/.config/sunshine-<name>/` contient les identifiants, certificats, l'état d'appairage, les configurations générées et les logs. `~/.local/bin/mac-mouse-bridge` est un exécutable généré ; `~/Library/LaunchAgents` contient les fichiers de démarrage générés.
- Linux : `~/.config/moonlight-<name>/` contient l'identité de chaque client et les hôtes appairés. `~/.local/state/mac-three-screens/` contient les logs des flux.
- Les deux : `~/.config/mac-three-screens/config` est votre fichier de réglages local. Les réglages KDE sont locaux aussi.

Ne copiez pas les identifiants/certificats Sunshine ni des profils Moonlight entiers dans le dépôt. Une installation neuve réappaire. Le récepteur est un service d'entrée UDP non authentifié et non chiffré, prévu pour un réseau local de confiance, et il envoie les entrées tant que le pont tourne.

## Références amont

- [Configuration de Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html) : chemins d'instance, ports, sélection de capture et options d'entrée/audio.
- [Installation de Moonlight et raccourcis de capture](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide) : appairage et bascules de capture et de verrouillage du pointeur utilisées par les lanceurs.
- [CLI de BetterDisplay](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI) : identifiants de tags et d'écrans.

La géométrie des écrans, le comportement des entrées KDE et la capacité d'encodage simultané varient selon la machine ; vérifiez les changements à la souris après la vérification automatique.
