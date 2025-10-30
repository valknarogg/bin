#!/usr/bin/env bash

#############################################################################
# GitHub Artifact Downloader
#
# Download and extract GitHub Actions artifacts with style
#
# Usage:
#   artifact_github_download.sh <REPO> [OPTIONS]
#
# Arguments:
#   REPO                GitHub repository (owner/repo)
#
# Options:
#   -n, --name NAME     Artifact name to download (preselect)
#   -o, --output DIR    Output directory (default: current directory)
#   -h, --help          Show this help message
#
# Examples:
#   artifact_github_download.sh valknarness/awesome
#   artifact_github_download.sh valknarness/awesome -n awesome-database-latest
#   artifact_github_download.sh valknarness/awesome -o ~/downloads
#############################################################################

set -euo pipefail

# ============================================================================
# Color Definitions
# ============================================================================

# Check if terminal supports colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    COLORS=$(tput colors 2>/dev/null || echo 0)
    if [[ $COLORS -ge 8 ]]; then
        # Standard colors
        RED=$(tput setaf 1)
        GREEN=$(tput setaf 2)
        YELLOW=$(tput setaf 3)
        BLUE=$(tput setaf 4)
        MAGENTA=$(tput setaf 5)
        CYAN=$(tput setaf 6)
        WHITE=$(tput setaf 7)

        # Bright colors
        BRIGHT_GREEN=$(tput setaf 10 2>/dev/null || tput setaf 2)
        BRIGHT_YELLOW=$(tput setaf 11 2>/dev/null || tput setaf 3)
        BRIGHT_BLUE=$(tput setaf 12 2>/dev/null || tput setaf 4)
        BRIGHT_MAGENTA=$(tput setaf 13 2>/dev/null || tput setaf 5)
        BRIGHT_CYAN=$(tput setaf 14 2>/dev/null || tput setaf 6)

        # Text formatting
        BOLD=$(tput bold)
        DIM=$(tput dim 2>/dev/null || echo "")
        RESET=$(tput sgr0)
    else
        RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE=""
        BRIGHT_GREEN="" BRIGHT_YELLOW="" BRIGHT_BLUE="" BRIGHT_MAGENTA="" BRIGHT_CYAN=""
        BOLD="" DIM="" RESET=""
    fi
else
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE=""
    BRIGHT_GREEN="" BRIGHT_YELLOW="" BRIGHT_BLUE="" BRIGHT_MAGENTA="" BRIGHT_CYAN=""
    BOLD="" DIM="" RESET=""
fi

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BRIGHT_BLUE}${BOLD}ℹ${RESET} ${CYAN}$*${RESET}" >&2
}

log_success() {
    echo -e "${BRIGHT_GREEN}${BOLD}✓${RESET} ${GREEN}$*${RESET}" >&2
}

log_warning() {
    echo -e "${BRIGHT_YELLOW}${BOLD}⚠${RESET} ${YELLOW}$*${RESET}" >&2
}

log_error() {
    echo -e "${RED}${BOLD}✗${RESET} ${RED}$*${RESET}" >&2
}

log_step() {
    echo -e "${BRIGHT_MAGENTA}${BOLD}▸${RESET} ${MAGENTA}$*${RESET}" >&2
}

log_header() {
    local text="$*"
    local length=${#text}
    local line=$(printf '═%.0s' $(seq 1 $length))
    echo "" >&2
    echo -e "${BRIGHT_CYAN}${BOLD}╔${line}╗${RESET}" >&2
    echo -e "${BRIGHT_CYAN}${BOLD}║${RESET}${BOLD}${WHITE}${text}${RESET}${BRIGHT_CYAN}${BOLD}║${RESET}" >&2
    echo -e "${BRIGHT_CYAN}${BOLD}╚${line}╝${RESET}" >&2
    echo "" >&2
}

log_data() {
    local label="$1"
    local value="$2"
    echo -e "  ${DIM}${label}:${RESET} ${BOLD}${value}${RESET}" >&2
}

# ============================================================================
# Helper Functions
# ============================================================================

check_dependencies() {
    local missing=()

    if ! command -v gh &> /dev/null; then
        missing+=("gh (GitHub CLI)")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v unzip &> /dev/null; then
        missing+=("unzip")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies:"
        for dep in "${missing[@]}"; do
            echo -e "  ${RED}•${RESET} ${dep}"
        done
        exit 1
    fi
}

check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated with GitHub CLI"
        log_info "Run: ${BOLD}gh auth login${RESET}"
        exit 1
    fi
}

