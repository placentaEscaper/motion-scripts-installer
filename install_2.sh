#!/usr/bin/env bash
#
# install.sh — installer for "projectifier" (https://github.com/placentaEscaper/projectifier) on macOS
#
# What this does:
#   1. Checks that the OS is macOS.
#   2. Installs Homebrew if it's missing (asks for confirmation first).
#   3. Installs git and uv (Python package manager) via Homebrew.
#   4. Clones/updates the private repository (main branch only) into
#        ~/.local/bin/projectifier
#      (kept as a subfolder inside ~/.local/bin, right next to the `prj`
#      command itself, per user preference. NOTE: this is a different
#      location from ~/.config/projectifier, which the app itself already
#      uses at runtime to store configs.txt and the "Liven_Template folder" —
#      those two locations are intentionally kept separate so the code
#      checkout and the app's own runtime data never collide.)
#   5. Runs `uv sync` to install the exact Python version (3.14, per
#      .python-version / pyproject.toml) and dependencies from uv.lock.
#   6. Creates the `prj` command in ~/.local/bin and adds it to PATH.
#   7. Bakes a self-update check into `prj`: once a day it checks the latest
#      commit on the main branch and, if a newer one exists, pulls it and
#      re-syncs dependencies via uv before running main.py.
#   8. Copies the "Liven_Template" template project folder into
#        ~/.config/projectifier/
#      and unpacks tokens.zip into
#        ~/.local/bin/projectifier/env
#      Both Liven_Template/ and tokens.zip must sit next to this script
#      (i.e. in the same folder as install_2.sh) at install time.
#
# Re-running install.sh always force-updates to the latest commit on main.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_OWNER="placentaEscaper"
REPO_NAME="projectifier"
REPO="${REPO_OWNER}/${REPO_NAME}"
BRANCH="main"
ENTRY_POINT="main.py"
CMD_NAME="prj"
PYTHON_VERSION="3.14"

BIN_DIR="${HOME}/.local/bin"
CODE_DIR="${BIN_DIR}/${REPO_NAME}"                 # the actual git checkout lives here
CONFIG_DIR="${HOME}/.config/projectifier"
INSTALLER_META_DIR="${CONFIG_DIR}/.installer"  # installer's own bookkeeping files
# NOTE: the app itself (projectifier/filesystem.py) separately writes
# ~/.config/projectifier/configs.txt at runtime — that's unrelated to where
# we put the code, and is left alone.

CRED_FILE="${INSTALLER_META_DIR}/.credentials"
SHA_FILE="${INSTALLER_META_DIR}/.commit_sha"
LAST_CHECK_FILE="${INSTALLER_META_DIR}/.last_check"
UPDATE_INTERVAL_SECONDS=86400   # 24 hours

