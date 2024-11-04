#!/bin/bash

# Initialize verbose flag
VERBOSE=false

# Process command line arguments
while getopts "v" opt; do
    case $opt in
        v) VERBOSE=true ;;
        *) echo "Usage: $0 [-v]" >&2
           exit 1 ;;
    esac
done

# Helper function for verbose logging
log() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Please install Docker before running this script."
        echo "Visit https://docs.docker.com/get-docker/ for installation instructions."
        exit 1
    fi

    # Check if Docker Compose is installed
    if ! command -v docker compose &> /dev/null; then
        echo "Docker Compose is not installed or not in PATH."
        echo "Recent Docker Desktop versions include Compose. If you're using Docker Desktop, please make sure it's up to date."
        echo "Otherwise, visit https://docs.docker.com/compose/install/ for installation instructions."
        exit 1
    fi

    log "Prerequisites check passed. Docker and Docker Compose are installed."
}

install_gum() {
    log "Installing gum..."

    # Check if gum is already installed
    if command -v gum &> /dev/null; then
        log "gum is already installed."
        return
    fi

    # Detect the operating system
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install gum
        else
            echo "Homebrew is not installed. Please install Homebrew first: https://brew.sh/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
            sudo apt update && sudo apt install -y gum
        elif command -v yum &> /dev/null; then
            # Fedora/RHEL
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
            sudo rpm --import https://repo.charm.sh/yum/gpg.key
            sudo yum install -y gum
        elif command -v zypper &> /dev/null; then
            # OpenSUSE
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/zypp/repos.d/charm.repo
            sudo rpm --import https://repo.charm.sh/yum/gpg.key
            sudo zypper refresh
            sudo zypper install -y gum
        elif command -v pacman &> /dev/null; then
            # Arch Linux
            sudo pacman -S gum
        else
            log "Unsupported Linux distribution. Attempting to install using Go..."
            install_using_go
        fi
    else
        log "Unsupported operating system. Attempting to install using Go..."
        install_using_go
    fi

    # Verify installation
    if command -v gum &> /dev/null; then
        log "gum has been successfully installed."
    else
        echo "Failed to install gum. Please try manual installation."
        exit 1
    fi
}

install_using_go() {
    if command -v go &> /dev/null; then
        go install github.com/charmbracelet/gum@latest
        # Add $HOME/go/bin to PATH if it's not already there
        if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
            echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
            source ~/.bashrc
        fi
    else
        echo "Go is not installed. Please install Go first: https://golang.org/doc/install"
        exit 1
    fi
}

# Reusable input prompt function
get_input() {
    local prompt="$1"
    local default="$2"
    local is_password="$3"
    local placeholder="$4"

    # Print prompts to stderr so they don't get captured in variable assignment
    echo >&2
    gum style --foreground="#CCCCCC" "$prompt" >&2
    [ -n "$default" ] && gum style --foreground="#888888" "Default: $default" >&2

    local input_args=(
        --value "${default:-}"
        --placeholder "$placeholder"
        --prompt "> "
        --prompt.foreground="#00FFFF"
    )
    [ "$is_password" = "true" ] && input_args+=(--password)

    # Only return the actual input value
    gum input "${input_args[@]}"
}

# Reusable function to write to .env
write_env() {
    echo "$1=$2" >> .env
}

# Function to check if ComfyUI Agent is ready
check_comfy_status() {
    local url="$1"
    # Remove trailing slash if present
    url="${url%/}"
    # Try to access the health endpoint
    curl -s -f "${url}/health" > /dev/null 2>&1
    return $?
}

