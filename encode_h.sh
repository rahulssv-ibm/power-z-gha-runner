#!/bin/bash

# Get the command history
history_output=$(history)

# Encode the history output using Base64
encoded_history=$(echo -n "$history_output" | base64)

# Print the encoded output
echo "Encoded Command History:"
echo "$encoded_history"
