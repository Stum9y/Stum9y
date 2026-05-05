#!/bin/bash
set -e

# -------------------------
# Color codes for visual feedback
# -------------------------
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"

info() { echo -e "${BLUE}[ℹ]${RESET} $1"; }
success() { echo -e "${GREEN}[✔]${RESET} $1"; }
warning() { echo -e "${YELLOW}[⚠]${RESET} $1"; }
error() { echo -e "${RED}[✖]${RESET} $1"; }

# -------------------------
# Set base folder
# -------------------------
BASE_DIR="/home/linuxadmin/docker"

# -------------------------
# 1️⃣ Create .env file with variables
# -------------------------
info "Creating .env file in ${BASE_DIR}..."
mkdir -p "$BASE_DIR"
cat > "$BASE_DIR/.env" <<'EOF'
#================================
# Global
#================================
TZ=Europe/London
UID=1000
GID=1000

# ================================
# Nginx Proxy Manager
# ================================
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_ADMIN_PORT=81
NPM_DATA_PATH=/home/linuxadmin/docker/nginx/data
NPM_LOGS_PATH=/home/linuxadmin/docker/nginx/logs
NPM_LETSENCRYPT_PATH=/home/linuxadmin/docker/nginx/letsencrypt
NPM_MYSQL_PATH=/home/linuxadmin/docker/nginx/mysql

# ================================
# MariaDB
# ================================
MARIADB_IMAGE=jc21/mariadb-aria:latest
MARIADB_RESTART=unless-stopped
NPM_DB_HOST=db
NPM_DB_PORT=3306
NPM_DB_USER=npm
NPM_DB_PASSWORD=Ng1nxPr0Xyman@g3r
NPM_DB_NAME=npm
MYSQL_ROOT_PASSWORD=Ng1nxPr0Xym@n@g3rR00t
MARIADB_AUTO_UPGRADE=true

# ================================
# Fail2Ban
# ================================
FAIL2BAN_DATA_PATH=/home/linuxadmin/docker/fail2ban/data
FAIL2BAN_JAILS_PATH=/home/linuxadmin/docker/fail2ban/jail.d
FAIL2BAN_FILTERS_PATH=/home/linuxadmin/docker/fail2ban/filter.d
FAIL2BAN_ACTIONS_PATH=/home/linuxadmin/docker/fail2ban/action.d

# ================================
# CrowdSec
# ================================
CROWDSEC_COLLECTIONS=crowdsecurity/nginx
CROWDSEC_API_PORT=8080
CROWDSEC_CONFIG_PATH=/home/linuxadmin/docker/crowdsec/config
CROWDSEC_DB_PATH=/home/linuxadmin/docker/crowdsec/data
CROWDSEC_ACQUIS_PATH=/home/linuxadmin/docker/crowdsec/acquis.d
CROWDSEC_BOUNCERS_PATH=/home/linuxadmin/docker/crowdsec/bouncers

# ================================
# Cloudflare
# ================================
CROWDSEC_CF_BOUNCER_KEY=+FXcxMPzTx3LjGOecx5t+TGfEzpcPGmZLK2Baehhw7w
CF_API_TOKEN=PASTE_CLOUDFLARE_API_TOKEN
CF_ACCOUNT_ID=b9e4f467e1b4d21a6212cc889b0bd416
EOF
success ".env file created in ${BASE_DIR}"

# -------------------------
# 2️⃣ Create all directories
# -------------------------
info "Creating required directories..."
mkdir -p \
"$BASE_DIR/nginx"/{data,logs,letsencrypt,mysql} \
"$BASE_DIR/mariadb/conf.d" \
"$BASE_DIR/fail2ban"/{data,jail.d,filter.d,action.d} \
"$BASE_DIR/crowdsec"/{config,data,acquis.d,bouncers}
success "All folders created"

# -------------------------
# 3️⃣ Fail2Ban Docker action
# -------------------------
info "Creating Fail2Ban Docker action..."
cat > "$BASE_DIR/fail2ban/action.d/iptables-docker.conf" <<'EOF'
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = iptables -I DOCKER-USER -s <ip> -j DROP
actionunban = iptables -D DOCKER-USER -s <ip> -j DROP
EOF
success "Fail2Ban Docker action created"

