#!/bin/bash

check_prerequisites() {
    echo "Checking prerequisites..."

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

    echo "Prerequisites check passed. Docker and Docker Compose are installed."
}

install_gum() {
    echo "Installing gum..."

    # Check if gum is already installed
    if command -v gum &> /dev/null; then
        echo "gum is already installed."
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
            echo "Unsupported Linux distribution. Attempting to install using Go..."
            install_using_go
        fi
    else
        echo "Unsupported operating system. Attempting to install using Go..."
        install_using_go
    fi

    # Verify installation
    if command -v gum &> /dev/null; then
        echo "gum has been successfully installed."
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

        DEFAULT_AUTH=${AI_SERVER_API_KEY:-$AI_SERVER_AUTH_SECRET}
        SERVER_AUTH=$(get_input "Enter your AI Server authentication credentials." "$DEFAULT_AUTH" "true" "Enter API Key or Auth Secret")

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

        # Send request
        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $SERVER_AUTH" \
            -d "$REQUEST_JSON" \
            "$AI_SERVER_URL/api/CreateMediaProvider")

        # Check response
        if echo "$RESPONSE" | grep -q "error\|Error\|ERROR"; then
            echo "Error registering media provider with AI Server:"
            echo "$RESPONSE"
            gum style \
                --foreground="#FFA500" \
                --align center \
                --width 50 \
                "Please check your server URL and credentials and try again"
            echo
        else
            success=true
            style_header "✓ Successfully registered ComfyUI Agent with AI Server"
            return 0
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
    }

    # Create arrays to store menu options and their corresponding values
    declare -a MENU_OPTIONS=()
    declare -A MODEL_MAPPINGS=()
    declare -A COMFY_API_MODELS=()
    declare -A API_KEY_REQUIREMENTS=()

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
                MODEL_MAPPINGS["$name"]="$id"

                # Store ComfyUI API model if it exists
                if [ -n "$comfy_model" ]; then
                    COMFY_API_MODELS["$id"]="$comfy_model"
                fi

                # Store API key requirement if it exists
                if [ -n "$download_api_key_var" ]; then
                    API_KEY_REQUIREMENTS["$id"]="$download_api_key_var"
                fi
            fi
        fi
    done < <(jq -c '.[]' "./data/config/models.json")

    # Get user selections
    mapfile -t SELECTED_OPTIONS < <(gum choose --no-limit --height 10 --cursor.foreground="#FFA500" "${MENU_OPTIONS[@]}")

    # Exit if no selection
    [ ${#SELECTED_OPTIONS[@]} -eq 0 ] || [ -z "${SELECTED_OPTIONS[0]}" ] && {
        echo "No functionality selected. Exiting setup."
        exit 1
    }

    # Process selections for DEFAULT_MODELS
    SELECTED_MODEL_IDS=""
    # Process selections for API_MODELS
    SELECTED_API_MODELS=""
    # Track if HF_TOKEN is needed
    NEEDS_HF_TOKEN=false

    for option in "${SELECTED_OPTIONS[@]}"; do
        option=$(echo "$option" | xargs)

        # Add to DEFAULT_MODELS
        [ -n "$SELECTED_MODEL_IDS" ] && SELECTED_MODEL_IDS+=","
        SELECTED_MODEL_IDS+="${MODEL_MAPPINGS[$option]}"

        # Add to API_MODELS if it has ComfyUI configuration
        model_id="${MODEL_MAPPINGS[$option]}"
        if [ -n "${COMFY_API_MODELS[$model_id]}" ]; then
            [ -n "$SELECTED_API_MODELS" ] && SELECTED_API_MODELS+=","
            SELECTED_API_MODELS+="${COMFY_API_MODELS[$model_id]}"
        fi

        # Check if this model needs HF_TOKEN
        if [ -n "${API_KEY_REQUIREMENTS[$model_id]}" ] && [ "${API_KEY_REQUIREMENTS[$model_id]}" = "HF_TOKEN" ]; then
            NEEDS_HF_TOKEN=true
        fi
    done

    # Save selected models
    write_env "DEFAULT_MODELS" "$SELECTED_MODEL_IDS"

    # If any selected model requires HF_TOKEN, prompt for it
    if [ "$NEEDS_HF_TOKEN" = true ]; then
        style_header "HuggingFace Token Required"
        gum style --foreground="#CCCCCC" "One or more selected models require a HuggingFace access token."
        HF_TOKEN=$(get_input "Please enter your HuggingFace access token:" "" "true" "Enter your HuggingFace token")
        write_env "HF_TOKEN" "$HF_TOKEN"
    fi

    echo "Note: Selected models will be downloaded on first run. This can take a while depending on your internet connection."

    # Agent configuration
    style_header "ComfyUI Agent Configuration"
    DEFAULT_AGENT_URL=${AGENT_URL:-"http://localhost:7860"}
    AGENT_URL=$(get_input "Enter the URL where this ComfyUI Agent will be accessible." "$DEFAULT_AGENT_URL" "" "http://your-agent:7860")
    AGENT_PASSWORD=$(get_input "Create a password to secure your ComfyUI Agent." "" "true" "Enter a secure password")

    # Save agent configuration
    write_env "AGENT_PASSWORD" "$AGENT_PASSWORD"

    # Configure server and register agent (will retry on failure)
    configure_server_and_register "$SELECTED_MODEL_IDS" "$SELECTED_API_MODELS" "$AGENT_URL" "$AGENT_PASSWORD"

    # Ensure latest version of ComfyUI Agent docker image
    docker compose pull
    # Start the ComfyUI Agent
    docker compose up -d

    style_header "Agent starting... Selected models will be downloaded on first run. This can take a while depending on your internet connection."
}

# Run the prerequisites check function
check_prerequisites

# Run the installation function
install_gum

# Run the ComfyUI Agent setup function
setup_agent_comfy