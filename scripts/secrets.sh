#!/usr/bin/env bash
# ==============================================================================
# SyncTogether Secrets Consolidation & Recovery Tool
# ------------------------------------------------------------------------------
# Consolidates all secret configuration and key files across the repository into
# a single, encrypted text bundle safe for Google Drive backup.
# Restores files into their exact paths with appropriate file permissions.
#
# Usage:
#   ./scripts/secrets.sh pack [output-file] [--yes]
#   ./scripts/secrets.sh unpack [bundle-file] [--force]
#   ./scripts/secrets.sh list [bundle-file]
#   ./scripts/secrets.sh help
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_BUNDLE_NAME="synctogether-secrets-bundle.txt"
DEFAULT_BUNDLE_PATH="$REPO_ROOT/$DEFAULT_BUNDLE_NAME"

CLEANUP_PATHS=()
cleanup() {
  if [ ${#CLEANUP_PATHS[@]} -gt 0 ]; then
    for p in "${CLEANUP_PATHS[@]}"; do
      if [ -n "$p" ] && [ -e "$p" ]; then
        rm -rf "$p"
      fi
    done
  fi
}
trap cleanup EXIT

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}ℹ ${NC}$1" >&2; }
success() { echo -e "${GREEN}✔ ${NC}$1" >&2; }
warn() { echo -e "${YELLOW}⚠ ${NC}$1" >&2; }
error() { echo -e "${RED}✖ ${NC}$1" >&2; }
banner() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n" >&2; }

# ------------------------------------------------------------------------------
# Help
# ------------------------------------------------------------------------------
show_help() {
  cat << 'EOF'
SyncTogether Secrets Consolidation & Recovery Tool

Consolidates all secret files across the repository into a single .txt bundle
suitable for backup on Google Drive or cold storage. When restoring on a new
or reset machine, restores each file to its exact relative directory.

USAGE:
  ./scripts/secrets.sh pack   [OUTPUT_FILE] [--yes]
  ./scripts/secrets.sh unpack [BUNDLE_FILE] [--force]
  ./scripts/secrets.sh list   [BUNDLE_FILE]
  ./scripts/secrets.sh help

COMMANDS:
  pack [FILE]     Scan repo for secrets, compress, encrypt, and output a .txt bundle.
                  Defaults to: ./synctogether-secrets-bundle.txt
                  Options:
                    --yes, -y  Skip interactive confirmation

  unpack [FILE]   Decrypt and unpack a .txt bundle, placing every secret in its
                  proper repository location. Creates timestamped .bak backups
                  if local files already exist.
                  Defaults to: ./synctogether-secrets-bundle.txt
                  Options:
                    --force, -f Overwrite without interactive prompt

  list [FILE]     Inspect the files contained inside a bundle without extracting them.
                  Defaults to: ./synctogether-secrets-bundle.txt

  help, -h        Show this documentation.

ENVIRONMENT VARIABLES:
  SECRETS_PASSPHRASE  Optional. Passphrase for encryption/decryption. If unset,
                      the script will prompt securely on standard input.
EOF
}

# ------------------------------------------------------------------------------
# Discovery: Find all secret files in the repository
# ------------------------------------------------------------------------------
discover_secret_files() {
  cd "$REPO_ROOT"

  local files=()

  # 1. Known static secret files
  local known_candidates=(
    ".env"
    "supabase/.env"
    "supabase/functions/.env"
    "website/.env.local"
    "website/.env"
    "website/.env.production.local"
    "dsa_priv.pem"
    "dsaparam.pem"
    "sparkle_ed_private_key"
    "android/key.properties"
  )

  for candidate in "${known_candidates[@]}"; do
    if [ -f "$REPO_ROOT/$candidate" ]; then
      files+=("$candidate")
    fi
  done

  # 2. Dynamic discovery: search for other secret files, ignoring build / node / fvm dirs
  while IFS= read -r f; do
    # Strip leading ./
    local clean_path="${f#./}"
    # Ensure not already in files array
    local already_present=false
    for existing in "${files[@]}"; do
      if [ "$existing" = "$clean_path" ]; then
        already_present=true
        break
      fi
    done
    if [ "$already_present" = false ]; then
      files+=("$clean_path")
    fi
  done < <(find . -type f \
    ! -path "./.git/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/.dart_tool/*" \
    ! -path "*/build/*" \
    ! -path "*/.fvm/*" \
    ! -path "*/Pods/*" \
    ! -path "*/ephemeral/*" \
    ! -path "*/.temp/*" \
    ! -path "*/coverage/*" \
    \( \
      -name "*.keystore" -o \
      -name "*.jks" -o \
      -name "*.p12" -o \
      -name "*.p8" -o \
      -name "*.pfx" -o \
      \( -name ".env*" ! -name "*.example*" ! -name "*.example" ! -name "*.bak*" \) \
    \) 2>/dev/null || true)

  # Echo array elements separated by newlines
  if [ ${#files[@]} -gt 0 ]; then
    for f in "${files[@]}"; do
      echo "$f"
    done
  fi
}

# ------------------------------------------------------------------------------
# Helper: Prompt for Passphrase
# ------------------------------------------------------------------------------
prompt_passphrase() {
  local prompt_label="$1"
  local pass=""
  if [ -t 0 ]; then
    # Interactive TTY
    read -r -s -p "$prompt_label: " pass
    echo "" >&2
  else
    # Non-interactive pipe / stdin
    read -r pass
  fi
  echo "$pass"
}

# ------------------------------------------------------------------------------
# Action: Pack
# ------------------------------------------------------------------------------
action_pack() {
  local out_file="$DEFAULT_BUNDLE_PATH"
  local skip_confirm=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --yes|-y)
        skip_confirm=true
        shift
        ;;
      -*)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
      *)
        out_file="$1"
        shift
        ;;
    esac
  done

  banner "Packing SyncTogether Secrets"

  info "Scanning repository for secret files..."
  local secret_files=()
  while IFS= read -r line; do
    [ -n "$line" ] && secret_files+=("$line")
  done < <(discover_secret_files)

  if [ ${#secret_files[@]} -eq 0 ]; then
    error "No secret files found in repository!"
    exit 1
  fi

  echo -e "\n${BOLD}Discovered Secret Files (${#secret_files[@]}):${NC}"
  for sf in "${secret_files[@]}"; do
    local f_size
    f_size=$(du -h "$REPO_ROOT/$sf" | cut -f1 | tr -d ' ')
    echo -e "  - ${CYAN}$sf${NC} ($f_size)"
  done
  echo ""

  if [ "$skip_confirm" = false ] && [ -t 0 ]; then
    read -r -p "Proceed with bundling into '$out_file'? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      info "Packing aborted by user."
      exit 0
    fi
  fi

  local passphrase=""
  if [ -n "${SECRETS_PASSPHRASE:-}" ]; then
    passphrase="$SECRETS_PASSPHRASE"
    info "Using passphrase from SECRETS_PASSPHRASE environment variable."
  else
    echo -e "${YELLOW}Please choose a strong passphrase to encrypt this bundle.${NC}"
    echo -e "You will need this same passphrase when restoring on another system."
    while true; do
      passphrase=$(prompt_passphrase "Enter encryption passphrase")
      if [ -z "$passphrase" ]; then
        error "Passphrase cannot be empty. Please try again."
        continue
      fi
      local confirm_pass
      confirm_pass=$(prompt_passphrase "Confirm encryption passphrase")
      if [ "$passphrase" != "$confirm_pass" ]; then
        error "Passphrases do not match. Please try again."
        continue
      fi
      break
    done
  fi

  info "Archiving and encoding files..."
  local stage_dir
  stage_dir=$(mktemp -d)
  CLEANUP_PATHS+=("$stage_dir")

  local tar_file="$stage_dir/secrets.tar.gz"
  cd "$REPO_ROOT"
  tar -czf "$tar_file" "${secret_files[@]}"

  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Create header comments
  {
    echo "# =============================================================================="
    echo "# SyncTogether Secrets Bundle (ENCRYPTED with AES-256-CBC & PBKDF2)"
    echo "# Generated: $now_iso"
    echo "# Total Files: ${#secret_files[@]}"
    echo "# ------------------------------------------------------------------------------"
    echo "# To restore these files on any system (e.g. after fresh git clone):"
    echo "#   ./scripts/secrets.sh unpack $(basename "$out_file")"
    echo "#"
    echo "# To inspect contents without extracting:"
    echo "#   ./scripts/secrets.sh list $(basename "$out_file")"
    echo "#"
    echo "# DO NOT COMMIT THIS FILE TO VERSION CONTROL."
    echo "# =============================================================================="
    echo "-----BEGIN SYNCTOGETHER ENCRYPTED SECRETS-----"
  } > "$out_file"

  openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass pass:"$passphrase" -in "$tar_file" | openssl enc -base64 >> "$out_file"
  echo "-----END SYNCTOGETHER ENCRYPTED SECRETS-----" >> "$out_file"

  chmod 600 "$out_file"
  local bundle_size
  bundle_size=$(du -h "$out_file" | cut -f1 | tr -d ' ')

  success "Secrets bundle created successfully!"
  echo -e "\n  File: ${BOLD}$out_file${NC} ($bundle_size)"
  echo -e "  Mode: ${GREEN}ENCRYPTED (AES-256-CBC)${NC}"
  echo ""
  info "Next Steps:"
  echo "  1. Upload '$out_file' to your private Google Drive folder."
  echo "  2. When setting up a new/reset machine, clone the repo, download this file, and run:"
  echo "     ./scripts/secrets.sh unpack $(basename "$out_file")"
}

# ------------------------------------------------------------------------------
# Helper: Extract archive from bundle into temporary directory
# ------------------------------------------------------------------------------
extract_to_temp() {
  local bundle_file="$1"
  local dest_dir="$2"

  if [ ! -f "$bundle_file" ]; then
    error "Secrets bundle file not found: $bundle_file"
    exit 1
  fi

  # Detect format
  if ! grep -q "BEGIN SYNCTOGETHER ENCRYPTED SECRETS" "$bundle_file"; then
    error "Invalid secrets bundle: missing encrypted SyncTogether header markers."
    exit 1
  fi

  # Extract base64 payload lines
  local base64_payload
  base64_payload=$(sed -n '/^-----BEGIN SYNCTOGETHER ENCRYPTED SECRETS/,/^-----END SYNCTOGETHER ENCRYPTED SECRETS/ { /^-----/d; p; }' "$bundle_file")

  if [ -z "$base64_payload" ]; then
    error "Secrets bundle payload is empty."
    exit 1
  fi

  local tar_file="$dest_dir/extracted.tar.gz"

  local passphrase=""
  if [ -n "${SECRETS_PASSPHRASE:-}" ]; then
    passphrase="$SECRETS_PASSPHRASE"
    info "Using passphrase from SECRETS_PASSPHRASE environment variable."
  else
    passphrase=$(prompt_passphrase "Enter decryption passphrase")
    if [ -z "$passphrase" ]; then
      error "Passphrase cannot be empty."
      exit 1
    fi
  fi

  info "Decrypting secrets bundle (AES-256-CBC)..."
  if ! echo "$base64_payload" | openssl enc -base64 -d | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:"$passphrase" > "$tar_file" 2>/dev/null; then
    error "Decryption failed! Incorrect passphrase or corrupted bundle."
    exit 1
  fi

  # Validate tar archive integrity
  if ! tar -tzf "$tar_file" >/dev/null 2>&1; then
    error "Archive integrity check failed. The payload is corrupted or the passphrase was incorrect."
    exit 1
  fi

  # Extract tar into dest_dir/unpacked
  local unpack_dir="$dest_dir/unpacked"
  mkdir -p "$unpack_dir"
  tar -xzf "$tar_file" -C "$unpack_dir"
  echo "$unpack_dir"
}

# ------------------------------------------------------------------------------
# Action: List
# ------------------------------------------------------------------------------
action_list() {
  local bundle_file="${1:-$DEFAULT_BUNDLE_PATH}"

  banner "Inspect Secrets Bundle"

  local temp_dir
  temp_dir=$(mktemp -d)
  CLEANUP_PATHS+=("$temp_dir")

  local unpack_dir
  unpack_dir=$(extract_to_temp "$bundle_file" "$temp_dir")

  echo -e "\n${BOLD}Contents of $(basename "$bundle_file"):${NC}\n"
  printf "  %-40s %10s\n" "FILE" "SIZE"
  printf "  %-40s %10s\n" "----------------------------------------" "----------"

  (
    cd "$unpack_dir"
    find . -type f | while IFS= read -r f; do
      local rel_path="${f#./}"
      local size
      size=$(du -h "$f" | cut -f1 | tr -d ' ')
      printf "  %-40s %10s\n" "$rel_path" "$size"
    done
  )
  echo ""
  success "Inspection complete. No local files were modified."
}

# ------------------------------------------------------------------------------
# Action: Unpack / Restore
# ------------------------------------------------------------------------------
action_unpack() {
  local bundle_file="$DEFAULT_BUNDLE_PATH"
  local force=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f)
        force=true
        shift
        ;;
      -*)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
      *)
        bundle_file="$1"
        shift
        ;;
    esac
  done

  banner "Restoring SyncTogether Secrets"

  local temp_dir
  temp_dir=$(mktemp -d)
  CLEANUP_PATHS+=("$temp_dir")

  local unpack_dir
  unpack_dir=$(extract_to_temp "$bundle_file" "$temp_dir")

  info "Checking files to restore into repository..."
  local files_to_restore=()
  cd "$unpack_dir"
  while IFS= read -r f; do
    files_to_restore+=("${f#./}")
  done < <(find . -type f)

  if [ ${#files_to_restore[@]} -eq 0 ]; then
    error "No files found in unpacked archive."
    exit 1
  fi

  echo -e "\n${BOLD}Files to Restore (${#files_to_restore[@]}):${NC}"
  local existing_conflicts=0
  for f in "${files_to_restore[@]}"; do
    local target="$REPO_ROOT/$f"
    if [ -f "$target" ]; then
      if cmp -s "$unpack_dir/$f" "$target"; then
        echo -e "  - ${CYAN}$f${NC} (identical to existing file)"
      else
        echo -e "  - ${YELLOW}$f${NC} (EXISTS LOCALLY - will backup to .bak before overwriting)"
        existing_conflicts=$((existing_conflicts + 1))
      fi
    else
      echo -e "  - ${GREEN}$f${NC} (NEW - will be created)"
    fi
  done
  echo ""

  if [ "$force" = false ] && [ -t 0 ]; then
    read -r -p "Restore these secrets into the repository? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      info "Restore aborted by user."
      exit 0
    fi
  fi

  local now_ts
  now_ts=$(date +"%Y%m%d%H%M%S")
  local restored_count=0
  local backup_count=0

  for f in "${files_to_restore[@]}"; do
    local src="$unpack_dir/$f"
    local dest="$REPO_ROOT/$f"
    local dest_dir
    dest_dir="$(dirname "$dest")"

    mkdir -p "$dest_dir"

    if [ -f "$dest" ]; then
      if ! cmp -s "$src" "$dest"; then
        local bak_path="${dest}.bak.${now_ts}"
        cp "$dest" "$bak_path"
        info "Backed up existing '$f' -> '$(basename "$bak_path")'"
        backup_count=$((backup_count + 1))
      fi
    fi

    cp "$src" "$dest"
    # Ensure sensitive private keys & env files have restricted permissions
    chmod 600 "$dest" 2>/dev/null || true
    restored_count=$((restored_count + 1))
  done

  success "All $restored_count secret files restored successfully!"
  if [ $backup_count -gt 0 ]; then
    warn "$backup_count existing file(s) had different contents and were backed up as .bak.$now_ts."
  fi

  echo ""
  info "You can now run:"
  echo "  ./scripts/dev.sh status"
  echo "  ./scripts/dev.sh"
}

# ------------------------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------------------------
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  pack)
    action_pack "$@"
    ;;
  unpack|restore)
    action_unpack "$@"
    ;;
  list|ls)
    action_list "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    error "Unknown command: $COMMAND"
    show_help
    exit 1
    ;;
esac
