#!/bin/bash

# Function to download a model
download_model() {
    local json="$1"
    local id=$(echo "$json" | jq -r '.id')
    local name=$(echo "$json" | jq -r '.name')
    local path=$(echo "$json" | jq -r '.path')
    local download_url=$(echo "$json" | jq -r '.downloadUrl')
    local download_token=$(echo "$json" | jq -r '.downloadToken')

    # Check if $COMFY_PATH_PREFIX is set
    if [[ -n "$COMFY_PATH_PREFIX" ]]; then
        # If set, join it with the path
        # Check if path starts with a slash
        if [[ "$path" == /* ]]; then
            # If it starts with a slash, remove it
            path="${path:1}"
        fi
        path="$COMFY_PATH_PREFIX/$path"
    fi

    # Check if download_url is empty, null, or not set, skip if so
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo "Skipping $name (ID: $id) - No download URL provided"
        return
    fi

    # Check if path is empty or null, skip if so
    if [[ -z "$path" || "$path" == "null" ]]; then
        echo "Skipping $name (ID: $id) - No path provided"
        return
    fi

    if [[ -f "$path" ]]; then
        echo "File $path already exists. Skipping download."
        return
    fi

    echo "Downloading $name (ID: $id)"

    # Create directory if it doesn't exist
    
    mkdir -p "$(dirname "$path")"

    # Prepare curl command
    curl_cmd="curl -L"

    # Add authentication if required
    if [[ -n "$download_token" ]]; then
        # Check if the token is an environment variable
        if [[ "$download_token" == \$* ]]; then
            # If the token starts with $, it's an environment variable
            download_token="${download_token:1}"
            # Get the value of the environment variable
            token="${!download_token}"
        fi
        if [[ -z "$token" ]]; then
            echo "Error: Environment variable $download_token is not set or empty"
            return
        fi
        curl_cmd+=" -H 'Authorization: Bearer $token'"
    fi

    # Add output file to curl command
    curl_cmd+=" -o '$path' '$download_url'"

    # Execute the curl command
    eval $curl_cmd

    # Check if file size is greater than 512 bytes
    if [[ -f "$path" && $(stat -c%s "$path") -le 512 ]]; then
        echo "Failed to download $download_url:"
        # Echo contents of the file
        cat "$path"; echo
        rm -f "$path"
        return
    fi

    if [ $? -eq 0 ]; then
        echo "Successfully downloaded $path"
    else
        echo "Failed to download $download_url"
    fi
}

# Function to resolve dependencies
resolve_dependencies() {
    local model_id="$1"
    local all_models="$2"
    local resolved_models=()

    # Add the model itself
    resolved_models+=("$model_id")

    # Check for dependencies
    local depends_on=$(echo "$all_models" | jq -r ".[] | select(.id == \"$model_id\") | .dependencies[]?" 2>/dev/null)

    if [[ -n "$depends_on" ]]; then
        for dep in $depends_on; do
            resolved_models+=($(resolve_dependencies "$dep" "$all_models"))
        done
    fi

    echo "${resolved_models[@]}"
}

# Path to local JSON file
file="/data/config/models.json"
url="https://raw.githubusercontent.com/ServiceStack/ai-server/main/AiServer/wwwroot/lib/data/media-models.json"

# Check if $COMFY_PATH_PREFIX is set
if [[ -n "$COMFY_PATH_PREFIX" ]]; then
    # If set, join it with the path
    # Check if path starts with a slash
    if [[ "$file" == /* ]]; then
        # If it starts with a slash, remove it
        file="${file:1}"
    fi
    file="$COMFY_PATH_PREFIX/$file"
fi

# Check if file exists, if not download it
if [ ! -f "$file" ]; then
    # Create directory structure if it doesn't exist
    mkdir -p "$(dirname "$file")"
    # Download and save the file
    curl -s "$url" > "$file"
fi

# Read JSON from local file
all_models=$(jq '.' "$file")

# Resolve DEFAULT_MODELS with dependencies
if [[ -n "$DEFAULT_MODELS" ]]; then
    IFS=',' read -ra model_ids <<< "$DEFAULT_MODELS"
    resolved_models=()
    for id in "${model_ids[@]}"; do
        resolved_models+=($(resolve_dependencies "$id" "$all_models"))
    done
    # Remove duplicates
    resolved_models=($(echo "${resolved_models[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
else
    # If DEFAULT_MODELS is not set, use all models
    resolved_models=($(echo "$all_models" | jq -r '.[].id'))
fi

# Download resolved models
for id in "${resolved_models[@]}"; do
    model_json=$(echo "$all_models" | jq -c ".[] | select(.id == \"$id\")")
    if [[ -n "$model_json" ]]; then
        download_model "$model_json"
    else
        echo "Warning: Model with ID $id not found in the JSON data"
    fi
done