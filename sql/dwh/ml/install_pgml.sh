#!/bin/bash
# Install pgml extension from source for PostgreSQL 15
# This script compiles and installs pgml in your existing PostgreSQL installation
#
# Prerequisites:
# - PostgreSQL 14+ installed
# - Build tools (build-essential), cmake (required by xgboost-sys / lightgbm-sys crates)
# - Python 3 development headers
#
# Usage: sudo ./install_pgml.sh

set -euo pipefail

# Minimal/containers and some sudo setups use a short PATH; cmake/gcc live in /usr/bin.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:${PATH}}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== pgml Installation Script ===${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
 echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
 exit 1
fi

# Check PostgreSQL version
echo -e "${YELLOW}Checking PostgreSQL installation...${NC}"

# Find all PostgreSQL versions installed
echo "Checking for installed PostgreSQL versions..."
PG_VERSIONS=$(find /usr/lib/postgresql -maxdepth 2 -name 'pg_config' -type f 2> /dev/null | sed 's|.*postgresql/\([0-9]*\)/.*|\1|' | sort -V)
if [[ -z "$PG_VERSIONS" ]]; then
 # Try alternative location
 PG_VERSIONS=$(find /usr/share/postgresql -maxdepth 2 -type d -name 'extension' 2> /dev/null | sed 's|.*postgresql/\([0-9]*\)/.*|\1|' | sort -V)
fi

if [[ -n "$PG_VERSIONS" ]]; then
 echo "Found PostgreSQL versions: $PG_VERSIONS"
fi

# Get version from psql
PG_VERSION=$(psql --version | grep -oP '\d+' | head -1)
if [[ -z "$PG_VERSION" ]]; then
 echo -e "${RED}Error: PostgreSQL not found${NC}"
 exit 1
fi
echo "Using PostgreSQL ${PG_VERSION} (from psql --version)"

# Find the correct pg_config for this version
PG_CONFIG_DEFAULT=$(which pg_config)
PG_CONFIG_VERSION="/usr/lib/postgresql/${PG_VERSION}/bin/pg_config"

if [[ -f "$PG_CONFIG_VERSION" ]]; then
 PG_CONFIG_FULL="$PG_CONFIG_VERSION"
 echo "Using pg_config from PostgreSQL ${PG_VERSION}: $PG_CONFIG_FULL"
elif [[ -n "$PG_CONFIG_DEFAULT" ]]; then
 PG_CONFIG_FULL="$PG_CONFIG_DEFAULT"
 echo "Using default pg_config: $PG_CONFIG_FULL"
 echo "Version: $($PG_CONFIG_FULL --version 2> /dev/null || echo 'unknown')"
else
 echo -e "${RED}Error: pg_config not found${NC}"
 exit 1
fi

# Check if PostgreSQL 14+
if [[ $PG_VERSION -lt 14 ]]; then
 echo -e "${RED}Error: pgml requires PostgreSQL 14 or higher (found ${PG_VERSION})${NC}"
 exit 1
fi

# Install build dependencies
echo -e "${YELLOW}Installing build dependencies...${NC}"
apt-get update
apt-get install -y \
 build-essential \
 cmake \
 binutils \
 lld \
 "postgresql-server-dev-${PG_VERSION}" \
 libpython3-dev \
 python3-pip \
 python3-numpy \
 python3-scipy \
 python3-xgboost \
 curl \
 git \
 pkg-config \
 libssl-dev \
 libopenblas-dev \
 libgomp1

hash -r 2> /dev/null || true

# Verify linkers are available
if ! command -v ld &> /dev/null; then
 echo -e "${RED}Error: Linker 'ld' not found after installing binutils${NC}"
 exit 1
fi
echo "Linker 'ld' found: $(which ld)"

if ! command -v ld.lld &> /dev/null; then
 echo -e "${YELLOW}Warning: LLD linker not found, but continuing...${NC}"
else
 echo "LLD linker found: $(which ld.lld)"
fi

if ! command -v cmake &> /dev/null; then
 echo -e "${RED}Error: cmake is required to build pgml (xgboost/lightgbm) but was not found${NC}"
 echo "Install with: apt-get install -y cmake"
 exit 1