# Function to handle server configuration and API registration
configure_server_and_register() {
    local selected_model_ids="$1"
    local selected_api_models="$2"
    local agent_url="$3"
    local agent_password="$4"
    local success=false

    # Extract domain from agent_url
    # Split on // and take everything after it
    local domain=$(echo "$agent_url" | sed 's|.*//||')
    local agent_name="ComfyUI Agent - ${domain}"

    while [ "$success" = false ]; do
        # Server configuration
        style_header "AI Server Configuration"
        DEFAULT_SERVER_URL=${AI_SERVER_URL:-"http://localhost:5006"}
        AI_SERVER_URL=$(get_input "Enter the URL where your AI Server is running." "$DEFAULT_SERVER_URL" "" "http://your-server:5006")

        if [ -z "$AI_SERVER_URL" ]; then
            if gum confirm "AI Server URL is empty. Do you want to exit?"; then
                exit 0
            elif test $? -eq 130; then
                exit 0
            else
                continue
            fi
        fi

        DEFAULT_AUTH=${AI_SERVER_API_KEY:-$AI_SERVER_AUTH_SECRET}
        SERVER_AUTH=$(get_input "Enter your AI Server authentication credentials." "$DEFAULT_AUTH" "true" "Enter AI Server Auth Secret")

        if [ -z "$SERVER_AUTH" ]; then
            if gum confirm "AI Server Auth Secret is empty. Do you want to exit?"; then
                exit 0
            elif test $? -eq 130; then
                exit 0
            else
                continue
            fi
        fi

        # Prepare API request
        # Convert API models string to array and format for JSON
        IFS=',' read -ra API_MODELS <<< "$selected_api_models"
        MODELS_JSON=$(printf '"%s",' "${API_MODELS[@]}" | sed 's/,$//')

        # Create request JSON
        REQUEST_JSON=$(cat <<EOF
{
    "name": "${agent_name}",
    "apiKey": "${agent_password}",
    "apiBaseUrl": "${agent_url}",
    "models": [${MODELS_JSON}],
    "mediaTypeId": "ComfyUI",
    "enabled": true
}
EOF
)

        # Log request details (masked sensitive data)
        echo "Sending request to: $AI_SERVER_URL/api/CreateMediaProvider"
        echo "Request headers:"
        echo "Content-Type: application/json"
        echo "Authorization: Bearer ********"
        echo "Request body:"
        echo "$REQUEST_JSON"

        # Create a temporary file for headers
        HEADER_FILE=$(mktemp)

        # Send request and save headers to temp file
        RESPONSE=$(curl -s -w "%{http_code}" \
            -D "${HEADER_FILE}" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $SERVER_AUTH" \
            -d "$REQUEST_JSON" \
            "$AI_SERVER_URL/api/CreateMediaProvider")

        # Extract the HTTP status code (last line of response)
        HTTP_STATUS="${RESPONSE: -3}"
        # Extract the response body (everything except last 3 characters)
        RESPONSE_BODY="${RESPONSE:0:${#RESPONSE}-3}"

        # Clean up temporary file
        rm -f "${HEADER_FILE}"

        # Check HTTP status code first
        if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
            success=true
            style_header "✓ Successfully registered ComfyUI Agent with AI Server"
            return 0
        else
            echo "HTTP Status Code: $HTTP_STATUS"
            echo "Error registering media provider with AI Server:"
            echo "$RESPONSE_BODY"

            # Additional error details based on status code
            case $HTTP_STATUS in
                401)
                    echo "Authentication failed. Please check your credentials."
                    ;;
                404)
                    echo "API endpoint not found. Please verify the server URL."
                    ;;
                500)
                    echo "Server internal error occurred."
                    ;;
            esac

            gum style \
                --foreground="#FFA500" \
                --align center \
                --width 50 \
                "Please check your server URL and credentials and try again"
            echo
        fi
    done
}

# Helper functions for array operations
get_model_id() {
    local name="$1"
    local i
    for i in "${!MENU_NAMES[@]}"; do
        if [ "${MENU_NAMES[$i]}" = "$name" ]; then
            echo "${MENU_IDS[$i]}"
            return
        fi
    done
}

