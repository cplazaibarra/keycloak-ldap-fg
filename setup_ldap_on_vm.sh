#!/bin/bash
set -e

# Login
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password admin

# Get master realm ID
REALM_ID=$(/opt/keycloak/bin/kcadm.sh get realms/master --fields id --format csv --noquotes)

# Clean up existing OpenLDAP component if it exists
echo "Checking for existing OpenLDAP provider..."
EXISTING_ID=$(/opt/keycloak/bin/kcadm.sh get components -r master -q name=OpenLDAP --fields id --format csv --noquotes || true)

if [ ! -z "$EXISTING_ID" ]; then
  echo "Deleting existing OpenLDAP component with ID: $EXISTING_ID"
  /opt/keycloak/bin/kcadm.sh delete components/$EXISTING_ID -r master
fi

# Create LDAP Component using JSON input pointing to host machine's IP (192.168.122.1)
echo "Creating LDAP Component..."
COMP_ID=$(echo '{
  "name": "OpenLDAP",
  "providerId": "ldap",
  "providerType": "org.keycloak.storage.UserStorageProvider",
  "parentId": "'$REALM_ID'",
  "config": {
    "enabled": ["true"],
    "editMode": ["WRITABLE"],
    "connectionUrl": ["ldap://192.168.122.1:389"],
    "usersDn": ["ou=people,dc=example,dc=org"],
    "usernameLDAPAttribute": ["uid"],
    "rdnLDAPAttribute": ["uid"],
    "uuidLDAPAttribute": ["entryUUID"],
    "userObjectClasses": ["inetOrgPerson, organizationalPerson, person"],
    "bindDn": ["cn=admin,dc=example,dc=org"],
    "bindCredential": ["adminpassword"],
    "vendor": ["other"],
    "importEnabled": ["true"],
    "syncRegistrations": ["true"],
    "authType": ["simple"],
    "searchScope": ["2"]
  }
}' | /opt/keycloak/bin/kcadm.sh create components -r master -f - --id)

echo "LDAP component created with ID: $COMP_ID"

# Create LDAP Group Mapper using JSON input
echo "Creating LDAP Group Mapper..."
echo '{
  "name": "GroupMapper",
  "providerId": "group-ldap-mapper",
  "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
  "parentId": "'$COMP_ID'",
  "config": {
    "groups.dn": ["ou=groups,dc=example,dc=org"],
    "group.name.ldap.attribute": ["cn"],
    "group.object.classes": ["groupOfNames"],
    "membership.ldap.attribute": ["member"],
    "membership.user.ldap.attribute": ["uid"],
    "membership.attribute.type": ["DN"],
    "user.groups.retrieve.strategy": ["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"],
    "mode": ["IMPORT"]
  }
}' | /opt/keycloak/bin/kcadm.sh create components -r master -f -

echo "Group Mapper created."

# Trigger full sync
/opt/keycloak/bin/kcadm.sh create "user-storage/$COMP_ID/sync?action=triggerFullSync" -r master
echo "LDAP users and groups synchronized."