fi
# cmake-rs (used by xgboost-sys) honors CMAKE; use an absolute path to avoid ENOENT under tight PATH.
CMAKE_BIN="$(command -v cmake)"
export CMAKE="$CMAKE_BIN"
echo "cmake found: ${CMAKE} ($(cmake --version | head -1))"
echo "Exported CMAKE=${CMAKE} for Rust build scripts"

# Check if Rust is installed
echo -e "${YELLOW}Checking Rust installation...${NC}"
if ! command -v cargo &> /dev/null; then
 echo "Rust not found. Installing Rust..."
 curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

 # Source Rust environment for current shell
 export PATH="$HOME/.cargo/bin:$PATH"
 # shellcheck disable=SC1091
 # Source may not exist immediately after installation
 if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
 fi

 # Also add to current session
 export CARGO_HOME="$HOME/.cargo"
 export RUSTUP_HOME="$HOME/.rustup"
else
 echo "Rust already installed: $(cargo --version)"
fi

# Ensure Rust is in PATH
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo &> /dev/null; then
 echo -e "${RED}Error: Rust installation failed or not in PATH${NC}"
 echo "Please run: source \$HOME/.cargo/env"
 exit 1
fi

# Install pgrx (PostgreSQL extension framework for Rust)
echo -e "${YELLOW}Installing pgrx...${NC}"
if ! command -v cargo-pgrx &> /dev/null; then
 echo "Installing cargo-pgrx..."
 if ! cargo install --locked cargo-pgrx --version 0.12.9; then
  echo -e "${RED}Error: Failed to install cargo-pgrx${NC}"
  exit 1
 fi
else
 echo "cargo-pgrx already installed: $(cargo-pgrx --version)"
fi

# Set up PGRX_HOME (required by pgrx framework)
echo -e "${YELLOW}Setting up pgrx environment...${NC}"
# Use explicit path to avoid issues with $HOME when running as root
PGRX_HOME_DIR="${PGRX_HOME:-$HOME/.pgrx}"
export PGRX_HOME="$PGRX_HOME_DIR"
mkdir -p "$PGRX_HOME"
echo "PGRX_HOME set to: $PGRX_HOME"
echo "Current user: $(whoami)"
echo "HOME: $HOME"

# Initialize pgrx (creates config.toml)
# The correct command is 'cargo pgrx init', not 'cargo-pgrx init'
if command -v cargo-pgrx &> /dev/null; then
 echo -e "${YELLOW}Initializing pgrx for PostgreSQL ${PG_VERSION}...${NC}"
 # Use the pg_config we found earlier (for the correct PostgreSQL version)
 echo "Using pg_config: $PG_CONFIG_FULL"
 echo "pg_config version: $($PG_CONFIG_FULL --version 2> /dev/null || echo 'unknown')"

 # Initialize pgrx with explicit PostgreSQL version and pg_config path
 # The correct syntax is --pg16=/path/to/pg_config (with =)
 echo "Running: cargo pgrx init --pg${PG_VERSION}=$PG_CONFIG_FULL"

 # Try with = syntax first (this is the correct syntax)
 if cargo pgrx init --pg"${PG_VERSION}"="$PG_CONFIG_FULL"; then
  echo -e "${GREEN}pgrx initialized successfully for PostgreSQL ${PG_VERSION}${NC}"
 else
  echo -e "${YELLOW}Warning: pgrx init with = syntax failed, trying space syntax...${NC}"
  # Try with space syntax
  if cargo pgrx init --pg"${PG_VERSION}" "$PG_CONFIG_FULL"; then
   echo -e "${GREEN}pgrx initialized successfully for PostgreSQL ${PG_VERSION}${NC}"
  else
   echo -e "${YELLOW}Warning: pgrx init with pg_config path failed, trying without path...${NC}"
   # Try with just the version flag
   if cargo pgrx init --pg"${PG_VERSION}"; then
    echo -e "${GREEN}pgrx initialized successfully for PostgreSQL ${PG_VERSION}${NC}"
   else
    echo -e "${RED}Error: Failed to initialize pgrx${NC}"
    echo "This is required for building pgml. Please check:"
    echo "  1. PostgreSQL ${PG_VERSION} is installed"
    echo "  2. pg_config is in PATH: $(which pg_config)"
    echo "  3. pg_config version: $(pg_config --version)"
    echo "  4. pg_config path: $PG_CONFIG_FULL"
    echo "  5. You have permissions to write to $PGRX_HOME"
    echo ""
    echo "Trying to get help from cargo-pgrx:"
    cargo pgrx init --help || true
    exit 1
   fi
  fi
 fi

 # Verify config.toml was created
 if [[ ! -f "$PGRX_HOME/config.toml" ]]; then
  echo -e "${RED}Error: pgrx config.toml was not created${NC}"
  exit 1
 fi

 echo "pgrx config.toml created at: $PGRX_HOME/config.toml"
 echo "Config contents:"
 head -20 < "$PGRX_HOME/config.toml"
