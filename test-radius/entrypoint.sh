#!/bin/bash
set -e

echo "=============================================="
echo "  TEST-RADIUS - Laboratorio RADIUS + OTP"
echo "=============================================="
echo ""
echo "Servidor SSH iniciado en puerto 22 (host: 2222)."
echo ""
echo "Para conectarte (desde tu PC):"
echo "  ssh cplaza@localhost -p 2222"
echo "  Contrasena: cplazapassword123[OTP de 6 digitos]"
echo "  Ejemplo: cplazapassword123982314"
echo ""
echo "  ssh vpnuser@localhost -p 2222"
echo "  Contrasena: vpnpassword123[OTP de 6 digitos]"
echo ""
echo "  ssh admin@localhost -p 2222  (cuenta local, sin RADIUS)"
echo "  Contrasena: admin"
echo "=============================================="

# Generar claves SSH del host si no existen
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -A
fi

# Arrancar SSH en primer plano
exec /usr/sbin/sshd -D -e
