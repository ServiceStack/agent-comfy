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
    # Add styled header for model selection
    gum style \
        --foreground="#00FFFF" \
        --border-foreground="#00FFFF" \
        --border double \
        --align center \
        --width 50 \
        "ComfyUI Model Selection"

    gum style \
        --foreground="#CCCCCC" \
        "Select which functionality you would like to support:"

    gum style \
        --foreground="#888888" \
        --italic \
        "Use space to select, enter to confirm"

    # Define model options with their IDs
    declare -A MODEL_OPTIONS=(
        ["Text & Image to Image (SDXL)"]="sdxl-lightning,jib-mix-realistic"
        ["Text to Image (Flux.Schnell)"]="flux-schnell"
        ["Image Upscale (RealESRGAN_x2)"]="image-upscale-2x"
        ["Speech to Text (Whisper)"]="speech-to-text"
        ["Text to Speech (Piper TTS)"]="text-to-speech"
        ["Image to Text (Florence2)"]="image-to-text"
    )

    # Convert options to array for gum choose
    OPTIONS=()
    for key in "${!MODEL_OPTIONS[@]}"; do
        OPTIONS+=("$key")
    done

    # Use gum choose with --no-limit flag for checkbox-like selection
    TEMP_FILE=$(mktemp)
    gum choose --no-limit --height 10 --cursor.foreground="#FFA500" "${OPTIONS[@]}" > "$TEMP_FILE"

    # Read selected options into an array, handling multi-line output correctly
    mapfile -t SELECTED_OPTIONS < "$TEMP_FILE"
    rm "$TEMP_FILE"

    # Process selected options
    SELECTED_MODEL_IDS=""
    NEEDS_CIVITAI=false

    echo "Selected options: ${SELECTED_OPTIONS[@]}"

    # Check if any options were selected
    if [ ${#SELECTED_OPTIONS[@]} -eq 0 ] || [ -z "${SELECTED_OPTIONS[0]}" ]; then
        echo "No functionality selected. Exiting setup."
        exit 1
    fi

    for option in "${SELECTED_OPTIONS[@]}"; do
        # Trim any whitespace from the option
        option=$(echo "$option" | xargs)

        if [ -n "$SELECTED_MODEL_IDS" ]; then
            SELECTED_MODEL_IDS="${SELECTED_MODEL_IDS},"
        fi
        SELECTED_MODEL_IDS="${SELECTED_MODEL_IDS}${MODEL_OPTIONS[$option]}"

        # Check if SDXL was selected
        if [ "$option" = "Text & Image to Image (SDXL)" ]; then
            NEEDS_CIVITAI=true
        fi
    done

    # If no options were selected, exit
    if [ -z "$SELECTED_MODEL_IDS" ]; then
        echo "No functionality selected. Exiting setup."
        exit 1
    fi

    # Ask for CivitAI token if SDXL was selected
    if [ "$NEEDS_CIVITAI" = true ]; then
        CIVITAI_TOKEN=$(gum input --password --placeholder "Enter your CivitAI token for downloading models")
        if [ -n "$CIVITAI_TOKEN" ]; then
            echo "CIVITAI_TOKEN=$CIVITAI_TOKEN" >> .env
        fi
    fi

    # Save selected model IDs to .env file
    echo "DEFAULT_MODELS=$SELECTED_MODEL_IDS" >> .env

    echo "Note: Selected models will be downloaded on first run. This can take a while depending on your internet connection."

    # Get AI Server URL with better prompting
    DEFAULT_SERVER_URL=${AI_SERVER_URL:-"http://localhost:5006"}
    echo "Configure AI Server Connection"
    gum style \
        --foreground="#00FFFF" \
        --border-foreground="#00FFFF" \
        --border double \
        --align center \
        --width 50 \
        "AI Server Configuration"

    gum style \
        --foreground="#CCCCCC" \
        "Enter the URL where your AI Server is running."

    gum style --foreground="#888888" "Default: $DEFAULT_SERVER_URL"

    AI_SERVER_URL=$(gum input \
        --value "$DEFAULT_SERVER_URL" \
        --placeholder "http://your-server:5006" \
        --prompt "> " \
        --prompt.foreground="#00FFFF")

    # Get AI Server authentication with improved formatting
    DEFAULT_AUTH=${AI_SERVER_API_KEY:-$AI_SERVER_AUTH_SECRET}
    echo
    gum style \
        --foreground="#CCCCCC" \
        "Enter your AI Server authentication credentials."

    gum style \
        --foreground="#888888" \
        --italic \
        "Note: You can create an API key via the Admin UI if you don't have one"

    SERVER_AUTH=$(gum input \
        --password \
        --value "$DEFAULT_AUTH" \
        --placeholder "Enter API Key or Auth Secret" \
        --prompt "> " \
        --prompt.foreground="#00FFFF")

    # Get Agent URL with improved formatting
    echo
    gum style \
        --foreground="#00FFFF" \
        --border-foreground="#00FFFF" \
        --border double \
        --align center \
        --width 50 \
        "ComfyUI Agent Configuration"

    gum style \
        --foreground="#CCCCCC" \
        "Enter the URL where this ComfyUI Agent will be accessible."

    gum style \
        --foreground="#888888" \
        "Default: http://localhost:7860"

    AGENT_URL=$(gum input \
        --value "http://localhost:7860" \
        --placeholder "http://your-agent:7860" \
        --prompt "> " \
        --prompt.foreground="#00FFFF")

    # Get Agent password with improved formatting
    echo
    gum style \
        --foreground="#CCCCCC" \
        "Create a password to secure your ComfyUI Agent."

    AGENT_PASSWORD=$(gum input \
        --password \
        --placeholder "Enter a secure password" \
        --prompt "> " \
        --prompt.foreground="#00FFFF")

    # Fix the JSON array construction for the API call
    # Convert selected model IDs to a proper JSON array
    MODEL_IDS_ARRAY=()
    IFS=',' read -ra ADDR <<< "$SELECTED_MODEL_IDS"
    for model_id in "${ADDR[@]}"; do
        MODEL_IDS_ARRAY+=("\"$model_id\"")
    done
    MODELS_JSON=$(printf '%s,' "${MODEL_IDS_ARRAY[@]}" | sed 's/,$//')

    # Prepare the API request payload with properly formatted JSON
    JSON_PAYLOAD=$(cat <<EOF
{
    "name": "ComfyUI Agent",
    "apiKey": "$AGENT_PASSWORD",
    "apiBaseUrl": "$AGENT_URL",
    "models": [$MODELS_JSON],
    "mediaTypeId": "ComfyUI"
}
EOF
)

    # Make the API call to register the provider
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SERVER_AUTH" \
        -d "$JSON_PAYLOAD" \
        "$AI_SERVER_URL/api/CreateMediaProvider")

    # Check if the API call was successful
    if echo "$RESPONSE" | grep -q "error\|Error\|ERROR"; then
        echo "Error registering media provider with AI Server:"
        echo "$RESPONSE"
        exit 1
    else
        gum style \
            --foreground="#00FF00" \
            --border-foreground="#00FF00" \
            --border normal \
            --align center \
            --width 50 \
            "Successfully registered ComfyUI Agent with AI Server"
    fi

    # Save configuration to .env file
    {
        echo "AGENT_URL=$AGENT_URL"
        echo "AGENT_PASSWORD=$AGENT_PASSWORD"
    } >> .env
}

# Run the prerequisites check function
check_prerequisites

# Run the installation function
install_gum

# Run the ComfyUI Agent setup function
setup_agent_comfy