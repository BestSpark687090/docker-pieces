#!/bin/bash
cd /home/www;
#docker compose down;
docker compose build --no-cache;
docker compose up -d --force-recreate;
# Surge rebuild because I can
cd /home/www/BestSpark687090;
git pull;
firebase deploy;
surge /home/www/BestSpark687090 --domain bestspark.surge.sh

