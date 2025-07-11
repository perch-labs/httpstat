#!/bin/bash

# httpstat-batch.sh
# Script to test multiple endpoints with httpstat (macOS compatible)

set -euo pipefail

# Configuration
ITERATIONS=25
OUTPUT_FILE="httpstat_results_$(date +%Y%m%d_%H%M%S).json"
DELAY_BETWEEN_REQUESTS=1  # seconds
DELAY_BETWEEN_ENDPOINTS=5  # seconds

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -f FILE     File containing list of endpoints (one per line)
    -e ENDPOINT Single endpoint to test
    -i NUM      Number of iterations per endpoint (default: 25)
    -o FILE     Output file name (default: httpstat_results_TIMESTAMP.json)
    -d SECONDS  Delay between requests (default: 1)
    -D SECONDS  Delay between endpoints (default: 5)
    -h          Show this help

Examples:
    $0 -f endpoints.txt
    $0 -e "https://httpbin.org/status/200"
    $0 -f endpoints.txt -i 50 -o my_results.json

Endpoints file format (one per line):
    https://httpbin.org/status/200
    https://httpbin.org/delay/1
    https://api.github.com
EOF
}

# macOS compatible function to read file into array
read_endpoints_file() {
    local file="$1"
    local -a endpoints=()

    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            endpoints+=("$line")
        fi
    done < "$file"

    # Return array via global variable
    ENDPOINTS=("${endpoints[@]}")
}

# Default endpoints if no file provided
create_sample_endpoints() {
    cat > endpoints.txt << EOF
https://httpbin.org/status/200
https://httpbin.org/delay/1
https://httpbin.org/delay/2
https://api.github.com
https://jsonplaceholder.typicode.com/posts/1
EOF
    echo "endpoints.txt"
}

# Parse command line arguments
ENDPOINTS_FILE=""
SINGLE_ENDPOINT=""

while getopts "f:e:i:o:d:D:h" opt; do
    case $opt in
        f) ENDPOINTS_FILE="$OPTARG" ;;
        e) SINGLE_ENDPOINT="$OPTARG" ;;
        i) ITERATIONS="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        d) DELAY_BETWEEN_REQUESTS="$OPTARG" ;;
        D) DELAY_BETWEEN_ENDPOINTS="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# Check for required tools
if ! command -v httpstat &> /dev/null; then
    error "httpstat is not installed or not in PATH"
    echo "Install with: pip install httpstat"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    warn "jq is not installed. Analysis features will be limited."
    echo "Install with: brew install jq"
fi

# Determine endpoints to test
declare -a ENDPOINTS
if [[ -n "$SINGLE_ENDPOINT" ]]; then
    ENDPOINTS=("$SINGLE_ENDPOINT")
elif [[ -n "$ENDPOINTS_FILE" ]]; then
    if [[ ! -f "$ENDPOINTS_FILE" ]]; then
        error "Endpoints file '$ENDPOINTS_FILE' not found"
        exit 1
    fi
    read_endpoints_file "$ENDPOINTS_FILE"
else
    warn "No endpoints specified, creating sample endpoints.txt"
    ENDPOINTS_FILE=$(create_sample_endpoints)
    read_endpoints_file "$ENDPOINTS_FILE"
fi

