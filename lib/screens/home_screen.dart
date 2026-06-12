import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'sync_screen.dart';
import 'cycle_count_screen.dart';
import 'history_screen.dart';
import 'change_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Tema Warna Sigma Berkat Sejati
  final Color sigmaBlack = const Color(0xFF111111);
  final Color sigmaMagenta = const Color(0xFFF31A6B);
  final Color bgLight = const Color(0xFFF4F6F9);

  String _userName = 'Memuat...';

  // State untuk Bottom Navigation Bar
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      // Mengambil nama, jika kosong maka default ke 'Staf Gudang'
      _userName = prefs.getString('user_name') ?? 'Staf Gudang';
    });
  }

  // Variabel untuk menampung data API
  bool isLoading = true;
  List<dynamic> myTasks = [];

  // Fungsi untuk memanggil API saat layar pertama kali dibuka
  Future<void> _fetchTasks() async {
    setState(() => isLoading = true);
    final tasks = await ApiService().getMyTasks();
    
    setState(() {
      myTasks = tasks;
      isLoading = false;
    });
  }

  // Fungsi saat menu bawah diklik
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Daftar layar yang akan ditampilkan sesuai menu yang diklik
    final List<Widget> pages = [
      _buildHomeTab(),                 // Tab 0: Beranda
      const SyncScreen(),              // Tab 1: Sinkronisasi
      const HistoryScreen(),           // Tab 2: Riwayat
      const ChangePasswordScreen(),    // Tab 3: Akun/Password
    ];

    return Scaffold(
        appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: AppBar(
          backgroundColor: sigmaBlack,
          elevation: 0,
        ),
      ),

      backgroundColor: bgLight,
      
      // Konten layar akan berubah sesuai index menu bawah
      body: pages[_selectedIndex],
      
      // BOTTOM NAVIGATION BAR (Gaya UI Modern)
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.white,
          selectedItemColor: sigmaMagenta,
          unselectedItemColor: Colors.grey.shade400,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed, // Mencegah animasi aneh jika tab > 3
          elevation: 0,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sync),
              label: 'Sinkronisasi',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Riwayat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.security),
              label: 'Akun',
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================
  // WIDGET KHUSUS TAB BERANDA (Tampilan Home Asli)
  // ========================================================
  Widget _buildHomeTab() {
    return SafeArea(
      child: Column(
        children: [
          // HEADER STICKY (Akan tetap menempel di atas)
          _buildCustomHeader(context),
          
          // AREA KONTEN (Bisa di-scroll dan di-pull-to-refresh)
          Expanded(
            child: RefreshIndicator(
              color: sigmaMagenta,
              onRefresh: _fetchTasks,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24), // Spasi setelah header
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // HERO CARD
                          const Text(
                            'Aksi Utama',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          _buildHeroCard(context),
                          
                          const SizedBox(height: 32),

                          _buildProgressDashboard(),

                          if (!isLoading && myTasks.isNotEmpty) 
                          const SizedBox(height: 32),
                          
                          // DAFTAR TUGAS HARI INI
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Tugas Saya Hari Ini',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
                              ),
                              // Badge jumlah tugas
                              if (!isLoading && myTasks.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: sigmaMagenta,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${myTasks.length}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                )
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          // Menampilkan List Tugas atau Loading
                          _buildTaskList(),

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET TAMPILAN TUGAS (Tidak Diubah)
  Widget _buildTaskList() {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (myTasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Column(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green, size: 40),
            SizedBox(height: 10),
            Text('Tidak ada jadwal hari ini.', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Gudang aman terkendali!', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    // Jika ada tugas, buat list card
    return Column(
      children: myTasks.map((task) {
        final rackCode = task['rack']?['code'] ?? 'Rak Tidak Diketahui';
        final scheduleDate = task['scheduled_at'] ?? '-';
        final status = task['status'] ?? 'draft';
        final supervisorNote = task['notes'];
        final isRecount = status == 'recount';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isRecount ? Colors.red.shade200 : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))
            ]
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isRecount ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isRecount ? Icons.warning_rounded : Icons.assignment_late,
                    color: isRecount ? Colors.red : Colors.orange
                  ),
                ),
                title: Text(
                  rackCode,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                ),
                subtitle: Text(
                  isRecount ? 'Tugas Hitung Ulang!' : 'Jadwal: $scheduleDate',
                  style: TextStyle(fontSize: 12, color: isRecount ? Colors.red : Colors.grey, fontWeight: isRecount ? FontWeight.bold : FontWeight.normal)
                ),
                trailing: ElevatedButton(
                  onPressed: () {
                    final String targetRackId = task['rack_id'].toString();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CycleCountScreen(initialRackId: targetRackId)
                      )
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecount ? Colors.red : sigmaMagenta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Hitung'),
                ),
              ),
              if (isRecount && supervisorNote != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16)
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.chat_bubble_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pesan Supervisor:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(
                              supervisorNote.toString(),
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontStyle: FontStyle.italic)
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // HEADER STICKY (Tidak Diubah)
  Widget _buildCustomHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: sigmaBlack,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock Opname PT Sigma Berkat Sejati',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Halo, $_userName!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: sigmaMagenta.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.logout, color: sigmaMagenta),
              tooltip: 'Keluar Aplikasi',
              onPressed: () => _prosesLogout(context),
            ),
          ),
        ],
      ),
    );
  }

  // FUNGSI LOGOUT (Tidak Diubah)
  Future<void> _prosesLogout(BuildContext context) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: sigmaMagenta,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  // HERO CARD (Tidak Diubah)
  Widget _buildHeroCard(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CycleCountScreen()));
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [sigmaMagenta, const Color(0xFFD11559)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: sigmaMagenta.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mulai Stock Opname',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan QR Code Rak untuk mulai menghitung fisik.',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_scanner, size: 18, color: Colors.black),
                        SizedBox(width: 8),
                        Text('BUKA SCANNER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.document_scanner, size: 80, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  // MINI DASHBOARD & PROGRESS TUGAS
  Widget _buildProgressDashboard() {
    // Sembunyikan jika masih loading atau tidak ada tugas
    if (isLoading || myTasks.isEmpty) return const SizedBox.shrink();

    int totalTasks = myTasks.length;
    
    // Menghitung otomatis tugas yang sudah selesai (asumsi status 'completed', 'counted', atau 'done')
    int completedTasks = myTasks.where((task) {
      String status = task['status'] ?? '';
      return status == 'completed' || status == 'counted' || status == 'done';
    }).length;
    
    int pendingTasks = totalTasks - completedTasks;
    double progressValue = totalTasks == 0 ? 0 : completedTasks / totalTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ringkasan Aktivitas',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02), 
                blurRadius: 10, 
                offset: const Offset(0, 4)
              )
            ]
          ),
          child: Column(
            children: [
              // Teks Progress dan Persentase
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Progress Hari Ini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    '${(progressValue * 100).toInt()}%', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: sigmaMagenta, fontSize: 16)
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Garis Loading (Progress Bar)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(sigmaMagenta),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Dua Kotak Statistik (Selesai vs Menunggu)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.withOpacity(0.2))
                      ),
                      child: Column(
                        children: [
                          Text(completedTasks.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                          const SizedBox(height: 4),
                          const Text('Selesai', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.withOpacity(0.2))
                      ),
                      child: Column(
                        children: [
                          Text(pendingTasks.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
                          const SizedBox(height: 4),
                          const Text('Menunggu', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        )
      ],
    );
  }
}