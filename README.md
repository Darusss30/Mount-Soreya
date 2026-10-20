# Darus Hub

Darus Hub dikembangkan dari **`UBEYHUB.lua`**, bukan `UbeyHubV3.lua`.
Sumber: [UbeyDev/Ubey-Hub — UBEYHUB.lua](https://github.com/UbeyDev/Ubey-Hub/blob/7152183/UBEYHUB.lua).
Berkas utama adalah [`DarusHub.lua`](./DarusHub.lua).
Menu langsung terbuka tanpa key, verifikasi HWID, Discord aktivasi, atau Supabase.

## Fitur

- Fishing & Sell: dua mode pancing yang saling eksklusif, pilihan spot, rotasi spot, jeda gigitan, dan timer jual ke NPC.
- Statistik: ringkasan sesi, ikan terlangka, riwayat 100 tangkapan, dan diagnostik.
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
**Anti-AFK** dan **Auto Join Galatama** otomatis ON saat hub dibuka atau konfigurasi
direset. Keduanya tetap dapat dimatikan melalui tombol masing-masing.
Auto Join menunggu jika `Remote/Galatama/Ikut` belum tersedia. Pemanggilan mengikuti
tipe objek yang ditemukan: `InvokeServer` untuk RemoteFunction, `FireServer` untuk
RemoteEvent. Status permintaan tidak berarti server sudah mengonfirmasi keikutsertaan.
Jika versi sumber lama sudah berjalan tanpa mekanisme cleanup, masuk ulang ke game sekali sebelum memakai versi ini.

Tidak ada fitur yang menjamin ikan atau mutasi tertentu dalam sekali pancing.
Keputusan hasil ikan tetap berada di server game; repositori ini tidak memuat kode server tersebut.

## Statistik

Buka **Statistik**, di bawah **Credits** pada sidebar. Fitur target, banner target,
dan penghentian otomatis saat target tertangkap sudah dihapus. Konfigurasi target
lama diabaikan dan tidak disimpan kembali.

Statistik menampilkan jumlah tangkapan, durasi, ikan per menit, Secret/Forgotten,
ikan terakhir, ikan terlangka, serta **Peluang terbaca: X/Y**. Peringkat hanya
membandingkan peluang yang sudah terbaca: **Secret 1M mengalahkan Mythical 600K**,
dan **20M mengalahkan 950K**. Kategori tidak menggantikan angka peluang.

Angka ditampilkan singkat: `4000` menjadi **4K**, `1000000` menjadi **1M**, dan
`2500000000` menjadi **2.5B**. Tampilan memakai maksimal tiga angka desimal;
perbandingan tetap memakai angka penuh sebelum pembulatan tampilan.

**Riwayat 100 tangkapan terakhir** mencatat semua notifikasi tangkapan yang valid,
termasuk ikan yang peluangnya belum terbaca. Data yang datang terlambat memperbarui
baris ikan tersebut dan rekor tanpa menambah hitungan atau mengganti ikan terakhir
jika sudah ada tangkapan baru. Rekor sesi tidak hilang saat baris lama keluar dari
riwayat; 100 kandidat dengan peluang terbesar dipertahankan untuk koreksi rekor.

Pembacaan peluang dilakukan melalui:

- Field `chance`/`Chance` pada event `GotFish`. Format angka, `1 in N`, `1 dari N`,
  `1/N`, `1:N`, pemisah ribuan, dan akhiran K/M/B didukung. Event tambahan dengan
  ID tangkapan sama boleh melengkapi atau mengoreksi peluang tanpa dihitung ulang.
- Popup game yang cocok dengan nama, mutasi, dan berat jika tersedia. Pembaca
  menunggu hingga 20 detik untuk animasi yang terlambat, menelusuri sampai 10 tingkat
  UI, dan menggabungkan label teks bayangan yang identik. Jumlah dekorasi tidak lagi
  dibatasi 40 elemen. Perubahan angka berikutnya pada popup yang sama dapat
  memperbarui peluang yang semula terbaca.
- Pemeriksaan inventaris untuk ID tangkapan sesi yang peluangnya masih kosong,
  maksimal tiga percobaan per tangkapan dengan interval worker delapan detik.
  Hanya field peluang yang benar-benar tersedia digunakan. Ikan inventaris lama
  tidak diimpor sebagai tangkapan sesi. Pemeriksaan ditunda ketika jual/favorite sibuk.

Popup harus memiliki judul berakhiran `(berat kg)` dan satu nilai peluang yang
unik pada kelompok UI yang sama. Teks RichText didukung. Popup tersembunyi, lama,
berbeda identitas, atau ambigu tidak digunakan. Contoh `Stone Big Manta Ray (157.97kg)`
dengan `1 in 50.0K` ditampilkan sebagai **1 dari 50K (tampilan game)**. Nilai ini
mengikuti angka tampilan game yang mungkin sudah dibulatkan; event/inventaris
menggantikan pembacaan popup jika memberikan data peluang yang lebih lengkap.

Jika semua sumber tidak menyediakan peluang yang cocok, ikan tetap ada di riwayat
dengan status **peluang belum terbaca**, dan angka X/Y menunjukkan data yang belum
lengkap. Belum ada pengujian langsung pada semua susunan popup game asli.
Statistik hanya mencatat event yang diterima sejak sesi/reset. ID ganda disaring
untuk 1.000 ID terakhir; notifikasi tanpa ID tidak dapat dideduplikasi secara andal.
**Reset Statistik Sesi** membersihkan hitungan, durasi, rekor, dan riwayat sesi.

### Diagnostik statistik

Jika ikan Secret belum masuk peringkat, tekan **Lihat / Salin Diagnostik Statistik**
di halaman Statistik setelah tangkapan tersebut. Laporan ditampilkan dalam kotak
teks dan disalin jika fungsi clipboard tersedia. Tidak ada pengiriman otomatis.
Laporan memuat status remote Galatama/inventaris, nama dan tipe field event,
nilai field peluang yang dikenal, 30 tangkapan Secret/Forgotten terakhir (tetap
tersimpan meski keluar dari riwayat 100 baris), serta 30 perubahan label peluang/berat
yang terlihat. Nilai field event lain tidak diekspor. Reset statistik menghapusnya.
Ringkasan juga menampilkan cakupan pembacaan peluang Secret dan Forgotten secara
terpisah. Data ini diperlukan untuk memastikan penyebab tangkapan tertentu terlewat;
pengujian simulasi tidak membuktikan seluruh layout game asli sudah terbaca.

Pelindung Auto Sell dan filter tambahannya sudah dihapus dari menu Statistik.
Auto sell langsung memakai perintah `JualSemua` game sesuai timer, tanpa pemeriksaan
filter nama, mutasi, rarity, atau favorit dari hub. Aturan penjualan tetap mengikuti
server game. Pengaturan pelindung lama diabaikan dan tidak disimpan kembali.

## Validasi

Kompilasi Luau dan **131 pemeriksaan regresi simulasi** lulus untuk basis `UBEYHUB.lua`.
Cakupan mencakup seluruh tab, pergantian mode pancing, gigitan cepat/terlambat,
respawn, pemulihan rod, favorite, konfigurasi, timeout jual, privacy, pembatalan
summit, webhook tiruan, halo, drag, dan pembersihan saat dijalankan ulang/ditutup.
Penghapusan menu editor rod serta peringkat peluang diuji, termasuk 950K vs 20M
dalam kategori Secret yang sama, format angka, nilai invalid, seri, dan reset.
Fallback popup diuji menggunakan teks pada laporan pengguna, RichText, prioritas
event, kecocokan identitas, popup lama/tersembunyi, pembaruan judul dan peluang
yang terpisah, tangkapan ambigu, timeout, reset, dan hitungan yang tidak bertambah ganda.
Statistik diuji untuk penghapusan target, Secret 1M vs Mythical 600K, popup dekoratif
terlambat, koreksi ID yang sama, pemeriksaan inventaris berdasarkan ID, singkatan K/M/B,
peringkat angka penuh, riwayat 100 baris, reset, penyimpanan dan pemuatan ulang.
Auto sell diuji tanpa ketergantungan pemeriksaan inventaris, dengan pemulihan posisi
dan penghapusan menu/konfigurasi pelindung.
Pengujian tidak mengirim pesan atau permintaan ke server game/Discord nyata.

Jalankan dengan binari dari [rilis resmi Luau](https://github.com/luau-lang/luau/releases):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 -LuauDirectory C:\path\to\luau
```

Simulasi tidak menguji rendering, fisika, replikasi, atau aturan server game asli.
Pengujian langsung di Roblox masih diperlukan; hasil ini bukan jaminan seluruh fitur kompatibel dengan setiap pembaruan game.
