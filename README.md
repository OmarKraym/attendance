# Attendance System — shared data on all devices

The app works offline and installs on a phone like a normal app.
With **cloud sync** turned on, every device shows the same data:
a change made on one device appears on the others within a few seconds.
Without internet, changes are saved on the device and uploaded automatically when the connection comes back.

## What is in this folder

| File / folder | What it is |
|---|---|
| `index.html` | The app itself |
| `config.js` | **Your Supabase connection** (2 values you paste in — step B) |
| `supabase/setup.sql` | Creates the database tables and access rules (step A) |
| `sw.js` | Offline cache |
| `manifest.webmanifest`, `icons/` | App name and icon for installing |
| `fonts/`, `vendor/` | Local copies of the Cairo font, the Excel library and the Supabase library (licences included) |

Keep the folder structure exactly as it is.

---

## ✅ Your project status (already connected)

This copy is **already connected** to its Supabase project
(`https://chwotupxoatvzpnckxto.supabase.co`):

- ✅ Tables, access rules and sync functions are created (step A2 below is done).
- ✅ The owner's email is the first **admin**.
- ✅ `config.js` already holds the project URL and publishable key (step B is done).

**What is left for you (about 10 minutes):**

1. **Create your login.** In the Supabase dashboard: **Authentication → Users → Add user → Create new user**.
   Email: the admin email. Choose a password. **Tick "Auto Confirm User".**
   Without this tick the app refuses the login on purpose, because only confirmed emails get access.
2. **Close public sign-up** (recommended): in the Authentication settings, turn off **Allow new users to sign up**.
3. **Put the app online:** follow step **C** below (GitHub Pages).
4. **First login on the computer that has your current data:** follow step **D** below.

Steps A and B below are kept for reference, in case you ever set up a new project.

---

## A. Prepare Supabase (one time, about 10 minutes)

Use the Supabase account you want to keep this data in.

1. **Create a project:** New project → give it a name (for example `attendance`) → choose a strong database password → choose a region in Europe, close to Libya → Create.
2. **Create the tables:** open **SQL Editor → New query**. Paste the whole content of `supabase/setup.sql`.
   At the very bottom, replace `YOUR-EMAIL@example.com` with **your own email**. Then click **Run**.
   It should end with "Success". (The file is safe to run again later.)
3. **Create your login:** open **Authentication → Users → Add user → Create new user**. Enter the **same email** and a password. Tick **Auto Confirm User**.
4. **Close public sign-up (recommended):** in the Authentication settings, turn off **Allow new users to sign up**.
   Even if you skip this, strangers still see nothing (only emails in the `app_members` table have access), but it keeps your user list clean.
   *The exact menu names can change in the Supabase dashboard; look for "sign up" in Authentication settings.*

## B. Connect the app

1. In Supabase, open **Project Settings → API Keys** (or **Connect**). Copy:
   - the **Project URL** (looks like `https://abcd1234.supabase.co`)
   - the **Publishable key** (starts with `sb_publishable_`). If you only see an "anon public" key, that works too.
2. Open `config.js` and paste them:
   ```js
   window.ATTENDANCE_CLOUD = {
     url: 'https://abcd1234.supabase.co',
     key: 'sb_publishable_...'
   };
   ```
> The publishable key is meant to be public; your data is protected by the login and the rules from `setup.sql`.
> **Never** put the `service_role` / secret key in `config.js`.

## C. Put it online for free (GitHub Pages)

1. Create a free account at <https://github.com>.
2. **New repository** → name it (for example `attendance`) → **Public** → **Create repository**.
3. Click **uploading an existing file**, drag **all files and folders** from this folder (including your edited `config.js`), then **Commit changes**.
4. **Settings → Pages → Deploy from a branch → main → / (root) → Save**.
5. After 1–2 minutes, the app is at `https://YOUR-USERNAME.github.io/attendance/`.

> **Never upload a backup file (`attendance-backup-*.json`) to GitHub.** It contains employee data.

## D. First login — start with the device that already has your data

1. Open the link on the **computer that has your current data**. Log in.
   The cloud is empty, so this device **uploads everything** automatically.
2. Then open the link on your phone and log in. It downloads everything.
3. If a device has its *own* data and the cloud also has data, the app asks you:
   - **Merge**: add this device's data to the cloud. The same employee (same code) is not duplicated.
   - **Use cloud data only**: replaces this device's data with the cloud data.
   - **Not now**.
   Export a backup from that device first if you are not sure.

**Install on the phone:** Android (Chrome) → **📲 تثبيت التطبيق** button, or menu **⋮ → Install app**.
iPhone (Safari) → **Share ⬆️ → Add to Home Screen**.

## E. Adding other people

For each person:
1. **Authentication → Users → Add user** (their email + a password, **tick Auto Confirm** — unconfirmed emails get no access).
2. **Table Editor → app_members → Insert row**: their email in **lowercase**, and a role:
   - `editor`: can view and change data
   - `admin`: same as editor (reserved for you)
   - `viewer`: can view data and reports only; their changes are not uploaded

To remove someone, delete their row from `app_members`. They lose access at their next sync.

## How sync behaves (good to know)

- **The badge under the title** shows the state: ☁ synced, ⏳ changes waiting, 📴 offline, ⚠ error. Tap it for details.
- **Same item changed on two devices:** the one that reached the server **last** wins.
  For example, if two people edit the same employee's same day while one of them is offline, the offline one's change wins when it reconnects.
- **Deletes are synced** to all devices.
- **Logging out** removes the data from that device only; it stays in the cloud. Changes that were not uploaded yet are lost, and the app warns you first.
- **Backups:** keep exporting a backup from time to time (tab **الاستيراد والنسخ الاحتياطي**). The free plan's backup options are limited.
- **Free plan pause:** Supabase pauses free projects after **7 days without use**. Daily use prevents this. If it is paused (for example after a long holiday), open the project in the Supabase dashboard and click **Restore**.

## Using it without the cloud

Leave both values in `config.js` empty. The app then works on each device separately, as before, with no login.
Data can be moved between devices with export plus **دمج** (merge) or **استبدال** (replace).

## Publishing a new version

1. Replace the changed files in the repository.
2. In `sw.js`, change `const VERSION = 'v3';` to `'v4'` (then `'v5'`, and so on). **If you forget this, phones keep the old version.**
   (Changes to `config.js` alone do not need this.)
3. Open apps show **«نسخة جديدة… تحديث الآن»**. Tapping it switches; data is not affected.

## Testing on your own computer

```
python -m http.server 8000
```
Then open <http://localhost:8000>. Double-clicking `index.html` also works, but without offline mode or installing.
