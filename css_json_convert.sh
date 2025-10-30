#!/usr/bin/env bash

#############################################
# CSS Variable to JSON/YAML Converter
# Extracts CSS custom properties (--var: value;)
# and converts them to JSON or YAML format
#############################################

set -euo pipefail

# Terminal colors using tput
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

# Icons for output (simple ASCII)
readonly ICON_SUCCESS="[OK]"
readonly ICON_ERROR="[ERROR]"
readonly ICON_INFO="[INFO]"
readonly ICON_CONVERT="==>"

# Default values
OUTPUT_FILE="${PWD}/output.yaml"
INPUT_FILE=""
CAMEL_CASE=false
VERBOSE=false

#############################################
# Functions
#############################################

print_banner() {
    echo ""
    echo "${CYAN}${BOLD}================================================================${RESET}"
    echo "${CYAN}${BOLD}  CSS Variable to JSON/YAML Converter${RESET}"
    echo "${CYAN}${BOLD}  Extract CSS custom properties with ease${RESET}"
    echo "${CYAN}${BOLD}================================================================${RESET}"
    echo ""
}

print_success() {
    echo "${GREEN}${ICON_SUCCESS}${RESET} $*"
}

print_error() {
    echo "${RED}${ICON_ERROR}${RESET} $*" >&2
}

print_info() {
    echo "${BLUE}${ICON_INFO}${RESET} $*"
}

print_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "${DIM}  ==> $*${RESET}"
    fi
    return 0
}

show_help() {
    cat << EOF
${BOLD}USAGE:${RESET}
    $(basename "$0") [OPTIONS] <input.css>

${BOLD}DESCRIPTION:${RESET}
    Extracts CSS custom properties (variables) from a CSS file and converts
    them to JSON or YAML format. Automatically detects output format from
    file extension.

${BOLD}ARGUMENTS:${RESET}
    <input.css>              Input CSS file containing CSS variables

${BOLD}OPTIONS:${RESET}
    -o, --output FILE        Output file path (default: ./output.yaml)
                             Format auto-detected from extension (.json/.yaml/.yml)
    -c, --camel-case         Convert variable names to camelCase
                             (e.g., --main-color -> mainColor)
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message

${BOLD}EXAMPLES:${RESET}
    # Extract CSS vars to YAML (default)
    $(basename "$0") styles.css

    # Extract to JSON with custom output
    $(basename "$0") styles.css -o theme.json

    # Convert variable names to camelCase
    $(basename "$0") styles.css -o vars.json --camel-case

${BOLD}CSS VARIABLE FORMAT:${RESET}
    The script extracts CSS custom properties in the format:
        --variable-name: value;

    Example input:
        :root {
          --main-color: #e8eaed;
          --font-size: 16px;
        }

    Example JSON output:
        {
          "main-color": "#e8eaed",
          "font-size": "16px"
        }

EOF
}

# Convert kebab-case to camelCase
to_camel_case() {
    local input="$1"
    # Remove leading dashes and convert to camelCase
    echo "$input" | sed -E 's/^--//; s/-(.)/\U\1/g'
}

# Extract CSS variables using advanced sed
extract_css_variables() {
    local input_file="$1"

    print_verbose "Extracting CSS variables from: $input_file" >&2

    # Advanced sed expression to extract CSS custom properties
    # Matches: --variable-name: value; (with flexible whitespace)
    sed -n 's/^[[:space:]]*\(--[a-zA-Z0-9_-]\+\)[[:space:]]*:[[:space:]]*\([^;]\+\);.*$/\1|\2/p' "$input_file" \
        | sed 's/[[:space:]]*$//' \
        | sed 's/^[[:space:]]*//'
}

# Convert to JSON format
convert_to_json() {
    local -a variables=("$@")
    local json="{"
    local first=true

    for var in "${variables[@]}"; do
        IFS='|' read -r name value <<< "$var"

        # Remove leading dashes
        name="${name#--}"

        # Convert to camelCase if requested
        if [[ "$CAMEL_CASE" == true ]]; then
            name=$(to_camel_case "--$name")
        fi

        # Trim whitespace from value
        value=$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        # Escape quotes in value
        value="${value//\"/\\\"}"

        if [[ "$first" == true ]]; then
            first=false
            json+=$'\n'
        else
            json+=","$'\n'
        fi

        json+="  \"$name\": \"$value\""
    done

    json+=$'\n'"}"
    echo "$json"
}

