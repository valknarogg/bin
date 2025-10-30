#!/usr/bin/env bash

##############################################################
# Rust Documentation Generator with Custom Themes
# Generates beautiful Rust documentation with custom color schemes
##############################################################

set -euo pipefail

# Color definitions using tput
RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" DIM="" RESET=""

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    COLORS=$(tput colors 2>/dev/null || echo 0)
    if [[ ${COLORS:-0} -ge 8 ]]; then
        RED=$(tput setaf 1 2>/dev/null || echo "")
        GREEN=$(tput setaf 2 2>/dev/null || echo "")
        YELLOW=$(tput setaf 3 2>/dev/null || echo "")
        BLUE=$(tput setaf 4 2>/dev/null || echo "")
        MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
        CYAN=$(tput setaf 6 2>/dev/null || echo "")
        BOLD=$(tput bold 2>/dev/null || echo "")
        DIM=$(tput dim 2>/dev/null || echo "")
        RESET=$(tput sgr0 2>/dev/null || echo "")
    fi
fi

# Script paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ASSETS_DIR="${SCRIPT_DIR}/assets/doc_rust_generate"
readonly THEME_DIR="${ASSETS_DIR}/theme"
readonly TMP_DIR="${SCRIPT_DIR}/tmp"

# Default values
OUTPUT_DIR="${PWD}/output"
PRIMARY_COLOR="#ff69b4"  # Default pink
STYLE="slate"
FONT_SANS="Inter"
FONT_MONO="JetBrains Mono"
INPUT_FILES=()
VERBOSE=false
DRY_RUN=false
SERVE=false
OPEN=false
SERVE_PORT=8000

# Style color mappings (neutral background colors)
declare -A STYLE_COLORS=(
    ["slate"]="#64748b"
    ["zinc"]="#71717a"
    ["neutral"]="#737373"
    ["stone"]="#78716c"
    ["gray"]="#6b7280"
)

##############################################################
# UI Functions
##############################################################

info() {
    echo "${BLUE}${BOLD}==>${RESET} $*"
}

success() {
    echo "${GREEN}${BOLD}[OK]${RESET} $*"
}

error() {
    echo "${RED}${BOLD}[ERROR]${RESET} $*" >&2
}

warning() {
    echo "${YELLOW}${BOLD}[WARN]${RESET} $*"
}

verbose() {
    [[ "$VERBOSE" == true ]] && echo "${DIM}  -> $*${RESET}"
}

# Spinner for long-running operations
spinner() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    # Only show spinner if not verbose and output is a terminal
    if [[ "$VERBOSE" == true ]] || [[ ! -t 1 ]]; then
        wait "$pid"
        return $?
    fi

    echo -n "${message} "

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "${CYAN}%c${RESET} " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done

    wait "$pid"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf "${GREEN}✓${RESET}\n"
    else
        printf "${RED}✗${RESET}\n"
    fi

    return $exit_code
}

##############################################################
# Help and Usage
##############################################################

