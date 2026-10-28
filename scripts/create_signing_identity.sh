#!/bin/zsh
# Creates a self-signed code-signing identity "Dictate Local Signing" in the login keychain.
# A stable signature lets macOS keep Dictate's Accessibility/Microphone grants across rebuilds.
# Remove it later in Keychain Access (search "Dictate Local Signing").
set -euo pipefail
NAME="Dictate Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "Identity already exists."; exit 0; fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" 2>/dev/null
PASS=$(uuidgen)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout pass:"$PASS" 2>/dev/null
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
echo "Created \"$NAME\"."