if [[ ${#ENDPOINTS[@]} -eq 0 ]]; then
    error "No valid endpoints found"
    exit 1
fi

# Initialize output file
echo "# httpstat batch results - $(date)" > "$OUTPUT_FILE"
echo "# Format: One JSON object per line" >> "$OUTPUT_FILE"

# Summary variables
total_tests=0
failed_tests=0
start_time=$(date +%s)

log "Starting httpstat batch testing"
log "Endpoints: ${#ENDPOINTS[@]}"
log "Iterations per endpoint: $ITERATIONS"
log "Output file: $OUTPUT_FILE"
log "Total tests: $((${#ENDPOINTS[@]} * ITERATIONS))"
echo

# Main testing loop
for i in $(seq 0 $((${#ENDPOINTS[@]} - 1))); do
    endpoint="${ENDPOINTS[$i]}"
    endpoint_start_time=$(date +%s)
    endpoint_failures=0

    log "Testing endpoint $((i+1))/${#ENDPOINTS[@]}: $endpoint"

    for j in $(seq 1 $ITERATIONS); do
        printf "\r  ${BLUE}Progress: %d/%d${NC}" "$j" "$ITERATIONS"

        # Set environment variable for JSON output
        export HTTPSTAT_METRICS_ONLY=true
        export HTTPSTAT_APPEND_JSON="$OUTPUT_FILE"

        # Run httpstat and capture exit code
        if timeout 30 httpstat "$endpoint" > /dev/null 2>&1; then
            total_tests=$((total_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
            endpoint_failures=$((endpoint_failures + 1))
            total_tests=$((total_tests + 1))
            error_msg="Failed test $j for $endpoint at $(date)"
            echo "# $error_msg" >> "$OUTPUT_FILE"
        fi

        # Delay between requests (except for last iteration)
        if [[ $j -lt $ITERATIONS ]]; then
            sleep "$DELAY_BETWEEN_REQUESTS"
        fi
    done

    # Clear the progress line and show summary for this endpoint
    printf "\r  ${GREEN}Completed: %d/%d tests" "$ITERATIONS" "$ITERATIONS"
    if [[ $endpoint_failures -gt 0 ]]; then
        printf " ${RED}(%d failures)${NC}" "$endpoint_failures"
    fi
    echo

    endpoint_duration=$(($(date +%s) - endpoint_start_time))
    log "Endpoint completed in ${endpoint_duration}s"

    # Delay between endpoints (except for last endpoint)
    if [[ $i -lt $((${#ENDPOINTS[@]} - 1)) ]]; then
        echo "  Waiting ${DELAY_BETWEEN_ENDPOINTS}s before next endpoint..."
        sleep "$DELAY_BETWEEN_ENDPOINTS"
    fi
    echo
done

# Clean up environment variables
unset HTTPSTAT_METRICS_ONLY HTTPSTAT_APPEND_JSON

# Final summary
total_duration=$(($(date +%s) - start_time))
success_rate=$(( (total_tests - failed_tests) * 100 / total_tests ))

echo "=================================="
log "Batch testing completed!"
echo "  Total tests: $total_tests"
echo "  Successful: $((total_tests - failed_tests))"
echo "  Failed: $failed_tests"
echo "  Success rate: ${success_rate}%"
echo "  Total duration: ${total_duration}s"
echo "  Results saved to: $OUTPUT_FILE"
echo "=================================="

# Show sample analysis commands
echo
echo "Sample analysis commands:"
echo "  # Count total requests:"
echo "    grep -c '^{' $OUTPUT_FILE"
echo

if command -v jq &> /dev/null; then
    echo "  # Average response time:"
    echo "    grep '^{' $OUTPUT_FILE | jq '.time_total' | awk '{sum+=\$1; count++} END {print \"Average:\", sum/count \"ms\"}'"
    echo
    echo "  # Response times by URL:"
    echo "    grep '^{' $OUTPUT_FILE | jq -r '\"\\(.url): \\(.time_total)ms\"'"
    echo
    echo "  # Find slowest requests:"
    echo "    grep '^{' $OUTPUT_FILE | jq -s 'sort_by(.time_total) | reverse | .[0:5]'"
else
    echo "  # Install jq for JSON analysis:"
    echo "    brew install jq"
fi

# Create analysis script (macOS compatible)
cat > "analyze_${OUTPUT_FILE%.json}.sh" << 'EOF'
#!/bin/bash
# Analysis script for httpstat results (macOS compatible)

RESULTS_FILE="$1"
if [[ -z "$RESULTS_FILE" ]] || [[ ! -f "$RESULTS_FILE" ]]; then
    echo "Usage: $0 <results_file.json>"
    exit 1
fi

echo "=== httpstat Results Analysis ==="
echo "File: $RESULTS_FILE"
echo

echo "=== Summary ==="
total_requests=$(grep -c '^{' "$RESULTS_FILE")
echo "Total requests: $total_requests"

if [[ $total_requests -gt 0 ]]; then
    if command -v jq &> /dev/null; then
        echo
        echo "=== Response Time Statistics ==="
        grep '^{' "$RESULTS_FILE" | jq '.time_total' | awk '
        {
            times[NR] = $1
            sum += $1
            if (NR == 1 || $1 < min) min = $1
            if (NR == 1 || $1 > max) max = $1
        }
        END {
            count = NR
            avg = sum / count
            printf "Average: %.2f ms\n", avg
            printf "Min:     %.2f ms\n", min
            printf "Max:     %.2f ms\n", max
        }'

        echo
        echo "=== By Endpoint ==="
        grep '^{' "$RESULTS_FILE" | jq -r '.url' | sort | uniq -c | while read count url; do
            avg=$(grep '^{' "$RESULTS_FILE" | jq -r "select(.url == \"$url\") | .time_total" | awk '{sum+=$1; n++} END {print sum/n}')
            printf "%3d requests | %8.2f ms avg | %s\n" "$count" "$avg" "$url"
        done
    else
        echo
        echo "Install jq for detailed analysis: brew install jq"
    fi
fi
EOF

chmod +x "analyze_${OUTPUT_FILE%.json}.sh"
echo "Created analysis script: analyze_${OUTPUT_FILE%.json}.sh"