# SCRIPT_DIR is where install_2.sh itself lives — Liven_Template/ and
# tokens.zip are expected to sit right next to it at install time.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_NAME="Liven_Template"
TEMPLATE_SRC="${SCRIPT_DIR}/${TEMPLATE_NAME}"
TEMPLATE_DEST="${CONFIG_DIR}/${TEMPLATE_NAME}"
TOKENS_ZIP="${SCRIPT_DIR}/tokens.zip"
ENV_DIR="${CODE_DIR}/env"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\033[1;34m[info]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[ok]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[warn]\033[0m  $*"; }
err()   { echo -e "\033[1;31m[error]\033[0m $*" >&2; }

# ---------------------------------------------------------------------------
# 0. OS check
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This installer only supports macOS."
  exit 1
fi
info "Detected macOS ($(sw_vers -productVersion 2>/dev/null || echo unknown))."

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found."
  read -r -p "Install Homebrew now? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    err "Without Homebrew, git/uv can't be installed automatically. Install them manually and re-run this script."
    exit 1
  fi
else
  ok "Homebrew is already installed."
  eval "$(brew shellenv)" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2. git
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  info "Installing git via Homebrew..."
  brew install git
else
  ok "git is already installed ($(git --version))."
fi

# ---------------------------------------------------------------------------
# 3. uv (it will fetch the right Python version itself — no separate
#    `brew install python` needed)
# ---------------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  info "Installing uv via Homebrew..."
  brew install uv
else
  ok "uv is already installed ($(uv --version))."
fi

info "Ensuring Python ${PYTHON_VERSION} is available (uv will install it if needed)..."
uv python install "${PYTHON_VERSION}"

# ---------------------------------------------------------------------------
# 4. Directories
# ---------------------------------------------------------------------------
mkdir -p "${BIN_DIR}"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${INSTALLER_META_DIR}"

# ---------------------------------------------------------------------------
# 4b. Template project ("Liven_Template" folder -> ~/.config/projectifier/)
# ---------------------------------------------------------------------------
if [[ -d "${TEMPLATE_SRC}" ]]; then
  info "Copying ${TEMPLATE_NAME}/ into ${CONFIG_DIR}..."
  rm -rf "${TEMPLATE_DEST}"
  cp -R "${TEMPLATE_SRC}" "${TEMPLATE_DEST}"
  ok "Template project installed at ${TEMPLATE_DEST}"
else
  warn "No '${TEMPLATE_NAME}' folder found next to this script (${SCRIPT_DIR}) — skipping template copy."
fi

# ---------------------------------------------------------------------------
# 5. Fine-grained GitHub token (the repo is private)
# ---------------------------------------------------------------------------
GITHUB_TOKEN=""

if [[ -f "${CRED_FILE}" ]]; then
  GITHUB_TOKEN="$(cat "${CRED_FILE}")"
  ok "Found a saved GitHub access token."
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  :
else
  warn "Repository ${REPO} is private — a GitHub Fine-grained Personal Access Token is required."
  echo
  info "Create one here: https://github.com/settings/personal-access-tokens/new"
  info "  Resource owner:        ${REPO_OWNER}"
  info "  Repository access:     Only select repositories -> ${REPO}"
  info "  Permissions:            Repository permissions -> Contents: Read-only"
  echo
  read -r -s -p "Paste your token (github_pat_...): " GITHUB_TOKEN
  echo
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    err "No token entered. Can't clone a private repository without one."
    exit 1
  fi
  printf '%s' "${GITHUB_TOKEN}" > "${CRED_FILE}"
  chmod 600 "${CRED_FILE}"
  ok "Token saved to ${CRED_FILE} (permissions set to 600)."
fi

AUTH_REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO}.git"

info "Verifying repository access with this token..."
if ! git ls-remote "${AUTH_REPO_URL}" >/dev/null 2>&1; then
  err "Could not access ${REPO} with this token."
  err "Check that: (1) the token hasn't expired, (2) it grants access to this specific repo,"
  err "(3) the 'Contents: Read-only' permission is enabled."
  rm -f "${CRED_FILE}"
  exit 1
fi
ok "Access verified."

# ---------------------------------------------------------------------------
# 6. Clone / update the repository (main branch only)
# ---------------------------------------------------------------------------
if [[ -d "${CODE_DIR}/.git" ]]; then
  info "Updating existing checkout to the latest commit on ${BRANCH}..."
  git -C "${CODE_DIR}" remote set-url origin "${AUTH_REPO_URL}"
  git -C "${CODE_DIR}" fetch origin "${BRANCH}" --depth=1
  git -C "${CODE_DIR}" checkout "${BRANCH}"
  git -C "${CODE_DIR}" reset --hard "origin/${BRANCH}"
else
  info "Cloning repository (branch ${BRANCH}) into ${CODE_DIR}..."
  git clone --branch "${BRANCH}" --single-branch --depth=1 "${AUTH_REPO_URL}" "${CODE_DIR}"
fi

CURRENT_SHA="$(git -C "${CODE_DIR}" rev-parse HEAD)"
echo "${CURRENT_SHA}" > "${SHA_FILE}"
date +%s > "${LAST_CHECK_FILE}"
ok "Installed commit: ${CURRENT_SHA:0:7}"

# ---------------------------------------------------------------------------
# 7. Dependencies via uv (venv + resolution come from uv.lock, created
#    automatically inside CODE_DIR/.venv)
# ---------------------------------------------------------------------------
info "Installing dependencies via 'uv sync' (per pyproject.toml / uv.lock)..."
( cd "${CODE_DIR}" && uv sync )
ok "Dependencies installed."

# ---------------------------------------------------------------------------
# 7b. Tokens (tokens.zip -> ~/.local/bin/projectifier/env)
# ---------------------------------------------------------------------------
if [[ -f "${TOKENS_ZIP}" ]]; then
  if ! command -v unzip >/dev/null 2>&1; then
    warn "'unzip' not found — skipping token extraction. Install unzip and re-run, or unpack ${TOKENS_ZIP} into ${ENV_DIR} manually."
  else
    info "Unpacking tokens.zip into ${ENV_DIR}..."
    mkdir -p "${ENV_DIR}"
    unzip -o -q "${TOKENS_ZIP}" -d "${ENV_DIR}"
    chmod 700 "${ENV_DIR}"
    find "${ENV_DIR}" -type f -exec chmod 600 {} +
    ok "Tokens unpacked into ${ENV_DIR}"
  fi
else
  warn "No 'tokens.zip' found next to this script (${SCRIPT_DIR}) — skipping token extraction."
fi

# ---------------------------------------------------------------------------
# 8. Wrapper script `prj` with self-update
# ---------------------------------------------------------------------------
WRAPPER_PATH="${BIN_DIR}/${CMD_NAME}"

cat > "${WRAPPER_PATH}" <<WRAPPER_EOF
#!/usr/bin/env bash
#
# Auto-generated by install.sh for ${REPO}. Don't edit by hand —
# changes will be overwritten the next time install.sh runs.
set -euo pipefail

CODE_DIR="${CODE_DIR}"
BRANCH="${BRANCH}"
REPO="${REPO}"
ENTRY_POINT="${ENTRY_POINT}"
SHA_FILE="${SHA_FILE}"
LAST_CHECK_FILE="${LAST_CHECK_FILE}"
CRED_FILE="${CRED_FILE}"
UPDATE_INTERVAL_SECONDS=${UPDATE_INTERVAL_SECONDS}

self_update() {
  [[ -f "\${CRED_FILE}" ]] || return 0
  local token
  token="\$(cat "\${CRED_FILE}")"

  local remote_sha
  remote_sha="\$(curl -fsSL -H "Authorization: token \${token}" \\
    "https://api.github.com/repos/\${REPO}/commits/\${BRANCH}" 2>/dev/null \\
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("sha",""))' 2>/dev/null || true)"

  [[ -z "\${remote_sha}" ]] && return 0

  local local_sha
  local_sha="\$(cat "\${SHA_FILE}" 2>/dev/null || echo "")"

  if [[ "\${remote_sha}" != "\${local_sha}" ]]; then
    echo "[${CMD_NAME}] New version found (\${remote_sha:0:7}) — updating..." >&2
    git -C "\${CODE_DIR}" fetch origin "\${BRANCH}" --depth=1 --quiet
    git -C "\${CODE_DIR}" reset --hard "origin/\${BRANCH}" --quiet
    ( cd "\${CODE_DIR}" && uv sync --quiet )
    echo "\${remote_sha}" > "\${SHA_FILE}"
    echo "[${CMD_NAME}] Updated to \${remote_sha:0:7}." >&2
  fi
  date +%s > "\${LAST_CHECK_FILE}"
}

