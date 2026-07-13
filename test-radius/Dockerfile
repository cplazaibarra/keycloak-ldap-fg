FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Instalar herramientas necesarias
RUN apt-get update && apt-get install -y \
    openssh-server \
    libpam-radius-auth \
    freeradius-utils \
    sudo \
    vim \
    curl \
    iputils-ping \
    net-tools \
    && apt-get clean

# Crear usuario local para entrar al sistema (para administración)
RUN useradd -m -s /bin/bash admin && \
    echo "admin:admin" | chpasswd && \
    usermod -aG sudo admin

# Crear un usuario local vacío que será "mapeado" vía RADIUS
# Esto permite que PAM cree la sesión para usuarios RADIUS
RUN useradd -m -s /bin/bash cplaza 2>/dev/null || true && \
    useradd -m -s /bin/bash vpnuser 2>/dev/null || true

# Configurar el servidor SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "" >> /etc/ssh/sshd_config && \
    echo "# PAM RADIUS Config" >> /etc/ssh/sshd_config && \
    echo "UsePAM yes" >> /etc/ssh/sshd_config && \
    echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# Configurar PAM RADIUS - apunta al servidor Keycloak
COPY radius.conf /etc/pam_radius_auth.conf

# Configurar PAM para SSH (usar RADIUS como autenticador)
COPY pam-sshd /etc/pam.d/sshd

# Exponer el puerto SSH
EXPOSE 22

# Script de inicio
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
