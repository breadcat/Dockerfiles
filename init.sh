#!/bin/bash

# delete env file
if [[ -f ".env" ]]; then echo Deleting existing env file && rm ".env"; fi

# variables and functions
traefik_conf_dir="$HOME/config/traefik"
function rclone_remote() { grep "$1" "$HOME/.config/rclone/rclone.conf" | sed 1q | tr -d \[\]; }
function domain_find() { grep domain "$traefik_conf_dir/traefik.toml" | cut -f2 -d\"; }

# password management
PASS_FILE="password.txt"
if ! [[ -f "$PASS_FILE" ]]; then head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 > "$PASS_FILE"; fi
if ! [[ -f "$traefik_conf_dir/htpasswd" ]]; then echo $(htpasswd -nbB $(whoami) "$(cat $PASS_FILE)") > "$traefik_conf_dir/htpasswd"; fi

# update submodules
git pull --recurse-submodules

# write env file
echo Writing env file
cat << EOF > .env
NAME=$(whoami)
PASS=$(cat $PASS_FILE)
DOMAIN=$(domain_find)

PUID=$(id -u)
PGID=$(id -g)
TZ=$(cat /etc/timezone)

CONFDIR=$HOME/config
DOWNDIR=$HOME/downloads
POOLDIR=$HOME/media
SAVEDIR=$HOME/saves
SYNCDIR=$HOME/vault
WORKDIR=$HOME/paperwork

RCLONE_REMOTE_MEDIA=$(rclone_remote media)
RCLONE_REMOTE_SAVES=$(rclone_remote saves)
RCLONE_REMOTE_WORK=$(rclone_remote work)
RCLONE_REMOTE_UNSORTED=$(rclone_remote unsorted)
EOF

# clean up existing stuff
echo Cleaning up existing docker files
for i in volume image system network; do docker "$i" prune -f; done
docker system prune -af

# make network, if not existing
if ! echo "$(docker network ls)" | grep -q "proxy"; then echo Creating docker network && docker network create proxy; fi

# start containers
echo Starting docker containers
docker-compose up -d --remove-orphans

# remove env file
if [[ -f ".env" ]]; then echo Removing env file && rm ".env"; fi