show_help() {
    cat << EOF
${BOLD}${MAGENTA}Rust Documentation Generator with Custom Themes${RESET}

${BOLD}USAGE:${RESET}
    $(basename "$0") [OPTIONS] <inputs...>

${BOLD}DESCRIPTION:${RESET}
    Generate beautiful Rust documentation with custom color schemes and styling.
    Supports various input types including Rust projects, individual files, and more.

${BOLD}ARGUMENTS:${RESET}
    <inputs>                 Input file(s) or pattern(s) to document:
                             - Rust project directories (containing Cargo.toml)
                             - Individual .rs files
                             - Markdown files (.md)
                             - JSON/TOML configuration files
                             - Glob patterns (e.g., src/**/*.rs)

${BOLD}OPTIONS:${RESET}
    -o, --output DIR         Output directory for generated docs
                             (default: \$PWD/output)
    -c, --color COLOR        Primary accent color (hex format)
                             (default: #ff69b4)
                             Examples: #3498db, #10b981, #8b5cf6
    -s, --style STYLE        Background style theme
                             Options: slate, zinc, neutral, stone, gray
                             (default: slate)
    --font-sans FONT         Google Font for body text (default: Inter)
    --font-mono FONT         Google Font for code blocks
                             (default: JetBrains Mono)
    --serve                  Start HTTP server after generation
    --open                   Open documentation in browser (implies --serve)
    -p, --port PORT          Port for HTTP server (default: 8000)
    -v, --verbose            Enable verbose output
    -d, --dry-run            Show what would be done without executing
    -h, --help               Show this help message

${BOLD}EXAMPLES:${RESET}
    ${DIM}# Generate docs for current Rust project${RESET}
    $(basename "$0") .

    ${DIM}# Custom color scheme${RESET}
    $(basename "$0") . -c "#3498db" -s zinc -o ./docs

    ${DIM}# Document specific files${RESET}
    $(basename "$0") src/lib.rs src/main.rs -o ./api-docs

    ${DIM}# Use custom fonts${RESET}
    $(basename "$0") . --font-sans "Roboto" --font-mono "Fira Code"

    ${DIM}# Generate and open in browser${RESET}
    $(basename "$0") . --open

${BOLD}NOTES:${RESET}
    - Requires: cargo, rustdoc, bc, yq, jq, python3 with jinja2
    - Colors are automatically generated in light and dark variants
    - Google Fonts are automatically imported
    - Mermaid.js diagrams are automatically rendered

EOF
}

##############################################################
# Dependency Checks
##############################################################

check_dependencies() {
    local missing=()

    command -v cargo >/dev/null 2>&1 || missing+=("cargo")
    command -v rustdoc >/dev/null 2>&1 || missing+=("rustdoc")
    command -v bc >/dev/null 2>&1 || missing+=("bc")
    command -v yq >/dev/null 2>&1 || missing+=("yq")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if ! python3 -c "import jinja2" 2>/dev/null; then
        missing+=("python3-jinja2")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        exit 1
    fi

    # Check for helper scripts
    if [[ ! -x "${SCRIPT_DIR}/css_color_palette.sh" ]]; then
        error "Helper script not found: ${SCRIPT_DIR}/css_color_palette.sh"
        exit 1
    fi

    if [[ ! -x "${SCRIPT_DIR}/jinja_template_render.sh" ]]; then
        error "Helper script not found: ${SCRIPT_DIR}/jinja_template_render.sh"
        exit 1
    fi
}

##############################################################
# Input Processing
##############################################################

validate_color() {
    local color="$1"
    # Remove leading # if present
    color="${color#\#}"

    if [[ ! "$color" =~ ^[0-9A-Fa-f]{3}$ ]] && [[ ! "$color" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        error "Invalid hex color: $1"
        error "Expected format: #RGB or #RRGGBB"
        exit 1
    fi

    # Ensure 6-digit format
    if [[ ${#color} -eq 3 ]]; then
        color="${color:0:1}${color:0:1}${color:1:1}${color:1:1}${color:2:1}${color:2:1}"
    fi

    echo "#${color}"
}

validate_style() {
    local style="$1"

    case "$style" in
        slate|zinc|neutral|stone|gray)
            echo "$style"
            ;;
        *)
            error "Invalid style: $style"
            error "Valid options: slate, zinc, neutral, stone, gray"
            exit 1
            ;;
    esac
}

##############################################################
# Color Palette Generation
##############################################################

generate_color_palette() {
    local primary_color="$1"
    local style="$2"
    local output_file="$3"

    verbose "Primary color: $primary_color"
    verbose "Style: $style"

    # Generate primary color palette (monochromatic)
    "${SCRIPT_DIR}/css_color_palette.sh" "$primary_color" \
        -p monochromatic \
        -o "${TMP_DIR}/primary_palette.yaml" \
        -m dark \
        -s all >/dev/null 2>&1 &

    local palette_pid=$!

    if ! spinner "$palette_pid" "Generating color palette..."; then
        error "Failed to generate primary color palette"
        return 1
    fi

    verbose "Generated primary palette: ${TMP_DIR}/primary_palette.yaml"
}

##############################################################
# CSS Variables Generation
##############################################################

generate_css_variables() {
    local primary_color="$1"
    local style="$2"
    local output_file="$3"

    info "Generating CSS variables..."

    # Read the generated palette
    local palette_file="${TMP_DIR}/primary_palette.yaml"

    if [[ ! -f "$palette_file" ]]; then
        error "Palette file not found: $palette_file"
        return 1
    fi

    # Extract color values from the palette
    local primary_50 primary_100 primary_200 primary_300 primary_400
    local primary_500 primary_600 primary_700 primary_800 primary_900 primary_950

    primary_50=$(yq -r '.colors.primary."50"' "$palette_file")
    primary_100=$(yq -r '.colors.primary."100"' "$palette_file")
    primary_200=$(yq -r '.colors.primary."200"' "$palette_file")
    primary_300=$(yq -r '.colors.primary."300"' "$palette_file")
    primary_400=$(yq -r '.colors.primary."400"' "$palette_file")
    primary_500=$(yq -r '.colors.primary."500"' "$palette_file")
    primary_600=$(yq -r '.colors.primary."600"' "$palette_file")
    primary_700=$(yq -r '.colors.primary."700"' "$palette_file")
    primary_800=$(yq -r '.colors.primary."800"' "$palette_file")
    primary_900=$(yq -r '.colors.primary."900"' "$palette_file")
    primary_950=$(yq -r '.colors.primary."950"' "$palette_file")

    # Get style-specific colors (from existing theme.yaml)
    local style_file="${THEME_DIR}/theme.yaml"

    # Generate CSS custom properties
    cat > "$output_file" << EOF
/* Generated CSS Variables for Rustdoc Theme */
/* Primary Color: ${primary_color} */
/* Style: ${style} */

:root {
    /* Primary color palette */
    --primary-50: ${primary_50};
    --primary-100: ${primary_100};
    --primary-200: ${primary_200};
    --primary-300: ${primary_300};
    --primary-400: ${primary_400};
    --primary-500: ${primary_500};
    --primary-600: ${primary_600};
    --primary-700: ${primary_700};
    --primary-800: ${primary_800};
    --primary-900: ${primary_900};
    --primary-950: ${primary_950};

    /* Google Fonts */
    --font-family: '${FONT_SANS}', 'Fira Sans', Arial, sans-serif;
    --font-family-code: '${FONT_MONO}', 'Fira Mono', monospace;
}

/* Import Google Fonts */
@import url('https://fonts.googleapis.com/css2?family=${FONT_SANS// /+}:wght@300;400;500;600;700&family=${FONT_MONO// /+}:wght@400;500;600;700&display=swap');

:root {
EOF

    # Now read the theme.yaml and replace color references with our palette
    verbose "Processing theme variables..."

    # Read theme.yaml and substitute colors
    while IFS=': ' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^# ]] && continue

        # Remove quotes and leading/trailing whitespace
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        value="${value# }"
        value="${value% }"

        # Replace hardcoded colors with our palette where appropriate
        # This is a simple substitution - for primary/accent colors use our palette
        if [[ "$value" == "#ff69b4" || "$value" == "#ff1493" || "$value" == "#ec407a" ]]; then
            value="${primary_500}"
        elif [[ "$value" == "#f06292" ]]; then
            value="${primary_400}"
        fi

        echo "    --${key}: ${value};" >> "$output_file"
    done < <(grep -E '^[a-zA-Z]' "$style_file" || true)

    # Close the :root block
    echo "}" >> "$output_file"

    verbose "Generated CSS variables: $output_file"
    success "CSS variables generated"
}

##############################################################
# Render Header Template
##############################################################

render_header_template() {
    local output_file="$1"

    info "Rendering header template..."

    # Process mermaid.yaml variables to match our theme
    local mermaid_yaml="${TMP_DIR}/mermaid_processed.yaml"

    # Copy and update mermaid colors
    cp "${THEME_DIR}/mermaid.yaml" "$mermaid_yaml"

    # Update with our primary color
    yq -i ".primaryColor = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".lineColor = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".border1 = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".noteBorderColor = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".arrowheadColor = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".clusterBorder = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".defaultLinkColor = \"${PRIMARY_COLOR}\"" "$mermaid_yaml"
    yq -i ".fontFamily = \"${FONT_SANS}, system-ui, -apple-system, sans-serif\"" "$mermaid_yaml"

    verbose "Processed mermaid config: $mermaid_yaml"

    # Render the Jinja2 template
    if ! "${SCRIPT_DIR}/jinja_template_render.sh" \
        -f "$mermaid_yaml" \
        -o "${TMP_DIR}" \
        "${THEME_DIR}/header.html.jinja"; then
        error "Failed to render header template"
        return 1
    fi

    # Move rendered file to expected location if different
    if [[ "${TMP_DIR}/header.html" != "$output_file" ]]; then
        mv "${TMP_DIR}/header.html" "$output_file"
    fi

    verbose "Rendered header: $output_file"
    success "Header template rendered"
}

##############################################################
# Consolidate CSS
##############################################################

consolidate_css() {
    local output_file="$1"

    info "Consolidating CSS files..."

    # Combine variables.css and theme.css
    cat "${TMP_DIR}/variables.css" > "$output_file"
    echo "" >> "$output_file"
    cat "${THEME_DIR}/theme.css" >> "$output_file"

    verbose "Consolidated CSS: $output_file"
    success "CSS consolidated"
}

##############################################################
# Run Rustdoc
##############################################################

run_rustdoc() {
    local inputs=("$@")

    info "Running rustdoc..."

    local header_file="${TMP_DIR}/header.html"
    local css_file="${TMP_DIR}/theme-combined.css"

    # Determine if we're documenting a cargo project or individual files
    local is_cargo_project=false

    for input in "${inputs[@]}"; do
        if [[ -f "${input}/Cargo.toml" ]] || [[ -f "${input%/}/Cargo.toml" ]]; then
            is_cargo_project=true
            break
        fi
    done

    if [[ "$is_cargo_project" == true ]]; then
        info "Detected Cargo project, using 'cargo doc'..."

        # Find the Cargo.toml directory
        local cargo_dir=""
        for input in "${inputs[@]}"; do
            if [[ -f "${input}/Cargo.toml" ]]; then
                cargo_dir="$input"
                break
            elif [[ -f "${input%/}/Cargo.toml" ]]; then
                cargo_dir="${input%/}"
                break
            fi
        done

        # Build cargo doc command with custom theme
        local cargo_args=(
            "doc"
            "--no-deps"
            "--target-dir" "${OUTPUT_DIR}"
        )

        # Set RUSTDOCFLAGS environment variable for custom styling
        export RUSTDOCFLAGS="--html-in-header ${header_file} --extend-css ${css_file}"

        if [[ "$VERBOSE" == true ]]; then
            cargo_args+=("-v")
        fi

        verbose "Running: cargo ${cargo_args[*]}"
        verbose "RUSTDOCFLAGS: $RUSTDOCFLAGS"

        if [[ "$DRY_RUN" == true ]]; then
            warning "Dry run: would execute cargo ${cargo_args[*]}"
        else
            if [[ "$VERBOSE" == false ]]; then
                # Run cargo in background with spinner
                (cd "$cargo_dir" && cargo "${cargo_args[@]}") >/dev/null 2>&1 &
                local cargo_pid=$!

                if ! spinner "$cargo_pid" "Running cargo doc (this may take a while)..."; then
                    error "cargo doc failed"
                    return 1
                fi
            else
                # Show cargo output in verbose mode
                (cd "$cargo_dir" && cargo "${cargo_args[@]}")
            fi

            success "Documentation generated successfully"
            info "Output directory: ${OUTPUT_DIR}/doc"
        fi
    else
        # Document individual files using rustdoc directly
        warning "Individual file documentation not fully implemented yet"
        warning "Please provide a Cargo project directory"
        return 1
    fi
}

##############################################################
# Serve and Open Documentation
##############################################################

serve_and_open_docs() {
    local doc_dir="${OUTPUT_DIR}/doc"
    local index_file="${doc_dir}/universal_lsp/index.html"

    # Find the actual index.html file (might be in different location)
    if [[ ! -f "$index_file" ]]; then
        # Try to find any index.html in the doc directory
        index_file=$(find "$doc_dir" -name "index.html" -type f | head -1)
        if [[ -z "$index_file" ]]; then
            warning "Could not find index.html in documentation"
            index_file="${doc_dir}/index.html"
        fi
    fi

    # Get the relative path from doc_dir to index_file for the URL
    local rel_path="${index_file#$doc_dir/}"
    local url="http://localhost:${SERVE_PORT}/${rel_path}"

    info "Starting HTTP server on port ${SERVE_PORT}..."
    echo ""

    # Start Python HTTP server in the background
    cd "$doc_dir" || {
        error "Failed to change to documentation directory: $doc_dir"
        return 1
    }

    # Kill any existing server on this port
    if lsof -Pi ":${SERVE_PORT}" -sTCP:LISTEN -t >/dev/null 2>&1; then
        warning "Port ${SERVE_PORT} is already in use. Trying to kill existing process..."
        lsof -Pi ":${SERVE_PORT}" -sTCP:LISTEN -t | xargs kill -9 2>/dev/null || true
        sleep 1
    fi

    # Start server
    python3 -m http.server "$SERVE_PORT" >/dev/null 2>&1 &
    local server_pid=$!

    # Give the server a moment to start
    sleep 1

    # Check if server started successfully
    if ! kill -0 "$server_pid" 2>/dev/null; then
        error "Failed to start HTTP server"
        return 1
    fi

    success "Server started (PID: $server_pid)"
    info "Documentation available at: ${CYAN}${url}${RESET}"

    # Open in browser if requested
    if [[ "$OPEN" == true ]]; then
        info "Opening documentation in browser..."

        # Try different browser openers
        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$url" >/dev/null 2>&1 &
        elif command -v open >/dev/null 2>&1; then
            open "$url" >/dev/null 2>&1 &
        elif command -v sensible-browser >/dev/null 2>&1; then
            sensible-browser "$url" >/dev/null 2>&1 &
        else
            warning "Could not detect browser opener (xdg-open, open, sensible-browser)"
            info "Please open manually: $url"
        fi

        sleep 1
        success "Browser opened"
    fi

    echo ""
    echo "${BOLD}${GREEN}Server running!${RESET}"
    echo "${DIM}Press Ctrl+C to stop the server${RESET}"
    echo ""

    # Wait for Ctrl+C
    trap "echo ''; info 'Shutting down server...'; kill $server_pid 2>/dev/null; success 'Server stopped'; exit 0" INT TERM

    # Keep the script running
    wait "$server_pid"
}

##############################################################
# Cleanup
##############################################################

cleanup() {
    if [[ "$VERBOSE" == true ]]; then
        verbose "Temporary files preserved in: ${TMP_DIR}"
    fi
}

trap cleanup EXIT

##############################################################
# Main Function
##############################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--color)
                PRIMARY_COLOR=$(validate_color "$2")
                shift 2
                ;;
            -s|--style)
                STYLE=$(validate_style "$2")
                shift 2
                ;;
            --font-sans)
                FONT_SANS="$2"
                shift 2
                ;;
            --font-mono)
                FONT_MONO="$2"
                shift 2
                ;;
            --serve)
                SERVE=true
                shift
                ;;
            --open)
                OPEN=true
                SERVE=true  # Opening implies serving
                shift
                ;;
            -p|--port)
                SERVE_PORT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
            *)
                INPUT_FILES+=("$1")
                shift
                ;;
        esac
    done

    # Print banner
    echo "${MAGENTA}${BOLD}"
    echo "=============================================="
    echo "  Rust Documentation Generator"
    echo "=============================================="
    echo "${RESET}"

    # Check dependencies
    info "Checking dependencies..."
    check_dependencies
    success "All dependencies found"

    # Validate inputs
    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        error "No input files specified"
        echo "Use -h or --help for usage information"
        exit 1
    fi

    # Create temporary directory
    mkdir -p "$TMP_DIR"
    verbose "Temporary directory: $TMP_DIR"

    # Show configuration
    echo ""
    info "Configuration:"
    echo "  Primary Color: ${PRIMARY_COLOR}"
    echo "  Style: ${STYLE}"
    echo "  Font Sans: ${FONT_SANS}"
    echo "  Font Mono: ${FONT_MONO}"
    echo "  Output: ${OUTPUT_DIR}"
    echo "  Inputs: ${INPUT_FILES[*]}"
    echo ""

    # Generate color palette
    generate_color_palette "$PRIMARY_COLOR" "$STYLE" "${TMP_DIR}/palette.yaml"

    # Generate CSS variables
    generate_css_variables "$PRIMARY_COLOR" "$STYLE" "${TMP_DIR}/variables.css"

    # Render header template
    render_header_template "${TMP_DIR}/header.html"

    # Consolidate CSS
    consolidate_css "${TMP_DIR}/theme-combined.css"

    # Run rustdoc
    run_rustdoc "${INPUT_FILES[@]}"

    echo ""
    success "Documentation generation complete!"

    if [[ "$DRY_RUN" == false ]]; then
        info "View your documentation:"
        echo "  ${CYAN}${OUTPUT_DIR}/doc/index.html${RESET}"

        # Serve and/or open documentation if requested
        if [[ "$SERVE" == true ]]; then
            echo ""
            serve_and_open_docs
        fi
    fi

    echo ""
}

# Run main function
main "$@"
