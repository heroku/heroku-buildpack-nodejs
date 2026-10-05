#!/usr/bin/env bash
# Generates a throwaway CA and a server certificate for the hostnames proxied by the functional
# test download cache (see nginx.conf in this directory).

set -euo pipefail

cert_dir="${1:?usage: generate-certs.sh <cert-dir>}"
mkdir -p "${cert_dir}"
cd "${cert_dir}"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-subj "/CN=heroku-buildpack-nodejs test download cache CA" \
	-keyout ca.key -out ca.pem 2>/dev/null

openssl req -newkey rsa:2048 -nodes \
	-subj "/CN=heroku-buildpack-nodejs test download cache" \
	-keyout server.key -out server.csr 2>/dev/null

openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 3650 \
	-extfile <(printf 'subjectAltName=DNS:registry.npmjs.org,DNS:registry.yarnpkg.com,DNS:nodejs.org') \
	-out server.pem 2>/dev/null

rm -f server.csr ca.srl
