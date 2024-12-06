#!/bin/bash

if [ "$1" = "prod" ]; then
  echo "Starting containers in production mode..."
  docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
else
  echo "Starting containers in development mode..."
  docker compose up -d
fi