# Convert to YAML format
convert_to_yaml() {
    local -a variables=("$@")
    local yaml=""

    for var in "${variables[@]}"; do
        IFS='|' read -r name value <<< "$var"

        # Remove leading dashes
        name="${name#--}"

        # Convert to camelCase if requested
        if [[ "$CAMEL_CASE" == true ]]; then
            name=$(to_camel_case "--$name")
        fi

        # Trim whitespace from value
        value=$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        # Quote value if it contains special characters or starts with special chars
        if [[ "$value" =~ ^[#\&\*\!\|\>\'\"] ]] || [[ "$value" =~ [:\{\}\[\],] ]]; then
            value="\"$value\""
        fi

        yaml+="$name: $value"$'\n'
    done

    echo "$yaml"
}

# Determine output format from file extension
get_output_format() {
    local file="$1"
    local ext="${file##*.}"

    case "$ext" in
        json)
            echo "json"
            ;;
        yaml|yml)
            echo "yaml"
            ;;
        *)
            print_error "Unsupported output format: .$ext"
            print_info "Supported formats: .json, .yaml, .yml"
            exit 1
            ;;
    esac
}

#############################################
# Main Script
#############################################

main() {
    print_banner

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -c|--camel-case)
                CAMEL_CASE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
            *)
                INPUT_FILE="$1"
                shift
                ;;
        esac
    done

    # Validate input file
    if [[ -z "$INPUT_FILE" ]]; then
        print_error "No input file specified"
        echo "Use -h or --help for usage information"
        exit 1
    fi

    if [[ ! -f "$INPUT_FILE" ]]; then
        print_error "Input file not found: $INPUT_FILE"
        exit 1
    fi

    # Show processing info
    print_info "${ICON_FILE} Input:  ${CYAN}$INPUT_FILE${RESET}"
    print_info "${ICON_FILE} Output: ${CYAN}$OUTPUT_FILE${RESET}"

    if [[ "$CAMEL_CASE" == true ]]; then
        print_info "${ICON_CONVERT} Mode:   ${YELLOW}camelCase conversion enabled${RESET}"
    fi

    echo ""

    # Extract CSS variables
    print_info "${ICON_CONVERT} Extracting CSS variables..."

    mapfile -t variables < <(extract_css_variables "$INPUT_FILE")

    if [[ ${#variables[@]} -eq 0 ]]; then
        print_error "No CSS variables found in $INPUT_FILE"
        print_info "Expected format: --variable-name: value;"
        exit 1
    fi

    print_success "Found ${BOLD}${#variables[@]}${RESET} CSS variable(s)"

    # Show extracted variables in verbose mode
    if [[ "$VERBOSE" == true ]]; then
        echo ""
        for var in "${variables[@]}"; do
            IFS='|' read -r name value <<< "$var"
            print_verbose "${MAGENTA}$name${RESET} = ${GREEN}$value${RESET}"
        done
        echo ""
    fi

    # Determine output format
    OUTPUT_FORMAT=$(get_output_format "$OUTPUT_FILE")
    print_verbose "Output format: $OUTPUT_FORMAT"

    # Convert and write output
    print_info "${ICON_CONVERT} Converting to ${BOLD}${OUTPUT_FORMAT^^}${RESET}..."

    case "$OUTPUT_FORMAT" in
        json)
            convert_to_json "${variables[@]}" > "$OUTPUT_FILE"
            ;;
        yaml)
            convert_to_yaml "${variables[@]}" > "$OUTPUT_FILE"
            ;;
    esac

    # Success message
    echo ""
    print_success "${ICON_ROCKET} Conversion complete!"
    print_info "Output saved to: ${BOLD}${GREEN}$OUTPUT_FILE${RESET}"

    # Show preview if verbose
    if [[ "$VERBOSE" == true ]]; then
        echo ""
        echo -e "${DIM}           Preview           ${RESET}"
        head -n 20 "$OUTPUT_FILE" | sed 's/^/  /'
        if [[ $(wc -l < "$OUTPUT_FILE") -gt 20 ]]; then
            echo -e "${DIM}  ... (truncated)${RESET}"
        fi
        echo -e "${DIM}                             ${RESET}"
    fi
}

# Run main function
main "$@"
