# 부팅 시 자동 시작 및 소켓 활성화
sudo systemctl enable pcscd.socket
sudo systemctl start pcscd.socket

# 데몬 서비스 상태 확인
sudo systemctl restart pcscd
sudo systemctl status pcscd