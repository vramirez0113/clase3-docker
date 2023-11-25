#!/bin/bash

# Clone git repository
git clone https://github.com/yourusername/yourrepository.git

# Navigate into the cloned directory
cd yourrepository

# Copy web page and database data
cp -r webpage/* /path/to/web/directory
cp -r database/* /path/to/database/directory

# Build and push PHP app
docker build -t yourusername/php-app -f Dockerfile.php .
docker push yourusername/php-app

# Build and push MariaDB
docker build -t yourusername/mariadb-db -f Dockerfile.mariadb .
docker push yourusername/mariadb-db

# Build and push Apache server
docker build -t yourusername/apache-server -f Dockerfile.apache .
docker push yourusername/apache-server

# Run docker compose
docker-compose up