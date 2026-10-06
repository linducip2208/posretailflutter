import 'dart:typed_data';
import 'dart:io';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _printCharacteristic;

  List<BluetoothDevice> discoveredDevices = [];

  Future<List<BluetoothDevice>> scanDevices() async {
    discoveredDevices = [];
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!discoveredDevices.any((d) => d.remoteId == result.device.remoteId)) {
          discoveredDevices.add(result.device);
        }
      }
    });
    await Future.delayed(const Duration(seconds: 5));
    await FlutterBluePlus.stopScan();
    return discoveredDevices;
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(license: License.nonprofit, autoConnect: false);
      final services = await device.discoverServices();

      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            _printCharacteristic = characteristic;
            _connectedDevice = device;
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _printCharacteristic = null;
    }
  }

  bool get isConnected => _connectedDevice?.isConnected ?? false;

  Future<img.Image?> _loadLogo() async {
    try {
      final byteData = await rootBundle.load('assets/logo.png');
      final bytes = byteData.buffer.asUint8List();
      return img.decodePng(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final byteData = await rootBundle.load('assets/logo.png');
      return byteData.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> printReceipt({
    required String orderNumber,
    required DateTime date,
    required String cashier,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required double change,
    String? customerName,
    String? outletName,
  }) async {
    if (_printCharacteristic == null) return;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);

    List<int> bytes = [];

    final logo = await _loadLogo();
    if (logo != null) {
      bytes += generator.image(logo);
      bytes += generator.feed(1);
    }

    // Header
    bytes += generator.text('POS RETAIL',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text(outletName ?? '',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    // Info
    bytes += generator.row([
      PosColumn(text: 'No: $orderNumber', width: 6),
      PosColumn(text: DateFormat('dd/MM/yy HH:mm').format(date), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.text('Kasir: $cashier');
    if (customerName != null) {
      bytes += generator.text('Customer: $customerName');
    }
    bytes += generator.hr();

    // Items
    bytes += generator.row([
      PosColumn(text: 'Item', width: 6),
      PosColumn(text: 'Qty', width: 2),
      PosColumn(text: 'Harga', width: 2, styles: const PosStyles(align: PosAlign.right)),
      PosColumn(text: 'Subtotal', width: 2, styles: const PosStyles(align: PosAlign.right)),
    ]);

    for (final item in items) {
      bytes += generator.row([
        PosColumn(text: item['name'].toString().length > 20
            ? item['name'].toString().substring(0, 20) : item['name'].toString(), width: 6),
        PosColumn(text: '${item['qty']}', width: 2),
        PosColumn(text: _formatCurrency(item['price']), width: 2, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: _formatCurrency(item['subtotal']), width: 2, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();

    // Totals
    bytes += generator.row([
      PosColumn(text: 'Subtotal', width: 6),
      PosColumn(text: _formatCurrency(subtotal), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    if (discount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon', width: 6),
        PosColumn(text: _formatCurrency(discount), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    if (tax > 0) {
      bytes += generator.row([
        PosColumn(text: 'Pajak', width: 6),
        PosColumn(text: _formatCurrency(tax), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: _formatCurrency(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)),
    ]);

    bytes += generator.hr();

    // Payment
    bytes += generator.row([
      PosColumn(text: 'Dibayar', width: 6),
      PosColumn(text: _formatCurrency(paid), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Kembalian', width: 6),
      PosColumn(text: _formatCurrency(change), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    bytes += generator.hr();
    bytes += generator.text('Terima kasih telah berbelanja!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Barang yang sudah dibeli tidak dapat ditukar',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(3);
    bytes += generator.cut();

    await _printCharacteristic!.write(bytes, withoutResponse: true);
  }

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    return format.format(amount);
  }

  Future<Uint8List> generatePdfReceipt({
    required String orderNumber,
    required DateTime date,
    required String cashier,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required double change,
    String? customerName,
    String? outletName,
  }) async {
    final pdf = pw.Document();
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    final logoBytes = await _loadLogoBytes();
    final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoImage != null) ...[
                pw.Center(child: pw.Image(logoImage, width: 60, height: 60)),
                pw.SizedBox(height: 4),
              ],
              pw.Center(child: pw.Text('POS RETAIL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
              if (outletName != null)
                pw.Center(child: pw.Text(outletName, style: const pw.TextStyle(fontSize: 8))),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('No: $orderNumber', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(DateFormat('dd/MM/yy HH:mm').format(date), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Text('Kasir: $cashier', style: const pw.TextStyle(fontSize: 7)),
              if (customerName != null)
                pw.Text('Customer: $customerName', style: const pw.TextStyle(fontSize: 7)),
              pw.Divider(),
              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text('Item', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 2, child: pw.Text('Qty', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 3, child: pw.Text('Harga', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                  pw.Expanded(flex: 3, child: pw.Text('Subtotal', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                ],
              ),
              ...items.map((item) => pw.Row(
                    children: [
                      pw.Expanded(flex: 5, child: pw.Text(
                        (item['name'] as String).length > 18
                            ? (item['name'] as String).substring(0, 18)
                            : item['name'] as String,
                        style: const pw.TextStyle(fontSize: 7),
                      )),
                      pw.Expanded(flex: 2, child: pw.Text('${item['qty']}', style: const pw.TextStyle(fontSize: 7))),
                      pw.Expanded(flex: 3, child: pw.Text(format.format(item['price'] as double), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right)),
                      pw.Expanded(flex: 3, child: pw.Text(format.format(item['subtotal'] as double), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right)),
                    ],
                  )),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(format.format(subtotal), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              if (discount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Diskon', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(format.format(discount), style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              if (tax > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Pajak', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(format.format(tax), style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(format.format(total), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Dibayar', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(format.format(paid), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Kembalian', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(format.format(change), style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Divider(),
              pw.Center(child: pw.Text('Terima kasih telah berbelanja!', style: const pw.TextStyle(fontSize: 7))),
              pw.Center(child: pw.Text('Barang yang sudah dibeli tidak dapat ditukar', style: const pw.TextStyle(fontSize: 6))),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> shareReceiptPdf(Uint8List pdfBytes, {String? orderNumber}) async {
    final dir = await getTemporaryDirectory();
    final filename = 'struk-${orderNumber ?? 'order'}.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(pdfBytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Struk $orderNumber',
      ),
    );
  }

  Future<void> saveAndOpenPdf(Uint8List pdfBytes, {String? orderNumber}) async {
    final dir = await getTemporaryDirectory();
    final filename = 'struk-${orderNumber ?? 'order'}.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(pdfBytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Struk $orderNumber',
      ),
    );
  }
}
