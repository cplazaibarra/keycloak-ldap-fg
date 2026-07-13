#!/bin/bash
set -e

VM_NAME="keycloak-vm"
STORAGE_DIR="/var/tmp/keycloak-vm"
IMAGE_SRC="/home/cplaza/.gemini/antigravity/scratch/nessus-vm/noble-server-cloudimg-amd64.img"

echo "=== 1. Preparando directorios ==="
mkdir -p "$STORAGE_DIR"

echo "=== 2. Leyendo clave SSH del host ==="
if [ ! -f ~/.ssh/id_ed25519.pub ]; then
    echo "Generando clave SSH para el host..."
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi
PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

echo "=== 3. Generando archivos de Cloud-Init ==="
cat << EOF > "$STORAGE_DIR/user-data"
#cloud-config
ssh_pwauth: True
chpasswd:
  list: |
    cplaza:Mquest
  expire: False
users:
  - name: cplaza
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - "$PUB_KEY"
EOF

cat << 'EOF' > "$STORAGE_DIR/meta-data"
local-hostname: keycloak-vm
EOF

echo "=== 4. Creando disco seed.img ==="
cloud-localds "$STORAGE_DIR/seed.img" "$STORAGE_DIR/user-data" "$STORAGE_DIR/meta-data"

echo "=== 5. Preparando disco del sistema operativo ==="
cp "$IMAGE_SRC" "$STORAGE_DIR/keycloak-vm.qcow2"
qemu-img resize "$STORAGE_DIR/keycloak-vm.qcow2" 25G

echo "=== 6. Ajustando permisos para QEMU ==="
chmod 777 "$STORAGE_DIR"
chmod 666 "$STORAGE_DIR/keycloak-vm.qcow2" "$STORAGE_DIR/seed.img"

echo "=== 7. Registrando y arrancando la maquina virtual en KVM ==="
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" 2>/dev/null || true

virt-install \
  --name "$VM_NAME" \
  --memory 2048 \
  --vcpus 2 \
  --disk path="$STORAGE_DIR/keycloak-vm.qcow2",format=qcow2 \
  --disk path="$STORAGE_DIR/seed.img",format=raw \
  --import \
  --os-variant ubuntu24.04 \
  --network network=default \
  --graphics spice \
  --noautoconsole

echo "=== 8. Esperando IP de la maquina virtual (DHCP) ==="
IP=""
for i in {1..30}; do
    IP=$(virsh domifaddr "$VM_NAME" | grep -oE "192\.168\.[0-9]+\.[0-9]+" | head -1 || true)
    if [ -n "$IP" ]; then
        break
    fi
    echo "Esperando IP... (intento $i/30)"
    sleep 5
done

if [ -z "$IP" ]; then
    echo "Error: No se pudo obtener la IP de la VM. Revisa la red 'default' de libvirt."
    exit 1
fi

echo "IP asignada: $IP"

echo "=== 9. Esperando que el servicio SSH este activo ==="
for i in {1..30}; do
    if ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes "cplaza@$IP" exit 2>/dev/null; then
        echo "SSH esta listo!"
        break
    fi
    echo "Esperando puerto SSH... (intento $i/30)"
    sleep 3
done

echo "=== 10. Creando script de instalacion interna de Keycloak ==="
cat << 'EOF' > "$STORAGE_DIR/install_keycloak.sh"
#!/bin/bash
set -e

echo "=== Instalando dependencias en la VM ==="
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk unzip wget curl

echo "=== Descargando Keycloak 26.4.0 ==="
wget -q --show-progress https://github.com/keycloak/keycloak/releases/download/26.4.0/keycloak-26.4.0.tar.gz
sudo tar -xzf keycloak-26.4.0.tar.gz -C /opt/
sudo mv /opt/keycloak-26.4.0 /opt/keycloak

echo "=== Descargando e instalando el plugin de RADIUS ==="
wget -q --show-progress https://github.com/vzakharchenko/keycloak-radius-plugin/releases/download/v1.6.1-26.4.0/keycloak-radius-1.6.1-26.4.0.zip
unzip -q keycloak-radius-1.6.1-26.4.0.zip -d /tmp/radius-plugin
sudo cp /tmp/radius-plugin/providers/*.jar /opt/keycloak/providers/
sudo cp -r /tmp/radius-plugin/config /opt/keycloak/
sudo sed -i 's/"sharedSecret":"secret"/"sharedSecret":"fortigateradiussecret"/' /opt/keycloak/config/radius.config

echo "=== Compilando Keycloak con el modulo RADIUS ==="
sudo /opt/keycloak/bin/kc.sh build

echo "=== Creando usuario del sistema keycloak ==="
sudo groupadd -r keycloak || true
sudo useradd -r -g keycloak -d /opt/keycloak -s /sbin/nologin keycloak || true
sudo chown -R keycloak:keycloak /opt/keycloak
sudo chown -R keycloak:keycloak /opt/keycloak/config

echo "=== Creando servicio Systemd ==="
sudo cat << 'SYSTEMD' > /tmp/keycloak.service
[Unit]
Description=Keycloak Identity Provider with RADIUS
After=network.target

[Service]
Type=idle
User=keycloak
Group=keycloak
WorkingDirectory=/opt/keycloak
Environment=KEYCLOAK_ADMIN=admin
Environment=KEYCLOAK_ADMIN_PASSWORD=admin
Environment=RADIUS_SHARED_SECRET=fortigateradiussecret
Environment=RADIUS_UDP=true
Environment=RADIUS_UDP_AUTH_PORT=1812
Environment=RADIUS_UDP_ACCOUNT_PORT=1813
ExecStart=/opt/keycloak/bin/kc.sh start-dev --http-port=8080 --http-host=0.0.0.0
TimeoutStartSec=600
TimeoutStopSec=600

[Install]
WantedBy=multi-user.target
SYSTEMD

sudo mv /tmp/keycloak.service /etc/systemd/system/keycloak.service
sudo systemctl daemon-reload
sudo systemctl enable keycloak
sudo systemctl start keycloak

echo "=== Keycloak instalado y arrancado correctamente en la VM ==="
EOF

chmod +x "$STORAGE_DIR/install_keycloak.sh"

echo "=== 11. Transfiriendo y ejecutando la instalacion en la VM ==="
scp -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no "$STORAGE_DIR/install_keycloak.sh" "cplaza@$IP:/tmp/install_keycloak.sh"
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no "cplaza@$IP" "/tmp/install_keycloak.sh"

echo "=========================================================="
echo " MAQUINA VIRTUAL Y KEYCLOAK INSTALADOS CON EXITO"
echo "=========================================================="
echo " IP de la VM: $IP"
echo " Consola Keycloak: http://$IP:8080"
echo " Credenciales: admin / admin"
echo " Acceso SSH: ssh cplaza@$IP (Clave: Mquest)"
echo "=========================================================="
