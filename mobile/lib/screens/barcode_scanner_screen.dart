import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool scanned = false;

  Future<void> showManualBarcodeDialog() async {
    final manualController = TextEditingController();

    final barcode = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Barkodu elle gir"),
          content: TextField(
            controller: manualController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Örn: 8691234567890",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("İptal"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, manualController.text.trim());
              },
              child: const Text("Ara"),
            ),
          ],
        );
      },
    );

    if (barcode != null && barcode.trim().isNotEmpty) {
      Navigator.pop(context, barcode.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Barkod Tara"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (scanned) return;

              final barcode = capture.barcodes.firstOrNull;
              final code = barcode?.rawValue;

              if (code == null || code.isEmpty) return;

              setState(() {
                scanned = true;
              });

              Navigator.pop(context, code);
            },
          ),

          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 42,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Text(
                  "Ürünün barkodunu çerçevenin içine getir",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: showManualBarcodeDialog,
                    icon: const Icon(Icons.keyboard_rounded),
                    label: const Text("Barkodu elle gir"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.55),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}