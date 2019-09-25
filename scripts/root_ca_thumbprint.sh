#!/bin/bash

# Helper script to compute a thumbprint for the Root CA Cert of the EKS OIDC
# issuer. If all goes well, the thumbprint is printed to stdout (logging to stderr).
#

set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Invalid arguments. OIDC provider URL missing." >&2
    exit 1
fi

# Create a temp directory to play around in (+ add cleanup hook)
DIR="$(mktemp --directory)"
trap "rm -rf $DIR" EXIT
cd "$DIR"

# From https://stackoverflow.com/a/11385736
ISSUER_ENDPOINT="$1"
ISSUER_HOST=$(echo $1 | awk -F[/:] '{print $4}')

# Save the certificates in the chain to numbered files from leaf to root. Snippet from https://unix.stackexchange.com/a/487546
openssl s_client -servername "$ISSUER_HOST" -showcerts -verify 5 -connect "$ISSUER_HOST":443 < /dev/null 2>/dev/null \
    | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; out="cert"a".pem"; print >out}'

# Compute the fingerprint for the Root CA cert and format it according to IAM requirements
ROOT_CERT_PEM=$(ls *.pem | sort -nr | head -1)
openssl x509 -in "$ROOT_CERT_PEM" -fingerprint -noout | cut -d "=" -f 2 | sed "s/://g"
