# Live Safety Demo

Demo kết nối app Flutter Android với backend FastAPI:

1. App gọi `GET /health` và `POST /sessions` bằng HTTPS.
2. App mở một kết nối WSS và giữ kết nối trong phiên.
3. Người dùng có thể gửi event video/audio giả lập và ping để kiểm tra server
   nhận rồi phản hồi.
4. Khi tắt, app gọi `DELETE /sessions/{id}` bằng HTTPS và đóng WSS.

> **Giới hạn demo:** event video/audio chỉ chứa chuỗi giả lập mã hóa Base64.
> App chưa mở camera/microphone, chưa có VAD, nhận dạng tiếng nói, xử lý an toàn
> hoặc AI. Chứng chỉ trong hướng dẫn chỉ dùng cho môi trường phát triển LAN.

## Cấu trúc project

```text
do-an/
├── backend/
│   ├── src/backend/                  # FastAPI và entry point chạy server
│   ├── tests/                        # Backend/API/WebSocket tests
│   ├── pyproject.toml
│   └── uv.lock
├── mobile/
│   ├── android/                      # Project Android và Gradle wrapper
│   ├── lib/
│   │   ├── features/live_demo/       # Màn hình và trạng thái UI
│   │   └── services/                 # HTTPS/WSS client
│   ├── test/                         # Flutter widget tests
│   ├── pubspec.yaml
│   └── pubspec.lock
├── .gitignore                        # Ignore rules chung
└── README.md                         # Hướng dẫn chạy project
```

Chỉ README này là hướng dẫn chạy. File chứng chỉ/private key, virtual
environment, cấu hình Android SDK riêng của máy và cache/build bị Git ignore.

## Yêu cầu cài đặt

