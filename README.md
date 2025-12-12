💬 ModernChat — Realtime Chat App (Flutter + Supabase)

ModernChat یک اپلیکیشن چت مدرن، سریع و کاملاً ریل‌تایم است که با استفاده از Flutter و Supabase ساخته شده.
هدف این پروژه ارائه‌ی یک تجربه‌ی پیام‌رسانی روان با طراحی حرفه‌ای، انیمیشن‌های نرم و معماری مقیاس‌پذیر است

## ⭐ ویژگی‌های کلیدی

### 🔐 احراز هویت (Authentication)
- ثبت‌نام و ورود با Email/Password  
- ذخیره Metadata کاربر (username, avatar, description)  
- خروج امن (Secure SignOut)

### 💬 چت ریل‌تایم (Realtime Chat)
- ارسال و دریافت پیام بدون تأخیر با Supabase Realtime  
- نمایش پیام‌های خوانده نشده (Unread)  
- دریافت آپدیت پیام‌ها بدون Refresh  
- مدل پیام حرفه‌ای و مقیاس‌پذیر

### 👤 پروفایل کاربر
- آپلود آواتار روی Supabase Storage  
- ویرایش نام کاربری و توضیحات  
- نمایش اطلاعات کاربر داخل Drawer زیبا با Blur UI

### 🔍 جستجوی کاربران
- جستجو با **Debounce**  
- جستجوی ILIKE در دیتابیس PostgreSQL  
- نتایج سریع و بهینه شده

### 🎨 رابط کاربری
- طراحی Glassmorphism (Blur)  
- رنگ‌بندی مدرن و حرفه‌ای  
- انیمیشن‌های نرم  
- کاملاً ریسپانسیو

---

## 📷 اسکرین‌شات‌ها

| Login | Chats | Profile |
|-------|--------|---------|
| ![](screenshots/login.png) | ![](screenshots/chat.png) | ![](screenshots/profile.png) |

> 📌 اگر اسکرین‌شات نداری، بگو برات قالب عکس پیش‌فرض هم بسازم.

---

## 🛠️ تکنولوژی‌های استفاده شده

- **Flutter 3.x**
- **Dart**
- **Supabase** (Auth + Realtime + Storage + Postgres DB)
- **StreamBuilder / State Management**
- **CachedNetworkImage**
- **Google Fonts / Glass UI Design**

---

## 🚀 راه‌اندازی پروژه

### 1️⃣ کلون کردن ریپازیتوری

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