show_help() {
    cat << EOF
${BOLD}${BRIGHT_CYAN}GitHub Artifact Downloader${RESET}

${BOLD}USAGE:${RESET}
    $(basename "$0") ${CYAN}<REPO>${RESET} [${YELLOW}OPTIONS${RESET}]

${BOLD}ARGUMENTS:${RESET}
    ${CYAN}REPO${RESET}                GitHub repository (${DIM}owner/repo${RESET})

${BOLD}OPTIONS:${RESET}
    ${YELLOW}-n, --name NAME${RESET}     Artifact name to download (preselect)
    ${YELLOW}-o, --output DIR${RESET}    Output directory (default: current directory)
    ${YELLOW}-h, --help${RESET}          Show this help message

${BOLD}EXAMPLES:${RESET}
    ${DIM}# Interactive mode - list and select artifacts${RESET}
    $(basename "$0") valknarness/awesome

    ${DIM}# Preselect artifact by name${RESET}
    $(basename "$0") valknarness/awesome -n awesome-database-latest

    ${DIM}# Download to specific directory${RESET}
    $(basename "$0") valknarness/awesome -o ~/downloads

    ${DIM}# Combine options${RESET}
    $(basename "$0") valknarness/awesome -n awesome-database-latest -o ~/downloads

EOF
}

format_size() {
    local bytes=$1
    if (( bytes < 1024 )); then
        echo "${bytes}B"
    elif (( bytes < 1048576 )); then
        awk "BEGIN {printf \"%.1fKB\", $bytes/1024}"
    elif (( bytes < 1073741824 )); then
        awk "BEGIN {printf \"%.1fMB\", $bytes/1048576}"
    else
        awk "BEGIN {printf \"%.2fGB\", $bytes/1073741824}"
    fi
}

format_date() {
    local iso_date="$1"
    if command -v date &> /dev/null; then
        if date --version &> /dev/null 2>&1; then
            # GNU date
            date -d "$iso_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$iso_date"
        else
            # BSD date (macOS)
            date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$iso_date"
        fi
    else
        echo "$iso_date"
    fi
}

# ============================================================================
# Main Functions
# ============================================================================

list_artifacts() {
    local repo="$1"

    log_step "Fetching artifacts from ${BOLD}${repo}${RESET}..."

    # First check if there are any artifacts using gh's built-in jq
    local count
    count=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        --jq '.artifacts | length' \
        "/repos/${repo}/actions/artifacts?per_page=100" 2>/dev/null)

    if [[ -z "$count" ]]; then
        log_error "Failed to fetch artifacts from repository"
        log_info "Please check that:"
        echo "  • The repository ${BOLD}${repo}${RESET} exists and you have access"
        echo "  • GitHub Actions is enabled for this repository"
        exit 1
    fi

    if [[ "$count" -eq 0 ]]; then
        log_warning "No artifacts found in repository ${BOLD}${repo}${RESET}"
        log_info "This repository may not have any workflow runs that produced artifacts"
        exit 0
    fi

    # Now fetch the full JSON response
    local artifacts_json
    artifacts_json=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/${repo}/actions/artifacts?per_page=100" 2>/dev/null)

    echo "$artifacts_json"
}

select_artifact() {
    local artifacts_json="$1"
    local preselect_name="$2"

    # Parse artifacts
    local artifacts
    artifacts=$(echo "$artifacts_json" | jq -r '.artifacts[] |
        "\(.id)|\(.name)|\(.size_in_bytes)|\(.created_at)|\(.workflow_run.id)"')

    # If preselect name is provided, find matching artifact
    if [[ -n "$preselect_name" ]]; then
        local selected
        selected=$(echo "$artifacts" | grep -F "|${preselect_name}|" | head -1)

        if [[ -z "$selected" ]]; then
            log_error "Artifact '${BOLD}${preselect_name}${RESET}' not found"
            log_info "Available artifacts:"
            echo "$artifacts" | while IFS='|' read -r id name size created workflow; do
                echo "  ${CYAN}•${RESET} ${name}"
            done
            exit 1
        fi

        echo "$selected"
        return 0
    fi

    # Interactive selection
    log_info "Available artifacts:"
    echo ""

    local i=1
    local -a artifact_array

    while IFS='|' read -r id name size created workflow; do
        artifact_array+=("$id|$name|$size|$created|$workflow")
        local formatted_size=$(format_size "$size")
        local formatted_date=$(format_date "$created")

        printf "  ${BOLD}${YELLOW}[%2d]${RESET} ${BRIGHT_CYAN}%s${RESET}\n" "$i" "$name"
        printf "       ${DIM}Size: ${RESET}%s  ${DIM}Created: ${RESET}%s\n" "$formatted_size" "$formatted_date"
        echo ""

        ((i++))
    done <<< "$artifacts"

    # Prompt for selection
    local selection
    while true; do
        echo -n -e "${BRIGHT_MAGENTA}${BOLD}�${RESET} ${MAGENTA}Select artifact [1-$((i-1))]:${RESET} "
        read -r selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -lt "$i" ]]; then
            break
        else
            log_warning "Invalid selection. Please enter a number between 1 and $((i-1))"
        fi
    done

    echo "${artifact_array[$((selection-1))]}"
}

