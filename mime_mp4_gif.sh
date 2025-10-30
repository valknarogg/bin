#!/usr/bin/env bash

# mime_mp4_gif.sh - Advanced MP4 to Animated GIF converter
# Converts MP4 videos to GIFs with sophisticated keyframe extraction,
# interpolation algorithms, and scheduling distributions

set -euo pipefail

# Default values
KEYFRAMES=10
INPUT_SCHEDULES=1
TRANSITION="linear"
SCHEDULE="uniform"
MAGIC="none"
KEYFRAME_DURATION=100
INPUT_FILE=""
OUTPUT_FILE=""
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Available algorithms
TRANSITIONS=("linear" "sinoid" "cubic" "quadratic" "exponential" "bounce" "elastic")
SCHEDULES=("uniform" "front-load" "back-load" "center-peak" "edge-peak" "fibonacci" "golden-ratio")
MAGICS=("none" "psychedelic" "dither-bloom" "edge-glow" "temporal-blur" "chromatic-shift" "vaporwave")

#############################################################################
# Helper Functions
#############################################################################

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] INPUT_FILE [OUTPUT_FILE]

Convert MP4 videos to animated GIFs with advanced frame extraction algorithms.

Arguments:
    INPUT_FILE              Input MP4 video file (required)
    OUTPUT_FILE             Output GIF file (optional, defaults to INPUT_FILE.gif)

Options:
    -k, --keyframes N       Number of keyframes to extract (default: 10)
    -d, --keyframe-duration MS  Duration of each frame in milliseconds (default: 100)
                            Valid range: 1-30000 ms
                            Lower values = faster animation
                            Higher values = slower animation
    -i, --input-schedules N Number of input schedules (default: 1)
                            1 schedule = entire video duration
                            N schedules = divide video into N segments
    -t, --transition TYPE   Interpolation function for frame timing
                            Available: ${TRANSITIONS[*]}
                            (default: linear)
    -s, --schedule TYPE     Algorithm to distribute keyframes across schedules
                            Available: ${SCHEDULES[*]}
                            (default: uniform)
    -m, --magic TYPE        Apply magical effects to the GIF
                            Available: ${MAGICS[*]}
                            (default: none)
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

Examples:
    # Basic conversion with 15 keyframes
    $(basename "$0") -k 15 video.mp4

    # Fast animation with 50ms per frame
    $(basename "$0") -k 20 -d 50 video.mp4

    # Slow animation with 500ms per frame
    $(basename "$0") -k 10 -d 500 video.mp4

    # Use sinusoidal transition with center-peak distribution
    $(basename "$0") -t sinoid -s center-peak -k 20 video.mp4

    # Apply psychedelic magic with fibonacci distribution
    $(basename "$0") -m psychedelic -s fibonacci -k 13 video.mp4 trippy.gif

    # Complex: 3 schedules with cubic interpolation and edge glow
    $(basename "$0") -i 3 -t cubic -s front-load -m edge-glow -k 30 video.mp4

EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "$@"
    fi
}

validate_enum() {
    local value="$1"
    local array_name="$2"
    local -n arr=$array_name

    for item in "${arr[@]}"; do
        if [[ "$value" == "$item" ]]; then
            return 0
        fi
    done
    return 1
}

#############################################################################
# Mathematical Functions
#############################################################################

