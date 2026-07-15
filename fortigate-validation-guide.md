# Guía de Validación: VPN IPsec con Keycloak RADIUS en FortiGate VM

Esta guía describe los pasos para realizar la prueba de validación de la VPN IPsec utilizando la máquina virtual de **FortiGate** (`192.168.122.161`), el servidor **Keycloak RADIUS** (`192.168.122.151`) y la máquina de pruebas.

---

## 1. Configurar el Mapeo de Grupos en Keycloak (Retornar Atributo de Grupo)

Para que FortiGate pueda ver a qué grupo pertenece el usuario, Keycloak debe enviar el atributo `Fortinet-Group-Name` en la respuesta RADIUS.

1. Abre tu navegador e ingresa a la consola de Keycloak:
   👉 **[http://192.168.122.151:8080](http://192.168.122.151:8080)** (credenciales: `admin` / `admin`).
2. En el menú de la izquierda, ve a la sección **Radius** -> pestaña **Radius Mappers**.
3. Haz clic en **Create Radius Mapper**:
   * **Name**: `FortinetGroupMapper`
   * **Mapper Type**: `Group Member Mapper`
   * **Radius Attribute**: `Fortinet-Group-Name` (Vendor ID: `12356`, Attribute ID: `1`).
   * **Keycloak Group**: Selecciona el grupo al que pertenecen los usuarios (ej: `/VPNGroup`).
   * **Value**: `VPNGroup` (este es el valor de texto que recibirá el FortiGate).
   * Haz clic en **Save**.

---

## 2. Configurar la VPN IPsec en FortiGate (Vía GUI)

Dado que es una máquina virtual de laboratorio recién levantada, la forma más rápida y segura de crear la VPN IPsec con la sintaxis exacta de FortiOS v7.6 es usando el **Asistente de VPN (VPN Wizard)**:

1. Entra a la consola web de FortiGate:
   👉 **[https://192.168.122.161](https://192.168.122.161)** (credenciales: `admin` / `Mquest!test2026`).
2. Ve a **VPN** -> **IPsec Wizard**.
3. Configura los siguientes parámetros:
   * **Name**: `DialupVPN`
   * **Template Type**: `Dial Up`
   * **Remote Device Type**: `FortiClient`
   * Haz clic en **Next**.
4. En **Incoming Interface** selecciona `port1`.
5. En **Authentication Method** selecciona `Pre-shared Key` e introduce una clave (ej: `fortigatevpnpsk`).
6. En **User Group** selecciona el grupo **`VPN-RADIUS-Users`** (que ya creamos y que está vinculado a tu servidor Keycloak RADIUS).
7. En los siguientes pasos de red y DHCP, puedes dejar los valores por defecto y hacer clic en **Create**.

---

## 3. Pruebas de Conexión desde FortiClient

Desde tu máquina principal o máquina de pruebas con **FortiClient IPsec VPN**:

1. Crea una nueva conexión IPsec VPN:
   * **Connection Name**: `Lab-VPN`
   * **Remote Gateway**: `192.168.122.161`
   * **Authentication Method**: `Pre-Shared Key` (ingresa `fortigatevpnpsk`).
   * **IKE Version**: `IKEv2`
2. Intenta conectar utilizando las credenciales de LDAP sincronizadas:
   * **User**: `vpnuser`
   * **Password**: `vpnpassword123` *(Dado que desactivamos el OTP globalmente en el paso anterior, solo requiere la contraseña de LDAP)*.

---

## 4. Comandos de Validación en FortiGate (Verificar el Grupo del Usuario)

Para verificar en tiempo real que el túnel está arriba y que FortiGate asignó correctamente al usuario a su grupo correspondiente (`VPNGroup`), entra por SSH a tu FortiGate (`admin` / `Mquest!test2026`) y ejecuta:

### A. Ver usuarios autenticados en el Firewall (Muestra el Grupo)
Este comando muestra la lista de sesiones activas autenticadas por RADIUS y el grupo exacto que retornó Keycloak:
```bash
diagnose firewall auth list
```
**Ejemplo de salida exitosa:**
```text
192.168.122.100, vpnuser
        ...
        group: VPN-RADIUS-Users (VPNGroup)  <-- ¡Aquí se confirma el mapeo del grupo!
        member of: VPN-RADIUS-Users
        ...
```

### B. Ver los túneles IPsec activos
Muestra el estado del túnel y las IPs asignadas a los clientes conectados:
```bash
diagnose vpn tunnel list
```

### C. Ver logs de autenticación detallados (fnbamd)
Si deseas ver el proceso de negociación RADIUS en vivo mientras el usuario se conecta:
```bash
diagnose debug application fnbamd -1
diagnose debug enable
```
*(Para apagarlo después de la prueba: `diagnose debug disable`)*.
