# Darus Hub

Darus Hub dikembangkan dari **`UBEYHUB.lua`**, bukan `UbeyHubV3.lua`.
Sumber: [UbeyDev/Ubey-Hub — UBEYHUB.lua](https://github.com/UbeyDev/Ubey-Hub/blob/7152183/UBEYHUB.lua).
Berkas utama adalah [`DarusHub.lua`](./DarusHub.lua).
Menu langsung terbuka tanpa key, verifikasi HWID, Discord aktivasi, atau Supabase.

## Fitur

- Fishing & Sell: dua mode pancing yang saling eksklusif, pilihan spot, rotasi spot, jeda gigitan, dan timer jual ke NPC.
- Target & Statistik: pemantau ikan/mutasi, penghentian otomatis saat target tertangkap, perlindungan auto sell, dan statistik sesi.
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

## Target & Statistik

Buka **Target & Statistik**, di bawah **Credits** pada sidebar (gulir bila perlu).

1. Isi nama ikan dan/atau mutasi target, lalu aktifkan **Pantau Target dan Stop Otomatis**.
   Keduanya dicocokkan persis tanpa membedakan huruf besar/kecil. Kolom kosong berarti bebas;
   keduanya tidak boleh kosong ketika mengaktifkan pemantauan.
2. Jalankan mode auto fishing yang diinginkan. Saat notifikasi `GotFish` dari game cocok,
   kedua mode auto fishing dan auto sell dimatikan. Banner tetap terlihat walaupun hub
   diminimalkan; klik banner untuk menutupnya. Pantauan tidak mengubah hasil undian server.
3. Isi daftar nama, mutasi, atau rarity yang dilindungi dengan pemisah koma.
   Bawaan melindungi **Secret** dan **Forgotten**. Ikan favorit dan target yang diisi
   selalu dilindungi dari auto sell hub, termasuk ketika pemantauan target sedang OFF.
4. Simpan pilihan melalui **Settings > Simpan Konfigurasi**. Pemantauan perlu diaktifkan
   kembali setiap sesi; statistik dimulai dari nol setiap kali hub dijalankan ulang.

**Perilaku jual:** sumber hanya menyediakan pemanggilan `JualSemua`, tanpa kontrak
penjualan per ikan yang terverifikasi. Karena itu, hub membatalkan **seluruh penjualan
otomatis** jika menemukan ikan dilindungi, termasuk yang sudah difavoritkan. Jika data
inventaris tidak lengkap/gagal dibaca, atau tangkapan baru terdeteksi selama pemeriksaan,
penjualan juga dibatalkan dan alasannya ditampilkan pada status. Gunakan penjualan
selektif di dalam game jika tersedia untuk menjual ikan lain.
Perlindungan ini memeriksa snapshot inventaris; pemeriksaan dan penjualan tidak atomik
di server. Perubahan server setelah pemeriksaan, penjualan manual di luar hub, dan
permintaan jual yang sudah dikirim tidak dapat dibatalkan oleh pelindung ini.

Statistik menampilkan jumlah tangkapan, durasi sesi, rata-rata tangkapan per menit,
jumlah Secret/Forgotten, tangkapan terakhir, dan **ikan terlangka berdasarkan peluang**.
Untuk peluang **1 dari N**, penyebut N yang lebih besar berarti lebih langka:
**1 dari 20M mengalahkan 1 dari 950K**, termasuk jika keduanya Secret.
Peringkat membaca field `chance`/`Chance` dari notifikasi game, mendukung angka penyebut,
format `1 in N`, `1 dari N`, `1/N`, `1:N`, pemisah ribuan, serta akhiran K/M/B.
Contoh: `950K`, `20M`, `20.5M`, `20,5M`, `20.000.000`, dan `20,000,000`.
Data peluang yang hilang/tidak terbaca tidak menggantikan rekor yang valid; tangkapannya
tetap dihitung. Kategori Secret/Forgotten tidak dipakai sebagai pengganti angka peluang.
Jika event tidak menyertakan peluang yang terbaca, hub menunggu popup tangkapan game
selama sekitar tiga detik. Popup dicocokkan dengan nama, mutasi, dan berat jika berat
tersedia di event. Contoh `Stone Big Manta Ray (157.97kg)` dengan `1 in 50.0K`
akan terbaca sebagai `1 dari 50000 (tampilan game)`; angka ini mengikuti tampilan
game dan mungkin sudah dibulatkan. Teks RichText didukung. Peluang dari event tetap
diutamakan jika tersedia.

Pembacaan popup hanya menerima judul berakhiran `(berat kg)` dan satu label peluang
yang baru diperbarui dalam kelompok UI kecil yang sama. Popup tersembunyi, teks hub,
popup lama, nama/berat/mutasi berbeda, atau beberapa tangkapan yang ambigu diabaikan.
Pembacaan terlambat memperbarui rekor tanpa menambah hitungan tangkapan atau menimpa
informasi ikan terakhir yang lebih baru. Jika susunan popup game tidak cocok, status
berubah dari `menunggu data peluang` menjadi `peluang belum terbaca`; hub tidak
menebak peluangnya. Dukungan susunan UI game asli masih perlu diuji di Roblox.

Angka hanya berasal dari notifikasi
`GotFish` yang diterima sejak sesi/reset, bukan seluruh inventaris atau jaminan peluang.
Duplikasi notifikasi dengan `uid`/`UUID` yang sama disaring untuk 1.000 ID terakhir;
tanpa ID dari game, notifikasi ganda tidak dapat dibedakan secara andal.
**Reset Statistik Sesi** menghapus hitungan dan durasi tanpa mengubah target/proteksi.

## Validasi

Kompilasi Luau dan **123 pemeriksaan regresi simulasi** lulus untuk basis `UBEYHUB.lua`.
Cakupan mencakup seluruh tab, pergantian mode pancing, gigitan cepat/terlambat,
respawn, pemulihan rod, favorite, konfigurasi, timeout jual, privacy, pembatalan
summit, webhook tiruan, halo, drag, dan pembersihan saat dijalankan ulang/ditutup.
Penghapusan menu editor rod serta peringkat peluang diuji, termasuk 950K vs 20M
dalam kategori Secret yang sama, format angka, nilai invalid, seri, dan reset.
Fallback popup diuji menggunakan teks pada laporan pengguna, RichText, prioritas
event, kecocokan identitas, popup lama/tersembunyi, pembaruan judul dan peluang
yang terpisah, tangkapan ambigu, timeout, reset, dan hitungan yang tidak bertambah ganda.
Target/statistik diuji untuk kecocokan literal, kombinasi nama/mutasi, duplikasi ID,
reset, penyimpanan dan pemuatan ulang. Pelindung jual diuji untuk favorit, target,
filter nama/mutasi/rarity, inventaris gagal/tidak lengkap, tangkapan baru saat
pemeriksaan, dan pembatalan ketika auto sell dimatikan atau OFF/ON dengan cepat.
Pengujian tidak mengirim pesan atau permintaan ke server game/Discord nyata.

Jalankan dengan binari dari [rilis resmi Luau](https://github.com/luau-lang/luau/releases):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 -LuauDirectory C:\path\to\luau
```

Simulasi tidak menguji rendering, fisika, replikasi, atau aturan server game asli.
Pengujian langsung di Roblox masih diperlukan; hasil ini bukan jaminan seluruh fitur kompatibel dengan setiap pembaruan game.
