#!/bin/bash

# Path to the credentials file
credentials_file="/home/runner/runners/2.321.0/.credentials"

# Check if the file exists
if [[ ! -f "$credentials_file" ]]; then
  echo "File $credentials_file not found!"
  exit 1
fi

# Read the contents of the file
cred_content=$(cat "$credentials_file")

# Encode the contents using base64
encoded_cred=$(echo -n "$cred_content" | base64)

# Print the encoded value
echo "Encoded value:"
echo "$encoded_cred"
