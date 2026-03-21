#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[ÉTAPE]${NC} $1"; }

# --- FONCTION INSTALLATION DOCKER ---
install_docker() {
    print_step "Installation de Docker Engine"
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg
    
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo systemctl enable docker
    sudo systemctl start docker
    print_message "Docker installé avec succès ! (Version: $(docker --version))"
}

# --- FONCTION DÉPLOIEMENT FLASK ---
deploy_flask() {
    print_message "Configuration du déploiement Flask..."
    read -p "Nom du projet (dossier dans /var/www/): " PROJET
    read -p "Nom de domaine (ex: monapp.com): " DOMAIN
    read -p "Nom du fichier Flask principal (ex: app): " FILE
    read -p "Nom de l'instance Flask (ex: app): " INSTANCE

    PROJECT_PATH="/var/www/$PROJET"
    
    if [[ ! -d "$PROJECT_PATH" ]]; then
        print_error "Le dossier $PROJECT_PATH n'existe pas."
        return
    fi

    print_step "1. Mise à jour et installation des paquets"
    sudo apt update && sudo apt upgrade -y
    sudo apt install python3 python3-pip python3-venv nginx certbot python3-certbot-nginx -y

    # --- CORRECTION NGINX PAR DÉFAUT ---
    print_step "Nettoyage de la configuration Nginx par défaut"
    if [ -f /etc/nginx/sites-enabled/default ]; then
        sudo rm /etc/nginx/sites-enabled/default
        print_message "Site par défaut supprimé de sites-enabled."
    fi

    print_step "2. Configuration de l'environnement virtuel"
    cd "$PROJECT_PATH"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    [ -f "requirements.txt" ] && pip install -r requirements.txt || print_warning "Pas de requirements.txt"
    pip install gunicorn

    print_step "3. Création du fichier wsgi.py"
    cat > wsgi.py << EOF
from $FILE import $INSTANCE
if __name__ == "__main__":
    $INSTANCE.run()
EOF

    print_step "4. Création du service systemd"
    sudo tee /etc/systemd/system/"$PROJET".service > /dev/null << EOF
[Unit]
Description=Gunicorn instance to serve $PROJET
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$PROJECT_PATH
Environment="PATH=$PROJECT_PATH/venv/bin"
ExecStart=$PROJECT_PATH/venv/bin/gunicorn --workers 3 --bind unix:$PROJECT_PATH/$PROJET.sock wsgi:app

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$PROJET"
    sudo systemctl start "$PROJET"

    print_step "5. Configuration SSL & Nginx"
    print_warning "Assurez-vous que le DNS pointe vers ce serveur."
    read -p "Générer SSL maintenant ? (y/N): " dns_ready
    if [[ "$dns_ready" =~ ^[Yy]$ ]]; then
        sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN || print_error "Échec Certbot"
    fi

    sudo tee /etc/nginx/sites-available/"$PROJET" > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        include proxy_params;
        proxy_pass http://unix:$PROJECT_PATH/$PROJET.sock;
    }
}
EOF

    [ ! -f /etc/nginx/sites-enabled/"$PROJET" ] && sudo ln -s /etc/nginx/sites-available/"$PROJET" /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx
    print_message "Déploiement terminé pour $DOMAIN !"
}

# --- MENU PRINCIPAL ---
clear
print_message "=================================================="
print_message "       OUTIL D'ADMINISTRATION SERVEUR           "
print_message "       v0.3 - Debian 12 (SkillFX)               "
print_message "=================================================="

echo -e "Choisissez une option :"
echo -e "1) Déployer une application Flask (Nginx + Gunicorn + SSL)"
echo -e "2) Installer Docker Engine & Compose"
echo -e "3) Quitter"
echo -n "Option : "
read choice

case $choice in
    1) deploy_flask ;;
    2) install_docker ;;
    3) exit 0 ;;
    *) print_error "Option invalide" ;;
esac
