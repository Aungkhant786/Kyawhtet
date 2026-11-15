import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shopName = 'ကျော်ထက်အောင် ငါးရောင်းဝယ်ရေး';
final money = NumberFormat('#,##0');
final dateFmt = DateFormat('dd/MM/yyyy');
const units = ['ပိဿာ', 'ကီလို', 'ကောင်', 'ခြင်း'];

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: shopName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const HomePage(),
      );
}

// ---------------- Models ----------------

class Item {
  String name;
  double qty;
  String unit;
  double price;
  Item({required this.name, required this.qty, required this.unit, required this.price});
  double get total => qty * price;

  Map<String, dynamic> toJson() => {'n': name, 'q': qty, 'u': unit, 'p': price};
  factory Item.fromJson(Map<String, dynamic> j) => Item(
        name: j['n'] as String,
        qty: (j['q'] as num).toDouble(),
        unit: j['u'] as String,
        price: (j['p'] as num).toDouble(),
      );
}

class Voucher {
  int no;
  DateTime date;
  String type; // ရောင်း / ဝယ်
  String customer;
  String note;
  List<Item> items;
  Voucher({
    required this.no,
    required this.date,
    required this.type,
    required this.customer,
    required this.note,
    required this.items,
  });
  double get total => items.fold(0.0, (s, i) => s + i.total);

  Map<String, dynamic> toJson() => {
        'no': no,
        'date': date.toIso8601String(),
        'type': type,
        'customer': customer,
        'note': note,
        'items': items.map((e) => e.toJson()).toList(),
      };
  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        no: j['no'] as int,
        date: DateTime.parse(j['date'] as String),
        type: j['type'] as String,
        customer: j['customer'] as String,
        note: (j['note'] ?? '') as String,
        items: (j['items'] as List).map((e) => Item.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class Store {
  static const _k = 'vouchers';
  static Future<List<Voucher>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Voucher.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> save(List<Voucher> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(l.map((e) => e.toJson()).toList()));
  }

  static Future<int> nextNo() async {
    final l = await load();
    if (l.isEmpty) return 1;
    return l.map((e) => e.no).reduce((a, b) => a > b ? a : b) + 1;
  }
}

// ---------------- Home (create voucher) ----------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String type = 'ရောင်း';
  final customer = TextEditingController();
  final note = TextEditingController();
  DateTime date = DateTime.now();
  final List<Item> items = [];

  double get total => items.fold(0.0, (s, i) => s + i.total);

  Future<void> _addItem() async {
    final name = TextEditingController();
    final qty = TextEditingController();
    final price = TextEditingController();
    String unit = units.first;
    final item = await showDialog<Item>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('ငါးအမျိုးအစား ထည့်ရန်'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'ငါးအမည်')),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'ပမာဏ'),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: unit,
                  items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => setS(() => unit = v!),
                ),
              ]),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '၁ $unit ဈေး (ကျပ်)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်တော့ပါ')),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qty.text.trim());
                final p = double.tryParse(price.text.trim().replaceAll(',', ''));
                if (name.text.trim().isEmpty || q == null || p == null) return;
                Navigator.pop(ctx, Item(name: name.text.trim(), qty: q, unit: unit, price: p));
              },
              child: const Text('ထည့်မည်'),
            ),
          ],
        ),
      ),
    );
    if (item != null) setState(() => items.add(item));
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> _issue() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ငါးအမျိုးအစား အနည်းဆုံး ၁ ခု ထည့်ပါ')),
      );
      return;
    }
    final v = Voucher(
      no: await Store.nextNo(),
      date: date,
      type: type,
      customer: customer.text.trim(),
      note: note.text.trim(),
      items: List.of(items),
    );
    final all = await Store.load();
    all.add(v);
    await Store.save(all);
    if (!mounted) return;
    setState(() {
      items.clear();
      customer.clear();
      note.clear();
      date = DateTime.now();
    });
    Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherPage(voucher: v)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(shopName, style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'ဘောင်ချာမှတ်တမ်း',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ရောင်း', label: Text('ရောင်းဘောင်ချာ'), icon: Icon(Icons.sell)),
            ButtonSegment(value: 'ဝယ်', label: Text('ဝယ်ဘောင်ချာ'), icon: Icon(Icons.shopping_basket)),
          ],
          selected: {type},
          onSelectionChanged: (s) => setState(() => type = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: customer,
          decoration: InputDecoration(
            labelText: type == 'ရောင်း' ? 'ဝယ်သူအမည်' : 'ရောင်းသူအမည်',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)),
          leading: const Icon(Icons.calendar_today),
          title: Text('ရက်စွဲ - ${dateFmt.format(date)}'),
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('ငါးစာရင်း', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          FilledButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('ထည့်မည်')),
        ]),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('ငါးစာရင်း မရှိသေးပါ')),
          ),
        ...items.asMap().entries.map((e) {
          final i = e.value;
          return Card(
            child: ListTile(
              title: Text(i.name),
              subtitle: Text('${_n(i.qty)} ${i.unit} × ${money.format(i.price)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${money.format(i.total)} ကျပ်', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => items.removeAt(e.key))),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'မှတ်ချက် (မလိုရင်ချန်ထားပါ)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Expanded(child: Text('စုစုပေါင်း', style: TextStyle(fontSize: 18))),
              Text('${money.format(total)} ကျပ်', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
          onPressed: _issue,
          icon: const Icon(Icons.receipt_long),
          label: const Text('ဘောင်ချာထုတ်မည်', style: TextStyle(fontSize: 16)),
        ),
      ]),
    );
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ---------------- Voucher view / share / print ----------------

