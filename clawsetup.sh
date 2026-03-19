#!/bin/bash

# Default values
DEFAULT_CONTEXT_WINDOW=128000
DEFAULT_MAX_TOKENS=16000

# Parse arguments
MODEL_ID=""
API_KEY=""
CONTEXT_WINDOW=$DEFAULT_CONTEXT_WINDOW
MAX_TOKENS=$DEFAULT_MAX_TOKENS

# Display usage
usage() {
    echo "Usage: $0 <model_id> <api_key> [context_window] [max_tokens]"
    echo "Example: $0 minimax/minimax-m2.1 sk-mykey123 128000 16000"
    echo ""
    echo "Arguments:"
    echo "  model_id         Model identifier (required, e.g., minimax/minimax-m2.1)"
    echo "  api_key          API key (required)"
    echo "  context_window   Context window size (optional, default: $DEFAULT_CONTEXT_WINDOW)"
    echo "  max_tokens       Max tokens (optional, default: $DEFAULT_MAX_TOKENS)"
    exit 0
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# Check if model_id is provided
if [ -z "$1" ]; then
    echo "Error: model_id is required"
    echo ""
    usage
fi

# Check if api_key is provided
if [ -z "$2" ]; then
    echo "Error: api_key is required"
    echo ""
    usage
fi

MODEL_ID="$1"
API_KEY="$2"
[ -n "$3" ] && CONTEXT_WINDOW="$3"
[ -n "$4" ] && MAX_TOKENS="$4"

# Install openclaw if not already installed
if ! command -v openclaw &> /dev/null; then
    echo "openclaw not found, installing..."

    OPENCLAW_REPO_DIR="$HOME/openclaw"

    # Only clone if directory doesn't exist
    if [ ! -d "$OPENCLAW_REPO_DIR" ]; then
        git clone https://github.com/openclaw/openclaw.git "$OPENCLAW_REPO_DIR"
    else
        echo "Repository directory already exists at $OPENCLAW_REPO_DIR, skipping clone."
    fi

    cd "$OPENCLAW_REPO_DIR" || { echo "Error: failed to enter $OPENCLAW_REPO_DIR"; exit 1; }

    pnpm install
    pnpm ui:build
    pnpm build
    pnpm link --global

    openclaw onboard --install-daemon --non-interactive --accept-risk || true

    cd - > /dev/null || exit 1
    echo "openclaw installed successfully!"
else
    echo "openclaw is already installed, skipping installation."
fi

CONFIG_FILE="$HOME/.openclaw/openclaw.json"

# Delete "agents", "commands", and "models" sections, then add them back with new config
jq --arg model_id "$MODEL_ID" \
   --arg model_key "llm/${MODEL_ID}" \
   --arg api_key "$API_KEY" \
   --argjson context_window "$CONTEXT_WINDOW" \
   --argjson max_tokens "$MAX_TOKENS" '
  # Delete the sections
  del(.agents, .commands, .models) |

  # Recreate agents section
  .agents = {
    "defaults": {
      "workspace": (env.HOME + "/.openclaw/workspace"),
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      },
      "model": {
        "primary": $model_key
      },
      "models": {
        ($model_key): {}
      }
    }
  } |

  # Recreate commands section
  .commands = {
    "native": "auto",
    "nativeSkills": "auto"
  } |

  # Recreate models section
  .models = {
    "mode": "merge",
    "providers": {
      "llm": {
        "baseUrl": "https://inference.asicloud.cudos.org/v1",
        "api": "openai-completions",
        "apiKey": $api_key,
        "models": [
          {
            "id": $model_id,
            "name": ($model_id + " (Custom Provider)"),
            "contextWindow": $context_window,
            "maxTokens": $max_tokens,
            "input": ["text"],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "reasoning": false
          }
        ]
      }
    }
  }
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"

# Replace the original file
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo "Model: $MODEL_ID"
echo "Context Window: $CONTEXT_WINDOW"
echo "Max Tokens: $MAX_TOKENS"

echo "Starting openclaw dashboard..."
openclaw dashboard
