#!/usr/bin/env bash
set -euo pipefail

MARKETPLACE_SOURCE="${FLEXCOMPUTE_MARKETPLACE_SOURCE:-flexcompute/plugin-marketplace}"
MARKETPLACE_NAME="flexcompute"

CLIENT_MODE="prompt"
INSTALL_UV=0
SELECTED_PLUGINS=(tidy3d photonforge)

usage() {
  cat <<'EOF'
Flexcompute agentic coding bootstrap

Usage:
  install.sh [options]

Options:
  --plugin all|tidy3d|photonforge  Plugin set to install. Defaults to all.
  --client prompt|auto|codex|claude|copilot|none
                                   Client to configure. Defaults to prompt.
  --install-uv                     Install uv without prompting if uvx is missing.
  -h, --help                       Show this help.

Examples:
  curl -LsSf https://raw.githubusercontent.com/flexcompute/plugin-marketplace/main/install.sh | bash
  curl -LsSf https://raw.githubusercontent.com/flexcompute/plugin-marketplace/main/install.sh | bash -s -- --install-uv
  bash install.sh --client codex --plugin tidy3d
EOF
}

section() {
  printf '\n==> %s\n' "$*"
}

ok() {
  printf 'OK: %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

run_or_print() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  env NO_COLOR=1 "$@"
}

capture_no_color() {
  env NO_COLOR=1 "$@"
}

confirm_yes_no() {
  local prompt="$1"
  local answer
  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    return 2
  fi

  while true; do
    printf '%s [Y/n] ' "$prompt" > /dev/tty
    IFS= read -r answer < /dev/tty || return 2
    case "$answer" in
      ''|[Yy]|[Yy][Ee][Ss])
        return 0
        ;;
      [Nn]|[Nn][Oo])
        return 1
        ;;
      *)
        printf 'Please answer y or n.\n' > /dev/tty
        ;;
    esac
  done
}

set_plugin_selection() {
  case "$1" in
    all)
      SELECTED_PLUGINS=(tidy3d photonforge)
      ;;
    tidy3d|photonforge)
      SELECTED_PLUGINS=("$1")
      ;;
    *)
      die "unknown plugin selection '$1'; expected all, tidy3d, or photonforge"
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plugin)
        [[ $# -ge 2 ]] || die "--plugin requires a value"
        set_plugin_selection "$2"
        shift 2
        ;;
      --client)
        [[ $# -ge 2 ]] || die "--client requires a value"
        case "$2" in
          prompt|auto|codex|claude|copilot|none)
            CLIENT_MODE="$2"
            ;;
          *)
            die "unknown client '$2'; expected prompt, auto, codex, claude, copilot, or none"
            ;;
        esac
        shift 2
        ;;
      --install-uv)
        INSTALL_UV=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option '$1'"
        ;;
    esac
  done
}

install_uv() {
  section "Installing uv"
  cat <<'EOF'
uv provides uvx, which runs tidy3d-mcp in an isolated Python environment.
This step uses Astral's official standalone installer from:

  https://astral.sh/uv/install.sh
EOF

  if command -v curl >/dev/null 2>&1; then
    # Intentionally follow Astral's official installer rather than pinning a copy here.
    curl -LsSf https://astral.sh/uv/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    # Intentionally follow Astral's official installer rather than pinning a copy here.
    wget -qO- https://astral.sh/uv/install.sh | sh
  else
    die "uvx is missing and neither curl nor wget is available to run the official uv installer"
  fi

  if [[ -n "${UV_INSTALL_DIR:-}" ]]; then
    export PATH="$UV_INSTALL_DIR:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  else
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi
  hash -r
}

explain_uv_needed() {
  cat <<'EOF'
uvx is not on PATH yet.

Flexcompute uses uvx to start tidy3d-mcp without adding Python packages to
your simulation project. tidy3d-mcp is the local MCP server that gives your AI
coding tool Flexcompute documentation search and fetch tools.
EOF
}

ensure_uvx() {
  section "Checking uvx"
  if command -v uvx >/dev/null 2>&1; then
    ok "uvx found at $(command -v uvx)"
    return
  fi

  explain_uv_needed

  if [[ "$INSTALL_UV" -eq 1 ]]; then
    install_uv
    command -v uvx >/dev/null 2>&1 || die "uv installer completed, but uvx is still not on PATH"
    ok "uvx found at $(command -v uvx)"
    return
  fi

  local install_answer
  if confirm_yes_no "Install uv now with Astral's official installer?"; then
    install_answer=0
  else
    install_answer=$?
  fi
  case "$install_answer" in
    0)
      install_uv
      command -v uvx >/dev/null 2>&1 || die "uv installer completed, but uvx is still not on PATH"
      ok "uvx found at $(command -v uvx)"
      return
      ;;
    1)
      cat <<'EOF'
