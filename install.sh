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

    # Server configuration
    style_header "AI Server Configuration"
    DEFAULT_SERVER_URL=${AI_SERVER_URL:-"http://localhost:5006"}
    AI_SERVER_URL=$(get_input "Enter the URL where your AI Server is running." "$DEFAULT_SERVER_URL" "" "http://your-server:5006")

    DEFAULT_AUTH=${AI_SERVER_API_KEY:-$AI_SERVER_AUTH_SECRET}
    SERVER_AUTH=$(get_input "Enter your AI Server authentication credentials." "$DEFAULT_AUTH" "true" "Enter API Key or Auth Secret")

    # Agent configuration
    style_header "ComfyUI Agent Configuration"
    AGENT_URL=$(get_input "Enter the URL where this ComfyUI Agent will be accessible." "http://localhost:7860" "" "http://your-agent:7860")
    AGENT_PASSWORD=$(get_input "Create a password to secure your ComfyUI Agent." "" "true" "Enter a secure password")

    # Prepare and send API request
    IFS=',' read -ra MODEL_IDS <<< "$SELECTED_MODEL_IDS"
    MODELS_JSON=$(printf '"%s",' "${MODEL_IDS[@]}" | sed 's/,$//')

    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SERVER_AUTH" \
        -d '{
            "name": "ComfyUI Agent",
            "apiKey": "'"$AGENT_PASSWORD"'",
            "apiBaseUrl": "'"$AGENT_URL"'",
            "models": ['"$MODELS_JSON"'],
            "mediaTypeId": "ComfyUI",
            "enabled": true
        }' \
        "$AI_SERVER_URL/api/CreateMediaProvider")

    # Check response and save configuration
    if echo "$RESPONSE" | grep -q "error\|Error\|ERROR"; then
        echo "Error registering media provider with AI Server:"
        echo "$RESPONSE"
        exit 1
    fi

    style_header "✓ Successfully registered ComfyUI Agent with AI Server"

    # Save agent configuration
    write_env "AGENT_URL" "$AGENT_URL"
    write_env "AGENT_PASSWORD" "$AGENT_PASSWORD"
}

# Run the prerequisites check function
check_prerequisites

# Run the installation function
install_gum

# Run the ComfyUI Agent setup function
setup_agent_comfy