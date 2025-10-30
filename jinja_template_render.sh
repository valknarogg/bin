#!/usr/bin/env bash

##############################################################
# Jinja2 Template Renderer - Ninja Edition
# A sophisticated template rendering engine with style
##############################################################

set -uo pipefail
# Note: Using -u and pipefail, but not -e to allow graceful error handling

# Terminal colors using tput
BLACK="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" GRAY=""
BOLD="" DIM="" ITALIC="" UNDERLINE="" RESET=""

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    COLORS=$(tput colors 2>/dev/null || echo 0)
    if [[ ${COLORS:-0} -ge 8 ]]; then
        BLACK=$(tput setaf 0 2>/dev/null || echo "")
        RED=$(tput setaf 1 2>/dev/null || echo "")
        GREEN=$(tput setaf 2 2>/dev/null || echo "")
        YELLOW=$(tput setaf 3 2>/dev/null || echo "")
        BLUE=$(tput setaf 4 2>/dev/null || echo "")
        MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
        CYAN=$(tput setaf 6 2>/dev/null || echo "")
        WHITE=$(tput setaf 7 2>/dev/null || echo "")
        GRAY=$(tput setaf 8 2>/dev/null || echo "")
        BOLD=$(tput bold 2>/dev/null || echo "")
        DIM=$(tput dim 2>/dev/null || echo "")
        ITALIC=$(tput sitm 2>/dev/null || echo "")
        UNDERLINE=$(tput smul 2>/dev/null || echo "")
        RESET=$(tput sgr0 2>/dev/null || echo "")
    fi
fi

# Ninja-themed icons (ASCII compatible)
readonly NINJA="[NINJA]"
readonly SHURIKEN="*"
readonly KATANA=">>"
readonly SCROLL="[SCROLL]"
readonly FIRE="[FIRE]"
readonly STAR="*"
readonly CHECK="[OK]"
readonly CROSS="[X]"
readonly ARROW="-->"
readonly LIGHTNING="[!]"
readonly GEAR="[GEAR]"
readonly TARGET="[TARGET]"

# Script configuration
OUTPUT_DIR="${PWD}/output"
TEMPLATES=()
VAR_FILES=()
CLI_VARS=()
VERBOSE=false
PREVIEW=false
WATCH=false
STRICT=false
DRY_RUN=false

# Performance tracking
START_TIME=0
TEMPLATE_COUNT=0
VAR_COUNT=0

##############################################################
# Ninja UI Functions
##############################################################

print_ninja_banner() {
    echo "${MAGENTA}${BOLD}"
    cat << 'EOF'
    TPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPW
    Q                                                       Q
    Q       �  JINJA2 TEMPLATE RENDERER - NINJA EDITION   Q
    Q                                                       Q
    Q   >w  Fast " Powerful " Stealthy Template Magic  �  Q
    Q                                                       Q
    ZPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP]
EOF
    echo "${RESET}"
}