No problem. Install uv later, then rerun this bootstrap:

  curl -LsSf https://astral.sh/uv/install.sh | sh
EOF
      exit 2
      ;;
    2)
      cat <<'EOF' >&2
This terminal is non-interactive, so the installer cannot ask before installing uv.

Run one of these commands instead:

  curl -LsSf https://astral.sh/uv/install.sh | sh
  curl -LsSf https://raw.githubusercontent.com/flexcompute/plugin-marketplace/main/install.sh | bash -s -- --install-uv
EOF
      exit 2
      ;;
  esac
}

print_intro() {
  section "Flexcompute plugin setup"
  cat <<'EOF'
This installs Tidy3D and PhotonForge for your AI coding tool.
If uvx is missing, you will be asked before uv is installed.
EOF

  printf 'Plugins: %s\n' "${SELECTED_PLUGINS[*]}"
}

select_client_mode() {
  if [[ "$CLIENT_MODE" != "prompt" ]]; then
    return 0
  fi

  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    die "no interactive terminal available; pass --client auto, --client codex, --client claude, --client copilot, or --client none"
  fi

  section "Choose your AI coding tool"
  local choice
  local PS3="Install for: "
  select choice in \
    "Auto-detect installed tools" \
    "Codex" \
    "Claude Code" \
    "GitHub Copilot CLI" \
    "Skip client setup"; do
    case "$REPLY" in
      1)
        CLIENT_MODE="auto"
        break
        ;;
      2)
        CLIENT_MODE="codex"
        break
        ;;
      3)
        CLIENT_MODE="claude"
        break
        ;;
      4)
        CLIENT_MODE="copilot"
        break
        ;;
      5)
        CLIENT_MODE="none"
        break
        ;;
      *)
        printf 'Please enter 1, 2, 3, 4, or 5.\n' > /dev/tty
        ;;
    esac
  done < /dev/tty
  if [[ "$CLIENT_MODE" == "prompt" ]]; then
    die "no selection made; pass --client auto, --client codex, --client claude, --client copilot, or --client none"
  fi
  ok "selected ${choice}"
}

check_mcp() {
  section "Checking tidy3d-mcp"
  if help_output="$(capture_no_color uvx tidy3d-mcp --help 2>&1)"; then
    ok "tidy3d-mcp CLI starts through uvx"
    return
  fi

  printf '%s\n' "$help_output" >&2
  die "tidy3d-mcp did not start through uvx"
}

client_marketplace_installed() {
  local client="$1"
  local marketplaces
  marketplaces="$(capture_no_color "$client" plugin marketplace list 2>/dev/null)" || return 1
  grep -Eq "(^|[[:space:]])${MARKETPLACE_NAME}($|[[:space:]])" <<<"$marketplaces"
}

client_plugin_state() {
  local client="$1"
  local plugin="$2"
  local selector="${plugin}@${MARKETPLACE_NAME}"

  case "$client" in
    codex)
      local plugin_list
      plugin_list="$(capture_no_color codex plugin list 2>/dev/null)" || {
        printf 'missing\n'
        return 0
      }
      local line
      line="$(awk -v id="$selector" '$1 == id { print; exit }' <<<"$plugin_list")"
      local status
      status="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"${line#"$selector"}")"
      local enabled_pattern='^\(installed,[[:space:]]*enabled\)$|^installed,[[:space:]]*enabled($|[[:space:]])'
      local installed_pattern='^\(installed([,)[:space:]]|$)|^installed([,[:space:]]|$)'
      if [[ "$status" =~ $enabled_pattern ]]; then
        printf 'enabled\n'
      elif [[ "$status" =~ $installed_pattern ]]; then
        printf 'installed\n'
      else
        printf 'missing\n'
      fi
      ;;
    claude)
      if ! command -v node >/dev/null 2>&1; then
        printf 'unknown\n'
        return 0
      fi
      local plugins_json
      plugins_json="$(capture_no_color claude plugin list --json 2>/dev/null)" || {
        printf 'missing\n'
        return 0
      }
      CLAUDE_PLUGIN_ID="$selector" node -e '
        const fs = require("fs");
        let plugins;
        try {
          plugins = JSON.parse(fs.readFileSync(0, "utf8"));
        } catch {
          process.exit(1);
        }
        const plugin = plugins.find((candidate) => candidate.id === process.env.CLAUDE_PLUGIN_ID);
        if (!plugin) {
          console.log("missing");
        } else if (plugin.enabled === true) {
          console.log("enabled");
        } else {
          console.log("installed");
        }
      ' <<<"$plugins_json" || printf 'missing\n'
      ;;
    copilot)
      local plugin_list
      plugin_list="$(capture_no_color copilot plugin list 2>/dev/null)" || {
        printf 'missing\n'
        return 0
      }
      if grep -Eq "(^|[[:space:]])${selector}([[:space:]]|\(|$)" <<<"$plugin_list"; then
        printf 'installed\n'
      else
        printf 'missing\n'
      fi
      ;;
    *)
      die "unknown client '$client'"
      ;;
  esac
}

