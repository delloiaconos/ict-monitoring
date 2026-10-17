#!/usr/bin/env bash
set -euo pipefail

cert_dir=$1
cert_days=$2
config=$3
: "${BASE_DOMAIN:?Set BASE_DOMAIN in ENV_FILE before generating certificates}"
if [[ ! "$BASE_DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    echo "BASE_DOMAIN must be a DNS hostname, without a scheme or port." >&2
    exit 1
fi
if [[ ! "$cert_days" =~ ^[1-9][0-9]*$ ]]; then
    echo "CERT_DAYS must be a positive integer." >&2
    exit 1
fi

umask 077
mkdir -p "$cert_dir"
for name in fullchain.pem privkey.pem; do
    if [[ -e "$cert_dir/$name" || -L "$cert_dir/$name" ]]; then
        echo "Refusing to overwrite $cert_dir/$name; archive the existing certificate and key before regenerating." >&2
        exit 1
    fi
done

# Publish the pair only after OpenSSL completes successfully.
temp_dir=$(mktemp -d "$cert_dir/.generate.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT
openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
    -days "$cert_days" -config "$config" \
    -keyout "$temp_dir/privkey.pem" -out "$temp_dir/fullchain.pem"
chmod 644 "$temp_dir/fullchain.pem"
mv "$temp_dir/privkey.pem" "$temp_dir/fullchain.pem" "$cert_dir/"
echo "Generated self-signed certificate for $BASE_DOMAIN and *.$BASE_DOMAIN in $cert_dir (valid for $cert_days days)."
