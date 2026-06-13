#!/usr/bin/env bash
#
# verify-apache-release.sh
# Reusable release verification script for ANY Apache project.
# Validates: SHA1, SHA256, SHA512 hashes, GPG signatures, and optionally Maven staging.
#
# Usage:
#   ./verify-apache-release.sh [options] <dist-url> [maven-repo-url]
#
# Arguments:
#   <dist-url>         URL to the dist directory on dist.apache.org
#                      e.g. https://dist.apache.org/repos/dist/dev/PROJECT/staging-NNN/NAME-VERSION/
#   [maven-repo-url]   Maven staging repository URL (optional)
#                      e.g. https://repository.apache.org/content/repositories/orgapachePROJECT-NNN/
#
# Options:
#   -k, --keys <url>         URL to the project KEYS file (default: auto-resolved from dist URL)
#   -o, --output <dir>       Output directory (default: temporary)
#   -s, --skip-maven         Skip Maven repository verification
#   -g, --maven-group <gid>  Maven group path, e.g. org/apache/tomee (default: auto-detect)
#   -a, --artifact-id <aid>  Maven artifactId, e.g. apache-tomee (default: auto-detect)
#   -V, --maven-version <v>  Maven version, e.g. 11.0.0-M1 (default: auto-extracted from dist URL)
#   -m, --maven-samples <n>  Max Maven module artifacts to sample (default: 5)
#   -v, --verbose            Verbose output
#   -h, --help               Show this help
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

# Defaults
KEYS_URL=""
OUTPUT_DIR=""
SKIP_MAVEN=false
MAVEN_SAMPLES=5
VERBOSE=false
DIST_URL=""
MAVEN_URL=""
MAVEN_GROUP=""
ARTIFACT_ID=""
MAVEN_VERSION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--keys)
            KEYS_URL="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--skip-maven)
            SKIP_MAVEN=true
            shift
            ;;
        -g|--maven-group)
            MAVEN_GROUP="$2"
            shift 2
            ;;
        -a|--artifact-id)
            ARTIFACT_ID="$2"
            shift 2
            ;;
        -V|--maven-version)
            MAVEN_VERSION="$2"
            shift 2
            ;;
        -m|--maven-samples)
            MAVEN_SAMPLES="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //;s/^#//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            if [ -z "$DIST_URL" ]; then
                DIST_URL="$1"
            elif [ -z "$MAVEN_URL" ]; then
                MAVEN_URL="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$DIST_URL" ]; then
    echo "Error: dist URL is required"
    echo "Usage: $0 <dist-url> [maven-repo-url]"
    exit 1
fi

# Normalize URLs
DIST_URL="${DIST_URL%/}/"

# Auto-detect KEYS URL from dist URL
# Pattern: .../dist/dev/PROJECT/...  ->  .../dist/release/PROJECT/KEYS
if [ -z "$KEYS_URL" ]; then
    if [[ "$DIST_URL" =~ .*dist\.apache\.org/repos/dist/dev/([^/]+)/ ]]; then
        PROJECT="${BASH_REMATCH[1]}"
        KEYS_URL="https://dist.apache.org/repos/dist/release/${PROJECT}/KEYS"
    fi
fi

# Auto-extract version from dist URL
# Looks for the last path segment and extracts a version-like suffix
# e.g. tomee-11.0.0-M1/ -> 11.0.0-M1, myproject-2.5.0/ -> 2.5.0
if [ -z "$MAVEN_VERSION" ]; then
    DIR_NAME=$(basename "$DIST_URL")
    # Try to extract version: anything after the last occurrence of a digit-dot pattern
    MAVEN_VERSION=$(echo "$DIR_NAME" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9]+)?' | head -1 || true)
    if [ -z "$MAVEN_VERSION" ]; then
        # Fallback: everything after the last hyphen
        MAVEN_VERSION=$(echo "$DIR_NAME" | grep -oE '[^-]+$' || true)
    fi
fi

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$(mktemp -d)"
    CLEANUP=true