download_artifact() {
    local repo="$1"
    local artifact_id="$2"
    local artifact_name="$3"
    local output_dir="$4"

    log_step "Downloading artifact ${BOLD}${artifact_name}${RESET}..."

    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"

    # Download artifact using gh
    local zip_file="${output_dir}/${artifact_name}.zip"

    if gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/${repo}/actions/artifacts/${artifact_id}/zip" \
        > "$zip_file" 2>/dev/null; then

        log_success "Downloaded to ${BOLD}${zip_file}${RESET}"
        echo "$zip_file"
    else
        log_error "Failed to download artifact"
        exit 1
    fi
}

extract_artifact() {
    local zip_file="$1"
    local output_dir="$2"

    log_step "Extracting archive..."

    # Create extraction directory
    local extract_dir="${output_dir}/$(basename "$zip_file" .zip)"
    mkdir -p "$extract_dir"

    if unzip -q "$zip_file" -d "$extract_dir"; then
        log_success "Extracted to ${BOLD}${extract_dir}${RESET}"

        # Show extracted files
        log_info "Extracted files:"
        find "$extract_dir" -type f -exec basename {} \; | while read -r file; do
            echo "  ${GREEN}•${RESET} ${file}"
        done

        # Remove zip file
        rm "$zip_file"
        log_info "Cleaned up zip file"

        echo "$extract_dir"
    else
        log_error "Failed to extract archive"
        exit 1
    fi
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    local repo=""
    local artifact_name=""
    local output_dir="."

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--name)
                artifact_name="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$repo" ]]; then
                    repo="$1"
                else
                    log_error "Unexpected argument: $1"
                    echo ""
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$repo" ]]; then
        log_error "Repository argument is required"
        echo ""
        show_help
        exit 1
    fi

    # Validate repository format
    if [[ ! "$repo" =~ ^[^/]+/[^/]+$ ]]; then
        log_error "Invalid repository format. Expected: ${BOLD}owner/repo${RESET}"
        exit 1
    fi

    # Show header
    log_header "GitHub Artifact Downloader"

    # Check dependencies
    log_step "Checking dependencies..."
    check_dependencies
    log_success "All dependencies found"

    # Check GitHub authentication
    log_step "Checking GitHub authentication..."
    check_gh_auth
    log_success "Authenticated with GitHub"

    echo ""
    log_data "Repository" "${BRIGHT_CYAN}${repo}${RESET}"
    if [[ -n "$artifact_name" ]]; then
        log_data "Artifact" "${BRIGHT_YELLOW}${artifact_name}${RESET}"
    fi
    log_data "Output" "${BRIGHT_GREEN}${output_dir}${RESET}"
    echo ""

    # List artifacts
    local artifacts_json
    artifacts_json=$(list_artifacts "$repo")

    # Select artifact
    local selected
    selected=$(select_artifact "$artifacts_json" "$artifact_name")

    IFS='|' read -r artifact_id name size created workflow <<< "$selected"

    echo ""
    log_info "Selected artifact:"
    log_data "  Name" "${BRIGHT_CYAN}${name}${RESET}"
    log_data "  Size" "$(format_size "$size")"
    log_data "  Created" "$(format_date "$created")"
    echo ""

    # Download artifact
    local zip_file
    zip_file=$(download_artifact "$repo" "$artifact_id" "$name" "$output_dir")

    # Extract artifact
    local extract_dir
    extract_dir=$(extract_artifact "$zip_file" "$output_dir")

    # Success summary
    echo ""
    log_header "Download Complete!"
    log_data "Location" "${BOLD}${extract_dir}${RESET}"
    echo ""

    log_success "All done! 🎉"
}

# Run main function
main "$@"
