# 1. 시스템 업데이트 및 필수 빌드 도구 설치
sudo apt-get update && sudo apt-get install -y build-essential curl git procps

# 2. Linuxbrew 공식 설치 스크립트 실행 (비대화형 자동 설치)
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. 현재 쉘 세션에 브루 환경 변수 즉시 적용
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# 4. 터미널을 다시 열어도 유지되도록 .bashrc에 환경 변수 등록
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc

# 5. 설치 상태 검증
brew doctor