# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng `> *Câu trả lời của bạn*` bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Tiến Tuân  Mã học viên: L3A202602595

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Em gặp đúng tình huống này khi làm bài. Ban đầu `Settings` chỉ được tạo ở request `/ask` đầu tiên, nên khi chạy `docker run` image mà không truyền
`AGENT_API_KEY`, container vẫn lên và `docker ps` báo `healthy` suốt 10 phút —
`/health` không đọc config. Nếu đó là Railway, bản deploy sẽ được đánh dấu
thành công, còn user thì nhận 500 ở mọi lần gọi `/ask`. Sau khi gọi
`get_settings()` ngay trong `lifespan`, container chết sau vài giây với log `ValidationError ... agent_api_key Field required` — lỗi
hiện ra ngay lúc deploy, đúng tên biến bị thiếu.

Nếu để mặc định `"changeme"` thì còn tệ hơn: app chạy "bình thường", và ai
đọc repo công khai cũng biết khóa là `changeme` → gọi `/ask` miễn phí bằng
tiền mà không có lỗi nào báo động.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật từ container khi gọi `/ask`:

```
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T07:48:36.366770+00:00", "user_id": "sv-rl", "tokens_in": 392, "tokens_out": 43, "cost_usd": 8.46e-05}
```

1. **Lọc và cộng theo trường**: tính tổng `cost_usd` theo `user_id` trong
ngày để biết ai tiêu nhiều nhất, hoặc đếm số `ask_completed` mỗi phút.
Railway đã tự tách dòng JSON này thành các trường `user_id=`,
`cost_usd=` trong tab Logs nên lọc được ngay.
2. **Đặt cảnh báo**: ví dụ báo động khi `tokens_in` vượt 5.000 (prompt phình
to) hoặc khi `level` = `error` tăng đột biến.

`print("đã trả lời xong")` không có user, không có số, không có thời điểm
chuẩn — máy không đọc được gì ngoài một chuỗi chữ.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1.73 GB |
| Multi-stage | 297 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Phần chênh ~1.43 GB gồm:
- **Base image**: `python:3.11` nặng 1.62 GB, `python:3.11-slim` chỉ 215 MB.
Bản đầy đủ mang theo gcc, header biên dịch, git, man page... Em kiểm tra:
`which gcc` trong image single ra `/usr/bin/gcc`, trong image multi thì không có.
- **Cache của pip**: bản single không có `--no-cache-dir` nên còn 17 MB ở
`/root/.cache/pip`.
- **Source thừa**: `COPY . .` chép cả `requirements.txt` và mọi thứ không bị
`.dockerignore` loại; bản multi chỉ copy `app/` và `utils/`.

Thư viện Python thì gần như bằng nhau (83 MB so với 77 MB) — tức là phần lớn
dung lượng không phải là thứ app cần để chạy.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Em đổi `SERVICE_VERSION` từ `1.0.0` thành `1.0.1` rồi build lại:

- **Multi-stage**: mọi layer đều `CACHED` (FROM, `COPY requirements.txt`,
`pip install`, `useradd`, `COPY --from=builder`, `COPY utils`), chỉ layer cuối
`COPY app ./app` chạy lại (0.1s). Tổng thời gian build: **1 giây**.
- **Bản single** (`COPY . .` đứng trước `pip install`): `COPY . .` thay đổi
nên mọi layer phía sau mất cache, `pip install` chạy lại hết (17.2s). Tổng:
**20 giây**.

Lý do: Docker bỏ cache từ layer đầu tiên có thay đổi trở đi. Đặt
`requirements.txt` + `pip install` lên trước thì chỉ khi đổi thư viện mới
phải cài lại.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy root:
1. Code Python có lỗ hổng (ví dụ thư viện bị lỗi cho phép thực thi lệnh) →
kẻ tấn công chạy được shell trong container.
2. Shell đó có quyền **root (uid 0)** — cùng uid 0 với root trên host, vì
container chỉ là process được cô lập bằng namespace, không phải máy ảo.
3. Với root trong container, kẻ tấn công đọc/ghi được mọi file, và nếu có
volume mount từ host, `docker.sock`, hay một lỗ hổng container escape,
họ ra tới host với quyền root.

