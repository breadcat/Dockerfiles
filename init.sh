#!/bin/bash

echo Removing old volumes
for i in volume image system; do docker $i prune -f; done

echo Running docker-compose
docker-compose up -d --remove-orphans