print_ninja_art() {
    echo "${CYAN}${DIM}"
    cat << 'EOF'
                    ___
                 __/_  `.  .-"""-.
                 \_,` | \-'  /   )`-')
                  "") `"`    \  ((`"`
                 ___Y  ,    .'7 /|
                (_,___/...-` (_/_/

         Silently rendering your templates...
EOF
    echo "${RESET}"
}

# Animated ninja message
ninja_say() {
    local message="$1"
    echo "${CYAN}${NINJA}${RESET} ${BOLD}${message}${RESET}"
}

ninja_success() {
    echo "${GREEN}${CHECK} ${NINJA}${RESET} ${GREEN}$*${RESET}"
}

ninja_error() {
    echo "${RED}${CROSS} ${NINJA}${RESET} ${RED}$*${RESET}" >&2
}

ninja_warn() {
    echo "${YELLOW}${LIGHTNING}${RESET} ${YELLOW}$*${RESET}"
}

ninja_info() {
    echo "${BLUE}${SHURIKEN}${RESET} ${BLUE}$*${RESET}"
}

ninja_verbose() {
    [[ "$VERBOSE" == true ]] && echo "${DIM}  ${ARROW} $*${RESET}"
}

ninja_progress() {
    local current=$1
    local total=$2
    local item=$3
    local percent=$((current * 100 / total))
    local bar_length=30
    local filled=$((bar_length * current / total))
    local bar=""

    for ((i=0; i<bar_length; i++)); do
        if ((i < filled)); then
            bar+="${FIRE}"
        else
            bar+="�"
        fi
    done

    echo -ne "\r${CYAN}${GEAR}${RESET} [${bar}] ${percent}% - ${ITALIC}${item}${RESET}"

    if ((current == total)); then
        echo "" # New line when complete
    fi
}

# Typing animation effect
ninja_type() {
    local text="$1"
    local delay="${2:-0.03}"

    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

##############################################################
# Help and Usage
##############################################################

show_help() {
    cat << EOF
${BOLD}${MAGENTA}JINJA2 TEMPLATE RENDERER - NINJA EDITION${RESET}

${BOLD}USAGE:${RESET}
    $(basename "$0") [OPTIONS] <template> [template...]

${BOLD}DESCRIPTION:${RESET}
    A sophisticated Jinja2 template rendering engine with support for
    multiple variable sources, glob patterns, and ninja-style operations.

${BOLD}ARGUMENTS:${RESET}
    <template>               Template file(s) to render (glob patterns supported)
                             Examples: template.j2, templates/*.j2, **/*.jinja2

${BOLD}OPTIONS:${RESET}
    -o, --output DIR         Output directory (default: ./output)
    -v, --var KEY=VALUE      Define template variable (can be used multiple times)
    -f, --file FILE          Load variables from JSON/YAML file (repeatable)
    -V, --verbose            Enable verbose ninja commentary
    -p, --preview            Preview rendered output without saving
    -s, --strict             Enable strict mode (fail on undefined variables)
    -d, --dry-run            Perform dry run without writing files
    -w, --watch              Watch templates and re-render on changes (experimental)
    -h, --help               Show this legendary scroll of knowledge

${BOLD}VARIABLE SOURCES:${RESET}
    Variables are merged in this order (later sources override earlier):
    1. YAML files (loaded via yq)
    2. JSON files (loaded via jq)
    3. CLI variables (-v KEY=VALUE)

${BOLD}EXAMPLES:${RESET}
    ${DIM}# Render single template with CLI variables${RESET}
    $(basename "$0") template.j2 -v name=Ninja -v level=Master

    ${DIM}# Render multiple templates with YAML config${RESET}
    $(basename "$0") templates/*.j2 -f config.yaml -o dist/

    ${DIM}# Render with multiple variable sources${RESET}
    $(basename "$0") app.j2 -f base.yaml -f env.json -v debug=true

    ${DIM}# Preview without saving${RESET}
    $(basename "$0") template.j2 -f vars.yaml --preview --verbose

    ${DIM}# Strict mode with dry run${RESET}
    $(basename "$0") *.j2 -f vars.json --strict --dry-run

${BOLD}TEMPLATE SYNTAX:${RESET}
    Jinja2 template example:
    ${DIM}
    Hello {{ name }}!
    {% for item in items %}
      - {{ item }}
    {% endfor %}
    {% if debug %}Debug mode enabled{% endif %}
    ${RESET}

${BOLD}REQUIREMENTS:${RESET}
    - Python 3 with jinja2 package
    - jq (for JSON parsing)
    - yq (for YAML parsing)

${MAGENTA}${NINJA} May your templates be swift and your renders be flawless! ${KATANA}${RESET}

EOF
}

##############################################################
# Variable Collection Functions
##############################################################

# Parse CLI variable in KEY=VALUE format
parse_cli_var() {
    local var="$1"

    if [[ ! "$var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*=.* ]]; then
        ninja_error "Invalid variable format: $var (expected KEY=VALUE)"
        return 1
    fi

    CLI_VARS+=("$var")
    ninja_verbose "Added CLI variable: ${CYAN}$var${RESET}"
}

# Load variables from YAML file
load_yaml_vars() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        ninja_error "YAML file not found: $file"
        return 1
    fi

    if ! command -v yq &> /dev/null; then
        ninja_error "yq not found. Install with: pip install yq"
        return 1
    fi

    ninja_verbose "Loading YAML variables from: ${MAGENTA}$file${RESET}"

    # Validate YAML syntax
    if ! yq -e '.' "$file" &> /dev/null; then
        ninja_error "Invalid YAML syntax in: $file"
        return 1
    fi

    VAR_FILES+=("yaml:$file")
}

# Load variables from JSON file
load_json_vars() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        ninja_error "JSON file not found: $file"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        ninja_error "jq not found. Install with: apt-get install jq"
        return 1
    fi

    ninja_verbose "Loading JSON variables from: ${MAGENTA}$file${RESET}"

    # Validate JSON syntax
    if ! jq empty "$file" &> /dev/null; then
        ninja_error "Invalid JSON syntax in: $file"
        return 1
    fi

    VAR_FILES+=("json:$file")
}

# Build Python dictionary from all variable sources
build_context_dict() {
    local python_dict="{"
    local first=true

    # Process variable files (YAML and JSON)
    for var_file in "${VAR_FILES[@]}"; do
        local type="${var_file%%:*}"
        local file="${var_file#*:}"

        if [[ "$type" == "yaml" ]]; then
            # Convert YAML to JSON using yq
            local json_content
            json_content=$(yq -o json '.' "$file" 2>/dev/null) || {
                ninja_error "Failed to parse YAML: $file"
                return 1
            }

            # Extract key-value pairs and fix Python boolean casing
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Fix boolean values: true -> True, false -> False
                    line="${line//: true/: True}"
                    line="${line//: false/: False}"
                    # Convert hyphens to underscores in key names for Jinja2 compatibility
                    # Extract key and value, replace hyphens in key only
                    if [[ "$line" =~ ^\"([^\"]+)\":[[:space:]]*(.+)$ ]]; then
                        local key="${BASH_REMATCH[1]}"
                        local value="${BASH_REMATCH[2]}"
                        key="${key//-/_}"  # Replace all hyphens with underscores
                        line="\"$key\": $value"
                    fi

                    if [[ "$first" == true ]]; then
                        first=false
                    else
                        python_dict+=", "
                    fi
                    python_dict+="$line"
                fi
            done < <(echo "$json_content" | jq -r 'to_entries | .[] | "\"\(.key)\": \(.value | tojson)"')

        elif [[ "$type" == "json" ]]; then
            # Process JSON file and fix Python boolean casing
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Fix boolean values: true -> True, false -> False
                    line="${line//: true/: True}"
                    line="${line//: false/: False}"
                    # Convert hyphens to underscores in key names for Jinja2 compatibility
                    if [[ "$line" =~ ^\"([^\"]+)\":[[:space:]]*(.+)$ ]]; then
                        local key="${BASH_REMATCH[1]}"
                        local value="${BASH_REMATCH[2]}"
                        key="${key//-/_}"  # Replace all hyphens with underscores
                        line="\"$key\": $value"
                    fi

                    if [[ "$first" == true ]]; then
                        first=false
                    else
                        python_dict+=", "
                    fi
                    python_dict+="$line"
                fi
            done < <(jq -r 'to_entries | .[] | "\"\(.key)\": \(.value | tojson)"' "$file")
        fi
    done

    # Process CLI variables (these override file variables)
    for var in "${CLI_VARS[@]}"; do
        local key="${var%%=*}"
        local value="${var#*=}"

        if [[ "$first" == true ]]; then
            first=false
        else
            python_dict+=", "
        fi

        # Auto-detect value type and format for Python
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            # Integer
            python_dict+="\"$key\": $value"
        elif [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]]; then
            # Float
            python_dict+="\"$key\": $value"
        elif [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
            # Boolean
            python_dict+="\"$key\": ${value^}"
        elif [[ "$value" == "null" ]]; then
            # Null
            python_dict+="\"$key\": None"
        elif [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
            # JSON array or object
            python_dict+="\"$key\": $value"
        else
            # String (escape quotes)
            value="${value//\"/\\\"}"
            python_dict+="\"$key\": \"$value\""
        fi
    done

    python_dict+="}"
    echo "$python_dict"
}

##############################################################
# Template Rendering Engine
##############################################################

render_template() {
    local template_file="$1"
    local output_file="$2"
    local context="$3"

    ninja_verbose "Rendering: ${CYAN}$(basename "$template_file")${RESET}"

    # Create Python rendering script
    local python_script=$(cat <<'PYTHON_EOF'
import sys
import json
import os
from jinja2 import Environment, FileSystemLoader, StrictUndefined, TemplateError

def render_template(template_path, context_dict, strict=False):
    """Render a Jinja2 template with given context."""
    try:
        # Setup Jinja2 environment
        template_dir = os.path.dirname(os.path.abspath(template_path))
        template_name = os.path.basename(template_path)

        env_kwargs = {
            'loader': FileSystemLoader(template_dir),
            'trim_blocks': True,
            'lstrip_blocks': True,
            'keep_trailing_newline': True,
        }

        if strict:
            env_kwargs['undefined'] = StrictUndefined

        env = Environment(**env_kwargs)

        # Load and render template
        template = env.get_template(template_name)
        rendered = template.render(**context_dict)

        return rendered, None

    except TemplateError as e:
        return None, f"Template Error: {e}"
    except Exception as e:
        return None, f"Unexpected Error: {e}"

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: script.py <template> <context_json> <strict>", file=sys.stderr)
        sys.exit(1)

    template_path = sys.argv[1]
    context_json = sys.argv[2]
    strict = sys.argv[3].lower() == 'true'

    # Parse context
    try:
        context = eval(context_json)  # Safe in this controlled context
    except Exception as e:
        print(f"Failed to parse context: {e}", file=sys.stderr)
        sys.exit(1)

    # Render template
    result, error = render_template(template_path, context, strict)

    if error:
        print(error, file=sys.stderr)
        sys.exit(1)

    print(result, end='')
PYTHON_EOF
)

    # Check if Python and Jinja2 are available
    if ! python3 -c "import jinja2" 2>/dev/null; then
        ninja_error "Python jinja2 module not found. Install with: pip install jinja2"
        return 1
    fi

    # Render template
    local rendered
    local strict_flag="false"
    [[ "$STRICT" == true ]] && strict_flag="true"

    if rendered=$(python3 -c "$python_script" "$template_file" "$context" "$strict_flag" 2>&1); then
        if [[ "$PREVIEW" == true ]]; then
            # Preview mode - just display
            echo ""
            echo "${CYAN}${BOLD}PPP Preview: $(basename "$template_file") PPP${RESET}"
            echo "$rendered"
            echo "${CYAN}${BOLD}PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP${RESET}"
            echo ""
        elif [[ "$DRY_RUN" == true ]]; then
            ninja_verbose "Would write to: ${GREEN}$output_file${RESET}"
        else
            # Write to output file
            echo "$rendered" > "$output_file"
            ninja_verbose "Wrote: ${GREEN}$output_file${RESET}"
        fi
        return 0
    else
        ninja_error "Failed to render $(basename "$template_file")"
        echo "${RED}$rendered${RESET}" >&2
        return 1
    fi
}

##############################################################
# Template Discovery and Processing
##############################################################

discover_templates() {
    local pattern="$1"
    local found_templates=()

    # Check if pattern contains glob characters
    if [[ "$pattern" == *"*"* ]] || [[ "$pattern" == *"?"* ]]; then
        # Glob expansion
        shopt -s nullglob globstar
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                found_templates+=("$file")
            fi
        done
        shopt -u nullglob globstar
    else
        # Direct file
        if [[ -f "$pattern" ]]; then
            found_templates+=("$pattern")
        else
            ninja_error "Template not found: $pattern"
            return 1
        fi
    fi

    if [[ ${#found_templates[@]} -eq 0 ]]; then
        ninja_error "No templates found matching: $pattern"
        return 1
    fi

    printf '%s\n' "${found_templates[@]}"
}

process_templates() {
    local context="$1"
    local all_templates=()

    # Discover all templates from patterns
    ninja_info "Discovering templates with ninja precision..."

    for pattern in "${TEMPLATES[@]}"; do
        while IFS= read -r template; do
            all_templates+=("$template")
        done < <(discover_templates "$pattern")
    done

    TEMPLATE_COUNT=${#all_templates[@]}

    if [[ $TEMPLATE_COUNT -eq 0 ]]; then
        ninja_error "No templates to render!"
        return 1
    fi

    ninja_success "Found ${BOLD}$TEMPLATE_COUNT${RESET}${GREEN} template(s)${RESET}"

    # Create output directory
    if [[ "$PREVIEW" == false ]] && [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$OUTPUT_DIR"
        ninja_verbose "Output directory: ${GREEN}$OUTPUT_DIR${RESET}"
    fi

    # Render each template
    echo ""
    ninja_say "Initiating stealth rendering sequence..."
    echo ""

    local success_count=0
    local fail_count=0

    for i in "${!all_templates[@]}"; do
        local template="${all_templates[$i]}"
        local template_name
        template_name=$(basename "$template")
        local output_name="${template_name%.j2}"
        output_name="${output_name%.jinja2}"
        output_name="${output_name%.jinja}"
        local output_file="$OUTPUT_DIR/$output_name"

        # Show progress
        ninja_progress $((i + 1)) "$TEMPLATE_COUNT" "$template_name"

        # Render template
        if render_template "$template" "$output_file" "$context"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    echo ""

    # Summary
    if [[ $fail_count -eq 0 ]]; then
        ninja_success "All $TEMPLATE_COUNT templates rendered successfully! ${STAR}"
    else
        ninja_warn "Rendered: $success_count success, $fail_count failed"
    fi

    return 0
}

##############################################################
# Main Function
##############################################################

main() {
    START_TIME=$(date +%s)

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -v|--var)
                parse_cli_var "$2"
                shift 2
                ;;
            -f|--file)
                VAR_FILE_ARG="$2"
                VAR_FILE_EXT="${VAR_FILE_ARG##*.}"

                case "$VAR_FILE_EXT" in
                    yaml|yml)
                        load_yaml_vars "$VAR_FILE_ARG"
                        ;;
                    json)
                        load_json_vars "$VAR_FILE_ARG"
                        ;;
                    *)
                        ninja_error "Unsupported file format: .$VAR_FILE_EXT (use .yaml, .yml, or .json)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -V|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--preview)
                PREVIEW=true
                shift
                ;;
            -s|--strict)
                STRICT=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -w|--watch)
                WATCH=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                ninja_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
            *)
                TEMPLATES+=("$1")
                shift
                ;;
        esac
    done

    # Show ninja banner
    print_ninja_banner

    if [[ "$VERBOSE" == true ]]; then
        print_ninja_art
    fi

    # Validate inputs
    if [[ ${#TEMPLATES[@]} -eq 0 ]]; then
        ninja_error "No templates specified!"
        echo "Use -h or --help for usage information"
        exit 1
    fi

    # Build context dictionary
    ninja_info "Gathering ninja scrolls and ancient wisdom..."

    local context
    if ! context=$(build_context_dict); then
        exit 1
    fi

    VAR_COUNT=$(echo "$context" | grep -o '"[^"]*":' | wc -l)

    if [[ "$VERBOSE" == true ]]; then
        ninja_verbose "Context dictionary built with ${CYAN}$VAR_COUNT${RESET} variables"
        echo "${DIM}$context${RESET}"
    fi

    ninja_success "Loaded ${BOLD}$VAR_COUNT${RESET}${GREEN} variable(s)${RESET}"

    # Show mode indicators
    [[ "$STRICT" == true ]] && ninja_warn "Strict mode: ${BOLD}ENABLED${RESET}"
    [[ "$DRY_RUN" == true ]] && ninja_warn "Dry run mode: ${BOLD}ENABLED${RESET}"
    [[ "$PREVIEW" == true ]] && ninja_info "Preview mode: ${BOLD}ENABLED${RESET}"

    # Process templates
    if ! process_templates "$context"; then
        exit 1
    fi

    # Calculate execution time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    echo ""
    ninja_success "Mission complete in ${BOLD}${duration}s${RESET} ${TARGET}"

    if [[ "$PREVIEW" == false ]] && [[ "$DRY_RUN" == false ]]; then
        ninja_info "Output directory: ${CYAN}${BOLD}$OUTPUT_DIR${RESET}"
    fi

    echo ""
    echo "${MAGENTA}${NINJA} The ninja vanishes into the shadows... ${KATANA}${RESET}"
    echo ""
}

# Execute main function
main "$@"
