set -e  # Arrêter le script en cas d'erreur

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[ÉTAPE]${NC} $1"
}

if [[ $EUID -eq 0 ]]; then
   print_error "Ce script ne doit pas être exécuté en tant que root pour des raisons de sécurité."
   print_message "Exécutez-le avec un utilisateur ayant des privilèges sudo."
   read -p "Voulez-vous vraiment continuer le déploiement ? (y/N): " confirm
   if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      print_message "Déploiement annulé."
      exit 0
   fi
fi

if ! command -v sudo &> /dev/null; then
    print_error "sudo n'est pas installé. Veuillez l'installer d'abord."
    exit 1
fi

print_message "=================================================="
print_message "Déploiement automatique d'application Python Flask"
print_message "v0.2 par SkillFX pour Debian 12"
print_message "=================================================="


echo

read -p "Nom du projet (doit correspondre au dossier dans /var/www/): " PROJET
read -p "Nom de domaine (ex: monapp.example.com): " DOMAIN
read -p "Nom du fichier Flask principale (ex: app): " FILE
read -p "Nom de l'instance Flask (ex: app): " INSTANCE


if [[ -z "$PROJET" ]]; then
    print_error "Le nom du projet ne peut pas être vide."
    exit 1
fi

if [[ -z "$DOMAIN" ]]; then
    print_error "Le nom de domaine ne peut pas être vide."
    exit 1
fi

PROJECT_PATH="/var/www/$PROJET"
if [[ ! -d "$PROJECT_PATH" ]]; then
    print_error "Le dossier $PROJECT_PATH n'existe pas."
    print_message "Veuillez créer le dossier et y placer votre code avant d'exécuter ce script."
    exit 1
fi

if [[ ! -f "$PROJECT_PATH/requirements.txt" ]]; then
    print_warning "Le fichier requirements.txt n'existe pas dans $PROJECT_PATH"
    read -p "Voulez-vous continuer quand même ? (y/N): " continue_without_req
    if [[ ! "$continue_without_req" =~ ^[Yy]$ ]]; then
        print_message "Veuillez créer un fichier requirements.txt et relancer le script."
        exit 1
    fi
fi

print_message "Configuration:"
print_message "  - Projet: $PROJET"
print_message "  - Domaine: $DOMAIN"
print_message "  - Chemin: $PROJECT_PATH"
print_message "  - Fichier principal: $FILE.py"
print_message "  - Instance Flask: $INSTANCE"

echo

read -p "Confirmer le déploiement ? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_message "Déploiement annulé."
    exit 0
fi

echo
print_step "1. Mise à jour du système et installation des paquets"
sudo apt update && sudo apt upgrade -y
sudo apt install python3 python3-pip python3-venv nginx certbot python3-certbot-nginx -y

print_step "2. Configuration de l'environnement virtuel Python"
cd "$PROJECT_PATH"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip

if [[ -f "requirements.txt" ]]; then
    pip install -r requirements.txt
else
    print_warning "Aucun fichier requirements.txt trouvé, passage de cette étape."
fi

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

print_step "5. Attribution des droits et activation du service"
sudo chown -R www-data:www-data "$PROJECT_PATH"
sudo chmod 755 "$PROJECT_PATH"

sudo systemctl daemon-reload
sudo systemctl enable "$PROJET"
sudo systemctl start "$PROJET"

print_message "Statut du service:"
sudo systemctl status "$PROJET" --no-pager -l

print_step "6. Obtention du certificat SSL avec Certbot"
print_warning "Assurez-vous que le DNS pointe vers ce serveur avant de continuer."
read -p "Le DNS est-il configuré ? (y/N): " dns_ready
if [[ "$dns_ready" =~ ^[Yy]$ ]]; then
    sudo certbot --nginx -d "$DOMAIN"
else
    print_warning "Vous devrez configurer SSL manuellement plus tard avec: sudo certbot --nginx -d $DOMAIN"
fi

print_step "7. Configuration de Nginx"
sudo tee /etc/nginx/sites-available/"$PROJET" > /dev/null << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    location / {
        proxy_pass http://unix:$PROJECT_PATH/$PROJET.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    access_log /var/log/nginx/$PROJET.access.log;
    error_log /var/log/nginx/$PROJET.error.log;
}
EOF

print_step "8. Activation de la configuration Nginx"
sudo ln -s /etc/nginx/sites-available/"$PROJET" /etc/nginx/sites-enabled/

print_message "Test de la configuration Nginx :"
if sudo nginx -t; then
    print_message "Configuration Nginx valide ✓"
    sudo systemctl reload nginx
    print_message "Nginx rechargé ✓"
else
    print_error "Erreur dans la configuration Nginx !"
    print_message "Tentative de suppression de la configuration Nginx par défaut pour corriger les problèmes..."

    sudo pkill -f nginx 

    if sudo rm /etc/nginx/sites-enabled/default; then
        print_message "Configuration Nginx par défaut (activée) supprimée ✓"
    else
        print_error "Erreur lors de la suppression de la configuration Nginx par défaut (activée) !"
        exit 1
    fi

    if sudo rm /etc/nginx/sites-available/default; then
        print_message "Configuration Nginx par défaut supprimée ✓"
    else
        print_error "Erreur lors de la suppression de la configuration Nginx par défaut !"
        exit 1
    fi

    print_message "Redémarrage de Nginx..."
    sudo systemctl start nginx

    print_message "Activation de Nginx au démarrage..."
    sudo systemctl enable nginx

    if sudo nginx -t; then
        print_message "Configuration Nginx valide ✓"
        sudo systemctl reload nginx
        print_message "Nginx rechargé ✓"
    else
        print_error "La configuration Nginx reste invalide après tentative de correction."
        exit 1
    fi
fi


echo
print_message "=== DÉPLOIEMENT TERMINÉ ==="
print_message "Application: $PROJET"
print_message "URL: https://$DOMAIN"
print_message "Service systemd: $PROJET.service"
print_message "Configuration Nginx: /etc/nginx/sites-available/$PROJET"
echo
print_message "Commandes utiles:"
print_message "  - Statut du service: sudo systemctl status $PROJET"
print_message "  - Redémarrer le service: sudo systemctl restart $PROJET"
print_message "  - Voir les logs: sudo journalctl -u $PROJET -f"
print_message "  - Logs Nginx: sudo tail -f /var/log/nginx/$PROJET.error.log"
echo
print_message "🎉 Votre application Python est maintenant en production !"