# -------------------------
# 4️⃣ Minimal Fail2Ban jail
# -------------------------
info "Creating Fail2Ban jail for Nginx Proxy Manager..."
cat > "$BASE_DIR/fail2ban/jail.d/nginx-proxy-manager.conf" <<'EOF'
[nginx-proxy-manager]
enabled = true
backend = polling
logpath = /home/linuxadmin/docker/nginx/logs/*access*.log
filter = nginx-proxy-manager
maxretry = 5
findtime = 10m
bantime = 1h
action = iptables-docker
EOF
success "Fail2Ban jail created"

# -------------------------
# 5️⃣ Minimal Fail2Ban filter
# -------------------------
info "Creating Fail2Ban filter for Nginx Proxy Manager..."
cat > "$BASE_DIR/fail2ban/filter.d/nginx-proxy-manager.conf" <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST).*
EOF
success "Fail2Ban filter created"

# -------------------------
# 6️⃣ CrowdSec acquisition file for NPM
# -------------------------
info "Creating CrowdSec acquisition file for NPM..."
cat > "$BASE_DIR/crowdsec/acquis.d/npm.yaml" <<'EOF'
filename: /var/log/npm.log
labels:
  service: npm
  type: log
EOF
success "CrowdSec acquisition file created"

# -------------------------
# 7️⃣ Docker Compose file
# -------------------------
info "Creating Docker Compose file at $BASE_DIR/compose.yaml..."
cat > "$BASE_DIR/compose.yaml" <<'EOF'
services:
  # ----------------------------
  # Nginx Proxy Manager
  # ----------------------------
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "${NPM_HTTP_PORT}:80"
      - "${NPM_HTTPS_PORT}:443"
      - "${NPM_ADMIN_PORT}:81"
    environment:
      TZ: ${TZ}
      DB_MYSQL_HOST: ${NPM_DB_HOST}
      DB_MYSQL_PORT: ${NPM_DB_PORT}
      DB_MYSQL_USER: ${NPM_DB_USER}
      DB_MYSQL_PASSWORD: ${NPM_DB_PASSWORD}
      DB_MYSQL_NAME: ${NPM_DB_NAME}
    volumes:
      - ${NPM_DATA_PATH}:/data
      - ${NPM_LOGS_PATH}:/var/log/nginx
      - ${NPM_LETSENCRYPT_PATH}:/etc/letsencrypt
    depends_on:
      - db
    networks:
      - internal
      - proxy

  # ----------------------------
  # MariaDB (official)
  # ----------------------------
  db:
    image: mariadb:10.11
    container_name: npm-db
    restart: unless-stopped
    environment:
      TZ: ${TZ}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${NPM_DB_NAME}
      MYSQL_USER: ${NPM_DB_USER}
      MYSQL_PASSWORD: ${NPM_DB_PASSWORD}
    volumes:
      - ${NPM_DATA_PATH}/mysql:/var/lib/mysql
      - /docker/mariadb/conf.d:/etc/mysql/conf.d:ro
    networks:
      - internal

  # ----------------------------
  # Fail2Ban (Docker-aware)
  # ----------------------------
  fail2ban:
    image: crazymax/fail2ban:latest
    container_name: fail2ban
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ${FAIL2BAN_DATA_PATH}:/data
      - ${FAIL2BAN_JAILS_PATH}:/etc/fail2ban/jail.d:ro
      - ${FAIL2BAN_FILTERS_PATH}:/etc/fail2ban/filter.d:ro
      - ${FAIL2BAN_ACTIONS_PATH}:/etc/fail2ban/action.d:ro
      - ${NPM_LOGS_PATH}:/var/log/nginx:ro
    restart: unless-stopped

  # ----------------------------
  # CrowdSec
  # ----------------------------
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    restart: unless-stopped
    environment:
      TZ: ${TZ}
      COLLECTIONS: ${CROWDSEC_COLLECTIONS}
      GID: ${GID}
      UID: ${UID}
    volumes:
      - ${CROWDSEC_CONFIG_PATH}:/etc/crowdsec
      - ${CROWDSEC_DB_PATH}:/var/lib/crowdsec/data
      - ${CROWDSEC_ACQUIS_PATH}:/etc/crowdsec/acquis.d
      - ${CROWDSEC_BOUNCERS_PATH}:/etc/crowdsec/bouncers
      - ${NPM_LOGS_PATH}:/var/log/nginx:ro
    networks:
      - internal
      - proxy
    depends_on:
      - npm

networks:
  proxy:
    driver: bridge

  internal:
    driver: bridge
    internal: true
EOF
success "Docker Compose file created"

# -------------------------
# 8️⃣ Validate Docker Compose file
# -------------------------
info "Validating Docker Compose file..."
if docker-compose -f "$BASE_DIR/compose.yaml" config >/dev/null 2>&1; then
    success "Docker Compose file is valid ✅"
else
    error "There is an error in the Docker Compose file! ❌ Please check compose.yaml"
    exit 1
fi

# -------------------------
# 9️⃣ Completion message
# -------------------------
echo
success "🎉 Setup complete! You can now start your services with:"
echo -e "${YELLOW}cd $BASE_DIR && docker-compose -f compose.yaml up -d${RESET}"
echo
info "Remember to replace CF_API_TOKEN in $BASE_DIR/.env before starting services."
