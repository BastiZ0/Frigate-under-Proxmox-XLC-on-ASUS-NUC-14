# Kurzüberblick

1. LXC anlegen (privileged, nesting)

2. iGPU & Coral (USB) an LXC durchreichen (GUI oder manuell)

3. LXC starten, Geräte prüfen (/dev/dri, lsusb)

4. Im LXC: Pakete, Coral-Runtime, VAAPI prüfen

5. Docker, Docker Compose, Portainer installieren

6. Frigate docker-compose.yml anlegen und starten

7. Tests & Troubleshooting

# 1) LXC erstellen (Proxmox GUI)

* GUI → Create CT
* Template: Debian 12 (bookworm) (oder Ubuntu 22.04)
* Hostname z. B. frigate
* Disk: 10–20 GB (Root), später erweiterbar
* CPU: 2 Cores (mind.)
* RAM: 4 GB empfohlen (mind. 2 GB möglich)
* Unprivileged: deaktivieren (also privileged container)
* Features / Options: aktiviere Nesting
* Network: statische IP oder DHCP
* Erstelle den Container, merke dir die CT-ID (z. B. 101).   -> **Starte ihn noch nicht! Setze erst die Geräte in der config!**


# 2) Geräte (iGPU + Coral USB) durchreichen

## Variante A 

**GUI**

*Proxmox Web UI → CT → Resources → Add → USB Device → wähle dein Coral (Vendor/Product 1a6e:089a oder anhand Beschreibung).*

*Für iGPU: GUI hat bei LXC kein „PCI passthrough“, daher nutze Bind-Mount → siehe Variante B oder pct set.*

## Variante B — Manuell per Bind-Mount (Host)

Falls Container schon läuft, stoppe ihn:

```bash
pct stop 101
```

oder

**GUI**


**Öffne / ergänze die CT-Config (Host):**

```bash
nano /etc/pve/lxc/101.conf
```


Füge am Ende ein (oder passe an):

```bash
# erlauben der DRM devices (Intel iGPU)
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir

# USB-Bus komplett durchgeben für Coral USB (einfach, zeigt alle USB Geräte)
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
```

Für das einzelne Durchreichen des USB-Devices, statt /dev/bus/usb den konkreten Pfad z. B. /dev/bus/usb/004/002 benutzen (das wäre sauberer und weniger exposed).

Zum auslesen des Pfads:

```bash
lsusb
```

danach - Starten des containers:

```bash
pct start 101
```

oder

**GUI**

# 3) Im Container prüfen (Console in Proxmox XLC)

Falls lsusb fehlt bzw noch nicht installiert ist ansonsten überspringen:

```bash
apt update
apt install -y usbutils
```

Prüfen, ob die iGPU und der Coral USB korrekt durchgereicht werden.

```bash
ls -l /dev/dri
lsusb
```

## optional: nach Coral filtern

```bash
lsusb | grep -i 1a6e || lsusb | grep -i coral || lsusb | grep -i google
```

Erwartet: */dev/dri/renderD128 (oder card0) sichtbar und ein lsusb-Eintrag für Coral (1a6e:089a oder Global Unichip).*



# 4) Im LXC: System vorbereiten, Coral runtime & VAAPI

```bash
apt update && apt upgrade -y
apt install -y curl gnupg ca-certificates apt-transport-https software-properties-common
```

## Coral repo & Installation (Debian 12)

```bash
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor > /usr/share/keyrings/coral-archive-keyring.gpg
```

Repo mit korrektem Verweis

```bash
echo "deb [signed-by=/usr/share/keyrings/coral-archive-keyring.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" \
  | tee /etc/apt/sources.list.d/coral-edgetpu.list
```

noch einmal aktualisieren  
```bash
apt update
```

und

```bash
apt install -y libedgetpu1-std
```


VAAPI / Intel media drivers (prüfen/installieren)

```bash
apt install -y vainfo intel-media-va-driver
```

## prüfung (optionale Umgebungsvariable bei Bedarf)

```bash
vainfo || LIBVA_DRIVER_NAME=iHD vainfo
```

**Wenn vainfo eine Liste von H264/HEVC Einträgen zeigt → VAAPI ist einsatzbereit.**

# 5) Docker + Docker Compose + Portainer installieren



## Docker
```bash
curl -fsSL https://get.docker.com | sh
```

## Docker compose plugin (falls benötigt)

```bash
apt install -y docker-compose-plugin
```

## Docker starten/aktivieren
```bash
systemctl enable --now docker
```

## Portainer (CE) starten

```bash
docker volume create portainer_data
docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

**Öffne Portainer: http://"LXC-IP":9000 → Adminkonto anlegen.**

# 6) Frigate Docker-Compose (Beispiel)

**Erstelle das Verzeichnisse und die Compose-Datei:**

```bash
mkdir -p /opt/frigate/config /media/frigate
cd /opt/frigate
nano docker-compose.yml
```

in die docker-compose.yml folgendes kopieren oder unter Portainer einen neuen STACK erstellen und dort einfügen!


```yaml
version: "3.9"
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    container_name: frigate
    privileged: true
    restart: unless-stopped
    shm_size: "1g"
    devices:
      - /dev/dri:/dev/dri #<- für die Intel iGPU
      - /dev/bus/usb:/dev/bus/usb #<- für den Coral USB
    volumes:
      - ./config:/config
      - /media/frigate:/media/frigate
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "5000:5000"   # Port für die Frigate UI
      - "8554:8554"   # RTSP (optional für z.B. go2rtc Streamweiterleitung)
    environment:
      - FRIGATE_RTSP_PASSWORD=HierDeinPasswortEintragen #<- trage hier dein sicheres Passwort ein
