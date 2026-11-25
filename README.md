# Math Learn

Bản **GitHub Pages**: giao diện tĩnh ở `site/`, dữ liệu/Auth/Realtime/Storage ở Supabase, AI và đăng nhập Owner ở Supabase Edge Functions. Không có Express server vì GitHub Pages chỉ phục vụ tệp tĩnh.

## Các chức năng

Tài khoản username/mật khẩu, chọn học sinh hoặc giáo viên một lần theo tài khoản, Owner `Admin`, tạo/tham gia lớp, kênh chat/thông báo/hỏi đáp/AI/bài tập, realtime, trạng thái thành viên online, tag, KaTeX, bảng vẽ, xem trước tệp riêng tư, bài nộp và chấm điểm, roles có màu và quyền, audit log, mute theo thời gian/kick/ban, Minigame lớp học, trang About, giao diện sáng/tối và onboarding.

## 1. Supabase

1. Trong Supabase SQL Editor, chạy toàn bộ [`supabase/schema.sql`](supabase/schema.sql). Có thể chạy lại để áp dụng cập nhật realtime thành viên và loại tệp trình chiếu.
2. Authentication → Sign In / Providers → Email: bật Email/Password. Tắt Confirm email khi dùng username giả email `@learnmath.local`.
3. Authentication → URL Configuration: đặt Site URL thành `https://TEN-GITHUB.github.io/TEN-REPO/`.
4. Tại Edge Function Secrets, thêm `MATH_LEARN_PUBLISHABLE_KEY` với publishable key, `ADMIN_PASSWORD` (mật khẩu Owner riêng, dài) và `OPENAI_API_KEY` (nếu bật AI). Username Owner là `Admin`.

`site/config.js` chứa Project URL và Publishable key. Khóa publishable là khóa public; không đặt Secret/Service Role key, mật khẩu hay OpenAI key ở thư mục `site/` hoặc trong GitHub.

## 2. GitHub Pages

Đẩy repo lên GitHub, nhánh chính `main`. Vào Settings → Pages → Build and deployment → chọn **GitHub Actions**. Workflow `.github/workflows/pages.yml` tự deploy khi thay đổi `site/`; URL hiện trong Actions → Deploy Math Learn to GitHub Pages.

## 3. Supabase Edge Functions

Để triển khai từ GitHub Actions, tạo hai repository secrets:

- `SUPABASE_ACCESS_TOKEN` — Access Token của Supabase.
- `SUPABASE_PROJECT_ID` — project ref `edjooijygfaaubmcpefa`.

Vào Actions → **Deploy Supabase Edge Functions** → Run workflow. Hàm `owner-session` xác minh thông tin Owner và phát hành phiên Supabase; `ai-chat` kiểm tra phiên người dùng rồi gọi OpenAI. Secrets của hàm được nhập riêng trong Supabase Dashboard, không phải GitHub Pages.

## Tệp chính

```text
site/index.html                 giao diện, CSS và client logic
site/config.js                  Supabase URL + publishable key (public)
supabase/schema.sql             bảng, RLS, Realtime, Storage
supabase/functions/ai-chat/     API gia sư Toán
supabase/functions/owner-session/ đăng nhập Owner
.github/workflows/pages.yml     deploy giao diện GitHub Pages
.github/workflows/supabase-functions.yml  deploy Edge Functions
```

Nếu repo trước đó đã chạy schema cũ, sao lưu dữ liệu trước khi chạy SQL nâng cấp. Không dùng GitHub Pages để giữ khóa bí mật; mọi quyền dữ liệu vẫn được áp dụng bởi Supabase RLS.

