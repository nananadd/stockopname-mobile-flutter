import 'package:flutter/material.dart';
import '../database/sqlite_helper.dart';
import 'package:barcode_scan2/barcode_scan2.dart';

class CycleCountScreen extends StatefulWidget {
  final String? initialRackId; 
  
  const CycleCountScreen({super.key, this.initialRackId}); 

  @override
  State<CycleCountScreen> createState() => _CycleCountScreenState();
}

class _CycleCountScreenState extends State<CycleCountScreen> {
  
  final Color sigmaBlack = const Color(0xFF111111);
  final Color sigmaMagenta = const Color(0xFFF31A6B);
  final Color bgLight = const Color(0xFFF4F6F9);

  bool _isRackLocked = false;
  
  // Variabel untuk menampung pesan hitung ulang
  bool _isRecount = false;
  String _spvNote = '';

  List<Map<String, dynamic>> _racks = [];
  List<Map<String, dynamic>> _items = [];
  String? _selectedRackId;
  
  final Map<String, TextEditingController> _controllers = {};
  final DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadRacksOnly();
  }

  Future<void> _loadRacksOnly() async {
    final db = await DatabaseHelper.instance.database;
    final racks = await db.query('racks');
    setState(() {
      _racks = racks;
    });

    if (widget.initialRackId != null) {
      bool isRackExist = _racks.any((r) => r['id'].toString() == widget.initialRackId);
      if (isRackExist) {
        setState(() {
          _selectedRackId = widget.initialRackId;
          _isRackLocked = true; 
        });
        _loadItemsForRack(widget.initialRackId!);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rak tidak ditemukan di HP! Lakukan "Download Data Master" di menu Sync terlebih dahulu.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.pop(context); 
        }
      }
    }
  }

  // Load Item sekaligus mengecek status Recount
  Future<void> _loadItemsForRack(String rackId) async {
    final db = await DatabaseHelper.instance.database;
    
    // Cek tugas Recount
    final recountTask = await db.query(
      'cycle_counts',
      where: 'rack_id = ? AND status = ?',
      whereArgs: [int.parse(rackId), 'recount'],
      limit: 1,
    );

    final itemsData = await DatabaseHelper.instance.getItemsByRack(int.parse(rackId));
    
    setState(() {
      _items = List<Map<String, dynamic>>.from(itemsData); 
      
      if (recountTask.isNotEmpty) {
        _isRecount = true;
        _spvNote = recountTask.first['notes']?.toString() ?? 'Hitung ulang rak ini.';
      } else {
        _isRecount = false;
        _spvNote = '';
      }
    });

    _controllers.clear(); 
    for (var item in _items) {
      _controllers[item['id'].toString()] = TextEditingController();
    }
  }

  Future<void> _saveOffline() async {
    if (_selectedRackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih Rak dulu!'), backgroundColor: Colors.red));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rak ini kosong, tidak ada yang bisa dihitung.'), backgroundColor: Colors.orange));
      return;
    }

    bool hasInput = false;
    for (var controller in _controllers.values) {
      if (controller.text.isNotEmpty) {
        hasInput = true;
        break;
      }
    }

    if (!hasInput) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi jumlah fisik minimal pada 1 barang!'), backgroundColor: Colors.red)
      );
      return;
    }

    final db = await DatabaseHelper.instance.database;
    
    // Pakai Transaksi agar lebih aman
    await db.transaction((txn) async {
      // Simpan header ke 'pending'
      int cycleId = await txn.insert('cycle_counts', {
        'rack_id': _selectedRackId,
        'status': 'pending', // Status jadi pending agar siap diupload
        'started_at': _startedAt.toIso8601String(),
        'finished_at': DateTime.now().toIso8601String(),
      });

      // Simpan detail barang
      for (var item in _items) {
        String itemId = item['id'].toString();
        String inputQty = _controllers[itemId]?.text ?? '';
        
        if (inputQty.isNotEmpty) {
          await txn.insert('cycle_count_details', {
            'cycle_count_id': cycleId,
            'item_id': item['id'],
            'system_stock_snapshot': item['system_stock'] ?? 0, 
            'physical_stock': int.parse(inputQty),
          });
        }
      }

      // Jika berasal dari tugas recount, HAPUS tugas recount lama agar tidak numpuk
      if (_isRecount) {
        await txn.delete(
          'cycle_counts',
          where: 'rack_id = ? AND status = ?',
          whereArgs: [int.parse(_selectedRackId!), 'recount']
        );
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hitungan berhasil disimpan Offline!'), backgroundColor: Colors.green));
      Navigator.pop(context);
    }
  }

  Future<void> _showAddMisplacedItemDialog() async {
    TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    Future<void> performSearch(String keyword, Function setModalState) async {
      if (keyword.isEmpty) return;
      setModalState(() => isSearching = true);
      
      final db = await DatabaseHelper.instance.database;
      final results = await db.query(
        'items',
        where: 'name LIKE ? OR sku LIKE ?',
        whereArgs: ['%$keyword%', '%$keyword%'],
        limit: 10, 
      );
      setModalState(() {
        searchResults = results;
        isSearching = false;
      });
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24, left: 24, right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tambah Barang Nyasar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Cari berdasarkan Nama atau SKU:', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Misal: ATK-001 atau Kertas',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onSubmitted: (value) => performSearch(value, setModalState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(color: sigmaBlack, borderRadius: BorderRadius.circular(12)),
                        child: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                          onPressed: () async {
                            try {
                              var result = await BarcodeScanner.scan();
                              if (result.type == ResultType.Barcode) {
                                searchController.text = result.rawContent;
                                performSearch(result.rawContent, setModalState);
                              }
                            } catch (e) {}
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (isSearching)
                    const Center(child: CircularProgressIndicator())
                  else if (searchResults.isNotEmpty)
                    SizedBox(
                      height: 250,
                      child: ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final item = searchResults[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('SKU: ${item['sku']}'),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: sigmaMagenta,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                ),
                                onPressed: () {
                                  bool alreadyExists = _items.any((i) => i['id'] == item['id']);
                                  if (alreadyExists) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barang sudah ada di daftar rak ini!'), backgroundColor: Colors.orange));
                                  } else {
                                    setState(() {
                                      Map<String, dynamic> newItem = Map<String, dynamic>.from(item);
                                      newItem['system_stock'] = 0; 
                                      _items.add(newItem);
                                      _controllers[item['id'].toString()] = TextEditingController();
                                    });
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barang berhasil ditambahkan!'), backgroundColor: Colors.green));
                                  }
                                },
                                child: const Text('Tambah'),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else if (searchController.text.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: Text('Barang tidak ditemukan di database.', style: TextStyle(color: Colors.red))),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _scanQR() async {
    try {
      var result = await BarcodeScanner.scan();
      if (result.type == ResultType.Barcode) {
        String hasilScan = result.rawContent.trim();
        final matchedRack = _racks.firstWhere(
          (rack) => rack['qr_code'] == hasilScan || rack['code'] == hasilScan,
          orElse: () => {}, 
        );
        if (matchedRack.isNotEmpty) {
          setState(() {
            _selectedRackId = matchedRack['id'].toString();
            _loadItemsForRack(_selectedRackId!);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rak dipilih: ${matchedRack['code']}'), backgroundColor: Colors.green)
          );
          return; 
        }

        final db = await DatabaseHelper.instance.database;
        final List<Map<String, dynamic>> matchedItems = await db.query(
          'items',
          where: 'sku LIKE ?', 
          whereArgs: [hasilScan],
        );
        if (matchedItems.isNotEmpty) {
          final item = matchedItems.first;
          if (_selectedRackId != null) {
            bool alreadyExists = _items.any((i) => i['id'] == item['id']);
            if (alreadyExists) {
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Barang ${item['name']} sudah ada di daftar bawah!'), backgroundColor: Colors.blue)
               );
            } else {
               setState(() {
                  Map<String, dynamic> newItem = Map<String, dynamic>.from(item);
                  newItem['system_stock'] = 0; 
                  _items.add(newItem);
                  _controllers[item['id'].toString()] = TextEditingController();
                });
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Berhasil mengalokasikan ${item['name']} ke rak ini!'), backgroundColor: Colors.green)
               );
            }
          } 
          else {
            final List<Map<String, dynamic>> rackLocations = await db.rawQuery('''
               SELECT r.id, r.code FROM racks r
               INNER JOIN item_rack ir ON r.id = ir.rack_id
               WHERE ir.item_id = ?
            ''', [item['id']]);
            if (rackLocations.isNotEmpty) {
               String rackCode = rackLocations.first['code'];
               String rackId = rackLocations.first['id'].toString();
               
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Barang ${item['name']} aslinya di Rak $rackCode. Membuka rak...'), backgroundColor: Colors.blue)
               );
               setState(() {
                  _selectedRackId = rackId;
                  _loadItemsForRack(rackId);
               });
            } else {
               ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Barang belum teralokasi! Pilih Rak dari dropdown dulu, lalu scan barang ini untuk mengalokasikannya.'), 
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 4),
                  )
               );
            }
          }
        } 
        else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Barcode tidak dikenali sistem!'), backgroundColor: Colors.red)
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membaca scanner.'), backgroundColor: Colors.red)
      );
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight, 
      appBar: AppBar(
        title: const Text('Mulai Cycle Count', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: sigmaBlack, 
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _racks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Belum ada data Rak.\nLakukan Sinkronisasi dulu!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih Lokasi Rak', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  const SizedBox(height: 12),
                  
                  // CARD DROPDOWN & SCAN
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                      ]
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: bgLight,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              hint: const Text('Pilih Rak...'),
                            ), 
                            value: _selectedRackId,
                            items: _racks.map((rack) {
                              return DropdownMenuItem<String>(
                                value: rack['id'].toString(),
                                child: Text('${rack['code']}'),
                              );
                            }).toList(),
                            onChanged: _isRackLocked 
                                ? null 
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedRackId = value;
                                        _loadItemsForRack(value);
                                      });
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _scanQR,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: sigmaBlack, 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Icon(Icons.qr_code_scanner, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Banner notes SPV
                  if (_isRecount && _spvNote.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade300, width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PERLU HITUNG ULANG!', 
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 14)
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '"$_spvNote"',
                                  style: const TextStyle(color: Colors.black87, fontStyle: FontStyle.italic, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Text('Daftar Barang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  const SizedBox(height: 12),

                  // LIST BARANG
                  Expanded(
                    child: _selectedRackId == null
                        ? Center(child: Text('Silakan pilih rak di atas', style: TextStyle(color: Colors.grey.shade500)))
                        : _items.isEmpty
                            ? Center(child: Text('Tidak ada barang di rak ini.', style: TextStyle(color: Colors.grey.shade500)))
                            : ListView.builder(
                                itemCount: _items.length,
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  final itemId = item['id'].toString();
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      title: Text(item['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('SKU: ${item['sku']}', style: TextStyle(color: sigmaMagenta, fontSize: 12)),
                                      trailing: SizedBox(
                                        width: 130, 
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _controllers[itemId],
                                                keyboardType: TextInputType.number,
                                                textAlign: TextAlign.center,
                                                decoration: InputDecoration(
                                                  labelText: 'Fisik',
                                                  filled: true,
                                                  fillColor: bgLight,
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _items.removeAt(index);
                                                  _controllers.remove(itemId);
                                                });
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Barang ${item['name']} dihapus dari daftar.'),
                                                    backgroundColor: Colors.orange,
                                                    duration: const Duration(seconds: 2),
                                                  )
                                                );
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),

                  // TOMBOL TAMBAH BARANG NYASAR
                  if (_selectedRackId != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: _showAddMisplacedItemDialog,
                        icon: Icon(Icons.add_circle_outline, color: sigmaMagenta),
                        label: Text('Tambah Barang Lain (Nyasar)', style: TextStyle(color: sigmaMagenta, fontWeight: FontWeight.bold)),
                      ),
                    ),

                  // TOMBOL SIMPAN BAWAH
                  if (_selectedRackId != null && _items.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 16, bottom: 24),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sigmaMagenta, 
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                          shadowColor: sigmaMagenta.withOpacity(0.4),
                        ),
                        onPressed: _saveOffline,
                        child: const Text('Simpan Hitungan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }
}