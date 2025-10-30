#!/usr/bin/env bash

#############################################################################
# CSS Color Palette Generator (Pure Bash)
#
# Generate comprehensive color palettes with tints, shades, and tones
# No Node.js required - pure bash implementation
#
# Usage:
#   css_color_palette.sh <COLOR> [OPTIONS]
#
# Arguments:
#   COLOR               Base hex color (e.g., #3498db, 3498db)
#
# Options:
#   -p, --palette TYPE  Palette type: monochromatic, analogous, complementary,
#                       split-complementary, triadic, tetradic (default: monochromatic)
#   -o, --output FILE   Output file (default: ./colors.yaml)
#   -m, --mode MODE     Color mode: light, dark (default: light)
#   -s, --style STYLE   Generate style variations: shades, tints, tones, all
#   -n, --name NAME     Color palette name (default: auto-generated)
#   --scales N          Number of scale steps (default: 11)
#   -i, --interactive   Interactive mode
#   -v, --verbose       Verbose output with color preview
#   -h, --help          Show this help message
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
# Global Variables
# ============================================================================

BASE_COLOR=""
PALETTE_TYPE="monochromatic"
OUTPUT_FILE="./colors.yaml"
COLOR_MODE="light"
STYLE_TYPE="all"
PALETTE_NAME=""
SCALE_STEPS=11
INTERACTIVE=false
VERBOSE=false

# Associative arrays for storing palette data
declare -A PALETTE_DATA
declare -a COLOR_GROUPS

# ============================================================================
# Helper Functions
# ============================================================================

