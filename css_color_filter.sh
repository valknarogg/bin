#!/usr/bin/env bash

#############################################################################
# CSS Color Filter Generator
#
# Generate CSS filter values to transform black elements into any target color
# No Node.js required - pure bash implementation
#
# Usage:
#   css_color_filter.sh [COLOR]
#   css_color_filter.sh -i        # Interactive mode
#   css_color_filter.sh --help    # Show help
#
# Arguments:
#   COLOR               Hex color (e.g., #FF0000, ff0000) or RGB (e.g., 255,0,0)
#
# Options:
#   -i, --interactive   Interactive mode with colored preview
#   -r, --raw           Output only the CSS filter (for piping)
#   -c, --copy          Copy result to clipboard automatically
#   -h, --help          Show this help message
#
# Examples:
#   css_color_filter.sh "#FF5733"
#   css_color_filter.sh ff5733
#   css_color_filter.sh "255,87,51"
#   css_color_filter.sh -i
#
# Dependencies:
#   bc                  For floating-point arithmetic
#   jq                  For JSON formatting (optional)
#
#############################################################################

set -euo pipefail

# ============================================================================
# Color Definitions
# ============================================================================

RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" DIM="" RESET=""
COLORS=0

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

# ============================================================================
# Helper Functions
# ============================================================================

