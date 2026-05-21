#!/bin/bash

# ==============================================================================
# TITRE : Linux post install
# DESCRIPTION : Réseau, AD, Bashrc, Install de paquets
# ==============================================================================

# Sécurité : Vérification du lancement avec root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez lancer ce script avec sudo !"
  exit 1
fi

# Utilisateur pour le .bashrc
USER=$SUDO_USER
if [ -z "$USER" ]; then USER=$(whoami); fi

# Détection de la distribution (Debian, Ubuntu, Mint...)
DISTRO=$(lsb_release -is 2>/dev/null || cat /etc/os-release | grep -E '^ID=' | cut -d= -f2 | tr -d '"')

# ==============================================================================
# 1. INITIALISATION DES DÉPÔTS SELON LA DISTRIBUTION
# ==============================================================================
# Si Debian : On active contrib et non-free
if [ "$DISTRO" == "Debian" ] || [ -f /etc/debian_version ] && [ "$DISTRO" != "Ubuntu" ] && [ "$DISTRO" != "LinuxMint" ]; then
    echo "Configuration des depots Debian (Contrib & Non-Free)..."
    sudo apt-get install -y software-properties-common
    sudo apt-add-repository contrib -y
    sudo apt-add-repository non-free -y
    sudo apt-add-repository non-free-firmware -y
fi

# Si on est sur Ubuntu ou Linux Mint : On s'assure d'activer le dépôt Multiverse pour Steam
if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "LinuxMint" ]; then
    echo "Configuration des depots Ubuntu/Mint (Multiverse)..."
    sudo add-apt-repository multiverse -y
fi

echo "Rafraichissement des sources et installation de la base Sysadmin..."
apt update

# Installations des outils de base
apt install -y whiptail flatpak zip locate ncdu curl git screen dnsutils \
               net-tools sudo lynx lsb-release winbind samba gpg

# Ajout du catalogue Flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ==============================================================================
# 2. MENU DES PAQUETS
# ==============================================================================

CHOIX_PAQUETS=$(whiptail --title "Selection des Logiciels" --checklist \
"Appuyez sur ESPACE pour cocher/decocher, puis ENTREE pour valider :" 22 85 15 \
"fastfetch"       "Affiche les infos du systeme au demarrage" ON \
"htop"            "Gestionnaire de taches classique en CLI" ON \
"btop"            "Gestionnaire de taches moderne" ON \
"vim"             "L editeur de texte incontournable (Sera mis par defaut)" ON \
"openssh-server"  "Serveur SSH pour controler la machine a distance" ON \
"wireshark"       "Analyseur de protocoles network" ON \
"cifs-utils"      "Outils de montage de partages reseau Windows/NAS" ON \
"thunderbird"     "Client de messagerie et calendrier complet" ON \
"build-essential" "Compilateurs C/C++ et utilitaires de dev (make)" OFF \
"docker.io"       "Moteur de conteneurs Docker" OFF \
"filezilla"       "Client FTP/SFTP graphique" OFF \
"steam"           "Plateforme de jeux video de Valve (Flatpak)" OFF \
"protonvpn"       "Client VPN officiel Proton GUI (Depot officiel .deb)" OFF \
"vscode"          "Editeur de code Visual Studio Code (Flatpak)" OFF \
"gimp"            "Retouche d images et dessin (Alternative Photoshop)" OFF \
"obs-studio"      "Logiciel d enregistrement d ecran et streaming" OFF \
"audacity"        "Editeur et enregistreur de fichiers audio" OFF \
"copyq"           "Gestionnaire de presse-papier avance" OFF \
"piper"           "Configuration graphique des souris Gaming" OFF \
"flatseal"        "Gestionnaire de permissions pour les Flatpak" OFF \
"bitwarden"       "Gestionnaire de mots de passe securise (Flatpak)" OFF \
"discord"         "Messagerie et chat pour les communautes (Flatpak)" OFF \
"lutris"          "Gestionnaire universel pour jeux Windows/Wine (Flatpak)" OFF \
"heroic"          "Launcher pour Epic Games et GOG (Flatpak)" OFF \
"protonup-qt"     "Gestionnaire de versions de Proton pour le jeu (Flatpak)" OFF \
"minecraft"       "Le launcher officiel du jeu Minecraft (Flatpak)" OFF \
3>&1 1>&2 2>&3)

