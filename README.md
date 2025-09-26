# Déploiement Automatique d'Application Python Flask

Script de déploiement automatique pour une application Flask utilisant **Gunicorn** et **Nginx**.  
Le script crée un service systemd, génère une clé HTTPS pour votre domaine et déploie l’application automatiquement.

---

## Prérequis

- Un projet Flask situé dans `/var/www/{votre_projet}`  
- Un fichier `requirements.txt` dans le dossier du projet  
- Python 3 installé sur le serveur  
- Accès root ou sudo  

---

## Compatibilité

| Système      | Statut       |
|-------------|-------------|
| Debian 12   | Fonctionnel |
| Linux (autre) | Non testé  |
| Windows     | Non compatible |

---

## Installation et utilisation

1. Cloner le dépôt :  
```bash
git clone https://github.com/SkillFXX/auto-deploy
cd auto-deploy
```
2. Rendre le script exécutable
```bash
chmod +x deploy_flask.sh
```
3. Lancer le script :
```bash
./deploy_flask.sh
```
4. Suivre les instructions affichées à l’écran et renseigner les informations demandées (nom du projet, domaine, fichier principal, instance Flask).

## Remarques
- Le script est actuellement en version bêta.
- Merci de signaler tout problème rencontré afin d’améliorer la stabilité et les fonctionnalités.
