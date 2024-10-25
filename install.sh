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
    local agent_url="$2"
    local agent_password="$3"
    local success=false

    while [ "$success" = false ]; do
        # Server configuration
        style_header "AI Server Configuration"
        DEFAULT_SERVER_URL=${AI_SERVER_URL:-"http://localhost:5006"}
        AI_SERVER_URL=$(get_input "Enter the URL where your AI Server is running." "$DEFAULT_SERVER_URL" "" "http://your-server:5006")

        DEFAULT_AUTH=${AI_SERVER_API_KEY:-$AI_SERVER_AUTH_SECRET}
        SERVER_AUTH=$(get_input "Enter your AI Server authentication credentials." "$DEFAULT_AUTH" "true" "Enter API Key or Auth Secret")

        # Prepare API request
        IFS=',' read -ra MODEL_IDS <<< "$selected_model_ids"
        MODELS_JSON=$(printf '"%s",' "${MODEL_IDS[@]}" | sed 's/,$//')

        # Create request JSON
        REQUEST_JSON=$(cat <<EOF
{
    "name": "ComfyUI Agent",
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

    # Model selection setup
    style_header "ComfyUI Model Selection"
    gum style --foreground="#CCCCCC" "Select which functionality you would like to support:"
    gum style --foreground="#888888" --italic "Use space to select, enter to confirm"

    # Define model options
    declare -A MODEL_OPTIONS=(
        ["Text & Image to Image (SDXL)"]="sdxl-lightning,jib-mix-realistic"
        ["Text to Image (Flux.Schnell)"]="flux-schnell"
        ["Image Upscale (RealESRGAN_x2)"]="image-upscale-2x"
        ["Speech to Text (Whisper)"]="speech-to-text"
        ["Text to Speech (Piper TTS)"]="text-to-speech"
        ["Image to Text (Florence2)"]="image-to-text"
    )

    # Get user selections
    mapfile -t SELECTED_OPTIONS < <(gum choose --no-limit --height 10 --cursor.foreground="#FFA500" "${!MODEL_OPTIONS[@]}")

    # Exit if no selection
    [ ${#SELECTED_OPTIONS[@]} -eq 0 ] || [ -z "${SELECTED_OPTIONS[0]}" ] && {
        echo "No functionality selected. Exiting setup."
        exit 1
    }

    # Process selections
    SELECTED_MODEL_IDS=""

    for option in "${SELECTED_OPTIONS[@]}"; do
        option=$(echo "$option" | xargs)
        [ -n "$SELECTED_MODEL_IDS" ] && SELECTED_MODEL_IDS+=","
        SELECTED_MODEL_IDS+="${MODEL_OPTIONS[$option]}"

    done

    # Save selected models
    write_env "DEFAULT_MODELS" "$SELECTED_MODEL_IDS"
    echo "Note: Selected models will be downloaded on first run. This can take a while depending on your internet connection."

    # Agent configuration
    style_header "ComfyUI Agent Configuration"
    AGENT_URL=$(get_input "Enter the URL where this ComfyUI Agent will be accessible." "http://localhost:7860" "" "http://your-agent:7860")
    AGENT_PASSWORD=$(get_input "Create a password to secure your ComfyUI Agent." "" "true" "Enter a secure password")

    # Save agent configuration
    write_env "AGENT_URL" "$AGENT_URL"
    echo "$AGENT_PASSWORD"
    write_env "AGENT_PASSWORD" "$AGENT_PASSWORD"
    # Configure server and register agent (will retry on failure)
    configure_server_and_register "$SELECTED_MODEL_IDS" "$AGENT_URL" "$AGENT_PASSWORD"

    # Start the ComfyUI Agent
    docker compose up -d

    style_header "✓ Successfully registered ComfyUI Agent with AI Server"
}

# Run the prerequisites check function
check_prerequisites

# Run the installation function
install_gum

# Run the ComfyUI Agent setup function
setup_agent_comfy