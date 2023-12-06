#!/bin/bash -x

# Script directory
SCRIPT_DIR=$(pwd)
REPO_DIR="$SCRIPT_DIR/bootcamp-devops-2023"
DB_DIR="/db_data"
WEB_DIR="/web_data"

# Creating local container volumes
if [ -d $DB_DIR ] && [ -d $WEB_DIR ]; then
    echo "$DB_DIR $WEB_DIR exists"
    rm -rf $DB_DIR/* $WEB_DIR/*
else
    mkdir $DB_DIR $WEB_DIR
fi

# Repo variables
REPO_URL="https://github.com/vramirez0113/bootcamp-devops-2023.git"
REPO_NAME="bootcamp-devops-2023"
BRANCH="ejercicio2-dockeriza"

# Check if script is being run as root.
echo "Checking if this script is run by root"
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Function to display progress bar.
function progress_bar() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local bar_length=30

    # Calculate the number of completed bars and spaces
    local completed_bar=$((percent * bar_length / 100))
    local spaces=$((bar_length - completed_bar))

    # Construct the progress bar representation
    local bar="["
    for ((i = 1; i <= completed_bar; i++)); do
        bar+="#"
    done
    for ((i = 1; i <= spaces; i++)); do
        bar+=" "
    done
    bar+="]"

    printf "\r%s %d%%" "$bar" "$percent"
}

# Add Docker's official GPG key:
DOCKER_GPG="/etc/apt/keyrings/docker.gpg"
sudo apt-get update -qq
if [ -f $DOCKER_GPG ]; then
    echo "$DOCKER_GPG exists"
else
    sudo apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi
# Add the repository to Apt sources:
DOCKER_REPO="/etc/apt/sources.list.d/docker.list"
if [ -f $DOCKER_REPO ]; then
    echo "$DOCKER_REPO exists"
else
    echo \
    "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq > /dev/null 2>&1
fi

# Install Apache, mysql, PHP, Curl, Git packages.
packages=("docker-ce" "docker-ce-cli" "containerd.io" "docker-buildx-plugin" "docker-compose" "docker-compose-plugin" "git")
total_count=${#packages[@]}
package_count=0

for package in "${packages[@]}"; do
    # Check if package is already installed.
    if dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -qq "installed"; then
        package_count=$((package_count + 1))
        progress_bar "$package_count" "$total_count"
        echo "$package already installed."
    else
        # Install package and show output
        if apt-get install -y -qq "$package" > /dev/null 2>&1; then
            package_count=$((package_count + 1))
            progress_bar "$package_count" "$total_count"
            echo "$package installed successfully."
        else
            echo "Failed to install $package."
            apt-get -y purge "${packages[@]}" -qq
            exit 1
        fi
    fi
done

# Start and enable all services if installation was successful.
if [ $package_count -eq $total_count ]; then
    systemctl start docker --quiet
    systemctl enable docker --quiet
    echo "Services started and enabled successfully."
fi

# Prompt for the mysql root password.
echo "Please enter the mysql root password:"
read -s db_root_passwd

# Ask the Database user for the password.
echo -n "Enter the password for the database user:"
read -s db_passwd

# Config Git account
git config --global user.name "vramirez0113"
git config --global user.email "vlakstarit@gmail.com"

# Check if app REPO_URL exist before cloning
if [ -d "$REPO_NAME" ]; then
    echo "$REPO_NAME exists"
    cd "$REPO_NAME"
    git pull
else
    echo "Repo does not exist, cloning the REPO_URL"
    sleep 1
    git clone -b "$BRANCH" "$REPO_URL"
fi

# Changing booking table to allow more digits.
cd "$SCRIPT_DIR"
DB_SRC="$SCRIPT_DIR/bootcamp-devops-2023/295devops-travel-lamp/database"
cd "$DB_SRC"
sed -i 's/`phone` int(11) DEFAULT NULL,/`phone` varchar(15) DEFAULT NULL,/g' devopstravel.sql

# Adding database password and container database nane to config.php.
DATA_SRC="$SCRIPT_DIR/bootcamp-devops-2023/295devops-travel-lamp"
sed -i "s/\$dbPassword \= \"\";/\$dbPassword \= \"$db_passwd\";/" "$DATA_SRC/config.php"
sed -i 's/$dbHost     \= "localhost";/$dbHost     \= "db";/' "$DATA_SRC/config.php"


# Copy and verify web data exist web_data dir.
if [ -f "$WEB_DIR/index.php" ]; then
    echo "File exists"
else
    cd "$DATA_SRC"
    cp -R ./* "$WEB_DIR"
fi

# Copy and verify database data exist database dir.
if [ -f "$SCRIPT_DIR/devopstravel.sql" ]; then
    echo "File exists"
else
    cd "$DB_SRC"
    cp devopstravel.sql "$SCRIPT_DIR"
fi

#Login to Docker Hub
echo "Login to Docker Hub"
sudo docker login --username=starvlak

# Create a network
sudo docker network create app-network

# Dockerfile to create a custom php-apache image containing mysqli extension
cd "$SCRIPT_DIR"
if [ -f "$SCRIPT_DIR/Dockerfile.web" ]; then
    echo "File exists"
else
    echo \
    "FROM php:apache
    RUN docker-php-ext-install mysqli" > "$SCRIPT_DIR/Dockerfile.web"
fi

# Dockerfile to create a custom mysql image
if [ -f "$SCRIPT_DIR/Dockerfile.mysql" ]; then
    echo "File exists"
else
    echo \
    "FROM mysql:latest
    ENV MYSQL_ROOT_PASSWORD=$db_root_passwd
    ENV MYSQL_DATABASE=devopstravel
    ENV MYSQL_USER=codeuser
    ENV MYSQL_PASSWORD=$db_passwd
    # Copy the devopstravel.sql file to the container
    COPY devopstravel.sql /docker-entrypoint-initdb.d/" > "$SCRIPT_DIR/Dockerfile.db"
fi

# Build and push Mysql Docker image to Docker Hub
sudo docker build -t starvlak/app-travel:mysql_v1.0 -f Dockerfile.db .
sudo docker push starvlak/app-travel:mysql_v1.0

# To create a custom apache-php image that includes mysqli extensions and push it to Docker Hub
sudo docker build -t starvlak/app-travel:my-php-app_v1.0 -f Dockerfile.web .
sudo docker push starvlak/app-travel:my-php-app_v1.0

# Docker compose file
echo \
"version: '3.8'
services:
    db:
        image: starvlak/app-travel:mysql_v1.0
        container_name: db
        environment:
            - MYSQL_ROOT_PASSWORD=${db_root_passwd}
            - MYSQL_DATABASE=devopstravel
            - MYSQL_USER=codeuser
            - MYSQL_PASSWORD=${db_passwd}
        volumes:
            - type: bind
              source: /db_data
              target: /var/lib/mysql
        networks:
            - app-network

    web:
        image: starvlak/app-travel:my-php-app_v1.0
        container_name: web
        depends_on:
            - db
        ports:
            - 80:80
        volumes:
            - type: bind
              source: /web_data
              target: /var/www/html
        networks:
            - app-network

networks:
    app-network:
        driver: bridge" > docker-compose.yml

# Run docker-compose
sudo docker-compose up -d
