#!/usr/bin/env bash
# eidr.sh — Generate and validate EIDR identifiers
# EIDR format: 10.5240/XXXX-XXXX-XXXX-XXXX-XXXX-C
# Check character: ISO 7064 MOD 37-36

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
EIDR_PREFIX="10.5240"
MOD37_CHARS="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ*"

# ---------------------------------------------------------------------------
# ISO 7064 MOD 37-36 check character
# Alphabet: 0-9 A-Z (36 chars), with '*' as the check for remainder 0
# ---------------------------------------------------------------------------
compute_check_char() {
    local payload="$1"   # string of hex digits (no dashes, no prefix)
    local product=0
    local char code

    # Convert each character to its numeric value (0-9 → 0-9, A-F → 10-15)
    while IFS= read -rn1 char; do
        [[ -z "$char" ]] && continue
        char="${char^^}"
        if [[ "$char" =~ [0-9] ]]; then
            code=$((10#$char))
        elif [[ "$char" =~ [A-Z] ]]; then
            code=$(( $(printf '%d' "'$char") - 55 ))  # A=10 … Z=35
        else
            echo "ERROR: invalid character '$char' in payload" >&2
            return 1
        fi
        product=$(( (product + code) * 2 % 37 ))
    done < <(printf '%s' "$payload")

    local remainder=$(( (38 - product) % 37 ))
    printf '%s' "${MOD37_CHARS:$remainder:1}"
}

# ---------------------------------------------------------------------------
# Generate a random EIDR
# ---------------------------------------------------------------------------
generate_eidr() {
    # 20 random hex digits split into 5 groups of 4
    local raw
    raw=$(LC_ALL=C tr -dc 'A-F0-9' < /dev/urandom | head -c 20 2>/dev/null || \
          od -A n -t x1 -N 10 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]' | head -c 20)

    local g1="${raw:0:4}" g2="${raw:4:4}" g3="${raw:8:4}" g4="${raw:12:4}" g5="${raw:16:4}"
    local check
    check=$(compute_check_char "${g1}${g2}${g3}${g4}${g5}")

    printf '%s/%s-%s-%s-%s-%s-%s\n' \
        "$EIDR_PREFIX" "$g1" "$g2" "$g3" "$g4" "$g5" "$check"
}

# ---------------------------------------------------------------------------
# Validate an EIDR
# ---------------------------------------------------------------------------
validate_eidr() {
    local eidr="$1"

    # ---- structural check --------------------------------------------------
    local pattern='^10\.5240/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Za-z*]$'
    if ! [[ "$eidr" =~ $pattern ]]; then
        echo "INVALID — malformed structure: $eidr"
        return 1
    fi

    # ---- check character ---------------------------------------------------
    local body="${eidr#*/}"          # strip "10.5240/"
    local given_check="${body: -1}"   # last character
    local payload="${body//-/}"       # remove all dashes
    payload="${payload:0:${#payload}-1}"  # drop check char

    local expected_check
    expected_check=$(compute_check_char "${payload^^}")

    if [[ "${given_check^^}" == "${expected_check^^}" ]]; then
        echo "VALID — $eidr  (check char: $expected_check)"
        return 0
    else
        echo "INVALID — check char mismatch in: $eidr  (got '${given_check^^}', expected '$expected_check')"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Batch validate from a file (one EIDR per line)
# ---------------------------------------------------------------------------
validate_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "ERROR: file not found: $file" >&2
        return 1
    fi

    local valid=0 invalid=0 total=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip blank lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        (( total++ )) || true
        if validate_eidr "$line" >/dev/null 2>&1; then
            echo "✓ $line"
            (( valid++ )) || true
        else
            echo "✗ $line  ← INVALID"
            (( invalid++ )) || true
        fi
    done < "$file"

    echo ""
    echo "── Summary ──────────────────────"
    echo "  Total:   $total"
    echo "  Valid:   $valid"
    echo "  Invalid: $invalid"
}

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  generate [N]          Generate N random EIDRs (default: 1)
  validate <EIDR>       Validate a single EIDR
  validate-file <file>  Validate every EIDR in a file (one per line)
  help                  Show this message

Examples:
  $(basename "$0") generate
  $(basename "$0") generate 5
  $(basename "$0") validate 10.5240/7791-8534-2C23-9030-8610-5
  $(basename "$0") validate-file ids.txt
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        generate)
            local n="${1:-1}"
            if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
                echo "ERROR: N must be a positive integer" >&2
                exit 1
            fi
            for (( i=0; i<n; i++ )); do
                generate_eidr
            done
            ;;
        validate)
            if [[ -z "${1:-}" ]]; then
                echo "ERROR: provide an EIDR to validate" >&2
                usage; exit 1
            fi
            validate_eidr "$1"
            ;;
        validate-file)
            if [[ -z "${1:-}" ]]; then
                echo "ERROR: provide a file path" >&2
                usage; exit 1
            fi
            validate_file "$1"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "ERROR: unknown command '$cmd'" >&2
            usage; exit 1
            ;;
    esac
}

main "$@"
