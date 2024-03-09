# ============================================================================
FROM alpine:3
SHELL ["/bin/ash", "-eu", "-o", "pipefail", "-c"]

# hadolint ignore=DL3018
RUN apk --no-cache add openldap openldap-back-mdb openldap-clients openssl

WORKDIR /etc/openldap
RUN sed -i "/^cn: config/aolcTLSCertificateFile: $PWD/ldaps.crt" slapd.ldif
RUN sed -i "/^cn: config/aolcTLSCertificateKeyFile: $PWD/ldaps.key" slapd.ldif
RUN mv slapd.ldif slapd.ldif.template
RUN mkdir -p slapd.d
RUN chown -R ldap:ldap .

COPY --chmod=755 <<'EOT' /docker-cmd
#!/bin/sh
set -eu -o pipefail

base_dn=${LDAP_BASE_DN-dc=example,dc=org}
bind_dn=${LDAP_BIND_DN-cn=admin,$base_dn}
bind_pw=${LDAP_BIND_PW-admin}
base_dc=$(echo "$base_dn" | sed -r 's/[^=]+=([^,]+).*/\1/g')

cd /etc/openldap

if [ -z "$(ls -A slapd.d/)" ]; then
    if [ ! -f slapd.ldif ]; then
        cp -a slapd.ldif.template slapd.ldif
        sed -i "s/^olcSuffix: .*$/olcSuffix: $base_dn/" slapd.ldif
        sed -i "s/^olcRootDN: .*$/olcRootDN: $bind_dn/" slapd.ldif
        sed -i "s/^olcRootPW: .*$/olcRootPW: $bind_pw/" slapd.ldif
    fi
    slapadd -n 0 -l slapd.ldif -F slapd.d
fi

if [ ! -f ldaps.key ] && [ ! -f ldaps.crt ]; then
    { yes "" || :; } | openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -keyout ldaps.key -out ldaps.crt
fi

db_ldif=$(grep -l olcDbDirectory -r slapd.d/)
db_path=$(awk '$1 == "olcDbDirectory:"{print $2}' "$db_ldif")
if [ -z "$(ls -A "$db_path")" ]; then
    if [ ! -f init.ldif ]; then
        cat > init.ldif <<EOF
dn: $base_dn
objectClass: dcObject
objectClass: organization
dc: $base_dc
o: $base_dc

dn: ou=people,$base_dn
objectClass: organizationalUnit
ou: people

dn: ou=groups,$base_dn
objectClass: organizationalUnit
ou: groups
EOF
    fi
    slapadd -b "$(awk '$1 == "olcRootDN:"{print $2}' "$db_ldif")" -l init.ldif
fi

exec /usr/sbin/slapd -h "ldap:/// ldaps:///" -d 0
EOT

USER ldap
CMD ["/docker-cmd"]
# ============================================================================
