#!/bin/bash

# Function to download a model
download_model() {
    local json="$1"
    local id=$(echo "$json" | jq -r '.id')
    local name=$(echo "$json" | jq -r '.name')
    local filename=$(echo "$json" | jq -r '.filename')
    local path=$(echo "$json" | jq -r '.path')
    local download_url=$(echo "$json" | jq -r '.downloadUrl')
    local download_api_key_var=$(echo "$json" | jq -r '.downloadApiKeyVar // empty')

    # Check if download_url is empty, null, or not set, skip if so
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo "Skipping $name (ID: $id) - No download URL provided"
        return
    fi

    # Check if filename is empty or null, skip if so
    if [[ -z "$filename" || "$filename" == "null" ]]; then
        echo "Skipping $name (ID: $id) - No filename provided"
        return
    fi

    # Check if path is empty or null, skip if so
    if [[ -z "$path" || "$path" == "null" ]]; then
        echo "Skipping $name (ID: $id) - No path provided"
        return
    fi

    # Check if file already exists
    local full_path="${path}/${filename}"
    if [[ -f "$full_path" ]]; then
        echo "File $filename already exists in $path. Skipping download."
        return
    fi


    # Check if file already exists
    local full_path="${path}/${filename}"
    if [[ -f "$full_path" ]]; then
        echo "File $filename already exists in $path. Skipping download."
        return
    fi

    echo "Downloading $name (ID: $id)"

    # Create directory if it doesn't exist
    mkdir -p "$path"

    # Prepare curl command
    curl_cmd="curl -L"

    # Add authentication if required
    if [[ -n "$download_api_key_var" ]]; then
        api_key="${!download_api_key_var}"
        if [[ -z "$api_key" ]]; then
            echo "Error: Environment variable $download_api_key_var is not set or empty"
            return
        fi
        curl_cmd+=" -H 'Authorization: Bearer $api_key'"
    fi

    # Add output file to curl command
    curl_cmd+=" -o '$full_path' '$download_url'"

    # Execute the curl command
    eval $curl_cmd

    if [ $? -eq 0 ]; then
        echo "Successfully downloaded $filename to $path"
    else
        echo "Failed to download $filename"
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
    local depends_on=$(echo "$all_models" | jq -r ".[] | select(.id == \"$model_id\") | .dependsOn[]?" 2>/dev/null)

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

# Check if file exists, if not download it, this is a backup in case the installer doesn't download the file
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