fi

# Clone pgml repository
BUILD_DIR="/tmp/pgml-build"
echo -e "${YELLOW}Cloning pgml repository...${NC}"
if [[ -d "$BUILD_DIR" ]]; then
 echo "Removing existing build directory..."
 rm -rf "$BUILD_DIR"
fi

git clone https://github.com/postgresml/postgresml.git "$BUILD_DIR"
cd "$BUILD_DIR"

# Checkout latest stable release (optional, but recommended)
echo -e "${YELLOW}Checking out latest stable release...${NC}"
LATEST_TAG=$(git describe --tags --abbrev=0 2> /dev/null || echo "")
if [[ -n "$LATEST_TAG" ]]; then
 echo "Using tag: $LATEST_TAG"
 git checkout "$LATEST_TAG"
else
 echo "Using latest commit from main branch"
fi

# pgml uses a monorepo structure - the extension is in pgml-extension/
if [[ ! -d "pgml-extension" ]]; then
 echo -e "${RED}Error: pgml-extension directory not found${NC}"
 echo "Repository structure may have changed. Please check https://github.com/postgresml/postgresml"
 exit 1
fi

# Change to the extension directory
cd pgml-extension

# Store the build directory path for later use in install_pgml_for_version
BUILD_DIR_EXTENSION="$BUILD_DIR/pgml-extension"

# Set PGRX_HOME (required by pgrx framework)
export PGRX_HOME="${PGRX_HOME:-$HOME/.pgrx}"
mkdir -p "$PGRX_HOME"
echo "PGRX_HOME set to: $PGRX_HOME"

# Configure Rust linker - use standard ld if lld is not available
# Rust tries to use lld by default, but it may not be installed
if ! command -v ld.lld &> /dev/null; then
 echo -e "${YELLOW}LLD not found, configuring Rust to use standard linker...${NC}"
 # Use bfd linker (standard GNU linker) instead of lld
 export RUSTFLAGS="-C link-arg=-fuse-ld=bfd"
else
 echo "Using LLD linker: $(which ld.lld)"
fi

# Set Cargo build jobs
CARGO_BUILD_JOBS=$(nproc)
export CARGO_BUILD_JOBS

echo -e "${YELLOW}Prepared pgml source code for building...${NC}"
echo "Will build and install for each PostgreSQL version found"

