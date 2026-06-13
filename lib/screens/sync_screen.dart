import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../database/sqlite_helper.dart';
import 'cycle_count_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final Color sigmaBlack = const Color(0xFF111111);
  final Color sigmaMagenta = const Color(0xFFF31A6B);
  final Color bgLight = const Color(0xFFF4F6F9);

  bool _isLoading = false;
  String _statusMessage = 'Pilih aksi sinkronisasi di bawah ini.';

  // Fungsi Pull (Download)
  Future<void> _startPull() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Mengunduh Master Data (Rak & Item)...';
    });

    try {
      final api = ApiService();
      final db = DatabaseHelper.instance;

      final masterData = await api.pullMasterData();
      final racks = masterData['racks'] ?? [];
      final items = masterData['items'] ?? [];

      await db.clearMasterData();
      await db.insertRacks(racks);
      await db.insertItems(items);

      setState(() {
        _isLoading = false;
        _statusMessage = 'Download Berhasil!\nTotal: ${racks.length} Rak dan ${items.length} Item.';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Download Gagal. Pastikan internet menyala.';
      });
    }
  }

// FUNGSI : Push (Upload) hasil hitungan ke Laravel
  Future<void> _startPush() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Mencari data hitungan offline...';
    });

    try {
      final db = DatabaseHelper.instance;
      final api = ApiService();

      // Ambil data asli (mentah) dari SQLite
      final rawPendingData = await db.getPendingCycleCounts();

      if (rawPendingData.isEmpty) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Tidak ada data hitungan baru yang perlu dikirim.';
        });
        return;
      }

      // PROSES BERISHKAN ID 
      List<Map<String, dynamic>> dataUntukDikirim = [];

      for (var item in rawPendingData) {
        // Map dari SQLite itu "read-only", jadi harus buat salinannya agar bisa diedit
        Map<String, dynamic> cycleData = Map<String, dynamic>.from(item);
        
        // HAPUS ID LOKAL bawaan SQLite agar Laravel tidak menolaknya (422 Invalid ID)
        cycleData.remove('id'); 

        dataUntukDikirim.add(cycleData);
      }

      setState(() => _statusMessage = 'Mengirim ${dataUntukDikirim.length} laporan ke server...');

      // Kirim data yang sudah "dibersihkan" ke Laravel
      await api.pushCycleCount(dataUntukDikirim);

      // Jika sukses, ubah status di SQLite jadi 'synced'
      // pakai rawPendingData untuk mendapatkan ID lokal SQLite aslinya
      List<int> syncedIds = rawPendingData.map<int>((e) => e['id'] as int).toList();
      await db.markAsSynced(syncedIds);

      setState(() {
        _isLoading = false;
        _statusMessage = 'Upload Berhasil!\n${rawPendingData.length} laporan telah masuk ke sistem pusat.';
      });

      // Munculkan pop-up hijau berhasil
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Berhasil Upload ke Pusat!'), backgroundColor: Colors.green),
        );
      }

    } catch (e) {
      // JIKA GAGAL: Tangkap pesan error spesifik dari Laravel
      setState(() {
        _isLoading = false;
        _statusMessage = 'Upload Gagal. Cek pesan error di bagian bawah layar.';
      });

      // Munculkan pop-up merah dengan pesan error aslinya
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal: $e'), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5), // Ditahan 5 detik biar staf bisa baca
          ),
        );
      }
    }
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text('Sinkronisasi Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: sigmaBlack,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))
              ]
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ANIMASI ICON
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: (_isLoading ? sigmaMagenta : sigmaBlack).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isLoading ? Icons.sync : Icons.cloud_sync_rounded,
                    size: 80,
                    color: _isLoading ? sigmaMagenta : sigmaBlack,
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.5),
                ),
                const SizedBox(height: 40),
                
                if (_isLoading)
                  CircularProgressIndicator(color: sigmaMagenta)
                else
                  Column(
                    children: [
                      // TOMBOL DOWNLOAD
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Download Data Master', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: sigmaBlack,
                          elevation: 0,
                          side: BorderSide(color: Colors.grey.shade300, width: 2),
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _startPull,
                      ),
                      const SizedBox(height: 16),
                      
                      // TOMBOL UPLOAD
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Upload Hasil Hitungan', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sigmaMagenta,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: sigmaMagenta.withOpacity(0.4),
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _startPush,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}