```
**Passwort anpassen nicht vergessen!!!**

.
	  
.

Zum Ausführen der docker-compose und damit installieren von Frigate nach den oben genannten Einstellungen:



```bash
docker compose up -d
docker ps
docker compose logs -f frigate
```


# 7) Beispiel config.yml (Frigate) — HW accel + Coral

**Nach dem Start noch auf der FRIGATE UI oder direkt in der config.yaml unter /opt/frigate/config/config.yml die Konfiguration anpassen.** 

Siehe auch [Frigat-Konfiguration](https://docs.frigate.video/configuration/reference)

Erreichbar unter der IP des XLCs -> http://192.168.XXX.XXX:5000

Ein Beispiel, wie es mit Nutzung iGPU und Coral aussehen kann:

```yaml
mqtt: 
  enabled: true  # or false <- für HomeAssistant unbedingt nötig, damit die [Frigate-Integration](https://docs.frigate.video/integrations/home-assistant/) läuft
  host: core-mosquitto
  port: 1883
  topic_prefix: frigate
  client_id: frigate
  user: #deinname
  password: #deinpasswort

# für die Intel iGPU

ffmpeg:
  hwaccel_args: preset-vaapi

# für den Coral USB

detectors:
  coral:
    type: edgetpu
    device: usb

detect:
  width: 640
  height: 360
  fps: 5

# zum "schonen" der Kamerastreams nutze ich go2rtc

go2rtc:
  streams:
    Camera_1: rtsp://benutzer:passwort@192.168.XXX.XXX:XXX/ch0   # <- hier den von der Kamera bereitgestellte URL zum RTSP Main-Stream eintragen
    Camera_1_sub: rtsp://thingino:thingino@192.168.XXX.XXX:XXX/ch1 # <- hier den von der Kamera bereitgestellte URL zum RTSP Sub-Stream eintragen

    Camera_2: rtsp://benutzer:passwort@192.168.XXX.XXX:XXX/ch0 # <- hier den von der Kamera bereitgestellte URL zum RTSP Main-Stream eintragen
    Camera_2_sub: rtsp://benutzer:passwort@192.168.XXX.XXX:XXX/ch1 # <- hier den von der Kamera bereitgestellte URL zum RTSP Sub-Stream eintragen

cameras:
  Camera_1:
    enabled: true #or false
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/Camera_1 # <- den Namen der unter go2rtc eingerichteten Kamera eintragen
          roles:
            - record # <- hier nur record, weil der bessere Stream
        - path: rtsp://127.0.0.1:8554/Camera_1_sub
          roles:
            - detect # <- hier nutzen wir den "schlechteren" Stream nur zum detektieren

  Camera_2:
    enabled: true #or false
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/Camera_2 # <- den Namen der unter go2rtc eingerichteten Kamera eintragen
          roles:
            - record # <- hier nur record, weil der bessere Stream
        - path: rtsp://127.0.0.1:8554/Camera_2_sub
          roles:
            - detect # <- hier nutzen wir den "schlechteren" Stream nur zum detektieren

# Passe RTSP-Pfad und Kameras an.

```
	  
	  
##  Weitere Einstellungsmöglichkeiten findest du unter der [Frigat-Konfiguration-Site](https://docs.frigate.video/configuration/reference)

# 8) Tests & nützliche Befehle

*prüfe iGPU auf Proxmoxhost*

```bash
ls -l /dev/dri
dmesg | grep -i i915
```

Im Proxmox LXC:

```bash
ls -l /dev/dri
lsusb | grep -i 1a6e
vainfo      # wenn installiert
docker ps
docker compose logs -f frigate
```


Wenn Frigate vaapi oder edgetpu nicht erkennt, prüfe Logs (docker compose logs frigate) und ob /dev/dri + USB vorhanden sind.

# 9) Optional: nur einzelne USB-Device binden (statt ganzen Bus)


Finde Bus/Device:

```bash
lsusb
```

Ausgabe wäre z.B. Bus 004 Device 002 -> /dev/bus/usb/004/002

*Host-Config Beispiel für LXC mit <CT-ID> 101 (nur diese Datei binden):*

```bash
nano /etc/pve/lxc/101.conf
lxc.mount.entry: /dev/bus/usb/004/002 dev/bus/usb/004/002 none bind,optional,create=file
lxc.cgroup2.devices.allow: c 189:* rwm
```


# 10) Sicherheit & Hinweise

Privileged LXC + Bindmounts haben Sicherheitsrisiken. Nur im heimischen, vertrauenswürdigen Netz verwenden.

Logs und Aufnahmen (Frigate) können viel Platz benötigen → nutze ggf. USB-SSD oder NFS.

Backup: vor größeren Änderungen CT backup erstellen (Proxmox GUI → Backup).

Wenn etwas nicht geht: immer zuerst ls -l /dev/dri, lsusb, docker ps, docker compose logs.

#11) Kurze Fehlersuche (häufig)

Kein /dev/dri in CT → hast du die bindmount + devices.allow gesetzt und CT neu gestartet? (pct restart 101)

Coral nicht sichtbar → kontrolliere lsusb im Host und in CT; prüfe, ob das Gerät nicht vom Host genutzt wird.

vainfo fehler can't connect to X server → ignorier das; vainfo gibt trotzdem Codec-Support aus; verwende LIBVA_DRIVER_NAME=iHD vainfo falls nötig.