# Function to build and install pgml for a specific PostgreSQL version
# This function must be called from the pgml-extension directory
install_pgml_for_version() {
 local target_version=$1
 local target_pg_config="/usr/lib/postgresql/${target_version}/bin/pg_config"

 if [[ ! -f "$target_pg_config" ]]; then
  echo -e "${YELLOW}Skipping PostgreSQL ${target_version}: pg_config not found${NC}"
  return 1
 fi

 # Ensure we're in the pgml-extension directory
 local original_dir
 original_dir=$(pwd)
 if [[ ! -f "Cargo.toml" ]] || ! grep -q "name = \"pgml\"" Cargo.toml 2> /dev/null; then
  if [[ -d "$BUILD_DIR_EXTENSION" ]]; then
   cd "$BUILD_DIR_EXTENSION" || {
    echo -e "${RED}Error: Cannot change to $BUILD_DIR_EXTENSION${NC}"
    return 1
   }
  else
   echo -e "${RED}Error: pgml-extension directory not found at $BUILD_DIR_EXTENSION${NC}"
   return 1
  fi
 fi

 echo ""
 echo -e "${GREEN}=== Installing pgml for PostgreSQL ${target_version} ===${NC}"
 echo "Working directory: $(pwd)"

 # Initialize pgrx for this version
 echo "Initializing pgrx for PostgreSQL ${target_version}..."
 if ! cargo pgrx init --pg"${target_version}"="$target_pg_config" 2> /dev/null; then
  # If init fails, manually add to config.toml
  if ! grep -q "\[pg${target_version}\]" "$PGRX_HOME/config.toml" 2> /dev/null; then
   echo "[pg${target_version}]" >> "$PGRX_HOME/config.toml"
   echo "path = \"$target_pg_config\"" >> "$PGRX_HOME/config.toml"
  fi
 fi

 # Set environment variables for this version
 export PGRX_PG_CONFIG_PATH="$target_pg_config"
 export PGRX_PG_VERSION_OVERRIDE="pg${target_version}"
 export PGRX_PG_VERSION="pg${target_version}"
 export PG_CONFIG="$target_pg_config"

 # Build with explicit version override
 # CRITICAL: pgml's Cargo.toml has default = ["pg17", "python"]
 # We MUST disable default features and enable pg${target_version} + python explicitly
 echo -e "${YELLOW}Building pgml extension for PostgreSQL ${target_version}...${NC}"
 echo "Using: cargo build --release --no-default-features --features pg${target_version},python"

 if ! cargo build --release --no-default-features --features "pg${target_version},python"; then
  echo -e "${RED}Error: Failed to build pgml for PostgreSQL ${target_version}${NC}"
  return 1
 fi

 # Install pgml extension
 # CRITICAL: cargo pgrx install uses the 'default' value from config.toml
 # We need to temporarily change it to the target version
 echo -e "${YELLOW}Installing pgml extension for PostgreSQL ${target_version}...${NC}"

 # Backup and update config.toml default
 local config_file="$PGRX_HOME/config.toml"
 local original_default=""
 if [[ -f "$config_file" ]]; then
  # Ensure pg${target_version} entry exists in config.toml (format: pg14 = "/path/to/pg_config")
  if ! grep -q "^pg${target_version}" "$config_file"; then
   # Find the [configs] section and add the entry after it
   if grep -q "^\[configs\]" "$config_file"; then
    # Add after [configs] line
    sed -i "/^\[configs\]/a pg${target_version} = \"$target_pg_config\"" "$config_file"
   else
    # Add [configs] section if it doesn't exist
    echo "[configs]" >> "$config_file"
    echo "pg${target_version} = \"$target_pg_config\"" >> "$config_file"
   fi
  else
   # Update existing entry to ensure it points to the correct path
   sed -i "s|^pg${target_version} = \".*\"|pg${target_version} = \"$target_pg_config\"|" "$config_file"
  fi

  # Extract current default value
  original_default=$(grep "^default" "$config_file" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' || echo "")

  # Update default to target version
  if grep -q "^default" "$config_file"; then
   # Replace existing default line
   sed -i "s/^default = \".*\"/default = \"pg${target_version}\"/" "$config_file"
  else
   # Add default if it doesn't exist (should be after [configs] section)
   if grep -q "^\[configs\]" "$config_file"; then
    sed -i "/^\[configs\]/a default = \"pg${target_version}\"" "$config_file"
   else
    echo "default = \"pg${target_version}\"" >> "$config_file"
   fi
  fi

  # Verify the change was applied
  local new_default
  new_default=$(grep "^default" "$config_file" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' || echo "")
  if [[ "$new_default" == "pg${target_version}" ]]; then
   echo "Temporarily set default to pg${target_version} in config.toml"
   echo "Config file now contains:"
   grep -E "^(default|pg${target_version}|\[configs\])" "$config_file" | head -5
  else
   echo -e "${RED}Error: Failed to set default to pg${target_version} (found: $new_default)${NC}"
   echo "Config file contents:"
   cat "$config_file"
   return 1
  fi
 fi

 # Set environment variables to ensure correct version is used
 export PGRX_PG_CONFIG_PATH="$target_pg_config"
 export PGRX_PG_VERSION_OVERRIDE="pg${target_version}"
 export PGRX_PG_VERSION="pg${target_version}"
 export PG_CONFIG="$target_pg_config"
 export PGRX_DEFAULT_PG_VERSION="pg${target_version}"

 # CRITICAL: Update PATH to prioritize the correct pg_config
 # This ensures that /usr/bin/pg_config (which might be a symlink to pg16) is not used
 local pg_config_dir
 pg_config_dir=$(dirname "$target_pg_config")
 export PATH="$pg_config_dir:$PATH"

 # Verify the correct pg_config is being used
 local current_pg_config
 current_pg_config=$(which pg_config)
 echo "Using pg_config: $current_pg_config"
 echo "Expected pg_config: $target_pg_config"
 if [[ "$current_pg_config" != "$target_pg_config" ]]; then
  echo -e "${YELLOW}Warning: pg_config in PATH ($current_pg_config) differs from target ($target_pg_config)${NC}"
  echo "Forcing use of target pg_config via PATH"
 fi

 if ! cargo pgrx install; then
  # Restore original default on error
  if [[ -n "$original_default" ]] && [[ -f "$config_file" ]]; then
   sed -i "s/^default = \".*\"/default = \"${original_default}\"/" "$config_file"
  fi
  echo -e "${RED}Error: Failed to install pgml for PostgreSQL ${target_version}${NC}"
  return 1
 fi

 # Restore original default after successful installation
 if [[ -n "$original_default" ]] && [[ -f "$config_file" ]]; then
  sed -i "s/^default = \".*\"/default = \"${original_default}\"/" "$config_file"
  echo "Restored default to ${original_default} in config.toml"
 fi

 # Verify installation for this version
 local pg_libdir
 local pg_sharedir
 pg_libdir=$("$target_pg_config" --pkglibdir)
 pg_sharedir=$("$target_pg_config" --sharedir)

 if [[ -f "$pg_sharedir/extension/pgml.control" ]]; then
  echo -e "${GREEN}✓ pgml extension files installed successfully for PostgreSQL ${target_version}${NC}"
  echo "  Control file: $pg_sharedir/extension/pgml.control"
 else
  echo -e "${YELLOW}⚠ Warning: pgml.control not found for PostgreSQL ${target_version}${NC}"
 fi

 if [[ -f "$pg_libdir/pgml.so" ]] || [[ -f "$pg_libdir/pgml-*.so" ]]; then
  echo -e "${GREEN}✓ pgml library installed successfully for PostgreSQL ${target_version}${NC}"
  echo "  Library directory: $pg_libdir"
 else
  echo -e "${YELLOW}⚠ Warning: pgml library not found for PostgreSQL ${target_version}${NC}"
 fi

 echo -e "${GREEN}✓ pgml installed successfully for PostgreSQL ${target_version}${NC}"

 # Return to original directory
 cd "$original_dir" || true
 return 0
}

# Determine which PostgreSQL versions to install for
# If PG_VERSIONS contains multiple versions, install for all 14+
INSTALL_VERSIONS=""
if [[ -n "$PG_VERSIONS" ]]; then
 echo "Processing detected PostgreSQL versions: $PG_VERSIONS"
 # Filter versions >= 14
 for ver in $PG_VERSIONS; do
  echo "Checking version: $ver"
  if [[ $ver -ge 14 ]]; then
   echo "  ✓ Version $ver is >= 14, adding to install list"
   INSTALL_VERSIONS="$INSTALL_VERSIONS $ver"
  else
   echo "  ✗ Version $ver is < 14, skipping"
  fi
 done
else
 echo "Warning: No PostgreSQL versions detected via find command"
fi

# If no versions found or empty, use the detected PG_VERSION
if [[ -z "$INSTALL_VERSIONS" ]]; then
 echo "No versions found in PG_VERSIONS, using detected PG_VERSION: $PG_VERSION"
 INSTALL_VERSIONS="$PG_VERSION"
fi

# Trim leading/trailing spaces
INSTALL_VERSIONS=$(echo "$INSTALL_VERSIONS" | xargs)

echo ""
echo -e "${YELLOW}Will install pgml for PostgreSQL versions: ${INSTALL_VERSIONS}${NC}"
echo "Number of versions to install: $(echo "$INSTALL_VERSIONS" | wc -w)"

# Install for each version
INSTALLED_COUNT=0
for ver in $INSTALL_VERSIONS; do
 echo ""
 echo -e "${YELLOW}========================================${NC}"
 echo -e "${YELLOW}Installing for PostgreSQL ${ver}...${NC}"
 echo -e "${YELLOW}========================================${NC}"
 if install_pgml_for_version "$ver"; then
  echo -e "${GREEN}✓ Successfully installed for PostgreSQL ${ver}${NC}"
  ((INSTALLED_COUNT++))
 else
  echo -e "${RED}✗ Failed to install for PostgreSQL ${ver}${NC}"
 fi
done

if [[ $INSTALLED_COUNT -eq 0 ]]; then
 echo -e "${RED}Error: Failed to install pgml for any PostgreSQL version${NC}"
 exit 1
fi

echo ""
echo -e "${GREEN}Successfully installed pgml for ${INSTALLED_COUNT} PostgreSQL version(s)${NC}"

# Summary verification
echo ""
echo -e "${YELLOW}Verifying installations...${NC}"
VERIFIED_COUNT=0
for ver in $INSTALL_VERSIONS; do
 pg_config_ver="/usr/lib/postgresql/${ver}/bin/pg_config"
 if [[ -f "$pg_config_ver" ]]; then
  pg_sharedir_ver=$("$pg_config_ver" --sharedir)
  if [[ -f "$pg_sharedir_ver/extension/pgml.control" ]]; then
   echo -e "${GREEN}✓ PostgreSQL ${ver}: pgml.control found${NC}"
   ((VERIFIED_COUNT++))
  else
   echo -e "${YELLOW}⚠ PostgreSQL ${ver}: pgml.control not found${NC}"
  fi
 fi
done

if [[ $VERIFIED_COUNT -eq 0 ]]; then
 echo -e "${RED}✗ Error: No pgml installations verified${NC}"
 exit 1
fi

# Cleanup
echo -e "${YELLOW}Cleaning up build directory...${NC}"
cd /
rm -rf "$BUILD_DIR"

# Cleanup any numpy source directories that might interfere
echo -e "${YELLOW}Cleaning up any numpy source directories...${NC}"
find /tmp -name "numpy" -type d -path "*/pgml-build/*" -exec rm -rf {} + 2> /dev/null || true
find /tmp -name "numpy" -type d -path "*/target/*" -exec rm -rf {} + 2> /dev/null || true

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""

# Install Python ML packages using pip (required for pgml)
echo -e "${YELLOW}Installing Python ML packages...${NC}"
echo "Note: pgml requires numpy, scipy, xgboost, lightgbm, and scikit-learn"
echo "These packages must be installed for the Python version that pgml was compiled with."

# Python for pip: same interpreter pgml was built against (override: export PYTHON_CMD=python3.13)
if [[ -n "${PYTHON_CMD:-}" ]] && command -v "${PYTHON_CMD}" &> /dev/null; then
 :
elif command -v python3 &> /dev/null; then
 PYTHON_CMD="python3"
elif command -v python3.13 &> /dev/null; then
 PYTHON_CMD="python3.13"
elif command -v python3.12 &> /dev/null; then
 PYTHON_CMD="python3.12"
elif command -v python3.11 &> /dev/null; then
 PYTHON_CMD="python3.11"
elif command -v python3.10 &> /dev/null; then
 PYTHON_CMD="python3.10"
fi

PYTHON_MINOR=""
if [[ -n "$PYTHON_CMD" ]]; then
 PYTHON_MINOR="$("${PYTHON_CMD}" -c 'import sys; print("%d.%d" % (sys.version_info[0:2]))' 2> /dev/null || echo "?")"
 echo "Using Python for pip: ${PYTHON_CMD} (${PYTHON_MINOR})"
fi

if [[ -n "$PYTHON_CMD" ]]; then
 PIP_CMD="${PYTHON_CMD} -m pip"

 echo "Installing numpy, scipy, xgboost, lightgbm, and scikit-learn using ${PIP_CMD}..."
 if ${PIP_CMD} install --break-system-packages --ignore-installed --no-cache-dir numpy scipy xgboost lightgbm scikit-learn 2> /dev/null; then
  echo -e "${GREEN}✓ Python ML packages installed successfully (${PYTHON_CMD})${NC}"
 else
  echo -e "${YELLOW}⚠ Warning: Failed to install Python packages with pip${NC}"
  echo "You may need to install them manually:"
  echo "  sudo ${PIP_CMD} install --break-system-packages --ignore-installed --no-cache-dir numpy scipy xgboost lightgbm scikit-learn"
 fi
else
 echo -e "${YELLOW}⚠ Warning: Python 3 not found, skipping Python package installation${NC}"
 echo "Install Python packages manually, e.g.:"
 echo "  sudo python3 -m pip install --break-system-packages --ignore-installed --no-cache-dir numpy scipy xgboost lightgbm scikit-learn"
fi

# Verify Python packages are accessible
echo ""
echo -e "${YELLOW}Verifying Python packages...${NC}"
if [[ -n "$PYTHON_CMD" ]]; then
 if ${PYTHON_CMD} -c "import numpy, scipy, xgboost, lightgbm, sklearn" 2> /dev/null; then
  echo -e "${GREEN}✓ Python packages are accessible (${PYTHON_CMD})${NC}"
 else
  echo -e "${YELLOW}⚠ Warning: Python packages may not be accessible${NC}"
  echo "Try installing with: sudo ${PIP_CMD} install --break-system-packages --ignore-installed --no-cache-dir numpy scipy xgboost lightgbm scikit-learn"
  echo "Then verify with: sudo -u postgres ${PYTHON_CMD} -c 'import numpy, scipy, xgboost, lightgbm, sklearn; print(\"OK\")'"
 fi
else
 echo -e "${YELLOW}⚠ Warning: Cannot verify Python packages (Python not found)${NC}"
fi

echo ""
echo "Next steps:"
echo "1. Install Python ML packages (if not already installed):"
if [[ -n "$PYTHON_CMD" ]]; then
 echo "   sudo ${PIP_CMD} install --break-system-packages --ignore-installed --no-cache-dir numpy scipy xgboost lightgbm scikit-learn"
else
 echo "   sudo python3 -m pip install --break-system-packages --ignore-installed --no-cache-dir numpy scipy xgboost lightgbm scikit-learn"
fi
echo ""
echo "2. Verify packages are accessible to PostgreSQL:"
if [[ -n "$PYTHON_CMD" ]]; then
 echo "   sudo -u postgres ${PYTHON_CMD} -c 'import numpy, scipy, xgboost, lightgbm, sklearn; print(\"OK\")'"
else
 echo "   sudo -u postgres python3 -c 'import numpy, scipy, xgboost, lightgbm, sklearn; print(\"OK\")'"
fi
echo ""
echo "3. Configure shared_preload_libraries in PostgreSQL:"
echo "   psql -d postgres -c \"ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,pgml';\""
echo "   (Note: If pg_stat_statements is not installed, use: 'pgml')"
echo ""
echo "4. Restart PostgreSQL service (Debian/Ubuntu typical cluster is main; adjust if needed):"
echo "   sudo systemctl restart postgresql@${PG_VERSION}-main"
echo "   Or list units: systemctl list-units 'postgresql@*' --no-legend"
echo ""
echo "5. Enable the extension in your database:"
echo "   sudo -u postgres /usr/lib/postgresql/${PG_VERSION}/bin/psql -d notes_dwh -c 'CREATE EXTENSION IF NOT EXISTS pgml;'"
echo ""
echo "6. Verify installation:"
echo "   sudo -u postgres /usr/lib/postgresql/${PG_VERSION}/bin/psql -d notes_dwh -c 'SELECT pgml.version();'"
echo ""
