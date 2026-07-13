# Guía de Configuración: FortiGate + LDAP + Keycloak RADIUS (OTP)

Esta guía explica paso a paso cómo configurar la integración de tu entorno Docker con un firewall **FortiGate** para autenticación con **LDAP**, **RADIUS** con **OTP (Double Factor)** y asignación dinámica de **Políticas de Grupo**.

---

## 1. Configurar Keycloak User Federation (LDAP)

Primero, debemos hacer que Keycloak lea los usuarios y grupos de OpenLDAP.

1. Accede a Keycloak ([http://localhost:8088](http://localhost:8088)) con usuario `admin` / clave `admin`.
2. En la barra lateral izquierda, asegúrate de estar en el Realm deseado (puedes usar `master` para el laboratorio o crear uno nuevo, ej. `Laboratorio`).
3. Ve a **User Federation** y haz clic en **Add provider** -> **ldap**.
4. Llena los siguientes campos:
   - **UI Display Name**: `OpenLDAP`
   - **Edit Mode**: `READ_ONLY` (o `WRITABLE` si deseas que Keycloak pueda editar usuarios en LDAP).
   - **Connection URL**: `ldap://openldap:389` (los contenedores están en la misma red de Docker).
   - **Users DN**: `ou=people,dc=mquest,dc=local`
   - **Username LDAP attribute**: `uid`
   - **RDN LDAP attribute**: `uid`
   - **UUID LDAP attribute**: `entryUUID`
   - **User Object Classes**: `inetOrgPerson, organizationalPerson, person`
   - **Bind Type**: `simple`
   - **Bind DN**: `cn=admin,dc=mquest,dc=local`
   - **Bind Credential**: `adminpassword`
5. Haz clic en **Test connection** y luego en **Test authentication** para verificar que los datos son correctos.
6. Haz clic en **Save**.
7. Una vez guardado, ve a la pestaña **Mappers** (arriba) y haz clic en **Add mapper**:
   - **Name**: `GroupMapper`
   - **Mapper Type**: `group-ldap-mapper`
   - **LDAP Groups DN**: `ou=groups,dc=mquest,dc=local`
   - **Group Object Classes**: `groupOfNames`
   - **Membership LDAP Attribute**: `member`
   - **Membership User LDAP Attribute**: `uid`
   - **User Groups Retrieve Strategy**: `LOAD_GROUPS_BY_MEMBER_ATTRIBUTE`
   - Haz clic en **Save**.
8. Regresa a la pestaña principal del proveedor LDAP y haz clic en **Sync all users** para importar el usuario `vpnuser`. Luego ve a la sección de **Groups** en Keycloak y verás que el grupo `VPNGroup` se ha importado automáticamente.

---

## 2. Configurar OTP (MFA) en Keycloak

1. Ve a **Authentication** en la barra lateral izquierda.
2. En la pestaña **Policies**, selecciona **OTP Policy**:
   - Asegúrate de que esté configurado como **TOTP** (Time-Based).
   - **OTP Hash Algorithm**: `SHA1`
   - **Number of Digits**: `6`
   - **Look Ahead Window**: `1` (tolerancia de desfase de tiempo).
   - Haz clic en **Save**.
3. Para forzar a los usuarios a registrar su aplicación de autenticación (Google Authenticator, Microsoft Authenticator o FreeOTP) en su primer inicio de sesión:
   - Ve a **Users** -> Busca al usuario `vpnuser` -> Ve a la pestaña **Details**.
   - En **Required User Actions**, añade **Configure OTP**.
   - Haz clic en **Save**.
   - *Nota de Laboratorio*: Si intentas iniciar sesión como `vpnuser` en el portal de usuarios de Keycloak (`http://localhost:8088/realms/master/account`), te pedirá escanear el código QR y asociar tu OTP.

---

## 3. Configurar RADIUS Client y Atributos de Grupo en Keycloak

El plugin de RADIUS de `vzakharchenko` añade menús específicos en la interfaz gráfica de Keycloak para gestionar los clientes de red (RADIUS Clients).

### 3.1. Registrar el FortiGate como Cliente RADIUS
1. En la barra lateral izquierda de Keycloak, verás una sección llamada **Radius** (añadida por el plugin). Ingresa allí.
2. Ve a **Radius Clients** y haz clic en **Create**.
3. Llena la información:
   - **Client IP / CIDR**: La IP del FortiGate en tu red de laboratorio (ej. `192.168.1.99` o `0.0.0.0/0` para permitir cualquier origen en el lab).
   - **Shared Secret**: `fortigateradiussecret`
   - Haz clic en **Save**.

### 3.2. Mapear Grupos a Atributos RADIUS de Fortinet
Para que FortiGate pueda saber a qué grupo pertenece el usuario y aplicar políticas dinámicas, Keycloak debe retornar el atributo Vendor-Specific Attribute (VSA) de Fortinet: `Fortinet-Group-Name`.

1. En la misma sección de **Radius** de Keycloak, ve a **Radius Mappers** (o puedes hacerlo en los mappers del cliente).
2. Haz clic en **Create Radius Mapper**:
   - **Name**: `FortinetGroupMapper`
   - **Mapper Type**: `Group Member Mapper` (asigna atributos según pertenencia a grupos).
   - **Radius Attribute**: `Fortinet-Group-Name` (Vendor ID: `12356`, Attribute ID: `1`).
   - **Keycloak Group**: Selecciona `/VPNGroup`.
   - **Value**: `VPNGroup` (este es el valor que recibirá el FortiGate).
   - Haz clic en **Save**.

---

## 4. Configurar el FortiGate

Ahora configuramos el FortiGate para que utilice tanto la conexión directa LDAP (para consulta) como la autenticación RADIUS con OTP.

### 4.1. Conectar FortiGate a OpenLDAP (Para lectura de grupos)
1. In FortiGate, ve a **User & Authentication** -> **LDAP Servers** y haz clic en **Create New**.
2. Rellena los datos:
   - **Name**: `OpenLDAP-Server`
   - **Server IP/Name**: IP de tu máquina host Docker (donde corre OpenLDAP).
   - **Port**: `389`
   - **Common Name Identifier**: `uid`
   - **Distinguished Name (DN)**: `dc=mquest,dc=local`
   - **Bind Type**: `Regular`
   - **Username**: `cn=admin,dc=mquest,dc=local`
   - **Password**: `adminpassword`
3. Haz clic en **Test Connectivity**. Debería aparecer como exitoso.
4. Haz clic en **Test User Credentials** y escribe `vpnuser` con su contraseña `vpnpassword123` para verificar la lectura.

### 4.2. Conectar FortiGate a Keycloak RADIUS (Para Autenticación con OTP)
1. Ve a **User & Authentication** -> **RADIUS Servers** y haz clic en **Create New**.
2. Rellena los datos:
   - **Name**: `Keycloak-RADIUS`
   - **Primary Server IP/Name**: IP de tu máquina host Docker.
   - **Primary Secret**: `fortigateradiussecret`
3. Abre la consola CLI del FortiGate (botón `>_` arriba a la derecha de la UI de FortiGate) y fuerza el uso del protocolo **PAP**. Esto es **fundamental** porque PAP permite enviar la contraseña concatenada con el OTP en un solo string hacia Keycloak:
   ```fortinet
   config user radius
       edit "Keycloak-RADIUS"
           set auth-type pap
       next
   end
   ```

### 4.3. Crear los Grupos de Usuarios en FortiGate
Crearemos un grupo que vincule la autenticación RADIUS y el mapeo de grupos dinámicos que envía Keycloak.

1. Ve a **User & Authentication** -> **User Groups** y haz clic en **Create New**.
2. **Name**: `FortiGate-VPN-Users`
3. **Type**: `Firewall`
4. En **Remote Groups**, haz clic en **Add**:
   - **Remote Server**: Selecciona `Keycloak-RADIUS`.
   - **Group Name**: Escribe `VPNGroup` (debe coincidir exactamente con el valor del VSA `Fortinet-Group-Name` que configuramos en el mapper de Keycloak).
5. Haz clic en **OK** y luego en **Save**.

---

## 5. Aplicar Políticas de Grupo en FortiGate

Ahora puedes utilizar el grupo de usuarios `FortiGate-VPN-Users` para políticas de acceso (ej. VPN SSL o Políticas de Firewall).

### Ejemplo 1: Permitir acceso a la LAN solo a miembros del grupo VPNGroup
1. Ve a **Policy & Objects** -> **Firewall Policy** -> **Create New**.
2. Configura:
   - **Incoming Interface**: `ssl.root` (si es VPN) o la interfaz de tu LAN de usuarios.
   - **Outgoing Interface**: `port1` (WAN o interfaz interna de servidores).
   - **Source**: Añade el grupo `FortiGate-VPN-Users` (y también `all` en direcciones IP).
   - **Destination**: Las subredes internas permitidas.
   - **Service**: Los servicios requeridos.
   - **Action**: `ACCEPT`.
3. Haz clic en **OK**.

---

## 6. Pruebas de Funcionamiento (Verificación)

### Flujo de Login del Usuario:
1. El usuario abre el cliente FortiClient VPN.
2. Ingresa su usuario: `vpnuser`.
3. Abre su aplicación de OTP (Google Authenticator) en su móvil y ve su código de 6 dígitos (ej. `589412`).
4. En el campo de contraseña del FortiClient, el usuario ingresa **su clave de LDAP seguida directamente del OTP sin espacios**:
   - Contraseña: `vpnpassword123589412`
5. Al presionar "Conectar":
   - El FortiGate envía la solicitud a Keycloak vía RADIUS.
   - Keycloak valida la contraseña `vpnpassword123` y el token OTP `589412`.
   - Keycloak retorna `Access-Accept` junto con la variable `Fortinet-Group-Name = VPNGroup`.
   - El FortiGate asocia al usuario al grupo `FortiGate-VPN-Users` y aplica la política de firewall correspondiente.
   - ¡El túnel VPN se establece exitosamente!