print_usage() {
    cat << EOF
${BOLD}CSS Color Palette Generator (Pure Bash)${RESET}

Generate comprehensive color palettes without Node.js dependencies.

${BOLD}USAGE:${RESET}
    $(basename "$0") COLOR [OPTIONS]

${BOLD}ARGUMENTS:${RESET}
    COLOR               Base hex color (e.g., #3498db, 3498db)

${BOLD}OPTIONS:${RESET}
    -p, --palette TYPE  Palette type: monochromatic, analogous, complementary,
                        split-complementary, triadic, tetradic
    -o, --output FILE   Output file (default: ./colors.yaml)
    -m, --mode MODE     Color mode: light, dark (default: light)
    -s, --style STYLE   Style: shades, tints, tones, all (default: all)
    -n, --name NAME     Palette name (default: auto-generated)
    --scales N          Number of scale steps (default: 11)
    -i, --interactive   Interactive mode
    -v, --verbose       Verbose output with color preview
    -h, --help          Show this help message

${BOLD}DEPENDENCIES:${RESET}
    bc                  For floating-point arithmetic

${BOLD}EXAMPLES:${RESET}
    $(basename "$0") "#3498db"
    $(basename "$0") "#3498db" -p triadic -o palette.json
    $(basename "$0") "ff5733" -p analogous -m dark

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

# Check for bc dependency
check_dependencies() {
    if ! command -v bc >/dev/null 2>&1; then
        error "bc is required but not found. Please install bc (apt-get install bc)"
    fi
}

# ============================================================================
# Math Utilities
# ============================================================================

# Floating point comparison
bc_calc() {
    local expr="$1"
    # Remove any leading/trailing whitespace
    expr=$(echo "$expr" | tr -d ' ')
    # Check if expression is empty
    if [[ -z "$expr" ]]; then
        echo "0"
        return
    fi
    echo "scale=6; $expr" | bc -l 2>/dev/null || echo "0"
}

# Boolean bc comparison (returns 0 for true, 1 for false)
bc_compare() {
    local result=$(echo "$1" | bc -l 2>/dev/null || echo "0")
    [[ "$result" == "1" ]]
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

# ============================================================================
# Color Validation and Normalization
# ============================================================================

validate_hex() {
    local hex="$1"
    hex="${hex#\#}"
    if [[ "$hex" =~ ^[0-9A-Fa-f]{3}$ ]] || [[ "$hex" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        return 0
    fi
    return 1
}

normalize_hex() {
    local hex="$1"
    hex="${hex#\#}"
    # Expand shorthand
    if [[ ${#hex} -eq 3 ]]; then
        hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"
    fi
    echo "#${hex^^}"
}

# ============================================================================
# Color Conversion Functions
# ============================================================================

# Convert hex to RGB (returns "r g b")
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

# Convert RGB to hex
rgb_to_hex() {
    local r=$(round "$1")
    local g=$(round "$2")
    local b=$(round "$3")

    # Clamp values
    r=$(clamp "$r" 0 255)
    g=$(clamp "$g" 0 255)
    b=$(clamp "$b" 0 255)

    # Use C locale to ensure proper number formatting
    LC_NUMERIC=C printf "#%02X%02X%02X" "$r" "$g" "$b"
}

# Convert RGB to HSL (returns "h s l")
rgb_to_hsl() {
    local r=$1 g=$2 b=$3

    # Normalize to 0-1
    r=$(bc_calc "$r / 255")
    g=$(bc_calc "$g / 255")
    b=$(bc_calc "$b / 255")

    local max=$(max "$r" "$(max "$g" "$b")")
    local min=$(min "$r" "$(min "$g" "$b")")
    local delta=$(bc_calc "$max - $min")

    local h=0 s=0 l
    l=$(bc_calc "($max + $min) / 2")

    if bc_compare "$delta != 0"; then
        # Calculate saturation
        if bc_compare "$l < 0.5"; then
            s=$(bc_calc "$delta / ($max + $min)")
        else
            s=$(bc_calc "$delta / (2 - $max - $min)")
        fi

        # Calculate hue
        if bc_compare "$max == $r"; then
            h=$(bc_calc "(($g - $b) / $delta) + (if ($g < $b) then 6 else 0)")
        elif bc_compare "$max == $g"; then
            h=$(bc_calc "(($b - $r) / $delta) + 2")
        else
            h=$(bc_calc "(($r - $g) / $delta) + 4")
        fi

        h=$(bc_calc "$h / 6")
    fi

    # Convert to degrees and percentages
    h=$(bc_calc "$h * 360")
    s=$(bc_calc "$s * 100")
    l=$(bc_calc "$l * 100")

    echo "$h $s $l"
}

# Helper for HSL to RGB conversion
hue_to_rgb() {
    local p=$1 q=$2 t=$3

    # Normalize t to 0-1
    if bc_compare "$t < 0"; then
        t=$(bc_calc "$t + 1")
    fi
    if bc_compare "$t > 1"; then
        t=$(bc_calc "$t - 1")
    fi

    if bc_compare "$t < 0.166666"; then
        echo "$(bc_calc "$p + ($q - $p) * 6 * $t")"
    elif bc_compare "$t < 0.5"; then
        echo "$q"
    elif bc_compare "$t < 0.666666"; then
        echo "$(bc_calc "$p + ($q - $p) * (0.666666 - $t) * 6")"
    else
        echo "$p"
    fi
}

# Convert HSL to RGB (returns "r g b")
hsl_to_rgb() {
    local h=$1 s=$2 l=$3

    # Normalize
    h=$(bc_calc "$h / 360")
    s=$(bc_calc "$s / 100")
    l=$(bc_calc "$l / 100")

    local r g b

    if bc_compare "$s == 0"; then
        # Achromatic (gray)
        r=$l
        g=$l
        b=$l
    else
        local q
        if bc_compare "$l < 0.5"; then
            q=$(bc_calc "$l * (1 + $s)")
        else
            q=$(bc_calc "$l + $s - $l * $s")
        fi

        local p=$(bc_calc "2 * $l - $q")

        r=$(hue_to_rgb "$p" "$q" "$(bc_calc "$h + 0.333333")")
        g=$(hue_to_rgb "$p" "$q" "$h")
        b=$(hue_to_rgb "$p" "$q" "$(bc_calc "$h - 0.333333")")
    fi

    # Convert to 0-255
    r=$(bc_calc "$r * 255")
    g=$(bc_calc "$g * 255")
    b=$(bc_calc "$b * 255")

    echo "$r $g $b"
}

# ============================================================================
# Color Manipulation Functions
# ============================================================================

# Adjust hue (degrees)
adjust_hue() {
    local h=$1 adjustment=$2
    h=$(bc_calc "$h + $adjustment")

    # Normalize to 0-360
    while bc_compare "$h < 0"; do
        h=$(bc_calc "$h + 360")
    done
    while bc_compare "$h >= 360"; do
        h=$(bc_calc "$h - 360")
    done

    echo "$h"
}

# Generate tint (mix with white)
generate_tint() {
    local hex="$1"
    local percentage=$2

    read -r r g b <<< "$(hex_to_rgb "$hex")"

    r=$(bc_calc "$r + (255 - $r) * ($percentage / 100)")
    g=$(bc_calc "$g + (255 - $g) * ($percentage / 100)")
    b=$(bc_calc "$b + (255 - $b) * ($percentage / 100)")

    rgb_to_hex "$r" "$g" "$b"
}

# Generate shade (mix with black)
generate_shade() {
    local hex="$1"
    local percentage=$2

    read -r r g b <<< "$(hex_to_rgb "$hex")"

    r=$(bc_calc "$r * (1 - $percentage / 100)")
    g=$(bc_calc "$g * (1 - $percentage / 100)")
    b=$(bc_calc "$b * (1 - $percentage / 100)")

    rgb_to_hex "$r" "$g" "$b"
}

# Generate tone (mix with gray)
generate_tone() {
    local hex="$1"
    local percentage=$2

    read -r r g b <<< "$(hex_to_rgb "$hex")"

    local gray=$(bc_calc "($r + $g + $b) / 3")

    r=$(bc_calc "$r + ($gray - $r) * ($percentage / 100)")
    g=$(bc_calc "$g + ($gray - $g) * ($percentage / 100)")
    b=$(bc_calc "$b + ($gray - $b) * ($percentage / 100)")

    rgb_to_hex "$r" "$g" "$b"
}

# Adjust lightness
adjust_lightness() {
    local hex="$1"
    local adjustment=$2

    read -r r g b <<< "$(hex_to_rgb "$hex")"
    read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"

    l=$(bc_calc "$l + $adjustment")
    l=$(clamp "$l" 0 100)

    read -r r g b <<< "$(hsl_to_rgb "$h" "$s" "$l")"
    rgb_to_hex "$r" "$g" "$b"
}

# Adjust saturation
adjust_saturation() {
    local hex="$1"
    local adjustment=$2

    read -r r g b <<< "$(hex_to_rgb "$hex")"
    read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"

    s=$(bc_calc "$s + $adjustment")
    s=$(clamp "$s" 0 100)

    read -r r g b <<< "$(hsl_to_rgb "$h" "$s" "$l")"
    rgb_to_hex "$r" "$g" "$b"
}

# ============================================================================
# Scale Generation
# ============================================================================

generate_color_scale() {
    local base_hex="$1"
    local group_name="$2"
    local style="$3"

    local -a scale_values=(50 100 200 300 400 500 600 700 800 900 950)
    local base_index=5  # 500 is the base

    # Set base color
    PALETTE_DATA["${group_name}.500"]="$base_hex"

    # Generate lighter variations (50-400)
    for i in {4..0}; do
        local step=$((base_index - i))
        local scale_val=${scale_values[$i]}
        local color

        if [[ "$style" == "tints" ]]; then
            local percentage=$(bc_calc "$step / $base_index * 85")
            color=$(generate_tint "$base_hex" "$percentage")
        elif [[ "$style" == "tones" ]]; then
            read -r r g b <<< "$(hex_to_rgb "$base_hex")"
            read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"
            local new_l=$(bc_calc "95 - $i * 8")
            local new_s=$(bc_calc "$(max 10 "$(bc_calc "$s - ($base_index - $i) * 5")")")
            read -r r g b <<< "$(hsl_to_rgb "$h" "$new_s" "$new_l")"
            color=$(rgb_to_hex "$r" "$g" "$b")
        else
            # Default: lighten
            local adjustment=$(bc_calc "$step * 12")
            color=$(adjust_lightness "$base_hex" "$adjustment")
            if [[ $i -le 2 ]]; then
                local sat_adj=$(bc_calc "-($base_index - $i) * 8")
                color=$(adjust_saturation "$color" "$sat_adj")
            fi
        fi

        PALETTE_DATA["${group_name}.${scale_val}"]="$color"
    done

    # Generate darker variations (600-950)
    for i in {6..10}; do
        local step=$((i - base_index))
        local scale_val=${scale_values[$i]}
        local color

        if [[ "$style" == "shades" ]]; then
            local percentage=$(bc_calc "$step / (${#scale_values[@]} - $base_index - 1) * 75")
            color=$(generate_shade "$base_hex" "$percentage")
        elif [[ "$style" == "tones" ]]; then
            read -r r g b <<< "$(hex_to_rgb "$base_hex")"
            read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"
            local new_l=$(bc_calc "45 - ($i - $base_index) * 7")
            new_l=$(max 5 "$new_l")
            local new_s=$(bc_calc "$(max 10 "$(bc_calc "$s - $step * 3")")")
            read -r r g b <<< "$(hsl_to_rgb "$h" "$new_s" "$new_l")"
            color=$(rgb_to_hex "$r" "$g" "$b")
        else
            # Default: darken
            local adjustment=$(bc_calc "-$step * 10")
            color=$(adjust_lightness "$base_hex" "$adjustment")
            if [[ $i -ge 9 ]]; then
                local sat_adj=$(bc_calc "-$step * 5")
                color=$(adjust_saturation "$color" "$sat_adj")
            fi
        fi

        PALETTE_DATA["${group_name}.${scale_val}"]="$color"
    done
}

# ============================================================================
# Palette Generation
# ============================================================================

generate_palette() {
    local base_hex="$1"
    local palette_type="$2"
    local style="$3"

    read -r r g b <<< "$(hex_to_rgb "$base_hex")"
    read -r h s l <<< "$(rgb_to_hsl "$r" "$g" "$b")"

    case "$palette_type" in
        monochromatic)
            COLOR_GROUPS=("primary")
            generate_color_scale "$base_hex" "primary" "$style"
            ;;

        analogous)
            COLOR_GROUPS=("primary" "analogous1" "analogous2")
            generate_color_scale "$base_hex" "primary" "$style"

            # Analogous 1: -30 degrees
            local h1=$(adjust_hue "$h" -30)
            read -r r g b <<< "$(hsl_to_rgb "$h1" "$s" "$l")"
            local color1=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$color1" "analogous1" "$style"

            # Analogous 2: +30 degrees
            local h2=$(adjust_hue "$h" 30)
            read -r r g b <<< "$(hsl_to_rgb "$h2" "$s" "$l")"
            local color2=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$color2" "analogous2" "$style"
            ;;

        complementary)
            COLOR_GROUPS=("primary" "complement")
            generate_color_scale "$base_hex" "primary" "$style"

            # Complement: 180 degrees
            local hc=$(adjust_hue "$h" 180)
            read -r r g b <<< "$(hsl_to_rgb "$hc" "$s" "$l")"
            local colorc=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$colorc" "complement" "$style"
            ;;

        split-complementary)
            COLOR_GROUPS=("primary" "split1" "split2")
            generate_color_scale "$base_hex" "primary" "$style"

            # Split 1: 150 degrees
            local hs1=$(adjust_hue "$h" 150)
            read -r r g b <<< "$(hsl_to_rgb "$hs1" "$s" "$l")"
            local colors1=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$colors1" "split1" "$style"

            # Split 2: 210 degrees
            local hs2=$(adjust_hue "$h" 210)
            read -r r g b <<< "$(hsl_to_rgb "$hs2" "$s" "$l")"
            local colors2=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$colors2" "split2" "$style"
            ;;

        triadic)
            COLOR_GROUPS=("primary" "triadic1" "triadic2")
            generate_color_scale "$base_hex" "primary" "$style"

            # Triadic 1: 120 degrees
            local ht1=$(adjust_hue "$h" 120)
            read -r r g b <<< "$(hsl_to_rgb "$ht1" "$s" "$l")"
            local colort1=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$colort1" "triadic1" "$style"

            # Triadic 2: 240 degrees
            local ht2=$(adjust_hue "$h" 240)
            read -r r g b <<< "$(hsl_to_rgb "$ht2" "$s" "$l")"
            local colort2=$(rgb_to_hex "$r" "$g" "$b")
            generate_color_scale "$colort2" "triadic2" "$style"
            ;;

        tetradic)
            COLOR_GROUPS=("primary" "tetradic1" "tetradic2" "tetradic3")
            generate_color_scale "$base_hex" "primary" "$style"

            # Tetradic colors: 90, 180, 270 degrees
            for deg in 90 180 270; do
                local idx=$((deg / 90))
                local hn=$(adjust_hue "$h" "$deg")
                read -r r g b <<< "$(hsl_to_rgb "$hn" "$s" "$l")"
                local colorn=$(rgb_to_hex "$r" "$g" "$b")
                generate_color_scale "$colorn" "tetradic${idx}" "$style"
            done
            ;;
    esac
}

# ============================================================================
# Output Functions
# ============================================================================

generate_yaml_output() {
    local name="$1"
    local type="$2"
    local mode="$3"
    local style="$4"
    local base="$5"

    cat << EOF
name: '$name'
type: '$type'
mode: '$mode'
style: '$style'
base: '$base'
colors:
EOF

    for group in "${COLOR_GROUPS[@]}"; do
        echo "  ${group}:"
        for scale in 50 100 200 300 400 500 600 700 800 900 950; do
            local key="${group}.${scale}"
            if [[ -n "${PALETTE_DATA[$key]:-}" ]]; then
                LC_NUMERIC=C printf "    %s: '%s'\n" "$scale" "${PALETTE_DATA[$key]}"
            fi
        done
    done

    cat << EOF
metadata:
  generated: '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
  generator: 'css_color_palette.sh'
  version: '1.0.0'
EOF
}

generate_json_output() {
    local name="$1"
    local type="$2"
    local mode="$3"
    local style="$4"
    local base="$5"

    echo "{"
    echo "  \"name\": \"$name\","
    echo "  \"type\": \"$type\","
    echo "  \"mode\": \"$mode\","
    echo "  \"style\": \"$style\","
    echo "  \"base\": \"$base\","
    echo "  \"colors\": {"

    local group_count=0
    for group in "${COLOR_GROUPS[@]}"; do
        ((group_count++))
        echo "    \"${group}\": {"

        local scale_count=0
        for scale in 50 100 200 300 400 500 600 700 800 900 950; do
            local key="${group}.${scale}"
            if [[ -n "${PALETTE_DATA[$key]:-}" ]]; then
                ((scale_count++))
                if [[ $scale_count -lt 11 ]]; then
                    echo "      \"$scale\": \"${PALETTE_DATA[$key]}\","
                else
                    echo "      \"$scale\": \"${PALETTE_DATA[$key]}\""
                fi
            fi
        done

        if [[ $group_count -lt ${#COLOR_GROUPS[@]} ]]; then
            echo "    },"
        else
            echo "    }"
        fi
    done

    echo "  },"
    echo "  \"metadata\": {"
    echo "    \"generated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "    \"generator\": \"css_color_palette_bash.sh\","
    echo "    \"version\": \"1.0.0\""
    echo "  }"
    echo "}"
}

# ============================================================================
# Display Functions
# ============================================================================

draw_color_swatch() {
    local hex="$1"
    local label="$2"
    local hex_clean="${hex#\#}"

    read -r r g b <<< "$(hex_to_rgb "$hex")"

    if [[ ${COLORS:-0} -ge 256 ]]; then
        local bg="\033[48;2;${r};${g};${b}m"
        local fg="\033[38;2;${r};${g};${b}m"
        local reset="\033[0m"

        # Determine text color based on luminance
        local luminance=$(bc_calc "(0.299*$r + 0.587*$g + 0.114*$b)/255")
        local text_color
        if bc_compare "$luminance > 0.5"; then
            text_color="\033[38;2;0;0;0m"
        else
            text_color="\033[38;2;255;255;255m"
        fi

        LC_NUMERIC=C printf "${bg}${text_color}  %-20s  ${reset} ${fg}%s${reset} %s\n" "$label" "■" "$hex"
    else
        LC_NUMERIC=C printf "  %-20s  %s\n" "$label" "$hex"
    fi
}

display_palette_preview() {
    if [[ "$VERBOSE" != "true" ]]; then
        return
    fi

    echo ""
    echo "${BOLD}================================================================${RESET}"
    echo "${BOLD}                   Color Palette Preview                        ${RESET}"
    echo "${BOLD}================================================================${RESET}"
    echo ""

    echo "${BOLD}Palette Name:${RESET} $PALETTE_NAME"
    echo "${BOLD}Type:${RESET} $PALETTE_TYPE"
    echo "${BOLD}Base Color:${RESET} $BASE_COLOR"
    echo ""

    for group in "${COLOR_GROUPS[@]}"; do
        echo "${BOLD}${CYAN}${group}:${RESET}"
        for scale in 50 100 200 300 400 500 600 700 800 900 950; do
            local key="${group}.${scale}"
            if [[ -n "${PALETTE_DATA[$key]:-}" ]]; then
                draw_color_swatch "${PALETTE_DATA[$key]}" "${group}.${scale}"
            fi
        done
        echo ""
    done

    echo "${BOLD}----------------------------------------------------------------${RESET}"
    echo ""
}

# ============================================================================
# Interactive Mode
# ============================================================================

interactive_mode() {
    echo ""
    echo "${BOLD}${BLUE}+================================================================+${RESET}"
    echo "${BOLD}${BLUE}|             CSS Color Palette Generator (Interactive)         |${RESET}"
    echo "${BOLD}${BLUE}+================================================================+${RESET}"
    echo ""

    while true; do
        echo -n "${BOLD}Enter base color${RESET} ${DIM}(hex, or 'q' to quit):${RESET} "
        read -r color_input

        if [[ "$color_input" =~ ^[qQ]$ ]]; then
            echo ""
            success "Goodbye!"
            exit 0
        fi

        if [[ -z "$color_input" ]]; then
            continue
        fi

        if ! validate_hex "$color_input"; then
            warning "Invalid hex color format"
            continue
        fi

        local hex=$(normalize_hex "$color_input")

        echo ""
        echo -n "${BOLD}Palette type${RESET} ${DIM}[monochromatic]:${RESET} "
        read -r palette_input
        palette_input=${palette_input:-monochromatic}

        echo -n "${BOLD}Output file${RESET} ${DIM}[./colors.yaml]:${RESET} "
        read -r output_input
        output_input=${output_input:-./colors.yaml}

        echo -n "${BOLD}Style${RESET} ${DIM}[all]:${RESET} "
        read -r style_input
        style_input=${style_input:-all}

        echo ""
        info "Generating palette..."

        # Reset palette data
        PALETTE_DATA=()
        COLOR_GROUPS=()

        BASE_COLOR="$hex"
        PALETTE_TYPE="$palette_input"
        OUTPUT_FILE="$output_input"
        STYLE_TYPE="$style_input"
        PALETTE_NAME="${palette_input}-${hex//\#/}"

        generate_palette "$BASE_COLOR" "$PALETTE_TYPE" "$STYLE_TYPE"

        VERBOSE=true
        display_palette_preview
        VERBOSE=false

        # Generate output
        local extension="${OUTPUT_FILE##*.}"
        if [[ "$extension" == "json" ]]; then
            generate_json_output "$PALETTE_NAME" "$PALETTE_TYPE" "$COLOR_MODE" "$STYLE_TYPE" "$BASE_COLOR" > "$OUTPUT_FILE"
        else
            generate_yaml_output "$PALETTE_NAME" "$PALETTE_TYPE" "$COLOR_MODE" "$STYLE_TYPE" "$BASE_COLOR" > "$OUTPUT_FILE"
        fi

        success "Palette saved to: ${BOLD}$OUTPUT_FILE${RESET}"

        # Count colors
        local total=0
        for key in "${!PALETTE_DATA[@]}"; do
            ((total++))
        done
        info "Total colors generated: $total"

        echo ""
        echo -n "${DIM}Press Enter to continue...${RESET}"
        read -r
        echo ""
    done
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    # Check dependencies
    check_dependencies

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -p|--palette)
                PALETTE_TYPE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -m|--mode)
                COLOR_MODE="$2"
                shift 2
                ;;
            -s|--style)
                STYLE_TYPE="$2"
                shift 2
                ;;
            -n|--name)
                PALETTE_NAME="$2"
                shift 2
                ;;
            --scales)
                SCALE_STEPS="$2"
                shift 2
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                error "Unknown option: $1. Use --help for usage information."
                ;;
            *)
                BASE_COLOR="$1"
                shift
                ;;
        esac
    done

    # Interactive mode
    if [[ "$INTERACTIVE" == "true" ]]; then
        interactive_mode
        exit 0
    fi

    # Validate inputs
    if [[ -z "$BASE_COLOR" ]]; then
        error "No base color specified. Use --help for usage information."
    fi

    if ! validate_hex "$BASE_COLOR"; then
        error "Invalid hex color format: $BASE_COLOR"
    fi

    # Normalize color
    BASE_COLOR=$(normalize_hex "$BASE_COLOR")

    # Auto-generate palette name if not provided
    if [[ -z "$PALETTE_NAME" ]]; then
        PALETTE_NAME="${PALETTE_TYPE}-${BASE_COLOR//\#/}"
    fi

    # Validate palette type
    case "$PALETTE_TYPE" in
        monochromatic|analogous|complementary|split-complementary|triadic|tetradic)
            ;;
        *)
            error "Invalid palette type: $PALETTE_TYPE"
            ;;
    esac

    # Validate style type
    case "$STYLE_TYPE" in
        all|shades|tints|tones)
            ;;
        *)
            error "Invalid style type: $STYLE_TYPE"
            ;;
    esac

    # Generate palette
    if [[ "$VERBOSE" == "true" ]]; then
        info "Generating $PALETTE_TYPE palette from $BASE_COLOR..."
    fi

    generate_palette "$BASE_COLOR" "$PALETTE_TYPE" "$STYLE_TYPE"

    # Display preview if verbose
    display_palette_preview

    # Generate output file
    local extension="${OUTPUT_FILE##*.}"
    if [[ "$extension" == "json" ]]; then
        generate_json_output "$PALETTE_NAME" "$PALETTE_TYPE" "$COLOR_MODE" "$STYLE_TYPE" "$BASE_COLOR" > "$OUTPUT_FILE"
    else
        generate_yaml_output "$PALETTE_NAME" "$PALETTE_TYPE" "$COLOR_MODE" "$STYLE_TYPE" "$BASE_COLOR" > "$OUTPUT_FILE"
    fi

    success "Palette saved to: ${BOLD}$OUTPUT_FILE${RESET}"

    if [[ "$VERBOSE" == "true" ]]; then
        local total=0
        for key in "${!PALETTE_DATA[@]}"; do
            ((total++))
        done
        info "Total colors generated: $total"
    fi
}

# Run main function
main "$@"