`USER appuser` cắt chuỗi ở bước 2: shell chỉ có uid 10001 (em kiểm tra bằng
`id` trong container: `uid=10001(appuser)`), không cài được gói, không sửa
được file hệ thống, và nếu có thoát ra host cũng chỉ là một user thường
không có quyền gì.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa **20 request trong 2 giây**. Gửi 10 request lúc 10:00:59 (hết hạn
mức của phút 10:00), rồi 10 request lúc 10:01:00–10:01:01 (bộ đếm vừa reset
về 0 ở giây 00) — cả 20 đều "hợp lệ".

Với sliding window thì lúc 10:01:01, 10 request lúc 10:00:59 vẫn nằm trong 60
giây gần nhất nên request thứ 11 bị chặn. Khi test bằng docker compose, em
gọi 15 lần liên tiếp và nhận `200 ×10` rồi `429 ×5`, không có kẽ hở ở ranh
giới phút.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Rate limit đếm **số request** trong 60 giây (chống spam, bảo vệ server);
cost guard cộng **số tiền** trong tháng (bảo vệ hóa đơn LLM).

- Rate limit cho qua, cost guard chặn: user gửi 5 request/phút — dưới hạn
mức 10 — nhưng mỗi câu hỏi và lịch sử dài 50.000 token. Sau vài giờ tổng
chi đã vượt $10 → 402. Em thử bằng cách set `cost:sv-rich:2026-09 = 999`
trong Redis: request đầu tiên đã bị 402 dù chưa gọi lần nào trong phút.
- Cost guard cho qua, rate limit chặn: user mới, chưa tiêu gì, nhưng bấm gửi
15 lần liên tục với câu hỏi ngắn → request 11–15 bị 429, dù tổng chi phí mới
chỉ khoảng $0.0003.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

1. Redis mất kết nối.
2. Endpoint gộp (liveness) của **cả 3** container cùng trả 503, vì cả 3 cùng
dùng chung Redis đó.
3. Sau vài lần probe thất bại, orchestrator coi cả 3 là "chết" và **restart cả
3 cùng lúc**.
4. Trong lúc restart, không còn container nào nhận request → toàn bộ service
down, kể cả những request không cần Redis.
5. Container khởi động lại, Redis vẫn chưa về → lại fail probe → restart tiếp
(restart loop).
6. Redis về sau 30 giây, nhưng các container đang ở giữa vòng restart nên cần
thêm thời gian mới phục vụ lại được.

Tách ra thì: `/health` vẫn 200 (không restart ai), `/ready` trả 503 → load
balancer chỉ tạm ngừng gửi traffic; Redis về là `/ready` 200 ngay, không mất
container nào.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?


Em chạy `docker compose --profile lb up -d --scale agent=3` (nginx phía
trước) và gọi 6 lần với `X-User-Id: sv-scale`. `history_length` là
**0, 2, 4, 6, 8, 10**; đếm trong log thì mỗi container xử lý đúng 2 request —
tức là request lần lượt đi qua cả 3 container mà lịch sử vẫn liền mạch vì
nằm trong Redis.

Nếu lưu trong dict Python, mỗi container có một dict riêng. Với nginx chia
round-robin A → B → C → A..., con số sẽ là **0, 0, 0, 2, 2, 2** — mỗi container
chỉ nhớ những câu nó tự trả lời, agent "quên" ngẫu nhiên. Container nào restart
thì mất sạch lịch sử của nó.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Lỗi:** job deploy trong GitHub Actions lỗi
`Invalid RAILWAY_TOKEN. Please check that it is valid and has access to the
resource you're trying to use.` (test và build đều xanh).

**Tìm nguyên nhân:** đọc log bằng `gh run view --log-failed` → token có được
truyền vào (`RAILWAY_TOKEN: ***`) nhưng Railway từ chối. Em đã copy nhầm token.

**Sửa:** tạo và copy lại đúng token railway → deploy và smoke test xanh.
