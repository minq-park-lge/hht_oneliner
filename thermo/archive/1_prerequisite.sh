#!/bin/bash
set -e

echo "=================================================="
# 1. 호스트 시스템 필수 패키지 및 gcc-12 설치
# ==================================================
echo "[1/3] Updating system packages and installing GCC 12..."
sudo apt-get update && sudo apt-get install -y \
    gcc-12 g++-12 build-essential libffi-dev libssl-dev \
    libdbus-1-dev libglib2.0-dev libavahi-client-dev \
    libgirepository1.0-dev libcairo2-dev libreadline-dev

# ==================================================
# 2. Homebrew를 통한 Python 3.11 및 빌드 툴체인 관리
# ==================================================
echo "[2/3] Installing Python 3.11, CMake, and Ninja via Homebrew..."
brew install python@3.11 cmake ninja

# ==================================================
# 3. PEP 668 우회 및 로컬 심볼릭 링크 정렬
# ==================================================
echo "[3/3] Setting up local Python symlinks and West..."
mkdir -p "$HOME/.local/bin"
ln -sf /home/linuxbrew/.linuxbrew/bin/pip3.11 "$HOME/.local/bin/pip"
ln -sf /home/linuxbrew/.linuxbrew/bin/pip3.11 "$HOME/.local/bin/pip3"
ln -sf /home/linuxbrew/.linuxbrew/bin/python3.11 "$HOME/.local/bin/python"
ln -sf /home/linuxbrew/.linuxbrew/bin/python3.11 "$HOME/.local/bin/python3"

# 환경변수 반영
export PATH="$HOME/.local/bin:$PATH"
hash -r

# West 전역 설치 (가상환경 외부 차단 우회)
pip3 install west --break-system-packages

echo "=================================================="
echo " Prerequisite installation completed successfully! "
echo "=================================================="