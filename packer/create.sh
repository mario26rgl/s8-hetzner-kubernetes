#!/usr/bin/env bash

# Set default path if not provided
if [ -z "$folder_path" ]; then
    folder_path="."
fi

if [[ -z "$HCLOUD_TOKEN" ]]; then
    read -p "Enter your (WRITE) HCLOUD_TOKEN: " hcloud_token
    export HCLOUD_TOKEN=$hcloud_token
fi
echo "Running packer build for hardened-image.pkr.hcl"
cd "${folder_path}" && packer init hardened-image.pkr.hcl && packer build hardened-image.pkr.hcl
