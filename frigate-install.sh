#!/bin/bash

# Definition der Farben für die Konsolenausgabe
GREEN='\e[32m'
NC='\e[0m' # No Color

# Funktion, um auf eine Benutzereingabe zu warten
function press_enter_to_continue() {
    echo ""
    echo -e "${GREEN}----------------------------------------------------${NC}"
    read -p "  Drücke ENTER, um fortzufahren..."
    echo -e "${GREEN}----------------------------------------------------${NC}"
    echo ""
}

# Skript-Start und Abfrage der Frigate-Passwort
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}▶️ FRIGATE INSTALLATIONS-ASSISTENT FÜR LXC${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
read -p "  Bitte gib das gewünschte Passwort für Frigate ein: " FRIGATE_PASSWORT
echo ""
echo "Das Skript wird nun die Installation in den folgenden Schritten durchführen."
echo "Halte dich an die Anweisungen, um eine erfolgreiche Installation zu gewährleisten."

# --- Schritt 1: System aktualisieren und grundlegende Pakete installieren ---
echo ""
echo -e "${GREEN}>>> SCHRITT 1: SYSTEM-PAKETE INSTALLIEREN <<<${NC}"
press_enter_to_continue
apt update && apt upgrade -y
apt install -y curl gnupg ca-certificates apt-transport-https software-properties-common usbutils
echo -e "  ✅ System-Pakete installiert."
echo ""

# --- Schritt 2: Coral Edge TPU Runtime installieren ---
echo ""
echo -e "${GREEN}>>> SCHRITT 2: CORAL RUNTIME INSTALLIEREN <<<${NC}"
press_enter_to_continue
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor > /usr/share/keyrings/coral-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/coral-archive-keyring.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list
apt update
apt install -y libedgetpu1-std
echo -e "  ✅ Coral Runtime installiert."
echo ""

# --- Schritt 3: VAAPI / Intel Media Treiber installieren ---
echo ""
echo -e "${GREEN}>>> SCHRITT 3: VAAPI-TREIBER INSTALLIEREN <<<${NC}"
press_enter_to_continue
apt install -y vainfo intel-media-va-driver
echo -e "  ✅ VAAPI-Treiber installiert."
echo ""

# --- Schritt 4: Docker und Docker Compose installieren ---
echo ""
echo -e "${GREEN}>>> SCHRITT 4: DOCKER INSTALLIEREN <<<${NC}"
press_enter_to_continue
curl -fsSL https://get.docker.com | sh
apt install -y docker-compose-plugin
systemctl enable --now docker
echo -e "  ✅ Docker und Docker Compose installiert."
echo ""

# --- Schritt 5: Portainer installieren und starten ---
echo ""
echo -e "${GREEN}>>> SCHRITT 5: PORTAINER STARTEN <<<${NC}"
press_enter_to_continue
docker volume create portainer_data
docker run -d --name portainer --restart=always -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
echo -e "  ✅ Portainer gestartet. Erreichbar unter http://<IP_DES_LXC>:9000"
echo ""

# --- Schritt 6: Frigate docker-compose.yml erstellen ---
echo ""
echo -e "${GREEN}>>> SCHRITT 6: FRIGATE EINRICHTEN <<<${NC}"
press_enter_to_continue
mkdir -p /opt/frigate/config /media/frigate
cd /opt/frigate
cat << EOF > docker-compose.yml
version: "3.9"
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    container_name: frigate
    privileged: true
    restart: unless-stopped
    shm_size: "1g"
    devices:
      - /dev/dri:/dev/dri
      - /dev/bus/usb:/dev/bus/usb
    volumes:
      - ./config:/config
      - /media/frigate:/media/frigate
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "5000:5000"
      - "8554:8554"
    environment:
      - FRIGATE_RTSP_PASSWORD=$FRIGATE_PASSWORT
EOF
echo -e "  ✅ docker-compose.yml erstellt."
echo ""

# --- Schritt 7: Frigate starten ---
echo ""
echo -e "${GREEN}>>> SCHRITT 7: FRIGATE STARTEN <<<${NC}"
press_enter_to_continue
docker compose up -d
echo -e "  ✅ Frigate wird im Hintergrund gestartet."
echo ""

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}🎉 INSTALLATION ABGESCHLOSSEN! 🎉${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo "▶️ Nächste Schritte:"
echo "- Frigate-UI aufrufen: http://<IP_DES_LXC>:5000"
echo "- Die 'config.yml' anpassen und die Kameras einrichten."
echo "- Den Status der Container mit 'docker ps' prüfen."
echo ""