- Windows 10/11.
- Python 3.12 trở lên và [`uv`](https://docs.astral.sh/uv/).
- Flutter SDK, Android Studio và Android SDK.
- Android NDK `28.2.13676358`.
- OpenSSL.
- Điện thoại Android có bật USB debugging. Máy tính và điện thoại cần cùng
  mạng LAN/Wi-Fi để app truy cập server bằng IP máy tính.

Kiểm tra lệnh đã có trong PowerShell:

```powershell
uv --version
flutter --version
openssl version
```

### Cài NDK nếu máy chưa có

Mở Android Studio → **Tools → SDK Manager → SDK Tools** → đánh dấu **Show
Package Details** → **NDK (Side by side)** → chọn `28.2.13676358` → **Apply**.
Đây là NDK Gradle cần để build app Android.

## Chạy lần đầu

### Bước 1: Lấy IP LAN của máy tính

Mở PowerShell và chạy:

```powershell
ipconfig
```

Trong card Wi-Fi đang dùng, ghi lại **IPv4 Address**, ví dụ `192.168.1.62`.
Điện thoại phải cùng mạng Wi-Fi. Không nhập `localhost` trong app: trên điện
thoại, `localhost` là chính điện thoại, không phải máy tính.

### Bước 2: Tạo chứng chỉ HTTPS/WSS

Mở **PowerShell số 1** và chạy các lệnh sau. Thay IP mẫu bằng IP máy tính vừa
tìm được:

```powershell
cd d:\do-an\backend
$LAN_IP = "192.168.1.62"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 `
  -keyout dev-key.pem -out dev-cert.pem -subj "/CN=$LAN_IP" `
  -addext "subjectAltName=IP:$LAN_IP,DNS:localhost,IP:127.0.0.1"
```

Hai file được tạo trong `d:\do-an\backend`:

- `dev-cert.pem`: certificate public; dán nội dung file này vào app.
- `dev-key.pem`: private key; chỉ backend sử dụng. Không dán vào app, không gửi
  cho người khác, không commit lên Git.

Cả hai file đều được ignore. Nếu `openssl` không nhận diện, cài OpenSSL hoặc
dùng OpenSSL đi kèm Git for Windows (thường ở
`C:\Program Files\Git\usr\bin\openssl.exe`), rồi chạy lại lệnh bằng đường dẫn
đầy đủ.

### Bước 3: Cài dependency và khởi động backend

Tiếp tục trong **PowerShell số 1**, ngay thư mục `d:\do-an\backend`:

```powershell
uv sync
$env:SSL_CERTFILE = (Resolve-Path .\dev-cert.pem).Path
$env:SSL_KEYFILE = (Resolve-Path .\dev-key.pem).Path
$env:HOST = "0.0.0.0"
$env:PORT = "8443"
uv run backend
```

Để nguyên cửa sổ này mở. Backend phải in dòng tương tự:

```text
Uvicorn running on https://0.0.0.0:8443
```

Log request và lỗi của server sẽ xuất hiện trong chính cửa sổ này. Dừng server
bằng `Ctrl+C`.

### Bước 4: Kiểm tra server trước khi chạy app

Mở **PowerShell số 2**:

```powershell
cd d:\do-an\backend
$LAN_IP = "192.168.1.62" # Dùng cùng IP đã nhập ở bước 2
curl.exe --cacert .\dev-cert.pem "https://${LAN_IP}:8443/health"
```

Kết quả đúng:

```json
{"ready":true}
```

Nếu không kết nối được, kiểm tra backend còn chạy và `$LAN_IP` đúng với IPv4
Wi-Fi hiện tại của máy tính.

### Bước 5: Mở cổng Windows Firewall nếu cần

Nếu app không kết nối được dù bước 4 chạy thành công, kiểm tra Windows
Firewall. Có thể mở PowerShell bằng **Run as Administrator**, rồi tạo rule chỉ
cho mạng nội bộ:

```powershell
New-NetFirewallRule -DisplayName "Live Safety Demo 8443" `
  -Direction Inbound -Protocol TCP -LocalPort 8443 `
  -Action Allow -Profile Any -RemoteAddress LocalSubnet
```

Không mở cổng demo này ra Internet.

### Bước 6: Kết nối điện thoại và chạy Flutter app

Trên điện thoại, bật **Developer options → USB debugging**, cắm USB và chọn
cho phép debugging nếu điện thoại hỏi. Mở **PowerShell số 3**:

```powershell
cd d:\do-an\mobile
flutter pub get
flutter devices
```

Tìm dòng điện thoại, ví dụ:

```text
CPH2495 (mobile) • DY8HXC7XOZU4LZZ5 • android-arm64
```

Chạy app bằng device ID hiển thị trên máy bạn:

```powershell
flutter run -d DY8HXC7XOZU4LZZ5
```

`flutter run` sẽ build, cài app và mở app trên điện thoại. Giữ cửa sổ PowerShell
này mở trong lúc debug; nhấn `q` để thoát phiên chạy Flutter.

> Nếu `flutter devices` chỉ hiện Windows/Chrome/Edge: kiểm tra cáp USB hỗ trợ
> truyền dữ liệu, bật USB debugging, chấp nhận hộp thoại RSA trên điện thoại,
> sau đó chạy lại `flutter devices`. Việc app thấy điện thoại qua USB không
> thay thế yêu cầu máy tính và điện thoại cùng Wi-Fi để kết nối backend.

### Bước 7: Nhập địa chỉ server và certificate trong app

Trong app trên điện thoại:

1. Tại **IP / hostname**, nhập IP LAN máy tính, ví dụ `192.168.1.62`.
2. Để **Port** là `8443`.
3. Mở **Chứng chỉ TLS dev (PEM)**.
4. Trên máy tính, mở certificate public:

   ```powershell
   notepad d:\do-an\backend\dev-cert.pem
   ```

5. Sao chép toàn bộ nội dung từ `-----BEGIN CERTIFICATE-----` đến
   `-----END CERTIFICATE-----`, rồi dán vào ô PEM trong app. **Không dán**
   `dev-key.pem`.
6. Nhấn **Bắt đầu**.

Kết nối thành công khi trạng thái là **ĐANG LIVE** và log trong app hiển thị
health sẵn sàng, tạo session, rồi `session_ready`. Cửa sổ backend cũng sẽ hiện
các request `GET /health` và `POST /sessions`.

## Thử dữ liệu qua WSS và tắt phiên

Khi app hiển thị **ĐANG LIVE**:

1. Nhấn **Thử video event**; app gửi event `video_frame`. Server trả
   `media_received`.
2. Nhấn **Thử audio event**; app gửi event `audio_chunk`. Server trả
   `media_received`.
3. Nhấn **Ping**; server trả `pong`.
4. Nhấn **Tắt phiên**; backend nhận `DELETE /sessions/{session_id}` rồi đóng
   WebSocket. App trở về trạng thái chưa kết nối.

Payload hiện tại chỉ là chuỗi giả lập Base64 để thử đường truyền, không phải
khung hình camera hay audio thật.

## Chạy lại sau lần đầu

Chứng chỉ đã tạo thì không cần tạo lại. Mỗi lần chạy lại, mở hai cửa sổ:

**PowerShell backend:**

```powershell
cd d:\do-an\backend
$env:SSL_CERTFILE = (Resolve-Path .\dev-cert.pem).Path
$env:SSL_KEYFILE = (Resolve-Path .\dev-key.pem).Path
$env:HOST = "0.0.0.0"
$env:PORT = "8443"
uv run backend
```

**PowerShell mobile:**

```powershell
cd d:\do-an\mobile
flutter run -d <device-id>
```

Thay `<device-id>` bằng ID điện thoại đang hiện trong `flutter devices`. Giữ
backend chạy trong toàn bộ phiên thử. Backend giữ session trong RAM; khởi động
lại backend sẽ xóa các session cũ.

## Tạo APK cài thủ công (không bắt buộc)

Để build APK debug:

```powershell
cd d:\do-an\mobile
flutter pub get
flutter build apk --debug
```

APK nằm tại:

```text
d:\do-an\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

Có thể cài APK lên điện thoại bằng USB debugging:

```powershell
flutter install -d <device-id>
```

## Lỗi thường gặp

### App báo timeout

- Xác nhận backend đang in `Uvicorn running ...` và chưa bị `Ctrl+C`.
- Điện thoại và máy tính đang cùng mạng Wi-Fi; nhập **IP Wi-Fi của máy tính**,
  không nhập `localhost`, `127.0.0.1` hoặc IP điện thoại.
- Chạy lại lệnh `curl.exe --cacert ... /health` ở bước 4.
- Kiểm tra Windows Firewall cho phép TCP `8443` từ mạng LAN.
- Kiểm tra IP máy tính không đổi sau khi chuyển Wi-Fi.

### App báo lỗi chứng chỉ hoặc TLS handshake

- Certificate dán vào app phải là `dev-cert.pem`, không phải private key.
- IP nhập trong app phải trùng IP đã dùng khi tạo certificate.
- Nếu IP máy tính đổi, tạo certificate mới theo IP mới và cập nhật certificate
  trong app.
- Không tắt xác minh certificate/TLS để né lỗi.

### Backend hiện `DELETE ... 404 Not Found`

Backend chỉ giữ session trong bộ nhớ. Nếu server đã restart thì session cũ
không còn; bản mobile hiện tại dọn trạng thái session cũ và cho phép bắt đầu
lại.

## Chạy kiểm tra code

```powershell
cd d:\do-an\backend
uv run python -m unittest discover -s tests -v

cd d:\do-an\mobile
flutter pub get
flutter analyze
flutter test
```

## API backend

| Method | Đường dẫn | Tác dụng |
|---|---|---|
| `GET` | `/health` | Kiểm tra server, trả `{"ready":true}` |
| `POST` | `/sessions` | Tạo session và trả `session_id`, `websocket_path` |
| `WSS` | `/ws/live/{session_id}` | Giữ kết nối và trao đổi event JSON |
| `DELETE` | `/sessions/{session_id}` | Kết thúc session và đóng socket |

Không dùng server hoặc certificate dev này cho production.