LISTE_PAQUETS=$(echo "$CHOIX_PAQUETS" | tr -d '"')

# ==============================================================================
# 3. CONFIGURATION RÉSEAU
# ==============================================================================
INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)

whiptail --title "Configuration Reseau" --yesno "Voulez-vous configurer une IP FIXE ?\n(Si vous repondez non, la machine restera en DHCP)" 10 60
CHOIX_RESEAU=$?

if [ $CHOIX_RESEAU -eq 0 ]; then
    IP_RESEAU=$(whiptail --inputbox "Entrez l IP souhaitee + CIDR (ex: 192.168.1.50/24):" 10 60 "192.168.1.50/24" 3>&1 1>&2 2>&3)
    GW_RESEAU=$(whiptail --inputbox "Entrez l IP de la Gateway :" 10 60 "192.168.1.1" 3>&1 1>&2 2>&3)
    DNS_RESEAU=$(whiptail --inputbox "Entrez l IP du serveur DNS :" 10 60 "1.1.1.1" 3>&1 1>&2 2>&3)

    if [ -d "/etc/netplan" ]; then
        cp /etc/netplan/*.yaml /etc/netplan/01-netcfg.yaml.bak 2>/dev/null
        cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [- $IP_RESEAU]
      routes: [- to: default, via: $GW_RESEAU]
      nameservers:
        addresses: [$DNS_RESEAU]
EOF
        netplan apply
    else
        cp /etc/network/interfaces /etc/network/interfaces.bak 2>/dev/null
        IP_PROPRE=$(echo $IP_RESEAU | cut -d/ -f1)
        cat << EOF >> /etc/network/interfaces
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_PROPRE
    gateway $GW_RESEAU
EOF
        echo "nameserver $DNS_RESEAU" > /etc/resolv.conf
        systemctl restart networking 2>/dev/null || systemctl restart systemd-networkd
    fi
fi

# ==============================================================================
# 4. JONCTION A UN DOMAINE ACTIVE DIRECTORY
# ==============================================================================
whiptail --title "Active Directory" --yesno "Voulez-vous joindre un domaine Active Directory ?" 10 60
CHOIX_AD=$?

if [ $CHOIX_AD -eq 0 ]; then
    NOM_DOMAINE=$(whiptail --inputbox "Entrez le nom du domaine (ex: domain.local) :" 10 60 3>&1 1>&2 2>&3)
    ADMIN_DOMAINE=$(whiptail --inputbox "Entrez le compte Administrateur du domaine :" 10 60 "Administrator" 3>&1 1>&2 2>&3)
    
    echo "Installation des paquets AD..."
    apt install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin
    realm join --user=$ADMIN_DOMAINE $NOM_DOMAINE
    pam-auth-update --enable mkhomedir
fi

# ==============================================================================
# 5. INSTALLATIONS DES LOGICIELS
# ==============================================================================
clear
echo "=========================================================================="
echo "DEBUT DES INSTALLATIONS LOGICIELLES"
echo "=========================================================================="

# Mise à jour des paquets
apt upgrade -y

# 1. Tri et installation des paquets système via apt
APTS_A_INSTALLER=""
for p in $LISTE_PAQUETS; do
    if [[ "$p" != "steam" && "$p" != "vscode" && "$p" != "bitwarden" && "$p" != "protonvpn" && "$p" != "spotify" && "$p" != "discord" && "$p" != "lutris" && "$p" != "heroic" && "$p" != "protonup-qt" && "$p" != "minecraft" ]]; then
        APTS_A_INSTALLER="$APTS_A_INSTALLER $p"
    fi
done

if [ ! -z "$APTS_A_INSTALLER" ]; then
    echo "Installation des paquets choisis :$APTS_A_INSTALLER"
    apt install -y $APTS_A_INSTALLER
fi

if [[ "$LISTE_PAQUETS" =~ "protonvpn" ]]; then
    echo "Recuperation dynamique et installation du depot Proton VPN..."
    
    # Importation prealable de la cle GPG publique de Proton pour eviter le blocage de signature sur Debian
    mkdir -p /usr/share/keyrings
    curl -s https://repo.protonvpn.com/debian/public_key.asc | gpg --dearmor -o /usr/share/keyrings/protonvpn-stable-archive-keyring.gpg 2>/dev/null
    
    URL_DEB=$(curl -s https://repo.protonvpn.com/debian/dists/stable/main/binary-all/ | grep -oE 'protonvpn-stable-release_[0-9.]+_all.deb' | head -n 1)
    
    if [ ! -z "$URL_DEB" ]; then
        wget -q "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/$URL_DEB"
        dpkg -i "./$URL_DEB"
        apt update
        apt install -y proton-vpn-gnome-desktop
        rm "./$URL_DEB"
        echo "Proton VPN a ete installe avec succes."
    else
        echo "Echec : Impossible de detecter le paquet Proton VPN sur les serveurs officiels. Installation annulee."
    fi
fi

# 2. Installation des applications choisies via FLATPAK
FLATPAK_BIN="/usr/bin/flatpak"

if [ -x "$FLATPAK_BIN" ]; then
    if [[ "$LISTE_PAQUETS" =~ "steam" ]];        then $FLATPAK_BIN install flathub com.valvesoftware.Steam -y; fi
    if [[ "$LISTE_PAQUETS" =~ "vscode" ]];      then $FLATPAK_BIN install flathub com.visualstudio.code -y; fi
    if [[ "$LISTE_PAQUETS" =~ "bitwarden" ]];   then $FLATPAK_BIN install flathub com.bitwarden.desktop -y; fi
    if [[ "$LISTE_PAQUETS" =~ "spotify" ]];     then $FLATPAK_BIN install flathub com.spotify.Client -y; fi
    if [[ "$LISTE_PAQUETS" =~ "discord" ]];     then $FLATPAK_BIN install flathub com.discordapp.Discord -y; fi
    if [[ "$LISTE_PAQUETS" =~ "lutris" ]];      then $FLATPAK_BIN install flathub net.lutris.Lutris -y; fi
    if [[ "$LISTE_PAQUETS" =~ "heroic" ]];      then $FLATPAK_BIN install flathub com.heroicgameslauncher.hgl -y; fi
    if [[ "$LISTE_PAQUETS" =~ "protonup-qt" ]]; then $FLATPAK_BIN install flathub net.davidotek.pupgui2 -y; fi
    if [[ "$LISTE_PAQUETS" =~ "minecraft" ]];   then $FLATPAK_BIN install flathub com.mojang.Minecraft -y; fi
fi

# Post-configuration de Wireshark pour pouvoir l'utiliser sans être Root
if [[ "$LISTE_PAQUETS" =~ "wireshark" ]]; then
    echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
    dpkg-reconfigure -f noninteractive wireshark-common
    usermod -aG wireshark $USER
fi

# ==============================================================================
# 6. CONFIGURATION DU FICHIER BASHRC
# ==============================================================================
echo "Configuration de l environnement par defaut"

# Définir Vim comme éditeur système par défaut
if [ -x /usr/bin/vim ]; then
    update-alternatives --set editor /usr/bin/vim.basic 2>/dev/null
fi

configurer_bashrc() {
    local TARGET_BASHRC=$1
    if [ -f "$TARGET_BASHRC" ] && ! grep -q "alias ll=" "$TARGET_BASHRC"; then
        cat << 'EOF' >> "$TARGET_BASHRC"

# --- CONFIGURATION UTILISATEUR ---
export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'
alias grep='grep --color=auto'

# Forcer l'utilisation de VIM par défaut
export EDITOR='vim'
export VISUAL='vim'

# Lancement automatique de fastfetch
if [ -x /usr/bin/fastfetch ]; then fastfetch; fi
EOF
    fi
}

# Application pour Root et l'Utilisateur
configurer_bashrc "/root/.bashrc"
if [ "$USER" != "root" ] && [ -d "/home/$USER" ]; then
    configurer_bashrc "/home/$USER/.bashrc"
    chown $USER:$USER /home/$USER/.bashrc
fi

echo "=========================================================================="
echo "Le script est termine !"
echo "=========================================================================="

exec sudo -u $USER bash#!/bin/bash

# ==============================================================================
# TITRE : Linux post install
# DESCRIPTION : Réseau, AD, Bashrc, Install de paquets
# ==============================================================================

# Sécurité : Vérification du lancement avec root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez lancer ce script avec sudo !"
  exit 1
fi

# Utilisateur pour le .bashrc
USER=$SUDO_USER
if [ -z "$USER" ]; then USER=$(whoami); fi

# Détection de la distribution (Debian, Ubuntu, Mint...)
DISTRO=$(lsb_release -is 2>/dev/null || cat /etc/os-release | grep -E '^ID=' | cut -d= -f2 | tr -d '"')

# ==============================================================================
# 1. INITIALISATION DES DÉPÔTS SELON LA DISTRIBUTION
# ==============================================================================
# Si Debian : On active contrib et non-free
if [ "$DISTRO" == "Debian" ] || [ -f /etc/debian_version ] && [ "$DISTRO" != "Ubuntu" ] && [ "$DISTRO" != "LinuxMint" ]; then
    echo "Configuration des depots Debian (Contrib & Non-Free)..."
    sudo apt-get install -y software-properties-common
    sudo apt-add-repository contrib -y
    sudo apt-add-repository non-free -y
    sudo apt-add-repository non-free-firmware -y
fi

# Si on est sur Ubuntu ou Linux Mint : On s'assure d'activer le dépôt Multiverse pour Steam
if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "LinuxMint" ]; then
    echo "Configuration des depots Ubuntu/Mint (Multiverse)..."
    sudo add-apt-repository multiverse -y
fi

echo "Rafraichissement des sources et installation de la base Sysadmin..."
apt update

# Installations des outils de base
apt install -y whiptail flatpak zip locate ncdu curl git screen dnsutils \
               net-tools sudo lynx lsb-release winbind samba

# Ajout du catalogue Flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ==============================================================================
# 2. MENU DES PAQUETS
# ==============================================================================

CHOIX_PAQUETS=$(whiptail --title "Selection des Logiciels" --checklist \
"Appuyez sur ESPACE pour cocher/decocher, puis ENTREE pour valider :" 22 85 15 \
"fastfetch"       "Affiche les infos du systeme au demarrage" ON \
"htop"            "Gestionnaire de taches classique en CLI" ON \
"btop"            "Gestionnaire de taches moderne" ON \
"vim"             "L editeur de texte incontournable (Sera mis par defaut)" ON \
"openssh-server"  "Serveur SSH pour controler la machine a distance" ON \
"wireshark"       "Analyseur de protocoles reseau" ON \
"cifs-utils"      "Outils de montage de partages reseau Windows/NAS" ON \
"thunderbird"     "Client de messagerie et calendrier complet" ON \
"build-essential" "Compilateurs C/C++ et utilitaires de dev (make)" OFF \
"docker.io"       "Moteur de conteneurs Docker" OFF \
"filezilla"       "Client FTP/SFTP graphique" OFF \
"steam"           "Plateforme de jeux video de Valve (APT)" OFF \
"protonvpn"       "Client VPN officiel Proton GUI (Depot officiel .deb)" OFF \
"vscode"          "Editeur de code Visual Studio Code (Flatpak)" OFF \
"gimp"            "Retouche d images et dessin (Alternative Photoshop)" OFF \
"obs-studio"      "Logiciel d enregistrement d ecran et streaming" OFF \
"audacity"        "Editeur et enregistreur de fichiers audio" OFF \
"copyq"           "Gestionnaire de presse-papier avance" OFF \
"piper"           "Configuration graphique des souris Gaming" OFF \
"flatseal"        "Gestionnaire de permissions pour les Flatpak" OFF \
"bitwarden"       "Gestionnaire de mots de passe securise (Flatpak)" OFF \
"discord"         "Messagerie et chat pour les communautes (Flatpak)" OFF \
"lutris"          "Gestionnaire universel pour jeux Windows/Wine (Flatpak)" OFF \
"heroic"          "Launcher pour Epic Games et GOG (Flatpak)" OFF \
"protonup-qt"     "Gestionnaire de versions de Proton pour le jeu (Flatpak)" OFF \
"minecraft"       "Le launcher officiel du jeu Minecraft (Flatpak)" OFF \
3>&1 1>&2 2>&3)

LISTE_PAQUETS=$(echo "$CHOIX_PAQUETS" | tr -d '"')

# ==============================================================================
# 3. CONFIGURATION RÉSEAU
# ==============================================================================
INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)

whiptail --title "Configuration Reseau" --yesno "Voulez-vous configurer une IP FIXE ?\n(Si vous repondez non, la machine restera en DHCP)" 10 60
CHOIX_RESEAU=$?

if [ $CHOIX_RESEAU -eq 0 ]; then
    IP_RESEAU=$(whiptail --inputbox "Entrez l IP souhaitee + CIDR (ex: 192.168.1.50/24):" 10 60 "192.168.1.50/24" 3>&1 1>&2 2>&3)
    GW_RESEAU=$(whiptail --inputbox "Entrez l IP de la Gateway :" 10 60 "192.168.1.1" 3>&1 1>&2 2>&3)
    DNS_RESEAU=$(whiptail --inputbox "Entrez l IP du serveur DNS :" 10 60 "1.1.1.1" 3>&1 1>&2 2>&3)

    if [ -d "/etc/netplan" ]; then
        cp /etc/netplan/*.yaml /etc/netplan/01-netcfg.yaml.bak 2>/dev/null
        cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [- $IP_RESEAU]
      routes: [- to: default, via: $GW_RESEAU]
      nameservers:
        addresses: [$DNS_RESEAU]
EOF
        netplan apply
    else
        cp /etc/network/interfaces /etc/network/interfaces.bak 2>/dev/null
        IP_PROPRE=$(echo $IP_RESEAU | cut -d/ -f1)
        cat << EOF >> /etc/network/interfaces
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_PROPRE
    gateway $GW_RESEAU
EOF
        echo "nameserver $DNS_RESEAU" > /etc/resolv.conf
        systemctl restart networking 2>/dev/null || systemctl restart systemd-networkd
    fi
fi

# ==============================================================================
# 4. JONCTION A UN DOMAINE ACTIVE DIRECTORY
# ==============================================================================
whiptail --title "Active Directory" --yesno "Voulez-vous joindre un domaine Active Directory ?" 10 60
CHOIX_AD=$?

if [ $CHOIX_AD -eq 0 ]; then
    NOM_DOMAINE=$(whiptail --inputbox "Entrez le nom du domaine (ex: domain.local) :" 10 60 3>&1 1>&2 2>&3)
    ADMIN_DOMAINE=$(whiptail --inputbox "Entrez le compte Administrateur du domaine :" 10 60 "Administrator" 3>&1 1>&2 2>&3)
    
    echo "Installation des paquets AD..."
    apt install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin
    realm join --user=$ADMIN_DOMAINE $NOM_DOMAINE
    pam-auth-update --enable mkhomedir
fi

# ==============================================================================
# 5. INSTALLATIONS DES LOGICIELS
# ==============================================================================
clear
echo "=========================================================================="
echo "DEBUT DES INSTALLATIONS LOGICIELLES"
echo "=========================================================================="

# Mise à jour des paquets
apt upgrade -y

# 1. Tri et installation des paquets système via apt
APTS_A_INSTALLER=""
for p in $LISTE_PAQUETS; do
    if [[ "$p" != "vscode" && "$p" != "bitwarden" && "$p" != "protonvpn" && "$p" != "spotify" && "$p" != "discord" && "$p" != "lutris" && "$p" != "heroic" && "$p" != "protonup-qt" && "$p" != "minecraft" ]]; then
        APTS_A_INSTALLER="$APTS_A_INSTALLER $p"
    fi
done

if [ ! -z "$APTS_A_INSTALLER" ]; then
    echo "Installation des paquets choisis :$APTS_A_INSTALLER"
    apt install -y $APTS_A_INSTALLER
fi

if [[ "$LISTE_PAQUETS" =~ "protonvpn" ]]; then
    echo "Recuperation dynamique et installation du depot Proton VPN..."
    
    URL_DEB=$(curl -s https://repo.protonvpn.com/debian/dists/stable/main/binary-all/ | grep -oE 'protonvpn-stable-release_[0-9.]+_all.deb' | head -n 1)
    
    if [ ! -z "$URL_DEB" ]; then
        wget -q "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/$URL_DEB"
        dpkg -i "./$URL_DEB"
        apt update
        apt install -y proton-vpn-gnome-desktop
        rm "./$URL_DEB"
        echo "Proton VPN a ete installe avec succes."
    else
        echo "Echec : Impossible de detecter le paquet Proton VPN sur les serveurs officiels. Installation annulee."
    fi
fi

# 2. Installation des applications choisies via FLATPAK
FLATPAK_BIN="/usr/bin/flatpak"

if [ -x "$FLATPAK_BIN" ]; then
    if [[ "$LISTE_PAQUETS" =~ "vscode" ]];      then $FLATPAK_BIN install flathub com.visualstudio.code -y; fi
    if [[ "$LISTE_PAQUETS" =~ "bitwarden" ]];   then $FLATPAK_BIN install flathub com.bitwarden.desktop -y; fi
    if [[ "$LISTE_PAQUETS" =~ "spotify" ]];     then $FLATPAK_BIN install flathub com.spotify.Client -y; fi
    if [[ "$LISTE_PAQUETS" =~ "discord" ]];     then $FLATPAK_BIN install flathub com.discordapp.Discord -y; fi
    if [[ "$LISTE_PAQUETS" =~ "lutris" ]];      then $FLATPAK_BIN install flathub net.lutris.Lutris -y; fi
    if [[ "$LISTE_PAQUETS" =~ "heroic" ]];      then $FLATPAK_BIN install flathub com.heroicgameslauncher.hgl -y; fi
    if [[ "$LISTE_PAQUETS" =~ "protonup-qt" ]]; then $FLATPAK_BIN install flathub net.davidotek.pupgui2 -y; fi
    if [[ "$LISTE_PAQUETS" =~ "minecraft" ]];   then $FLATPAK_BIN install flathub com.mojang.Minecraft -y; fi
fi

# Post-configuration de Wireshark pour pouvoir l'utiliser sans être Root
if [[ "$LISTE_PAQUETS" =~ "wireshark" ]]; then
    echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
    dpkg-reconfigure -f noninteractive wireshark-common
    usermod -aG wireshark $USER
fi

# ==============================================================================
# 6. CONFIGURATION DU FICHIER BASHRC
# ==============================================================================
echo "Configuration de l environnement par defaut"

# Définir Vim comme éditeur système par défaut
if [ -x /usr/bin/vim ]; then
    update-alternatives --set editor /usr/bin/vim.basic 2>/dev/null
fi

configurer_bashrc() {
    local TARGET_BASHRC=$1
    if [ -f "$TARGET_BASHRC" ] && ! grep -q "alias ll=" "$TARGET_BASHRC"; then
        cat << 'EOF' >> "$TARGET_BASHRC"

# --- CONFIGURATION UTILISATEUR ---
export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'
alias grep='grep --color=auto'

# Forcer l'utilisation de VIM par défaut
export EDITOR='vim'
export VISUAL='vim'

# Lancement automatique de fastfetch
if [ -x /usr/bin/fastfetch ]; then fastfetch; fi
EOF
    fi
}

# Application pour Root et l'Utilisateur
configurer_bashrc "/root/.bashrc"
if [ "$USER" != "root" ] && [ -d "/home/$USER" ]; then
    configurer_bashrc "/home/$USER/.bashrc"
    chown $USER:$USER /home/$USER/.bashrc
fi

echo "=========================================================================="
echo "Le script est termine !"
echo "=========================================================================="

exec sudo -u $USER bash