# Calculate transition weight based on interpolation type
# Input: progress (0.0 to 1.0), Returns: weighted value (0.0 to 1.0)
calculate_transition() {
    local progress="$1"
    local type="$2"

    case "$type" in
        linear)
            echo "$progress"
            ;;
        sinoid)
            # Smooth sinusoidal easing
            awk -v p="$progress" 'BEGIN { print (1 - cos(p * 3.14159265359)) / 2 }'
            ;;
        cubic)
            # Cubic easing in-out
            awk -v p="$progress" 'BEGIN {
                if (p < 0.5)
                    print 4 * p * p * p;
                else
                    print 1 - ((-2 * p + 2) ^ 3) / 2;
            }'
            ;;
        quadratic)
            # Quadratic easing
            awk -v p="$progress" 'BEGIN {
                if (p < 0.5)
                    print 2 * p * p;
                else
                    print 1 - ((-2 * p + 2) ^ 2) / 2;
            }'
            ;;
        exponential)
            # Exponential easing
            awk -v p="$progress" 'BEGIN {
                if (p == 0) print 0;
                else if (p == 1) print 1;
                else if (p < 0.5) print (2 ^ (20 * p - 10)) / 2;
                else print (2 - (2 ^ (-20 * p + 10))) / 2;
            }'
            ;;
        bounce)
            # Bouncing effect
            awk -v p="$progress" 'BEGIN {
                n1 = 7.5625; d1 = 2.75;
                x = 1 - p;
                if (x < 1/d1) result = n1 * x * x;
                else if (x < 2/d1) { x -= 1.5/d1; result = n1 * x * x + 0.75; }
                else if (x < 2.5/d1) { x -= 2.25/d1; result = n1 * x * x + 0.9375; }
                else { x -= 2.625/d1; result = n1 * x * x + 0.984375; }
                print 1 - result;
            }'
            ;;
        elastic)
            # Elastic spring effect
            awk -v p="$progress" 'BEGIN {
                c4 = (2 * 3.14159265359) / 3;
                if (p == 0) print 0;
                else if (p == 1) print 1;
                else if (p < 0.5) print -(2 ^ (20 * p - 10) * sin((20 * p - 11.125) * c4)) / 2;
                else print (2 ^ (-20 * p + 10) * sin((20 * p - 11.125) * c4)) / 2 + 1;
            }'
            ;;
        *)
            echo "$progress"
            ;;
    esac
}

# Generate keyframe distribution based on schedule type
generate_schedule_distribution() {
    local num_frames="$1"
    local schedule_type="$2"
    local -n result_array=$3

    case "$schedule_type" in
        uniform)
            for ((i=0; i<num_frames; i++)); do
                result_array[$i]=$(awk -v i="$i" -v n="$num_frames" 'BEGIN { print i / (n - 1) }')
            done
            ;;
        front-load)
            # More frames at the beginning
            for ((i=0; i<num_frames; i++)); do
                local t=$(awk -v i="$i" -v n="$num_frames" 'BEGIN { print i / (n - 1) }')
                result_array[$i]=$(awk -v t="$t" 'BEGIN { print t * t }')
            done
            ;;
        back-load)
            # More frames at the end
            for ((i=0; i<num_frames; i++)); do
                local t=$(awk -v i="$i" -v n="$num_frames" 'BEGIN { print i / (n - 1) }')
                result_array[$i]=$(awk -v t="$t" 'BEGIN { print 1 - (1 - t) * (1 - t) }')
            done
            ;;
        center-peak)
            # More frames in the middle
            for ((i=0; i<num_frames; i++)); do
                local t=$(awk -v i="$i" -v n="$num_frames" 'BEGIN { print i / (n - 1) }')
                result_array[$i]=$(awk -v t="$t" 'BEGIN { print 1 - 4 * (t - 0.5) * (t - 0.5) }')
                result_array[$i]=$(awk -v val="${result_array[$i]}" -v t="$t" 'BEGIN { print t }')
            done
            ;;
        edge-peak)
            # More frames at start and end
            for ((i=0; i<num_frames; i++)); do
                local t=$(awk -v i="$i" -v n="$num_frames" 'BEGIN { print i / (n - 1) }')
                result_array[$i]=$(awk -v t="$t" 'BEGIN { print 4 * (t - 0.5) * (t - 0.5) }')
                result_array[$i]=$(awk -v val="${result_array[$i]}" -v t="$t" 'BEGIN { print t }')
            done
            ;;
        fibonacci)
            # Fibonacci sequence distribution
            local fib=(1 1)
            for ((i=2; i<num_frames; i++)); do
                fib[$i]=$((fib[i-1] + fib[i-2]))
            done
            local sum=0
            for val in "${fib[@]}"; do
                ((sum += val))
            done
            local cumsum=0
            for ((i=0; i<num_frames; i++)); do
                ((cumsum += fib[i]))
                result_array[$i]=$(awk -v c="$cumsum" -v s="$sum" 'BEGIN { print c / s }')
            done
            ;;
        golden-ratio)
            # Golden ratio distribution
            local phi=1.618033988749895
            for ((i=0; i<num_frames; i++)); do
                result_array[$i]=$(awk -v i="$i" -v n="$num_frames" -v phi="$phi" 'BEGIN {
                    print ((i * phi) - int(i * phi))
                }')
            done
            # Sort the array for monotonic distribution
            IFS=$'\n' result_array=($(sort -n <<<"${result_array[*]}"))
            ;;
        *)
            # Default to uniform
            for ((i=0; i<num_frames; i++)); do
                result_array[$i]=$(awk -v i="$i" -v n="$num_frames" 'BEGIN { print i / (n - 1) }')
            done
            ;;
    esac
}

