우분투 22.04 환경에서 NXP 스마트카드 판독기나 NFC 칩셋(예: PN7462 등)을 사용하기 위해 PC/SC 환경을 구축하는 방법입니다.

기본적으로 오픈소스 PC/SC 스택인 `pcsc-lite`와 스마트카드 판독용 표준 드라이버인 `libccid`를 설치하면 대부분의 NXP CCID 장치들이 자동으로 인식됩니다.

---

## 1. 기본 패키지 설치

터미널을 열고 PC/SC 데몬, 툴, 오픈소스 드라이버를 설치합니다. 우분투 22.04에서는 공식 저장소의 패키지로 대부분 해결됩니다.

```bash
sudo apt update
sudo apt install pcscd pcsc-tools libccid libusb-1.0-0-dev opensc

```

---

## 2. 우분투 22.04 자동 시작 버그 조치

우분투 22.04에 포함된 일부 `pcscd` 패키지 버전(1.9.5 등)에서 **백그라운드 서비스(소켓 디바이스)가 자동으로 켜지지 않는 알려진 버그**가 있습니다. 안정적인 연결을 위해 소켓을 강제로 활성화하고 데몬을 재시작해 주어야 합니다.

```bash
# 부팅 시 자동 시작 및 소켓 활성화
sudo systemctl enable pcscd.socket
sudo systemctl start pcscd.socket

# 데몬 서비스 상태 확인
sudo systemctl restart pcscd
sudo systemctl status pcscd

```

---

## 3. (필요 시) NXP 하드웨어 특정 정보 수동 등록

만약 공식 `libccid` 패키지가 너무 구형이거나 최신 NXP 평가 보드(예: PN7462, PR601 등)의 Vendor ID와 Product ID를 바로 잡지 못한다면 드라이버 설정 파일(`Info.plist`)에 명시적으로 추가해 줘야 할 수 있습니다.

1. 장치를 연결한 뒤 `lsusb`를 쳐서 NXP 장치의 ID(예: `1fc9:0117`)를 확인합니다.
2. 아래 설정 파일을 엽니다.
```bash
sudo nano /etc/libccid_Info.plist

```



```
   *(경로에 없다면 `/usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist` 확인)*
3. `<key>ifdVendorID</key>`와 `<key>ifdProductID</key>`의 `<array>` 블록 내부에 확인한 ID 값을 추가한 후 저장합니다. (기본 호환 장치라면 이 과정 없이 바로 인식됩니다.)

---

## 4. 장치 인식 테스트

하드웨어를 USB에 연결한 뒤 아래 명령어를 실행하여 카드가 정상적으로 스캔되는지 확인합니다.

```bash
pcsc_scan

```

정상적으로 연동되었다면 연결된 NXP Reader 장치 명칭과 카드가 접촉/비접촉 되었을 때의 ATR(Answer To Reset) 신호가 터미널에 실시간으로 출력됩니다.
