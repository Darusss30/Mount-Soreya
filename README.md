# Darus Hub

Versi Darus Hub tersedia di [`DarusHub.lua`](./DarusHub.lua), dikembangkan dari
`UbeyHubV3.lua` pada proyek [Ubey-Hub](https://github.com/UbeyDev/Ubey-Hub).
Menu utama langsung terbuka tanpa memasukkan key, melewati iklan, atau menghubungi layanan aktivasi Supabase.

Fitur yang tersedia:

- Auto Collect material.
- Auto Mine & Wood, dengan pilihan material dan pengaturan waktu tunggu.
- Auto Kios Taruh, dengan pilihan slot dan item.
- Tombol mengambang untuk menampilkan atau menyembunyikan menu.
- Kontrol geser dengan mouse/sentuhan, penyesuaian ukuran layar, dan tombol X
  untuk menghentikan sesi serta membersihkan prosesnya.
- Pesan status untuk alat yang tidak ditemukan, kios yang tidak tersedia,
  penolakan server, dan permintaan kios yang belum mendapat respons.

Gunakan `DarusHub.lua` sebagai berkas utama untuk pengembangan berikutnya.
Skrip ini bergantung pada lingkungan klien Roblox dan struktur objek game yang sesuai.
State kini disimpan secara lokal; `getgenv()` dan `fireproximityprompt()` tidak diperlukan.
Ini bukan aplikasi HTML atau aplikasi desktop mandiri.

Versi lama dapat dilihat di repositori sumber Ubey-Hub.
Generator key `index.html` versi lama tidak diperlukan oleh Darus Hub.

Perbaikan bug:

- Menjalankan ulang versi baru menghentikan worker dan koneksi sesi sebelumnya.
- OFF, respawn, dan penutupan menu melepaskan interaksi prompt yang sedang ditahan.
- Anti-Water memulihkan transparansi, collision, pengaturan Terrain, dan status berenang.
  Pencocokan nama `air` tidak lagi mengenai objek seperti `Chair` atau `Stairs`.
  Bagian air dikenali dari nama persis `air`/`water`, Material Water, atau atribut `DarusWater = true`.
- Prompt dicatat sekali dan diperbarui saat objek masuk/keluar Workspace;
  model bertingkat tidak menimbulkan interaksi ganda.
- Mining dan wood memakai cooldown per prompt; worker kios tidak menunggu aktivitas tersebut selesai.
- Permintaan kios manual dan otomatis berbagi satu kunci permintaan aktif.
  Setelah 10 detik tanpa jawaban, UI menampilkan timeout tanpa mengirim ulang
  permintaan yang mungkin masih diproses server.
- Scroll mengikuti isi halaman; slider dan tombol mengambang mengabaikan jari lain
  serta melepaskan drag saat aplikasi kehilangan fokus.

Luck pancing dan mutasi:

Tidak ada fitur yang menjamin ikan atau mutasi tertentu dalam satu kali pancing.
Repositori ini tidak memuat kode server pemilihan hasil ikan. Nilai lokal pada hub
tidak dapat menjamin perubahan keputusan server game. Fitur tersebut memerlukan
integrasi dengan logika pemancingan di server yang dikelola pemilik game.
Lihat [komunikasi klien/server Roblox](https://create.roblox.com/docs/scripting/events/remote).

Validasi:

- Kompilasi menggunakan CLI Luau.
- 45 pemeriksaan regresi dalam runtime simulasi: lifecycle, UI, multi-touch,
  pemulihan air, respawn, pembatalan prompt, cooldown, dan respons kios.
- Jalankan di PowerShell dengan direktori binari dari [rilis resmi Luau](https://github.com/luau-lang/luau/releases):

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 -LuauDirectory C:\path\to\luau
  ```

Simulasi tidak menguji rendering, fisika, replikasi, atau aturan server game asli.
Validasi langsung di Roblox masih diperlukan, terutama kecocokan nama alat,
ActionText prompt, dan path RemoteFunction kios yang diwarisi dari versi V3.
Jika versi lama yang belum memiliki cleanup sudah berjalan, masuk ulang ke game
sekali sebelum menguji versi baru agar loop lama tidak ikut berjalan.