else
    mkdir -p "$OUTPUT_DIR"
    CLEANUP=false
fi

LOG="$OUTPUT_DIR/verification.log"
RESULTS="$OUTPUT_DIR/results.md"
exec 3>&1 4>&2
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "========================================================"
echo "  Apache Release Verification"
echo "========================================================"
echo "  Dist URL: $DIST_URL"
[ -n "$MAVEN_URL" ] && echo "  Maven URL: $MAVEN_URL"
[ -n "$KEYS_URL" ] && echo "  KEYS URL: $KEYS_URL"
[ -n "$MAVEN_VERSION" ] && echo "  Detected version: $MAVEN_VERSION"
echo "  Work dir: $OUTPUT_DIR"
echo "========================================================"
echo ""

# ----------------------------------------------------------------
# Step 1: Download and import KEYS
# ----------------------------------------------------------------
echo -e "${CYAN}${BOLD}[1/5] Downloading KEYS file${NC}"
mkdir -p "$OUTPUT_DIR/keys"
KEYS_FILE="$OUTPUT_DIR/keys/KEYS"

if curl -sS -o "$KEYS_FILE" "$KEYS_URL" 2>/dev/null; then
    KEY_COUNT=$(grep -c "^pub" "$KEYS_FILE" || true)
    echo -e "  ${PASS} Downloaded KEYS file from $KEYS_URL ($KEY_COUNT keys)"
else
    echo -e "  ${FAIL} Failed to download KEYS file from $KEYS_URL"
    exit 1
fi
gpg --import --no-permission-warning "$KEYS_FILE" 2>&1 | grep -E "(imported|not changed|Total number)" | sed 's/^/  /'
echo ""

# ----------------------------------------------------------------
# Step 2: Download artifacts from dist
# ----------------------------------------------------------------
echo -e "${CYAN}${BOLD}[2/5] Downloading artifacts from dist${NC}"
mkdir -p "$OUTPUT_DIR/dist"
ARTIFACTS=()
echo "  Scanning $DIST_URL ..."

LISTING=$(curl -sS "$DIST_URL" 2>/dev/null || true)
# Match archive files: .tar.gz, .zip (but not .asc, .sha*, .md5)
ARCHIVE_FILES=$(echo "$LISTING" | grep -oE 'href="[^"]*\.(tar\.gz|zip)"' | sed 's/href="//;s/"//g' || true)

DOWNLOADED=0
while IFS= read -r fname; do
    [ -z "$fname" ] && continue
    ARTIFACTS+=("$fname")
    if [ ! -f "$OUTPUT_DIR/dist/$fname" ]; then
        echo "  Downloading $fname ..."
        curl -sS -o "$OUTPUT_DIR/dist/$fname" "$DIST_URL/$fname" 2>/dev/null
    fi
    for ext in .asc .sha1 .sha256 .sha512 .md5; do
        if [ ! -f "$OUTPUT_DIR/dist/$fname$ext" ]; then
            curl -sf -o "$OUTPUT_DIR/dist/$fname$ext" "$DIST_URL/$fname$ext" 2>/dev/null || true
        fi
    done
    DOWNLOADED=$((DOWNLOADED + 1))
done <<< "$ARCHIVE_FILES"

if [ "$DOWNLOADED" -eq 0 ]; then
    echo -e "  ${FAIL} No artifacts found at $DIST_URL"
    exit 1
fi
echo -e "  ${PASS} Downloaded $DOWNLOADED artifacts"
echo ""

# ----------------------------------------------------------------
# Step 3: Verify hashes
# ----------------------------------------------------------------
echo -e "${CYAN}${BOLD}[3/5] Verifying hashes${NC}"

SHA1_FAIL=0; SHA256_FAIL=0; SHA512_FAIL=0