#############################################################################
# Video Processing Functions
#############################################################################

get_video_duration() {
    local file="$1"
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file"
}

extract_frames() {
    local input="$1"
    local duration="$2"
    local -n ts_ref=$3
    local temp_dir="$4"

    verbose_log "Extracting ${#ts_ref[@]} frames from video..."

    for i in "${!ts_ref[@]}"; do
        local time="${ts_ref[$i]}"
        verbose_log "  Frame $((i+1)): ${time}s"

        ffmpeg -v quiet -ss "$time" -i "$input" -vframes 1 \
            -vf "scale=480:-1:flags=lanczos" \
            "${temp_dir}/frame_$(printf "%04d" "$i").png" 2>/dev/null
    done
}

apply_magic_effects() {
    local magic_type="$1"
    local temp_dir="$2"

    if [[ "$magic_type" == "none" ]]; then
        return 0
    fi

    verbose_log "Applying magic effect: $magic_type"

    case "$magic_type" in
        psychedelic)
            for frame in "$temp_dir"/*.png; do
                ffmpeg -v quiet -i "$frame" -vf "hue=s=3:h=sin(2*PI*t)*360" \
                    "${frame}.tmp.png" 2>/dev/null && mv "${frame}.tmp.png" "$frame"
            done
            ;;
        dither-bloom)
            for frame in "$temp_dir"/*.png; do
                ffmpeg -v quiet -i "$frame" -vf "format=gbrp,split[a][b],[a]negate[c],[b][c]blend=all_mode=xor,noise=alls=20:allf=t" \
                    "${frame}.tmp.png" 2>/dev/null && mv "${frame}.tmp.png" "$frame"
            done
            ;;
        edge-glow)
            for frame in "$temp_dir"/*.png; do
                ffmpeg -v quiet -i "$frame" -vf "edgedetect=low=0.1:high=0.3,negate,hue=s=2" \
                    "${temp_dir}/edges_$(basename "$frame")"
                ffmpeg -v quiet -i "$frame" -i "${temp_dir}/edges_$(basename "$frame")" \
                    -filter_complex "[0:v][1:v]blend=all_mode=addition:all_opacity=0.5" \
                    "${frame}.tmp.png" 2>/dev/null && mv "${frame}.tmp.png" "$frame"
                rm "${temp_dir}/edges_$(basename "$frame")"
            done
            ;;
        temporal-blur)
            # Create motion blur effect
            local frames=("$temp_dir"/*.png)
            for i in "${!frames[@]}"; do
                local prev_idx=$((i > 0 ? i - 1 : 0))
                local next_idx=$((i < ${#frames[@]} - 1 ? i + 1 : ${#frames[@]} - 1))

                ffmpeg -v quiet -i "${frames[$prev_idx]}" -i "${frames[$i]}" -i "${frames[$next_idx]}" \
                    -filter_complex "[0:v][1:v][2:v]blend=all_mode=average" \
                    "${frames[$i]}.tmp.png" 2>/dev/null && mv "${frames[$i]}.tmp.png" "${frames[$i]}"
            done
            ;;
        chromatic-shift)
            for frame in "$temp_dir"/*.png; do
                ffmpeg -v quiet -i "$frame" -vf "rgbashift=rh=5:bh=-5" \
                    "${frame}.tmp.png" 2>/dev/null && mv "${frame}.tmp.png" "$frame"
            done
            ;;
        vaporwave)
            for frame in "$temp_dir"/*.png; do
                ffmpeg -v quiet -i "$frame" -vf "curves=vintage,hue=h=300:s=1.5,eq=saturation=1.5:contrast=1.2" \
                    "${frame}.tmp.png" 2>/dev/null && mv "${frame}.tmp.png" "$frame"
            done
            ;;
    esac
}

create_gif() {
    local temp_dir="$1"
    local output="$2"
    local frame_delay="$3"

    verbose_log "Creating animated GIF with ${frame_delay}ms per frame..."

    # Convert milliseconds to centiseconds (GIF delay unit)
    local delay_cs
    delay_cs=$(awk -v ms="$frame_delay" 'BEGIN { print int(ms / 10) }')

    # Ensure minimum delay of 1 centisecond
    if [[ $delay_cs -lt 1 ]]; then
        delay_cs=1
    fi

    # Calculate input framerate (frames are read at this rate)
    # For GIF delay, we want 1000ms / frame_delay fps
    local fps
    fps=$(awk -v ms="$frame_delay" 'BEGIN { printf "%.2f", 1000.0 / ms }')

    verbose_log "Frame delay: ${delay_cs} centiseconds (${frame_delay}ms), FPS: ${fps}"

    # Generate palette for better color quality
    ffmpeg -v error -pattern_type glob -i "${temp_dir}/frame_*.png" \
        -vf "scale=480:-1:flags=lanczos,palettegen=stats_mode=diff" \
        -y "${temp_dir}/palette.png"

    # Create GIF using palette with specified frame delay
    ffmpeg -v error -framerate "$fps" -pattern_type glob -i "${temp_dir}/frame_*.png" -i "${temp_dir}/palette.png" \
        -filter_complex "[0:v]scale=480:-1:flags=lanczos[scaled];[scaled][1:v]paletteuse=dither=bayer:bayer_scale=5" \
        -gifflags +transdiff -y "$output"
}

#############################################################################
# Main Processing
#############################################################################

process_video() {
    local input="$INPUT_FILE"
    local output="$OUTPUT_FILE"

    # Validate input file
    if [[ ! -f "$input" ]]; then
        log_error "Input file not found: $input"
        exit 1
    fi

    # Get video duration
    local duration
    duration=$(get_video_duration "$input")
    verbose_log "Video duration: ${duration}s"

    # Calculate schedule duration
    local schedule_duration
    schedule_duration=$(awk -v d="$duration" -v s="$INPUT_SCHEDULES" 'BEGIN { print d / s }')
    verbose_log "Schedule duration: ${schedule_duration}s (${INPUT_SCHEDULES} schedule(s))"

    # Generate frame distribution
    local -a distribution
    generate_schedule_distribution "$KEYFRAMES" "$SCHEDULE" distribution

    verbose_log "Using schedule: $SCHEDULE"
    verbose_log "Using transition: $TRANSITION"

    # Calculate actual timestamps with transition function
    local -a timestamps
    for i in "${!distribution[@]}"; do
        local base_time="${distribution[$i]}"
        local weighted_time
        weighted_time=$(calculate_transition "$base_time" "$TRANSITION")

        # Map to video duration considering input schedules
        local actual_time
        actual_time=$(awk -v w="$weighted_time" -v d="$duration" 'BEGIN { print w * d }')

        # Ensure we don't exceed video duration
        timestamps[$i]=$(awk -v t="$actual_time" -v d="$duration" 'BEGIN {
            if (t > d) print d;
            else print t;
        }')
    done

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    # Extract frames
    extract_frames "$input" "$duration" timestamps "$temp_dir"

    # Apply magic effects
    apply_magic_effects "$MAGIC" "$temp_dir"

    # Create GIF with specified frame duration
    create_gif "$temp_dir" "$output" "$KEYFRAME_DURATION"

    log_success "GIF created successfully: $output"

    # Show file size
    local size
    size=$(du -h "$output" | cut -f1)
    log_info "Output size: $size"
}

#############################################################################
# Command Line Parsing
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -k|--keyframes)
                KEYFRAMES="$2"
                shift 2
                ;;
            -d|--keyframe-duration)
                KEYFRAME_DURATION="$2"
                shift 2
                ;;
            -i|--input-schedules)
                INPUT_SCHEDULES="$2"
                shift 2
                ;;
            -t|--transition)
                TRANSITION="$2"
                if ! validate_enum "$TRANSITION" TRANSITIONS; then
                    log_error "Invalid transition type: $TRANSITION"
                    log_error "Available: ${TRANSITIONS[*]}"
                    exit 1
                fi
                shift 2
                ;;
            -s|--schedule)
                SCHEDULE="$2"
                if ! validate_enum "$SCHEDULE" SCHEDULES; then
                    log_error "Invalid schedule type: $SCHEDULE"
                    log_error "Available: ${SCHEDULES[*]}"
                    exit 1
                fi
                shift 2
                ;;
            -m|--magic)
                MAGIC="$2"
                if ! validate_enum "$MAGIC" MAGICS; then
                    log_error "Invalid magic type: $MAGIC"
                    log_error "Available: ${MAGICS[*]}"
                    exit 1
                fi
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                if [[ -z "$INPUT_FILE" ]]; then
                    INPUT_FILE="$1"
                elif [[ -z "$OUTPUT_FILE" ]]; then
                    OUTPUT_FILE="$1"
                else
                    log_error "Too many arguments"
                    print_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$INPUT_FILE" ]]; then
        log_error "Input file is required"
        print_usage
        exit 1
    fi

    # Set default output file
    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="${INPUT_FILE%.*}.gif"
    fi

    # Validate numeric arguments
    if ! [[ "$KEYFRAMES" =~ ^[0-9]+$ ]] || [[ "$KEYFRAMES" -lt 2 ]]; then
        log_error "Keyframes must be a positive integer >= 2"
        exit 1
    fi

    if ! [[ "$KEYFRAME_DURATION" =~ ^[0-9]+$ ]] || [[ "$KEYFRAME_DURATION" -lt 1 ]] || [[ "$KEYFRAME_DURATION" -gt 30000 ]]; then
        log_error "Keyframe duration must be an integer between 1 and 30000 milliseconds"
        exit 1
    fi

    if ! [[ "$INPUT_SCHEDULES" =~ ^[0-9]+$ ]] || [[ "$INPUT_SCHEDULES" -lt 1 ]]; then
        log_error "Input schedules must be a positive integer >= 1"
        exit 1
    fi
}

#############################################################################
# Entry Point
#############################################################################

main() {
    parse_arguments "$@"

    log_info "Starting MP4 to GIF conversion..."
    log_info "Configuration:"
    log_info "  Input: $INPUT_FILE"
    log_info "  Output: $OUTPUT_FILE"
    log_info "  Keyframes: $KEYFRAMES"
    log_info "  Frame Duration: ${KEYFRAME_DURATION}ms"
    log_info "  Schedules: $INPUT_SCHEDULES"
    log_info "  Transition: $TRANSITION"
    log_info "  Schedule: $SCHEDULE"
    log_info "  Magic: $MAGIC"

    process_video
}

# Run main function
main "$@"