if [[ "\${1:-}" == "--update" ]]; then
  self_update
  shift
  [[ \$# -eq 0 ]] && exit 0
fi

now="\$(date +%s)"
last_check="\$(cat "\${LAST_CHECK_FILE}" 2>/dev/null || echo 0)"
if (( now - last_check >= UPDATE_INTERVAL_SECONDS )); then
  self_update || true
fi

# IMPORTANT: cd into CODE_DIR is required because main.py reads "env/.env"
# and "env/credentials.json" as paths relative to the current working directory.
cd "\${CODE_DIR}"
exec uv run "\${ENTRY_POINT}" "\$@"
WRAPPER_EOF

chmod +x "${WRAPPER_PATH}"
ok "Created the ${CMD_NAME} command at ${WRAPPER_PATH}"

# ---------------------------------------------------------------------------
# 9. Add BIN_DIR to PATH (for both zsh and bash)
# ---------------------------------------------------------------------------
add_path_line='export PATH="$HOME/.local/bin:$PATH"'

update_rc_file() {
  local rc_file="$1"
  if [[ -f "${rc_file}" ]] && grep -qF "${add_path_line}" "${rc_file}" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# Added by the ${CMD_NAME} installer ($(date))"
    echo "${add_path_line}"
  } >> "${rc_file}"
  ok "PATH updated in ${rc_file}"
}

case "${SHELL:-}" in
  */zsh)  update_rc_file "${HOME}/.zshrc" ;;
  */bash) update_rc_file "${HOME}/.bash_profile" ;;
  *)
    update_rc_file "${HOME}/.zshrc"
    update_rc_file "${HOME}/.bash_profile"
    ;;
esac

# ---------------------------------------------------------------------------
# 10. Reminder about secrets that aren't part of the repo (they're gitignored)
# ---------------------------------------------------------------------------
echo
ok "Done! Installed ${REPO} (${BRANCH}@${CURRENT_SHA:0:7})."
info "Open a new terminal (or run 'source ~/.zshrc' / 'source ~/.bash_profile'),"
info "after which the '${CMD_NAME}' command will be available."
info "To force an update check manually: ${CMD_NAME} --update"
echo

if [[ ! -f "${ENV_DIR}/.env" ]]; then
  warn "${ENV_DIR}/.env is missing (it's gitignored, so it doesn't come with the repo,"
  warn "and no tokens.zip with it was found next to install_2.sh)."
  warn "Create it manually before the first run:"
  warn "  mkdir -p '${ENV_DIR}'"
  warn "  echo 'TOKEN=<your Airtable Personal Access Token>' > '${ENV_DIR}/.env'"
  warn "If you use the Google Drive download feature ('Related creative' field),"
  warn "you'll also need an OAuth client secret from Google Cloud Console at:"
  warn "  ${ENV_DIR}/credentials.json"
fi