for f in "${ARTIFACTS[@]}"; do
    artifact_path="$OUTPUT_DIR/dist/$f"
    [ ! -f "$artifact_path" ] && continue

    for algo in 1 256 512; do
        ext=".sha${algo}"
        if [ -f "$artifact_path$ext" ]; then
            computed=$(shasum -a "$algo" "$artifact_path" 2>/dev/null | awk '{print $1}')
            stored=$(cat "$artifact_path$ext" | awk '{print $1}')
            if [ "$computed" = "$stored" ]; then
                $VERBOSE && echo -e "  ${PASS} SHA${algo} OK: $f"
            else
                echo -e "  ${FAIL} SHA${algo} MISMATCH: $f"
                echo "         computed: $computed"
                echo "         stored:   $stored"
                eval "SHA${algo}_FAIL=\$((SHA${algo}_FAIL + 1))"
            fi
        fi
    done
done

echo ""
echo "  Hash verification results:"
echo "    SHA1:   $([ $SHA1_FAIL -eq 0 ] && echo "${PASS}" || echo "${FAIL}")  ${#ARTIFACTS[@]} checked, ${SHA1_FAIL} failures"
echo "    SHA256: $([ $SHA256_FAIL -eq 0 ] && echo "${PASS}" || echo "${FAIL}")  ${#ARTIFACTS[@]} checked, ${SHA256_FAIL} failures"
echo "    SHA512: $([ $SHA512_FAIL -eq 0 ] && echo "${PASS}" || echo "${FAIL}")  ${#ARTIFACTS[@]} checked, ${SHA512_FAIL} failures"
echo ""

# ----------------------------------------------------------------
# Step 4: Verify GPG signatures
# ----------------------------------------------------------------
echo -e "${CYAN}${BOLD}[4/5] Verifying GPG signatures${NC}"

SIG_FAIL=0; SIG_PASS=0
SIGNER=""; SIGNER_KEY=""; SIGNER_TIME=""

for f in "${ARTIFACTS[@]}"; do
    artifact_path="$OUTPUT_DIR/dist/$f"
    [ ! -f "$artifact_path" ] || [ ! -f "$artifact_path.asc" ] && continue

    VERIFY_OUTPUT=$(gpg --verify --no-permission-warning "$artifact_path.asc" "$artifact_path" 2>&1 || true)
    if echo "$VERIFY_OUTPUT" | grep -q "^gpg: Good signature"; then
        SIG_PASS=$((SIG_PASS + 1))
        if [ -z "$SIGNER" ]; then
            SIGNER=$(echo "$VERIFY_OUTPUT" | grep "^gpg: Good signature" | sed 's/.*from "//;s/".*//' || true)
            SIGNER_KEY=$(echo "$VERIFY_OUTPUT" | grep "using RSA key\|using DSA key\|using ECDSA key" | sed 's/.*key //' || true)
            SIGNER_TIME=$(echo "$VERIFY_OUTPUT" | grep "^gpg: Signature made" | sed 's/^gpg: Signature made //' || true)
        fi
        $VERBOSE && echo -e "  ${PASS} Good signature: $f"
    else
        echo -e "  ${FAIL} Bad signature: $f"
        echo "    $VERIFY_OUTPUT" | head -3
        SIG_FAIL=$((SIG_FAIL + 1))
    fi
done

echo ""
echo "  Signature verification results:"
echo "    ${PASS} Good: $SIG_PASS"
[ "$SIG_FAIL" -gt 0 ] && echo "    ${FAIL} Bad: $SIG_FAIL"
echo ""
if [ -n "$SIGNER" ]; then
    echo "  Signer: $SIGNER"
    echo "  Key ID: $SIGNER_KEY"
    echo "  Signed: $SIGNER_TIME"
    echo ""
fi