get_comfy_api_model() {
    local id="$1"
    local i
    for i in "${!COMFY_MODEL_IDS[@]}"; do
        if [ "${COMFY_MODEL_IDS[$i]}" = "$id" ]; then
            echo "${COMFY_API_MODEL_NAMES[$i]}"
            return
        fi
    done
}

persist_models_config() {
    # Path to local JSON file
    file="./data/config/models.json"
    url="https://raw.githubusercontent.com/ServiceStack/ai-server/main/AiServer/wwwroot/lib/data/media-models.json"

    # Ensure directory exists
    mkdir -p "$(dirname "$file")"
    curl -s "$url" > "$file"
}

setup_agent_comfy() {
    # Initialize/reset .env file
    : > .env

    # Reusable style function for headers
    style_header() {
        gum style \
            --foreground="#00FFFF" \
            --border-foreground="#00FFFF" \
            --border double \
            --align center \
            --width 50 \
            "$1"
    }

    # Persist models configuration
    persist_models_config

    # Model selection setup
    style_header "ComfyUI Model Selection"
    gum style --foreground="#CCCCCC" "Select which functionality you would like to support:"
    gum style --foreground="#888888" --italic "Use space to select, enter to confirm"

    # Read and parse the JSON file
    if ! [ -f "./data/config/models.json" ]; then
        echo "Error: models.json file not found"
        exit 1
    fi  # Fixed: Missing 'fi'

    # Create arrays to store menu options and their corresponding values
    declare -a MENU_OPTIONS
    declare -a HF_TOKEN_REQUIRED

    # Use parallel arrays for MODEL_MAPPINGS
    MENU_NAMES=()
    MENU_IDS=()
    # Use parallel arrays for COMFY_API_MODELS
    COMFY_MODEL_IDS=()
    COMFY_API_MODEL_NAMES=()

    # Parse JSON and populate arrays
    while IFS= read -r line; do
        if [[ $line == *"installer"* ]] && [[ $line == *"name"* ]]; then
            # Extract installer name and corresponding model ID
            name=$(echo "$line" | jq -r '.installer.name')
            id=$(echo "$line" | jq -r '.id')
            comfy_model=$(echo "$line" | jq -r '.apiModels.ComfyUI // empty')
            download_api_key_var=$(echo "$line" | jq -r '.downloadApiKeyVar // empty')

            if [ -n "$name" ] && [ -n "$id" ]; then
                MENU_OPTIONS+=("$name")
                # Add to parallel arrays instead of associative array
                MENU_NAMES+=("$name")
                MENU_IDS+=("$id")

                # Store ComfyUI API model if it exists
                if [ -n "$comfy_model" ]; then
                    COMFY_MODEL_IDS+=("$id")
                    COMFY_API_MODEL_NAMES+=("$comfy_model")
                fi

                # Check if this model requires HF_TOKEN
                if [ "$download_api_key_var" = "HF_TOKEN" ]; then
                    HF_TOKEN_REQUIRED+=("$id")
                fi
            fi
        fi
    done < <(jq -c '.[]' "./data/config/models.json")

    # Get user selections
    SELECTED_OPTIONS=()
    while IFS= read -r option; do
        SELECTED_OPTIONS+=("$option")
    done < <(gum choose --no-limit --height 10 --cursor.foreground="#FFA500" "${MENU_OPTIONS[@]}")

    # Exit if no selection
    if [ ${#SELECTED_OPTIONS[@]} -eq 0 ] || [ -z "${SELECTED_OPTIONS[0]}" ]; then
        echo "No functionality selected. Exiting setup."
        exit 1
    fi  # Changed from single-line syntax for clarity

    # Process selections for DEFAULT_MODELS
    SELECTED_MODEL_IDS=""
    # Process selections for API_MODELS
    SELECTED_API_MODELS=""
    # Flag to track if any selected model requires HF_TOKEN
    NEEDS_HF_TOKEN=false

    # Process selections
    for option in "${SELECTED_OPTIONS[@]}"; do
        option=$(echo "$option" | xargs)  # Trim whitespace

        # Add to DEFAULT_MODELS
        [ -n "$SELECTED_MODEL_IDS" ] && SELECTED_MODEL_IDS+=","
        model_id=$(get_model_id "$option")
        SELECTED_MODEL_IDS+="$model_id"

        # Add to API_MODELS if it has ComfyUI configuration
        comfy_model=$(get_comfy_api_model "$model_id")
        if [ -n "$comfy_model" ]; then
            [ -n "$SELECTED_API_MODELS" ] && SELECTED_API_MODELS+=","
            SELECTED_API_MODELS+="$comfy_model"
        fi

        # Check if this model requires HF_TOKEN
        for hf_required in "${HF_TOKEN_REQUIRED[@]}"; do
            if [ "$model_id" = "$hf_required" ]; then
                NEEDS_HF_TOKEN=true
                break
            fi
        done
    done

    # Save selected models
    write_env "DEFAULT_MODELS" "$SELECTED_MODEL_IDS"

    # If any selected model requires HF_TOKEN, prompt for it
    if [ "$NEEDS_HF_TOKEN" = true ]; then
        style_header "HuggingFace Token Required"
        gum style --foreground="#CCCCCC" "One or more selected models require a HuggingFace access token."
        gum style --foreground="#888888" "You can get your token at https://huggingface.co/settings/tokens"

        HF_TOKEN=$(get_input "Please enter your HuggingFace access token:" "" "true" "Enter your HuggingFace token")
        if [ -n "$HF_TOKEN" ]; then
            write_env "HF_TOKEN" "$HF_TOKEN"
        else
            echo "Error: HuggingFace token is required but was not provided."
            exit 1
        fi
    fi

    echo "Note: Selected models will be downloaded on first run. This can take a while depending on your internet connection."

    # Agent configuration
    style_header "ComfyUI Agent Configuration"
    DEFAULT_AGENT_URL=${AGENT_URL:-"http://localhost:7860"}
    AGENT_URL=$(get_input "Enter the URL where this ComfyUI Agent will be accessible." "$DEFAULT_AGENT_URL" "" "http://your-agent:7860")

    if [ -z "$AGENT_URL" ]; then
        if gum confirm "Agent URL is empty. Do you want to exit?"; then
            exit 0
        elif test $? -eq 130; then
            exit 0
        else
            AGENT_URL="http://localhost:7860"
        fi
    fi

    AGENT_PASSWORD=$(get_input "Create a password to secure your ComfyUI Agent." "" "true" "Enter a secure password")

    if [ -z "$AGENT_PASSWORD" ]; then
        if gum confirm "Agent password is empty. Do you want to exit?"; then
            exit 0
        elif test $? -eq 130; then
            exit 0
        else
            AGENT_PASSWORD=""
        fi
    fi

    if [ "$AGENT_PASSWORD" = "" ]; then
        echo "Warning: The ComfyUI Agent will not be secured with a password."
    else
        # Save agent configuration
        write_env "AGENT_PASSWORD" "$AGENT_PASSWORD"
    fi

    if gum confirm "Do you want to register the ComfyUI Agent with the AI Server?"; then
        configure_server_and_register "$SELECTED_MODEL_IDS" "$SELECTED_API_MODELS" "$AGENT_URL" "$AGENT_PASSWORD"
    fi

    # Create ai-services network if it doesn't exist
    docker network create ai-services &> /dev/null || true

    # Ensure latest version of ComfyUI Agent docker image
    docker compose pull
    # Start the ComfyUI Agent
    docker compose up -d

    style_header "Agent starting... Selected models will be downloaded on first run. This can take a while depending on your internet connection."
    echo "You can check the status of the agent by running 'docker compose logs'"
}

# Run the prerequisites check function
check_prerequisites

# Run the installation function
install_gum

# Run the ComfyUI Agent setup function
setup_agent_comfy