print_usage() {
    cat << EOF
${BOLD}CSS Color Filter Generator${RESET}

Generate CSS filter values to transform black elements into any target color.

${BOLD}USAGE:${RESET}
    $(basename "$0") [OPTIONS] [COLOR]

${BOLD}ARGUMENTS:${RESET}
    COLOR               Hex color (e.g., #FF0000, ff0000) or RGB (e.g., 255,0,0)

${BOLD}OPTIONS:${RESET}
    -i, --interactive   Interactive mode with colored preview
    -r, --raw           Output only the CSS filter (for piping)
    -c, --copy          Copy result to clipboard automatically
    -h, --help          Show this help message

${BOLD}EXAMPLES:${RESET}
    $(basename "$0") "#FF5733"
    $(basename "$0") ff5733
    $(basename "$0") "255,87,51"
    $(basename "$0") -i

${BOLD}NOTE:${RESET}
    This tool generates filters that work on ${BOLD}black${RESET} elements.
    To use with non-black elements, prepend: ${DIM}brightness(0) saturate(100%)${RESET}

${BOLD}ALGORITHM:${RESET}
    Uses SPSA (Simultaneous Perturbation Stochastic Approximation) to find
    optimal filter combinations that minimize color difference in RGB and HSL.

${BOLD}DEPENDENCIES:${RESET}
    bc                  For floating-point arithmetic
    jq                  For JSON formatting (optional)

EOF
}

error() {
    echo "${RED}${BOLD}Error:${RESET} $1" >&2
    exit 1
}

info() {
    echo "${BLUE}${BOLD}==>${RESET} $1"
}

success() {
    echo "${GREEN}${BOLD}[OK]${RESET} $1"
}

warning() {
    echo "${YELLOW}${BOLD}[WARN]${RESET} $1"
}

check_dependencies() {
    if ! command -v bc >/dev/null 2>&1; then
        error "bc is required but not found. Please install bc (apt-get install bc)"
    fi
}

# ============================================================================
# Math Utilities
# ============================================================================

bc_calc() {
    local expr="$1"
    expr=$(echo "$expr" | tr -d ' ')
    if [[ -z "$expr" ]]; then
        echo "0"
        return
    fi
    echo "scale=10; $expr" | bc -l 2>/dev/null || echo "0"
}

bc_compare() {
    local result=$(echo "$1" | bc -l 2>/dev/null || echo "0")
    [[ "$result" == "1" ]]
}

abs_val() {
    local val="$1"
    if bc_compare "$val < 0"; then
        echo "$(bc_calc "-1 * $val")"
    else
        echo "$val"
    fi
}

min() {
    local a=$1 b=$2
    if bc_compare "$a < $b"; then
        echo "$a"
    else
        echo "$b"
    fi
}

max() {
    local a=$1 b=$2
    if bc_compare "$a > $b"; then
        echo "$a"
    else
        echo "$b"
    fi
}

clamp() {
    local val=$1 min_val=$2 max_val=$3
    val=$(max "$val" "$min_val")
    val=$(min "$val" "$max_val")
    echo "$val"
}

round() {
    LC_NUMERIC=C printf "%.0f" "$1"
}

# Generate random number between 0 and 1
random_float() {
    echo "scale=10; $RANDOM / 32767" | bc -l
}

# ============================================================================
# Color Validation
# ============================================================================

validate_hex() {
    local hex="$1"
    hex="${hex#\#}"
    if [[ "$hex" =~ ^[0-9A-Fa-f]{3}$ ]] || [[ "$hex" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        return 0
    fi
    return 1
}

validate_rgb() {
    local rgb="$1"
    if [[ "$rgb" =~ ^[0-9]{1,3},[0-9]{1,3},[0-9]{1,3}$ ]]; then
        IFS=',' read -r r g b <<< "$rgb"
        if [[ $r -le 255 && $g -le 255 && $b -le 255 ]]; then
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# Color Conversion
# ============================================================================

hex_to_rgb() {
    local hex="$1"
    hex="${hex#\#}"

    if [[ ${#hex} -eq 3 ]]; then
        hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"
    fi

    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    echo "$r $g $b"
}

rgb_to_hex() {
    local r=$(round "$1")
    local g=$(round "$2")
    local b=$(round "$3")

    r=$(clamp "$r" 0 255)
    g=$(clamp "$g" 0 255)
    b=$(clamp "$b" 0 255)

    LC_NUMERIC=C printf "#%02X%02X%02X" "$r" "$g" "$b"
}

rgb_to_hsl() {
    local r=$1 g=$2 b=$3

    r=$(bc_calc "$r / 255")
    g=$(bc_calc "$g / 255")
    b=$(bc_calc "$b / 255")

    local max=$(max "$r" "$(max "$g" "$b")")
    local min=$(min "$r" "$(min "$g" "$b")")
    local delta=$(bc_calc "$max - $min")

    local h=0 s=0 l
    l=$(bc_calc "($max + $min) / 2")

    if bc_compare "$delta != 0"; then
        if bc_compare "$l < 0.5"; then
            s=$(bc_calc "$delta / ($max + $min)")
        else
            s=$(bc_calc "$delta / (2 - $max - $min)")
        fi

        if bc_compare "$max == $r"; then
            h=$(bc_calc "(($g - $b) / $delta) + (if ($g < $b) then 6 else 0)")
        elif bc_compare "$max == $g"; then
            h=$(bc_calc "(($b - $r) / $delta) + 2")
        else
            h=$(bc_calc "(($r - $g) / $delta) + 4")
        fi

        h=$(bc_calc "$h / 6")
    fi

    h=$(bc_calc "$h * 100")
    s=$(bc_calc "$s * 100")
    l=$(bc_calc "$l * 100")

    echo "$h $s $l"
}

# ============================================================================
# Color Class Implementation
# ============================================================================

# Global color state (r, g, b)
declare -a COLOR_STATE

color_set() {
    local r=$(clamp "$1" 0 255)
    local g=$(clamp "$2" 0 255)
    local b=$(clamp "$3" 0 255)
    COLOR_STATE=("$r" "$g" "$b")
}

color_get_rgb() {
    echo "${COLOR_STATE[0]} ${COLOR_STATE[1]} ${COLOR_STATE[2]}"
}

# Matrix multiplication for color transformations
color_multiply() {
    local r=${COLOR_STATE[0]}
    local g=${COLOR_STATE[1]}
    local b=${COLOR_STATE[2]}

    # Matrix passed as arguments (9 values)
    local m=("$@")

    local new_r=$(bc_calc "$r * ${m[0]} + $g * ${m[1]} + $b * ${m[2]}")
    local new_g=$(bc_calc "$r * ${m[3]} + $g * ${m[4]} + $b * ${m[5]}")
    local new_b=$(bc_calc "$r * ${m[6]} + $g * ${m[7]} + $b * ${m[8]}")

    new_r=$(clamp "$new_r" 0 255)
    new_g=$(clamp "$new_g" 0 255)
    new_b=$(clamp "$new_b" 0 255)

    COLOR_STATE=("$new_r" "$new_g" "$new_b")
}

# CSS filter functions

color_invert() {
    local value=${1:-1}
    local r=${COLOR_STATE[0]}
    local g=${COLOR_STATE[1]}
    local b=${COLOR_STATE[2]}

    r=$(bc_calc "($value + $r / 255 * (1 - 2 * $value)) * 255")
    g=$(bc_calc "($value + $g / 255 * (1 - 2 * $value)) * 255")
    b=$(bc_calc "($value + $b / 255 * (1 - 2 * $value)) * 255")

    color_set "$r" "$g" "$b"
}

color_sepia() {
    local value=${1:-1}
    color_multiply \
        "$(bc_calc "0.393 + 0.607 * (1 - $value)")" \
        "$(bc_calc "0.769 - 0.769 * (1 - $value)")" \
        "$(bc_calc "0.189 - 0.189 * (1 - $value)")" \
        "$(bc_calc "0.349 - 0.349 * (1 - $value)")" \
        "$(bc_calc "0.686 + 0.314 * (1 - $value)")" \
        "$(bc_calc "0.168 - 0.168 * (1 - $value)")" \
        "$(bc_calc "0.272 - 0.272 * (1 - $value)")" \
        "$(bc_calc "0.534 - 0.534 * (1 - $value)")" \
        "$(bc_calc "0.131 + 0.869 * (1 - $value)")"
}

color_saturate() {
    local value=${1:-1}
    color_multiply \
        "$(bc_calc "0.213 + 0.787 * $value")" \
        "$(bc_calc "0.715 - 0.715 * $value")" \
        "$(bc_calc "0.072 - 0.072 * $value")" \
        "$(bc_calc "0.213 - 0.213 * $value")" \
        "$(bc_calc "0.715 + 0.285 * $value")" \
        "$(bc_calc "0.072 - 0.072 * $value")" \
        "$(bc_calc "0.213 - 0.213 * $value")" \
        "$(bc_calc "0.715 - 0.715 * $value")" \
        "$(bc_calc "0.072 + 0.928 * $value")"
}

color_hue_rotate() {
    local angle=${1:-0}
    angle=$(bc_calc "$angle / 180 * 3.14159265359")

    local sin=$(echo "s($angle)" | bc -l)
    local cos=$(echo "c($angle)" | bc -l)

    color_multiply \
        "$(bc_calc "0.213 + $cos * 0.787 - $sin * 0.213")" \
        "$(bc_calc "0.715 - $cos * 0.715 - $sin * 0.715")" \
        "$(bc_calc "0.072 - $cos * 0.072 + $sin * 0.928")" \
        "$(bc_calc "0.213 - $cos * 0.213 + $sin * 0.143")" \
        "$(bc_calc "0.715 + $cos * 0.285 + $sin * 0.140")" \
        "$(bc_calc "0.072 - $cos * 0.072 - $sin * 0.283")" \
        "$(bc_calc "0.213 - $cos * 0.213 - $sin * 0.787")" \
        "$(bc_calc "0.715 - $cos * 0.715 + $sin * 0.715")" \
        "$(bc_calc "0.072 + $cos * 0.928 + $sin * 0.072")"
}

color_brightness() {
    local value=${1:-1}
    local r=${COLOR_STATE[0]}
    local g=${COLOR_STATE[1]}
    local b=${COLOR_STATE[2]}

    r=$(bc_calc "$r * $value")
    g=$(bc_calc "$g * $value")
    b=$(bc_calc "$b * $value")

    color_set "$r" "$g" "$b"
}

color_contrast() {
    local value=${1:-1}
    local slope="$value"
    local intercept=$(bc_calc "-(0.5 * $value) + 0.5")

    local r=${COLOR_STATE[0]}
    local g=${COLOR_STATE[1]}
    local b=${COLOR_STATE[2]}

    r=$(bc_calc "$r * $slope + $intercept * 255")
    g=$(bc_calc "$g * $slope + $intercept * 255")
    b=$(bc_calc "$b * $slope + $intercept * 255")

    color_set "$r" "$g" "$b"
}

# ============================================================================
# Solver Implementation
# ============================================================================

# Target color
declare -a TARGET_RGB
declare -a TARGET_HSL

# Calculate loss between current color and target
calculate_loss() {
    local -a filters=("$@")

    # Reset to black
    color_set 0 0 0

    # Apply filters
    color_invert "$(bc_calc "${filters[0]} / 100")"
    color_sepia "$(bc_calc "${filters[1]} / 100")"
    color_saturate "$(bc_calc "${filters[2]} / 100")"
    color_hue_rotate "$(bc_calc "${filters[3]} * 3.6")"
    color_brightness "$(bc_calc "${filters[4]} / 100")"
    color_contrast "$(bc_calc "${filters[5]} / 100")"

    # Get resulting color
    read -r r g b <<< "$(color_get_rgb)"
    read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"

    # Calculate color difference
    local loss=0
    loss=$(bc_calc "$loss + $(abs_val "$(bc_calc "$r - ${TARGET_RGB[0]}")")")
    loss=$(bc_calc "$loss + $(abs_val "$(bc_calc "$g - ${TARGET_RGB[1]}")")")
    loss=$(bc_calc "$loss + $(abs_val "$(bc_calc "$b - ${TARGET_RGB[2]}")")")
    loss=$(bc_calc "$loss + $(abs_val "$(bc_calc "$h - ${TARGET_HSL[0]}")")")
    loss=$(bc_calc "$loss + $(abs_val "$(bc_calc "$s - ${TARGET_HSL[1]}")")")
    loss=$(bc_calc "$loss + $(abs_val "$(bc_calc "$l - ${TARGET_HSL[2]}")")")

    echo "$loss"
}

# Fix filter values to valid ranges
fix_filter_value() {
    local value=$1
    local idx=$2
    local max=100

    if [[ $idx -eq 2 ]]; then
        max=7500  # saturate
    elif [[ $idx -eq 4 ]] || [[ $idx -eq 5 ]]; then
        max=200  # brightness, contrast
    fi

    if [[ $idx -eq 3 ]]; then
        # hue-rotate: wrap around
        while bc_compare "$value > $max"; do
            value=$(bc_calc "$value - $max")
        done
        while bc_compare "$value < 0"; do
            value=$(bc_calc "$value + $max")
        done
    else
        value=$(clamp "$value" 0 "$max")
    fi

    echo "$value"
}

# SPSA optimization
spsa() {
    local A=$1
    local c=$2
    shift 2
    local -a a=("$1" "$2" "$3" "$4" "$5" "$6")
    shift 6
    local -a values=("$1" "$2" "$3" "$4" "$5" "$6")
    shift 6
    local iters=$1

    local alpha=1
    local gamma=0.16666666666666666

    local -a best=("${values[@]}")
    local best_loss=999999

    for ((k=0; k<iters; k++)); do
        local ck=$(bc_calc "$c / ($k + 1) ^ $gamma")

        local -a deltas
        local -a high_args
        local -a low_args

        for i in {0..5}; do
            # Random delta: 1 or -1
            if [[ $((RANDOM % 2)) -eq 0 ]]; then
                deltas[$i]=1
            else
                deltas[$i]=-1
            fi

            high_args[$i]=$(bc_calc "${values[$i]} + $ck * ${deltas[$i]}")
            low_args[$i]=$(bc_calc "${values[$i]} - $ck * ${deltas[$i]}")
        done

        local loss_high=$(calculate_loss "${high_args[@]}")
        local loss_low=$(calculate_loss "${low_args[@]}")
        local loss_diff=$(bc_calc "$loss_high - $loss_low")

        for i in {0..5}; do
            local g=$(bc_calc "$loss_diff / (2 * $ck) * ${deltas[$i]}")
            local ak=$(bc_calc "${a[$i]} / ($A + $k + 1) ^ $alpha")
            values[$i]=$(bc_calc "${values[$i]} - $ak * $g")
            values[$i]=$(fix_filter_value "${values[$i]}" "$i")
        done

        local loss=$(calculate_loss "${values[@]}")

        if bc_compare "$loss < $best_loss"; then
            best=("${values[@]}")
            best_loss="$loss"
        fi
    done

    echo "${best[@]} $best_loss"
}

# Solve wide search
solve_wide() {
    local A=5
    local c=15
    local -a a=(60 180 18000 600 1.2 1.2)

    local -a best_values
    local best_loss=999999

    for ((i=0; i<3; i++)); do
        local -a initial=(50 20 3750 50 100 100)

        read -r -a result <<< "$(spsa $A $c "${a[@]}" "${initial[@]}" 1000)"

        # Last element is loss
        local loss="${result[6]}"

        if bc_compare "$loss < $best_loss"; then
            best_values=("${result[@]:0:6}")
            best_loss="$loss"
        fi

        # Break if good enough
        if bc_compare "$best_loss <= 25"; then
            break
        fi
    done

    echo "${best_values[@]} $best_loss"
}

# Solve narrow search
solve_narrow() {
    local -a wide=("$@")
    local wide_loss="${wide[6]}"

    local A="$wide_loss"
    local c=2
    local A1=$(bc_calc "$A + 1")
    local -a a
    a[0]=$(bc_calc "0.25 * $A1")
    a[1]=$(bc_calc "0.25 * $A1")
    a[2]="$A1"
    a[3]=$(bc_calc "0.25 * $A1")
    a[4]=$(bc_calc "0.2 * $A1")
    a[5]=$(bc_calc "0.2 * $A1")

    local -a values=("${wide[@]:0:6}")

    spsa "$A" "$c" "${a[@]}" "${values[@]}" 500
}

# Main solve function
solve_filters() {
    local target_hex="$1"

    # Set target
    read -r r g b <<< "$(hex_to_rgb "$target_hex")"
    TARGET_RGB=("$r" "$g" "$b")
    read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"
    TARGET_HSL=("$h" "$s" "$l")

    # Solve
    local -a wide
    read -r -a wide <<< "$(solve_wide)"

    local -a narrow
    read -r -a narrow <<< "$(solve_narrow "${wide[@]}")"

    # Format output
    local -a values=("${narrow[@]:0:6}")
    local loss="${narrow[6]}"

    # Generate CSS
    local filter="invert($(round "${values[0]}")%)"
    filter="$filter sepia($(round "${values[1]}")%)"
    filter="$filter saturate($(round "${values[2]}")%)"
    filter="$filter hue-rotate($(round "$(bc_calc "${values[3]} * 3.6")")deg)"
    filter="$filter brightness($(round "${values[4]}")%)"
    filter="$filter contrast($(round "${values[5]}")%)"

    echo "$filter|$loss"
}

# ============================================================================
# Display Functions
# ============================================================================

draw_color_block() {
    local hex="$1"
    local label="$2"

    read -r r g b <<< "$(hex_to_rgb "$hex")"

    if [[ ${COLORS:-0} -ge 256 ]]; then
        local bg_color="\033[48;2;${r};${g};${b}m"
        local reset="\033[0m"
        echo -e "${BOLD}${label}${RESET}"
        echo -e "${bg_color}          ${reset}"
        echo -e "${bg_color}          ${reset}"
        echo -e "${bg_color}          ${reset}"
        echo ""
    fi
}

copy_to_clipboard() {
    local text="$1"

    if command -v xclip >/dev/null 2>&1; then
        echo -n "$text" | xclip -selection clipboard
        return 0
    elif command -v xsel >/dev/null 2>&1; then
        echo -n "$text" | xsel --clipboard
        return 0
    elif command -v wl-copy >/dev/null 2>&1; then
        echo -n "$text" | wl-copy
        return 0
    elif command -v pbcopy >/dev/null 2>&1; then
        echo -n "$text" | pbcopy
        return 0
    fi

    return 1
}

display_result() {
    local hex="$1"
    local filter="$2"
    local loss="$3"
    local raw_mode="${4:-false}"

    if [[ "$raw_mode" == "true" ]]; then
        echo "filter: $filter;"
        return
    fi

    echo ""
    echo "${BOLD}================================================================${RESET}"
    echo "${BOLD}                   CSS Color Filter Generator                   ${RESET}"
    echo "${BOLD}================================================================${RESET}"
    echo ""

    read -r r g b <<< "$(hex_to_rgb "$hex")"
    echo "${BOLD}Target Color:${RESET}"
    echo "  Hex:  ${CYAN}${hex}${RESET}"
    echo "  RGB:  ${CYAN}rgb($r, $g, $b)${RESET}"
    echo ""

    if [[ ${COLORS:-0} -ge 256 ]]; then
        draw_color_block "$hex" "Preview:"
    fi

    echo "${BOLD}Generated CSS Filter:${RESET}"
    echo "${GREEN}filter: ${filter};${RESET}"
    echo ""

    local loss_float=$(LC_NUMERIC=C printf "%.1f" "$loss")
    echo "${BOLD}Accuracy:${RESET}"
    echo -n "  Loss: ${YELLOW}${loss_float}${RESET} "

    if bc_compare "$loss < 1"; then
        echo "${GREEN}(Perfect match!)${RESET}"
    elif bc_compare "$loss < 5"; then
        echo "${GREEN}(Excellent match)${RESET}"
    elif bc_compare "$loss < 15"; then
        echo "${YELLOW}(Good match - consider re-running)${RESET}"
    else
        echo "${RED}(Poor match - try running again)${RESET}"
    fi

    echo ""
    echo "${BOLD}----------------------------------------------------------------${RESET}"
    echo "${DIM}Note: This filter works on black elements. For non-black elements,"
    echo "      prepend: brightness(0) saturate(100%)${RESET}"
    echo "${BOLD}----------------------------------------------------------------${RESET}"
    echo ""
}

# ============================================================================
# Interactive Mode
# ============================================================================

interactive_mode() {
    echo ""
    echo "${BOLD}${BLUE}+================================================================+${RESET}"
    echo "${BOLD}${BLUE}|           CSS Color Filter Generator (Interactive)            |${RESET}"
    echo "${BOLD}${BLUE}+================================================================+${RESET}"
    echo ""

    while true; do
        echo -n "${BOLD}Enter a color${RESET} ${DIM}(hex or rgb, or 'q' to quit):${RESET} "
        read -r color_input

        if [[ "$color_input" =~ ^[qQ]$ ]]; then
            echo ""
            success "Goodbye!"
            exit 0
        fi

        if [[ -z "$color_input" ]]; then
            continue
        fi

        process_color "$color_input" "false" "true"

        echo ""
        echo -n "${DIM}Press Enter to continue...${RESET}"
        read -r
        echo ""
    done
}

# ============================================================================
# Color Processing
# ============================================================================

process_color() {
    local color_input="$1"
    local raw_mode="${2:-false}"
    local auto_copy="${3:-false}"

    local r g b hex

    if validate_hex "$color_input"; then
        hex="$color_input"
        [[ "$hex" != \#* ]] && hex="#$hex"
        # Expand shorthand
        hex="${hex#\#}"
        if [[ ${#hex} -eq 3 ]]; then
            hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"
        fi
        hex="#${hex^^}"
    elif validate_rgb "$color_input"; then
        IFS=',' read -r r g b <<< "$color_input"
        hex=$(rgb_to_hex "$r" "$g" "$b")
    else
        error "Invalid color format. Use hex (e.g., #FF0000) or RGB (e.g., 255,0,0)"
    fi

    if [[ "$raw_mode" != "true" ]]; then
        info "Calculating optimal CSS filter for $hex..."
        echo ""
    fi

    local result
    result=$(solve_filters "$hex")

    IFS='|' read -r filter loss <<< "$result"

    display_result "$hex" "$filter" "$loss" "$raw_mode"

    if [[ "$auto_copy" == "true" ]]; then
        if copy_to_clipboard "filter: $filter;"; then
            success "CSS filter copied to clipboard!"
        else
            warning "Could not copy to clipboard (install xclip, xsel, wl-copy, or pbcopy)"
        fi
    fi
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    check_dependencies

    local color_input=""
    local interactive=false
    local raw_mode=false
    local auto_copy=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -r|--raw)
                raw_mode=true
                shift
                ;;
            -c|--copy)
                auto_copy=true
                shift
                ;;
            -*)
                error "Unknown option: $1. Use --help for usage information."
                ;;
            *)
                color_input="$1"
                shift
                ;;
        esac
    done

    if [[ "$interactive" == "true" ]]; then
        interactive_mode
        exit 0
    fi

    if [[ -z "$color_input" ]]; then
        error "No color specified. Use --help for usage information."
    fi

    process_color "$color_input" "$raw_mode" "$auto_copy"
}

main "$@"
