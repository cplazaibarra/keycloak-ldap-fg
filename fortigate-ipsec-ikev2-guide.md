# Guía de Configuración: FortiGate v7.4.12 + IPsec IKEv2 + RADIUS Challenge-Response (OTP)

Esta guía explica detalladamente cómo configurar una VPN IPsec IKEv2 en un FortiGate (versión v7.4.12) utilizando autenticación EAP contra el servidor Keycloak RADIUS, con soporte para el segundo factor (OTP) en dos pasos mediante **Access-Challenge**.

## Arquitectura de Autenticación
1. El usuario inicia la conexión en FortiClient e ingresa su usuario y su contraseña principal.
2. El FortiGate encapsula esta solicitud y la envía a Keycloak vía RADIUS.
3. Keycloak valida la contraseña principal y, al detectar que el usuario requiere OTP, responde con un paquete `Access-Challenge`.
4. El FortiGate le presenta una ventana interactiva al usuario en FortiClient solicitando el código OTP de 6 dígitos.
5. El usuario ingresa el código OTP, que se valida en Keycloak para otorgar el `Access-Accept` final.

---

## 1. Configuración en Keycloak

El servidor Keycloak ya está listo y configurado en tu máquina virtual (`192.168.122.151`). Solo asegúrate de que el cliente de RADIUS tenga los siguientes parámetros activos:

1. Ve a **Radius** -> **Radius Clients**.
2. Tu cliente `radius-client` debe tener el atributo **`radius.OTP = true`**.
3. Asegúrate de que el usuario (ej. `cplaza2`) tenga registrado su autenticador OTP escaneando el código QR en `http://192.168.122.151:8080/realms/master/account`.

---

## 2. Configuración en FortiGate (v7.4.12)

### 2.1. Configurar el Servidor RADIUS
1. Ve a **User & Authentication** -> **RADIUS Servers** y haz clic en **Create New**.
2. Rellena los datos:
   - **Name**: `Keycloak-RADIUS`
   - **Primary Server IP/Name**: `192.168.122.151` (IP de la VM Keycloak).
   - **Primary Secret**: `fortigateradiussecret`
3. En la consola CLI de tu FortiGate, configura el protocolo para usar **MS-CHAPv2**:
   ```fortinet
   config user radius
       edit "Keycloak-RADIUS"
           set auth-type mschap2
       next
   end
   ```

### 2.2. Crear el Grupo de Usuarios en FortiGate
1. Ve a **User & Authentication** -> **User Groups** y haz clic en **Create New**.
2. **Name**: `VPN-RADIUS-Users`
3. **Type**: `Firewall`
4. En **Remote Groups**, haz clic en **Add**:
   - **Remote Server**: `Keycloak-RADIUS`
   - **Group Name**: Escribe `VPNGroup` (coincidiendo con el atributo `Fortinet-Group-Name` que envía Keycloak).
5. Haz clic en **OK** y guarda.

### 2.3. Configurar el Túnel IPsec VPN (IKEv2)
Ejecuta la siguiente configuración en la consola CLI de tu FortiGate para crear el túnel IPsec con soporte de autenticación EAP remoto:

```fortinet
config vpn ipsec phase1-interface
    edit "VPN-IPsec-IKEv2"
        set type dynamic
        set interface "port1"  # Tu interfaz WAN
        set ike-version 2
        set localid "vpn.mquest.local"
        set authmethod-remote eap
        set eap-friendly-name "RADIUS-VPN"
        set peertype any
        set mode-cfg enable
        set ipv4-start-ip 10.212.134.200
        set ipv4-end-ip 10.212.134.250
        set ipv4-netmask 255.255.255.0
        set dns-server1 8.8.8.8
        set client-auto-ip enable
        set client-keep-alive enable
        set proposal aes256-sha256 aes128-sha1
        set dpd-backend asym-client
    next
end

config vpn ipsec phase2-interface
    edit "VPN-IPsec-IKEv2_p2"
        set phase1name "VPN-IPsec-IKEv2"
        set proposal aes256-sha256 aes128-sha1
    next
end
```

### 2.4. Asociar el Grupo de Autenticación al Túnel
Debemos indicarle al FortiGate qué grupo de usuarios RADIUS tiene permitido conectar al túnel:

```fortinet
config user peer
    edit "RADIUS-Peer"
        set mandatory-ca-verify disable
    next
end

config vpn ipsec phase1-interface
    edit "VPN-IPsec-IKEv2"
        set authusrgrp "VPN-RADIUS-Users"
    next
end
```

### 2.5. Crear la Política de Firewall
Para permitir que los usuarios conectados a la VPN naveguen o accedan a la LAN:

1. Ve a **Policy & Objects** -> **Firewall Policy** -> **Create New**.
2. Configura:
   - **Name**: `VPN-Access`
   - **Incoming Interface**: `VPN-IPsec-IKEv2`
   - **Outgoing Interface**: La interfaz de tu red interna o internet.
   - **Source**: `all` y el grupo **`VPN-RADIUS-Users`**.
   - **Destination**: Las subredes internas permitidas o `all` para navegación general.
   - **Service**: `ALL`.
   - **Action**: `ACCEPT`.
3. Haz clic en **OK**.

---

## 3. Experiencia de Conexión en FortiClient

1. En FortiClient, crea una nueva conexión VPN de tipo **IPsec VPN**:
   - **Remote Gateway**: IP WAN de tu FortiGate.
   - **Authentication**: Prompt on login.
   - **IKE Version**: 2.
2. Haz clic en **Conectar**.
3. **Paso 1**: FortiClient solicitará el usuario (`cplaza2`) y la contraseña.
   - El usuario ingresa únicamente su clave de LDAP (`cplazapassword123`).
4. **Paso 2**: Tras validar la contraseña, FortiClient mostrará una caja emergente interactiva solicitando el **"Challenge Response"** o **"OTP Code"**.
   - El usuario abre su app de OTP e ingresa el token de 6 dígitos actual.
5. ¡El túnel VPN IPsec IKEv2 se establecerá de forma segura!
