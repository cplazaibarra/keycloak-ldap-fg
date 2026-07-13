# Laboratorio de LDAP, OTP y RADIUS (para FortiGate)

Este proyecto levanta un entorno de laboratorio contenedorizado en Docker para probar la integración de un firewall **FortiGate** con servicios de directorio (LDAP), autenticación multifactor (OTP) y servidor de autenticación de red (RADIUS) con la menor cantidad de elementos posible.

El laboratorio está compuesto por:
1. **OpenLDAP**: Base de datos de usuarios y grupos corporativos.
2. **LDAP Account Manager (LAM)**: Interfaz web moderna para gestionar el directorio LDAP de forma visual.
3. **Keycloak + RADIUS Plugin**: Servidor de Identidad (IdP) con soporte nativo de OTP y servidor RADIUS embebido de alto rendimiento.

---

## Requisitos Previos

- Tener instalado **Docker** y **Docker Compose**.
- Tener los puertos host libres: `389` (TCP), `8085` (TCP), `8088` (TCP), `1812` (UDP) y `1813` (UDP).

---

## Cómo Levantar el Laboratorio

1. Abre tu terminal en esta carpeta.
2. Levanta los contenedores ejecutando:
   ```bash
   docker compose up -d
   ```
3. Verifica que todos los servicios estén corriendo:
   ```bash
   docker compose ps
   ```

---

## Información de Conexión y Credenciales

### 1. LDAP Account Manager - LAM (Interfaz Web LDAP)
- **URL**: [http://localhost:8085](http://localhost:8085)
- **Usuario**: `admin` (del servidor LDAP)
- **Contraseña**: `adminpassword`
- *Nota*: Al iniciar, se creará automáticamente un usuario de pruebas `vpnuser` (clave: `vpnpassword123`) dentro del grupo `VPNGroup`.

### 2. OpenLDAP (Servicio de Directorio)
- **Host / IP**: `localhost` (para uso externo) o `openldap` (para comunicación entre contenedores)
- **Puerto**: `389` (LDAP) o `636` (LDAPS)
- **Base DN**: `dc=mquest,dc=local`
- **Admin DN**: `cn=admin,dc=mquest,dc=local`
- **Contraseña**: `adminpassword`

### 3. Keycloak (Consola Web SSO/MFA)
- **URL**: [http://localhost:8088](http://localhost:8088)
- **Usuario**: `admin`
- **Contraseña**: `admin`

### 4. RADIUS Server (Keycloak Plugin)
- **Host / IP**: IP de la máquina host Docker
- **Puerto de Autenticación**: `1812` (UDP)
- **Puerto de Contabilidad**: `1813` (UDP)
- **Secret Compartido (Shared Secret)**: `fortigateradiussecret`

---

## Guía de Configuración

Para integrar estos elementos y conectar tu FortiGate, sigue detalladamente los pasos explicados en la guía:
👉 **[fortigate-config-guide.md](fortigate-config-guide.md)**
