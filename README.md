# Darus Hub

Darus Hub dikembangkan dari **`UBEYHUB.lua`**, bukan `UbeyHubV3.lua`.
Sumber: [UbeyDev/Ubey-Hub — UBEYHUB.lua](https://github.com/UbeyDev/Ubey-Hub/blob/7152183/UBEYHUB.lua).
Berkas utama adalah [`DarusHub.lua`](./DarusHub.lua).
Menu langsung terbuka tanpa key, verifikasi HWID, Discord aktivasi, atau Supabase.

## Fitur

- Fishing & Sell: dua mode pancing yang saling eksklusif, pilihan spot, rotasi spot, jeda gigitan, dan timer jual ke NPC.
- Rod & Value: daftar rod milik pemain, pemeriksaan nilai angka, editor lokal, dan reset.
- Favorite: filter rarity/mutasi, auto favorite, serta unfavorite berdasarkan filter atau seluruh ikan.
- Galatama dan perpindahan berdasarkan perkiraan jadwal Core.
- Teleport shop/NPC dan pemain.
- Summit dengan rute checkpoint dan pengaturan tween.
- Pengaturan pemain, Anti-AFK, headless lokal, RGB Fire, dan halo.
- Privacy, pengaturan grafis, konfigurasi, webhook opsional, dan kredit sumber.

Fitur pancing mengikuti struktur `Withering Rod/Mechanics/Remotes` dari sumber.
Nama remote, lokasi, dan aturan game tetap harus cocok dengan versi game yang sedang dimainkan.
Pengaturan visual lokal tidak menjamin perubahan yang terlihat oleh pemain lain.
Jadwal Core memakai menit 00–10 pada jam perangkat; ini perkiraan, bukan deteksi event dari server.

## Perbaikan

- Satu worker pancing untuk kedua mode; listener gigitan dipasang sebelum lemparan.
- OFF, pergantian mode, dan respawn membatalkan tahap pancing berikutnya.
- Menu X dan eksekusi ulang membersihkan koneksi, worker, tween, serta efek buatan sesi.
- Pengaturan rod, PlatformStand, nama tampilan, WalkSpeed, kepala, dan grafis dipulihkan sesuai perubahan sesi.
- Jual ikan mengembalikan posisi meskipun pancing OFF atau server gagal; permintaan yang belum selesai tidak diduplikasi.
- Pemanggilan RemoteFunction memiliki batas tunggu 10 detik di klien. Timeout tidak membatalkan pekerjaan yang mungkin masih berjalan di server.
- Nilai angka divalidasi; konfigurasi rusak menggunakan default. Kegagalan penyimpanan ditampilkan sesuai hasilnya.
- Filter disimpan; reset menyelaraskan konfigurasi dan tampilan. Mutasi `8-Bit` dicocokkan sebagai teks literal.
- Select All mengikuti pilihan aktual; Unfavorite menghentikan Auto Favorite agar kedua operasi tidak saling membatalkan.
- Scroll mengikuti isi, ukuran menu menyesuaikan layar, dan drag mengabaikan jari lain serta tidak memicu klik setelah digeser.
- Halo mempertahankan posisi antarbagian dan mengelas semua bagian yang diperlukan.
- Webhook hanya melaporkan sukses untuk respons HTTP 2xx, tanpa mention massal. Pengiriman otomatis perlu diaktifkan kembali setiap sesi.

## Konfigurasi dan penggunaan

Skrip berjalan di lingkungan klien Roblox. Ini bukan aplikasi HTML atau desktop.
State tidak membutuhkan `getgenv()`. Penyimpanan `DarusHub_Config.json` membutuhkan
fungsi `readfile`, `isfile`, dan `writefile` dari lingkungan yang mendukungnya.
Jika tidak tersedia, pengaturan sesi tetap dapat dipakai dan status penyimpanan akan menjelaskan keterbatasannya.
Webhook opsional memerlukan fungsi HTTP request yang kompatibel dan URL yang Anda isi sendiri.

Gunakan tombol X untuk mengakhiri sesi. Tombol minus dan tombol DH hanya mengubah tampilan menu.
Jika versi sumber lama sudah berjalan tanpa mekanisme cleanup, masuk ulang ke game sekali sebelum memakai versi ini.

Tidak ada fitur yang menjamin ikan atau mutasi tertentu dalam sekali pancing.
Keputusan hasil ikan tetap berada di server game; repositori ini tidak memuat kode server tersebut.

## Rod & Value

1. Buka menu **Rod & Value**. Rod di Backpack dan karakter ditampilkan dengan status **Tas** atau **Dipakai**. Nama yang sama dibedakan dengan nomor sesi.
2. Pilih rod, lalu pilih value dari daftar. Editor membaca `NumberValue`, `IntValue`, dan atribut angka pada rod beserta turunannya. Nilai `Luck` hanya muncul jika memang tersedia pada rod tersebut.
3. Masukkan angka dan tekan **Terapkan Value Lokal**. Input yang bukan angka atau tak hingga ditolak; `IntValue` memerlukan bilangan bulat dalam rentang presisi Luau.
4. Gunakan **Reset Value Terpilih** atau **Reset Semua Value Rod** untuk mengembalikan nilai sebelum edit. Menutup hub, menjalankan ulang, atau kehilangan rod dari inventaris juga memulihkan perubahan sesi.

Daftar diperbarui saat halaman terbuka; tombol **Refresh Daftar Rod** tersedia untuk pemindaian manual.
Perpindahan rod antara tas dan karakter mempertahankan pilihan. Nilai yang dihapus game tidak dibuat ulang.
Edit manual pada jeda rod tidak ditimpa optimasi Auto Fishing; setelah reset, optimasi otomatis dapat berjalan kembali.
Editor tidak menyimpan perubahan value ke file dan tidak membuat nilai luck/server yang tidak tersedia.
Perubahan hanya lokal, dapat diabaikan atau ditimpa server, serta tidak menjamin pengaruh terhadap hasil tangkapan.
Jika konfigurasi pancing hanya berada dalam kode/server, halaman akan menjelaskan bahwa tidak ada value angka yang tersedia.

## Validasi

Kompilasi Luau dan **87 pemeriksaan regresi simulasi** lulus untuk basis `UBEYHUB.lua`.
Cakupan mencakup seluruh tab, pergantian mode pancing, gigitan cepat/terlambat,
respawn, pemulihan rod, favorite, konfigurasi, timeout jual, privacy, pembatalan
summit, webhook tiruan, halo, drag, dan pembersihan saat dijalankan ulang/ditutup.
Editor rod diuji untuk daftar inventaris, nama ganda, NumberValue/IntValue/atribut,
input invalid, nilai yang dihapus, perpindahan rod, perubahan dari luar editor,
reset, pembersihan handler, dan interaksi dengan optimasi pancing.
Pengujian tidak mengirim pesan atau permintaan ke server game/Discord nyata.

Jalankan dengan binari dari [rilis resmi Luau](https://github.com/luau-lang/luau/releases):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 -LuauDirectory C:\path\to\luau
```

Simulasi tidak menguji rendering, fisika, replikasi, atau aturan server game asli.
Pengujian langsung di Roblox masih diperlukan; hasil ini bukan jaminan seluruh fitur kompatibel dengan setiap pembaruan game.