install_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    [[ "$CLIENT_MODE" == "codex" ]] && die "Codex CLI not found; install Codex or choose --client auto"
    return 0
  fi

  section "Configuring Codex"

  if client_marketplace_installed codex; then
    ok "Codex marketplace '${MARKETPLACE_NAME}' is already configured"
  else
    run_or_print codex plugin marketplace add "$MARKETPLACE_SOURCE"
  fi

  for plugin in "${SELECTED_PLUGINS[@]}"; do
    case "$(client_plugin_state codex "$plugin")" in
      enabled)
        ok "Codex plugin ${plugin}@${MARKETPLACE_NAME} is already installed and enabled"
        continue
        ;;
      installed)
        die "Codex plugin ${plugin}@${MARKETPLACE_NAME} is installed but not enabled. Codex does not expose an enable command; remove and re-add this plugin manually, then rerun this installer."
        ;;
      missing)
        ;;
      *)
        die "could not determine Codex plugin state for ${plugin}@${MARKETPLACE_NAME}"
        ;;
    esac

    run_or_print codex plugin add "${plugin}@${MARKETPLACE_NAME}"
  done
}

install_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    [[ "$CLIENT_MODE" == "claude" ]] && die "Claude Code CLI not found; install Claude Code or choose --client auto"
    return 0
  fi
  section "Configuring Claude Code"

  if client_marketplace_installed claude; then
    ok "Claude marketplace '${MARKETPLACE_NAME}' is already configured"
  else
    run_or_print claude plugin marketplace add "$MARKETPLACE_SOURCE"
  fi

  if ! command -v node >/dev/null 2>&1; then
    warn "node is not available to inspect Claude plugin state; installing selected Claude plugins without a state precheck"
    for plugin in "${SELECTED_PLUGINS[@]}"; do
      run_or_print claude plugin install "${plugin}@${MARKETPLACE_NAME}"
    done
    return 0
  fi

  for plugin in "${SELECTED_PLUGINS[@]}"; do
    case "$(client_plugin_state claude "$plugin")" in
      enabled)
        ok "Claude plugin ${plugin}@${MARKETPLACE_NAME} is already installed and enabled"
        ;;
      installed)
        warn "Claude plugin ${plugin}@${MARKETPLACE_NAME} is installed but disabled; enabling"
        run_or_print claude plugin enable "${plugin}@${MARKETPLACE_NAME}"
        ;;
      missing)
        run_or_print claude plugin install "${plugin}@${MARKETPLACE_NAME}"
        ;;
      *)
        die "could not determine Claude plugin state for ${plugin}@${MARKETPLACE_NAME}"
        ;;
    esac
  done
}

install_copilot() {
  if ! command -v copilot >/dev/null 2>&1; then
    [[ "$CLIENT_MODE" == "copilot" ]] && die "GitHub Copilot CLI not found; install GitHub Copilot CLI or choose --client auto"
    return 0
  fi

  section "Configuring GitHub Copilot CLI"

  if client_marketplace_installed copilot; then
    ok "Copilot marketplace '${MARKETPLACE_NAME}' is already configured"
  else
    run_or_print copilot plugin marketplace add "$MARKETPLACE_SOURCE"
  fi

  for plugin in "${SELECTED_PLUGINS[@]}"; do
    case "$(client_plugin_state copilot "$plugin")" in
      installed|enabled)
        ok "Copilot plugin ${plugin}@${MARKETPLACE_NAME} is already installed"
        ;;
      missing)
        run_or_print copilot plugin install "${plugin}@${MARKETPLACE_NAME}"
        ;;
      *)
        die "could not determine Copilot plugin state for ${plugin}@${MARKETPLACE_NAME}"
        ;;
    esac
  done
}

configure_clients() {
  section "Configuring AI coding tools"
  case "$CLIENT_MODE" in
    none)
      ok "client installation skipped"
      ;;
    codex)
      install_codex
      ;;
    claude)
      install_claude
      ;;
    copilot)
      install_copilot
      ;;
    auto)
      install_codex
      install_claude
      install_copilot
      ;;
  esac
}

print_reload_guidance() {
  section "Restart or reload"
  cat <<'EOF'
Restart your AI coding tool after installation so it reloads plugin and MCP configuration.

Claude Code can also reload in-session with:

  /reload-plugins

Codex users can run /plugins in a new session to confirm the installed plugins.
EOF
}

main() {
  parse_args "$@"

  print_intro

  ensure_uvx
  check_mcp
  select_client_mode
  configure_clients
  print_reload_guidance

  section "Complete"
  ok "Flexcompute bootstrap finished"
}

main "$@"
