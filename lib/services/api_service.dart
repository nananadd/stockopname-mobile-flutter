import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // PENTING: Jika menjalankan Flutter di Emulator Android, 
  // localhost (127.0.0.1) harus diganti menjadi 10.0.2.2 agar bisa menembak ke komputer Windows.
  // Jika menggunakan HP asli, ganti dengan IP Address WiFi laptopmu (contoh: 192.168.1.5)
  // static const String baseUrl = 'http://10.0.2.2:8000/api'; // Untuk Android Studio
  static const String baseUrl = 'http://192.168.1.7:8000/api'; //HP

  // Kunci rahasia untuk menyimpan token di brankas HP
  static const String _tokenKey = 'jwt_token';

  /// Fungsi untuk melakukan Login
  Future<Map<String, dynamic>> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/login');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Jika sukses, simpan token JWT ke memori HP
        await saveToken(data['access_token']);

        final prefs = await SharedPreferences.getInstance();
        
        // Kita gunakan operator kustom agar aman jika struktur JSON Laravel-mu
        // berbentuk data['user']['name'] atau langsung data['user_name']
        String namaStaf = 'Staf Gudang';
        if (data['user'] != null && data['user']['name'] != null) {
          namaStaf = data['user']['name'];
        } else if (data['name'] != null) {
          namaStaf = data['name'];
        }
        
        await prefs.setString('user_name', namaStaf);

        return {'success': true, 'data': data};
      } else {
        // Jika gagal (email/password salah)
        return {'success': false, 'message': data['error'] ?? 'Login gagal'};
      }
    } catch (e) {
      // Jika server mati atau tidak ada internet
      return {'success': false, 'message': 'Tidak dapat terhubung ke server. Pastikan server menyala.'};
    }
  }

  /// Fungsi untuk menyimpan token
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Fungsi untuk mengambil token (akan digunakan saat hitung cycle count nanti)
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Fungsi untuk Logout (Hapus token)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Fungsi bantuan untuk mengecek apakah user sudah login atau belum
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  /// Fungsi untuk menarik semua Master Data (Rak & Item) sekaligus
  Future<Map<String, dynamic>> pullMasterData() async {
    final token = await getToken();
    
    // Sesuaikan URL ini dengan yang ada di routes/api.php Laravel-mu
    // Misalnya route-nya: Route::get('/sync/pull', [SyncController::class, 'pullMasterData']);
    final url = Uri.parse('$baseUrl/sync/pull'); 

    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        // Mengembalikan Map yang berisi array 'racks' dan 'items'
        return jsonDecode(response.body); 
      }
      return {'racks': [], 'items': []};
    } catch (e) {
      // TAMBAHKAN BARIS INI UNTUK MELIHAT ERROR ASLINYA
      print('============= ERROR API =============');
      print(e.toString());
      print('=====================================');
      
      throw Exception('Gagal memuat data');
    }
  }

  /// Fungsi untuk mengirim data hitungan offline ke Laravel
  Future<bool> pushCycleCount(List<Map<String, dynamic>> cycleCounts) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/sync/push');

    print('📦 ISI PAKET YANG DIBAWA KURIR KE LARAVEL:');
    print(jsonEncode({'cycle_counts': cycleCounts}));
    print('===========================================');

    try {
      final response = await http.post(
        url,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'cycle_counts': cycleCounts, // Format array yang ditunggu Laravel
        }),
      );

      if (response.statusCode == 200) {
        return true; // Berhasil
      } else {
        // --- KODE YANG DIUBAH ---
        // Kita tangkap pesan error asli dari Laravel (misal error validasi atau 400/500)
        String errorMessage = 'Gagal mengirim data ke server.';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['error'] != null) {
            errorMessage = errorData['error'];
          } else if (errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          // Kalau response Laravel bukan JSON (misal error HTML 500), pakai pesan default
        }

        print('=== ERROR DARI LARAVEL ===');
        print('Status: ${response.statusCode}');
        print('Pesan: ${response.body}');
        
        // Kita "lempar" errornya ke UI agar SnackBar tahu pesannya apa
        throw Exception(errorMessage); 
        // --- AKHIR KODE YANG DIUBAH ---
      }
    } catch (e) {
      // Ubah return false menjadi throw exception agar pesan errornya sampai ke pengguna
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // Mengambil tugas jadwal
  Future<List<dynamic>> getMyTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey) ?? '';

    //testing token
    print('=============================');
    print('TOKEN YANG DIBAWA FLUTTER: $token');
    print('=============================');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sync/pull'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['my_tasks'] ?? [];
      } else {
        // TAMBAHKAN DUA BARIS INI UNTUK MENGINTIP ERROR ASLI LARAVEL
        print('STATUS CODE LARAVEL: ${response.statusCode}');
        print('PESAN DARI LARAVEL: ${response.body}');
        throw Exception('Gagal memuat tugas');
      }
    } catch (e) {
      print('Error Fetching Tasks: $e');
      return [];
    }
  }

  // FUNGSI GANTI PASSWORD FLUTTER
  Future<Map<String, dynamic>> changePassword(String currentPassword, String newPassword) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/change-password');

    try {
      final response = await http.post(
        url,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200, 'message': data['message'] ?? 'Terjadi kesalahan'};
    } catch (e) {
      return {'success': false, 'message': 'Gagal terhubung ke server.'};
    }
  }
}