class VoucherView extends StatelessWidget {
  final Voucher v;
  const VoucherView({super.key, required this.v});

  @override
  Widget build(BuildContext context) {
    const s = TextStyle(color: Colors.black, fontSize: 14);
    const b = TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold);
    Widget cell(String t, {TextStyle st = s, TextAlign a = TextAlign.left}) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text(t, style: st, textAlign: a));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text(shopName, style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold))),
        Center(child: Text('${v.type}ဘောင်ချာ', style: s)),
        const Divider(color: Colors.black),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('ဘောင်ချာအမှတ် - ${v.no.toString().padLeft(4, '0')}', style: s),
          Text('ရက်စွဲ - ${dateFmt.format(v.date)}', style: s),
        ]),
        if (v.customer.isNotEmpty) Text('${v.type == 'ရောင်း' ? 'ဝယ်သူ' : 'ရောင်းသူ'} - ${v.customer}', style: s),
        const SizedBox(height: 8),
        Table(
          border: TableBorder.all(color: Colors.black54),
          columnWidths: const {
            0: FixedColumnWidth(28),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
            4: FlexColumnWidth(2.4),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFE0F2F1)),
              children: [
                cell('စဉ်', st: b),
                cell('ငါးအမည်', st: b),
                cell('ပမာဏ', st: b, a: TextAlign.right),
                cell('ဈေး', st: b, a: TextAlign.right),
                cell('သင့်ငွေ', st: b, a: TextAlign.right),
              ],
            ),
            ...v.items.asMap().entries.map((e) {
              final i = e.value;
              return TableRow(children: [
                cell('${e.key + 1}'),
                cell(i.name),
                cell('${_n(i.qty)} ${i.unit}', a: TextAlign.right),
                cell(money.format(i.price), a: TextAlign.right),
                cell(money.format(i.total), a: TextAlign.right),
              ]);
            }),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text('စုစုပေါင်း - ${money.format(v.total)} ကျပ်',
              style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        if (v.note.isNotEmpty) ...[const SizedBox(height: 8), Text('မှတ်ချက် - ${v.note}', style: s)],
        const SizedBox(height: 24),
        const Center(child: Text('ဝယ်ယူအားပေးမှုကို ကျေးဇူးတင်ပါသည်', style: s)),
      ]),
    );
  }
}

class VoucherPage extends StatefulWidget {
  final Voucher voucher;
  const VoucherPage({super.key, required this.voucher});
  @override
  State<VoucherPage> createState() => _VoucherPageState();
}

class _VoucherPageState extends State<VoucherPage> {
  final _key = GlobalKey();

  // Flutter ရဲ့ text engine နဲ့ မြန်မာစာ မှန်ကန်စွာပေါ်အောင် ပုံအဖြစ်ယူပြီး share/print လုပ်သည်
  Future<Uint8List> _capture() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _share() async {
    final png = await _capture();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/voucher_${widget.voucher.no}.png');
    await f.writeAsBytes(png);
    await Share.shareXFiles([XFile(f.path)], text: '$shopName ဘောင်ချာ #${widget.voucher.no}');
  }

  Future<void> _print() async {
    final png = await _capture();
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (_) => pw.Align(
        alignment: pw.Alignment.topCenter,
        child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'voucher_${widget.voucher.no}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ဘောင်ချာ #${widget.voucher.no.toString().padLeft(4, '0')}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: RepaintBoundary(key: _key, child: VoucherView(v: widget.voucher)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _share, icon: const Icon(Icons.share), label: const Text('ပို့မည် (ပုံ)'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: _print, icon: const Icon(Icons.print), label: const Text('Print / PDF'))),
          ]),
        ),
      ),
    );
  }
}

// ---------------- History ----------------

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Voucher> list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Store.load();
    l.sort((a, b) => b.no.compareTo(a.no));
    setState(() => list = l);
  }

  Future<void> _delete(Voucher v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ဘောင်ချာ #${v.no} ကို ဖျက်မလား?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မဖျက်ပါ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ဖျက်မည်')),
        ],
      ),
    );
    if (ok != true) return;
    final all = await Store.load();
    all.removeWhere((e) => e.no == v.no);
    await Store.save(all);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ဘောင်ချာမှတ်တမ်း')),
      body: list.isEmpty
          ? const Center(child: Text('မှတ်တမ်း မရှိသေးပါ'))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final v = list[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(v.type)),
                  title: Text('#${v.no.toString().padLeft(4, '0')}  ${v.customer.isEmpty ? '-' : v.customer}'),
                  subtitle: Text(dateFmt.format(v.date)),
                  trailing: Text('${money.format(v.total)} ကျပ်', style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoucherPage(voucher: v))),
                  onLongPress: () => _delete(v),
                );
              },
            ),
    );
  }
}