# ----------------------------------------------------------------
# Step 5: Verify Maven staging (optional)
# ----------------------------------------------------------------
if [ -n "$MAVEN_URL" ] && [ "$SKIP_MAVEN" = false ]; then
    echo -e "${CYAN}${BOLD}[5/5] Verifying Maven staging repository${NC}"

    MAVEN_URL="${MAVEN_URL%/}/"
    mkdir -p "$OUTPUT_DIR/maven"
    MAVEN_OK=0; MAVEN_FAIL=0

    # Determine Maven group path if not provided
    if [ -z "$MAVEN_GROUP" ]; then
        # Scan the Maven repo for group directories under org/apache/
        # Sonatype Nexus returns full URLs; SVN listing returns relative paths
        RAW=$(curl -sS "${MAVEN_URL}org/apache/" 2>/dev/null || true)
        CANDIDATES=$(echo "$RAW" | grep -oE 'href="[^"]+/"' | grep -v '\.\.' | sed 's/href="//;s/"//g;s/\/$//' || true)
        # Strip scheme+host prefix if present (Nexus absolute URLs)
        EXTRACTED=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            # Take only the last path segment
            name=$(basename "$line")
            EXTRACTED="${EXTRACTED}${name}
"
        done <<< "$CANDIDATES"
        # Prefer the directory that matches the project name from KEYS URL
        if [[ "$KEYS_URL" =~ /release/([^/]+)/KEYS ]]; then
            PROJECT_NAME="${BASH_REMATCH[1]}"
            GROUP=$(echo "$EXTRACTED" | grep -E "^${PROJECT_NAME}$" | head -1 || true)
            if [ -z "$GROUP" ]; then
                GROUP=$(echo "$EXTRACTED" | head -1 || true)
            fi
        else
            GROUP=$(echo "$EXTRACTED" | head -1 || true)
        fi
        if [ -n "$GROUP" ]; then
            MAVEN_GROUP="org/apache/${GROUP}"
        fi
    fi

    if [ -z "$MAVEN_GROUP" ]; then
        echo "  ${WARN} Could not determine Maven group. Use --maven-group to specify it."
    else
        echo "  Maven group: $MAVEN_GROUP"
        echo "  Maven version: $MAVEN_VERSION"

        scan_maven_dir() {
            local dir_url="$1"
            local items
            items=$(curl -sS "$dir_url" 2>/dev/null | grep -oE 'href="[^"]*\.(jar|pom)"' | sed 's/href="//;s/"//' || true)
            while IFS= read -r item; do
                [ -z "$item" ] && continue
                local fname
                fname=$(basename "$item")
                local base_url="${dir_url}${fname}"
                if curl -sf -o "$OUTPUT_DIR/maven/$fname" "$base_url" 2>/dev/null && \
                   curl -sf -o "$OUTPUT_DIR/maven/$fname.asc" "${base_url}.asc" 2>/dev/null; then
                    local verify_out
                    verify_out=$(gpg --verify --no-permission-warning "$OUTPUT_DIR/maven/$fname.asc" "$OUTPUT_DIR/maven/$fname" 2>&1 || true)
                    if echo "$verify_out" | grep -q "^gpg: Good signature"; then
                        MAVEN_OK=$((MAVEN_OK + 1))
                        echo -e "  ${PASS} Maven: $fname"
                    else
                        echo -e "  ${FAIL} Maven: $fname bad signature"
                        MAVEN_FAIL=$((MAVEN_FAIL + 1))
                    fi
                fi
            done <<< "$items"
        }

        # Strategy 1: Known artifact ID (aggregate or project pom)
        if [ -n "$ARTIFACT_ID" ]; then
            version_dir="${MAVEN_URL}${MAVEN_GROUP}/${ARTIFACT_ID}/${MAVEN_VERSION}/"
            if curl -sf "$version_dir" >/dev/null 2>&1; then
                scan_maven_dir "$version_dir"
            else
                echo "  ${WARN} Artifact $ARTIFACT_ID version $MAVEN_VERSION not found at $MAVEN_GROUP"
            fi
        fi

        # Strategy 2: Scan sub-modules under the group dir for this version
        if [ "$MAVEN_OK" -eq 0 ] && [ "$MAVEN_FAIL" -eq 0 ]; then
            echo "  ${WARN} No known artifact matched. Sampling sub-modules ..."
            RAW=$(curl -sS "${MAVEN_URL}${MAVEN_GROUP}/" 2>/dev/null || true)
            SUBMODULES=$(echo "$RAW" | grep -oE 'href="[^"]+/"' | grep -v '\.\.' | sed 's/href="//;s/"//g;s/\/$//' || true)
            SAMPLE_COUNT=0
            for raw_mod in $SUBMODULES; do
                [ "$SAMPLE_COUNT" -ge "$MAVEN_SAMPLES" ] && break
                mod=$(basename "$raw_mod")
                version_dir="${MAVEN_URL}${MAVEN_GROUP}/${mod}/${MAVEN_VERSION}/"
                if curl -sf "$version_dir" >/dev/null 2>&1; then
                    scan_maven_dir "$version_dir"
                    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
                fi
            done
        fi

        # Strategy 3: If still nothing, try to discover version from repo
        if [ "$MAVEN_OK" -eq 0 ] && [ "$MAVEN_FAIL" -eq 0 ]; then
            echo "  ${WARN} No ${MAVEN_VERSION} artifacts found. Scanning for any version ..."
            RAW=$(curl -sS "${MAVEN_URL}${MAVEN_GROUP}/" 2>/dev/null || true)
            SUBMODULES=$(echo "$RAW" | grep -oE 'href="[^"]+/"' | grep -v '\.\.' | sed 's/href="//;s/"//g;s/\/$//' || true)
            SAMPLE_COUNT=0
            for raw_mod in $SUBMODULES; do
                [ "$SAMPLE_COUNT" -ge "$MAVEN_SAMPLES" ] && break
                mod=$(basename "$raw_mod")
                VERSIONS=$(curl -sS "${MAVEN_URL}${MAVEN_GROUP}/${mod}/" 2>/dev/null | grep -oE 'href="[^"]+/"' | grep -v '\.\.' | sed 's/href="//;s/"//g;s/\/$//' || true)
                latest_ver=$(echo "$VERSIONS" | sort -V | tail -1)
                [ -z "$latest_ver" ] && continue
                version_dir="${MAVEN_URL}${MAVEN_GROUP}/${mod}/${latest_ver}/"
                scan_maven_dir "$version_dir"
                SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
            done
        fi

        echo ""
        echo "  Maven verification results:"
        [ "$MAVEN_OK" -gt 0 ] && echo "    ${PASS} Signed artifacts verified: $MAVEN_OK"
        [ "$MAVEN_FAIL" -gt 0 ] && echo "    ${FAIL} Failed: $MAVEN_FAIL"
        if [ "$MAVEN_OK" -eq 0 ] && [ "$MAVEN_FAIL" -eq 0 ]; then
            echo "    ${WARN} No Maven artifacts found to verify"
        fi
        echo ""
    fi
fi

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
echo "========================================================"
echo -e "${BOLD}  VERIFICATION SUMMARY${NC}"
echo "========================================================"

OVERALL=true
TOTAL=${#ARTIFACTS[@]}

echo "  1. KEYS file                    $([ -n "$KEY_COUNT" ] && echo "${PASS}" || echo "${FAIL}") Found: $([ -n "$KEY_COUNT" ] && echo "$KEY_COUNT keys" || echo "no")"
echo "  2. Artifact downloads           $([ "$DOWNLOADED" -gt 0 ] && echo "${PASS}" || echo "${FAIL}") $DOWNLOADED artifacts"
echo "  3. SHA1 hashes                  $([ "$SHA1_FAIL" -eq 0 ] && echo "${PASS}" || echo "${FAIL}") ${TOTAL} checked"
echo "  4. SHA256 hashes                $([ "$SHA256_FAIL" -eq 0 ] && echo "${PASS}" || echo "${FAIL}") ${TOTAL} checked"
echo "  5. SHA512 hashes                $([ "$SHA512_FAIL" -eq 0 ] && echo "${PASS}" || echo "${FAIL}") ${TOTAL} checked"
echo "  6. GPG signatures               $([ "$SIG_FAIL" -eq 0 ] && echo "${PASS}" || echo "${FAIL}") ${SIG_PASS} good, ${SIG_FAIL} bad"
echo -n "  7. Maven staging               "
if [ -n "$MAVEN_URL" ] && [ "$SKIP_MAVEN" = false ]; then
    echo -e " $([ "$MAVEN_FAIL" -eq 0 ] && [ "$MAVEN_OK" -gt 0 ] && echo "${PASS}" || echo "${FAIL}") ${MAVEN_OK} verified, ${MAVEN_FAIL} failed"
else
    echo -e " ${YELLOW}skipped${NC}"
fi

[ "$SHA1_FAIL" -gt 0 ] && OVERALL=false
[ "$SHA256_FAIL" -gt 0 ] && OVERALL=false
[ "$SHA512_FAIL" -gt 0 ] && OVERALL=false
[ "$SIG_FAIL" -gt 0 ] && OVERALL=false

echo ""
if [ "$OVERALL" = true ]; then
    echo -e "${GREEN}${BOLD}  ✅ RELEASE INTEGRITY VERIFIED${NC}"
else
    echo -e "${RED}${BOLD}  ❌ RELEASE INTEGRITY CHECK FAILED${NC}"
fi
echo ""
echo "  Full log: $LOG"
echo ""

# Write results.md
{
    echo "# Apache Release Verification Results"
    echo ""
    echo "**Dist URL:** $DIST_URL"
    [ -n "$MAVEN_URL" ] && echo "**Maven URL:** $MAVEN_URL"
    [ -n "$KEYS_URL" ] && echo "**KEYS URL:** $KEYS_URL"
    echo ""
    echo "## Summary"
    echo ""
    echo "| Check | Result | Details |"
    echo "|---|---|---|"
    echo "| KEYS file | $([ -n "$KEY_COUNT" ] && echo "✅" || echo "❌") | $([ -n "$KEY_COUNT" ] && echo "$KEY_COUNT keys from $KEYS_URL" || echo "Not found") |"
    echo "| Artifact downloads | $([ "$DOWNLOADED" -gt 0 ] && echo "✅" || echo "❌") | $DOWNLOADED artifacts |"
    echo "| SHA1 hashes | $([ "$SHA1_FAIL" -eq 0 ] && echo "✅" || echo "❌") | ${TOTAL} checked |"
    echo "| SHA256 hashes | $([ "$SHA256_FAIL" -eq 0 ] && echo "✅" || echo "❌") | ${TOTAL} checked |"
    echo "| SHA512 hashes | $([ "$SHA512_FAIL" -eq 0 ] && echo "✅" || echo "❌") | ${TOTAL} checked |"
    echo "| GPG signatures | $([ "$SIG_FAIL" -eq 0 ] && echo "✅" || echo "❌") | ${SIG_PASS} good |"
    echo ""
    if [ -n "$SIGNER" ]; then
        echo "### Signer Details"
        echo ""
        echo "- **Name:** $SIGNER"
        echo "- **Key ID:** $SIGNER_KEY"
        echo "- **Signed:** $SIGNER_TIME"
        echo ""
    fi
    echo "## Artifacts"
    echo ""
    echo "| File | SHA1 | SHA256 | SHA512 | GPG |"
    echo "|---|---|---|---|---|"
    for f in "${ARTIFACTS[@]}"; do
        [ ! -f "$OUTPUT_DIR/dist/$f" ] && continue
        s1="$([ -f "$OUTPUT_DIR/dist/$f.sha1" ] && echo "✅" || echo "-")"
        s256="$([ -f "$OUTPUT_DIR/dist/$f.sha256" ] && echo "✅" || echo "-")"
        s512="$([ -f "$OUTPUT_DIR/dist/$f.sha512" ] && echo "✅" || echo "-")"
        gp="$([ -f "$OUTPUT_DIR/dist/$f.asc" ] && echo "✅" || echo "-")"
        echo "| $f | $s1 | $s256 | $s512 | $gp |"
    done
} > "$RESULTS"

echo "  Markdown report: $RESULTS"
echo ""

if [ "$CLEANUP" = true ]; then
    echo "  (work directory will be cleaned up on exit)"
fi
echo "========================================================"

exit $([ "$OVERALL" = true ] && echo 0 || echo 1)
