import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../services/api_client.dart';
import '../../services/shop_api.dart';
import '../home/home_avatar.dart';

const _bg = Color(0xFF110E20);
const _panel = Color(0xFF201A32);
const _accent = Color(0xFFC5A2FF);
const _categories = <({String name, String? slots, IconData icon})>[
  (name: 'ผม', slots: 'hair', icon: Icons.face_retouching_natural),
  (name: 'หมวก', slots: 'headwear', icon: Icons.sports_baseball_outlined),
  (name: 'หน้า', slots: 'face', icon: Icons.face_outlined),
  (name: 'เสื้อ', slots: 'inner_top,outer_top', icon: Icons.checkroom),
  (name: 'ปีก', slots: 'back', icon: Icons.air),
  (name: 'ของถือ', slots: null, icon: Icons.work_outline),
  (name: 'กางเกง', slots: 'pants', icon: Icons.accessibility_new),
  (name: 'รองเท้า', slots: 'shoes', icon: Icons.directions_run),
  (name: 'แท่นยืน', slots: null, icon: Icons.layers_outlined),
];
const _rarities = {
  'common': 'ทั่วไป',
  'rare': 'หายาก',
  'epic': 'เอปิก',
  'legendary': 'ตำนาน'
};
const _sorts = {
  'featured': 'แนะนำ',
  'price_asc': 'ราคา: ต่ำ → สูง',
  'price_desc': 'ราคา: สูง → ต่ำ',
  'rarity_desc': 'ความหายาก: สูง → ต่ำ',
  'rarity_asc': 'ความหายาก: ต่ำ → สูง'
};
String _error(Object error) => error is ApiException
    ? error.message
    : 'โหลดสินค้าไม่สำเร็จ กรุณาลองอีกครั้ง';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});
  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  final _sheet = DraggableScrollableController();
  late Future<List<ShopPage>> _catalog;
  late Future<int> _balance;
  int? _selected;
  bool _expanded = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final api = ref.read(shopApiProvider);
    _catalog = Future.wait(_categories.map((c) => c.slots == null
        ? Future.value(const ShopPage([], 0))
        : api.list(c.slots!, limit: 8)));
    _balance = api.balance();
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _move(double value) {
    if (_sheet.isAttached) {
      _sheet.animateTo(value,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic);
    }
  }

  void _all(int index) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => ShopCategoryScreen(categoryIndex: index)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final height = constraints.maxHeight;
          final minimum = (48 / height).clamp(.06, .2);
          return Stack(children: [
            Positioned.fill(
                child: GestureDetector(
                    onTap: () => _move(minimum),
                    child: const DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: RadialGradient(
                                center: Alignment(0, -.4),
                                radius: .9,
                                colors: [Color(0xFF49345C), _bg]))))),
            Positioned(
                top: 72,
                left: 60,
                right: 60,
                height: math.max(80.0, math.min(310.0, height * .4 - 78)),
                child: const HomeAvatar()),
            Positioned(
                top: 8,
                left: 12,
                right: 20,
                child: Row(children: [
                  BackButton(onPressed: () => Navigator.maybePop(context)),
                  Text('ร้านค้า', style: AppText.heading(size: 22)),
                  const Spacer(),
                  const Icon(Icons.toll, color: AppColors.gold2, size: 20),
                  const SizedBox(width: 8),
                  FutureBuilder<int>(
                      future: _balance,
                      builder: (_, snapshot) => Text(
                          snapshot.hasData ? '${snapshot.data}' : '—',
                          style: AppText.heading(
                              size: 16, color: AppColors.gold2))),
                ])),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: .6,
              minChildSize: minimum,
              maxChildSize: .88,
              snap: true,
              snapSizes: const [.6],
              builder: (context, scroll) => Material(
                  color: _panel,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _move(_sheet.size < .59
                            ? .6
                            : _sheet.size < .87
                                ? .88
                                : .6),
                        onVerticalDragUpdate: (d) => _sheet.jumpTo(
                            (_sheet.size - d.delta.dy / height)
                                .clamp(minimum, .88)),
                        onVerticalDragEnd: (_) {
                          final stops = [minimum, .6, .88]..sort((a, b) =>
                              (a - _sheet.size)
                                  .abs()
                                  .compareTo((b - _sheet.size).abs()));
                          _move(stops.first);
                        },
                        child: Semantics(
                            button: true,
                            label: 'ย่อหรือขยายร้านค้า',
                            child: SizedBox(
                                height: 48,
                                width: double.infinity,
                                child: Center(
                                    child: Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: _accent,
                                            borderRadius:
                                                BorderRadius.circular(4))))))),
                    Expanded(
                        child: CustomScrollView(controller: scroll, slivers: [
                      SliverToBoxAdapter(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(children: [
                                Expanded(
                                    child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(children: [
                                          _tab('ทั้งหมด', null),
                                          for (var i = 0;
                                              i < _categories.length;
                                              i++)
                                            _tab(_categories[i].name, i),
                                        ]))),
                                IconButton(
                                    tooltip: 'หมวดหมู่ทั้งหมด',
                                    onPressed: () =>
                                        setState(() => _expanded = !_expanded),
                                    icon: Icon(
                                        _expanded
                                            ? Icons.expand_less
                                            : Icons.chevron_right,
                                        color: _accent)),
                              ]))),
                      if (_expanded)
                        SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        mainAxisExtent: 82),
                                delegate: SliverChildBuilderDelegate(
                                    (_, i) => OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                            backgroundColor: _selected == i
                                                ? const Color(0xFF493460)
                                                : null),
                                        onPressed: () => setState(() {
                                              _selected = i;
                                              _expanded = false;
                                            }),
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(_categories[i].icon,
                                                  color: _accent),
                                              const SizedBox(height: 6),
                                              Text(_categories[i].name,
                                                  style: const TextStyle(
                                                      color: _accent)),
                                            ])),
                                    childCount: _categories.length))),
                      FutureBuilder<List<ShopPage>>(
                          future: _catalog,
                          builder: (_, snapshot) {
                            if (snapshot.hasError) {
                              return SliverToBoxAdapter(
                                  child: _Notice(_error(snapshot.error!),
                                      retry: () => setState(_reload)));
                            }
                            if (!snapshot.hasData) {
                              return const SliverToBoxAdapter(
                                  child: Padding(
                                      padding: EdgeInsets.all(40),
                                      child: Center(
                                          child: CircularProgressIndicator())));
                            }
                            final indices = _selected == null
                                ? List.generate(_categories.length, (i) => i)
                                : [_selected!];
                            return SliverList(
                                delegate: SliverChildListDelegate([
                              for (final i in indices)
                                Container(
                                    margin: const EdgeInsets.fromLTRB(
                                        16, 12, 16, 0),
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 4, 12, 12),
                                    decoration: BoxDecoration(
                                        color: _bg.withValues(alpha: .5),
                                        borderRadius:
                                            BorderRadius.circular(18)),
                                    child: Column(children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(_categories[i].name,
                                                style:
                                                    AppText.heading(size: 16))),
                                        TextButton(
                                            onPressed: () => _all(i),
                                            child: const Text('ดูทั้งหมด ›',
                                                style:
                                                    TextStyle(color: _accent))),
                                      ]),
                                      if (snapshot.data![i].items.isEmpty)
                                        _Notice(_categories[i].slots == null
                                            ? 'หมวดนี้ยังไม่พร้อมใช้งาน'
                                            : 'ยังไม่มีสินค้าในหมวดนี้')
                                      else
                                        SizedBox(
                                            height: 194,
                                            child: ListView.separated(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount: snapshot
                                                    .data![i].items.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 12),
                                                itemBuilder: (_, j) => SizedBox(
                                                    width: 112,
                                                    child: _ItemCard(snapshot
                                                        .data![i].items[j])))),
                                    ])),
                              const SizedBox(height: 24),
                            ]));
                          }),
                    ])),
                  ])),
            ),
          ]);
        })),
      );
  Widget _tab(String label, int? index) => TextButton(
      onPressed: () => setState(() => _selected = index),
      child: Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: _selected == index ? _accent : Colors.transparent,
                      width: 3))),
          child: Text(label,
              style: AppText.heading(
                  size: 13,
                  color: _selected == index
                      ? _accent
                      : AppColors.textSecondary))));
}

class ShopCategoryScreen extends ConsumerStatefulWidget {
  final int categoryIndex;
  const ShopCategoryScreen({super.key, required this.categoryIndex});
  @override
  ConsumerState<ShopCategoryScreen> createState() => _ShopCategoryScreenState();
}

class _ShopCategoryScreenState extends ConsumerState<ShopCategoryScreen> {
  List<ShopItem> _items = [];
  String _sort = 'featured';
  String? _rarity, _failure;
  int _total = 0, _generation = 0;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final slots = _categories[widget.categoryIndex].slots;
    setState(() {
      _loading = true;
      _failure = null;
      if (!more) {
        _items = [];
        _total = 0;
      }
    });
    try {
      final result = slots == null
          ? const ShopPage([], 0)
          : await ref.read(shopApiProvider).list(slots,
              sort: _sort, rarity: _rarity, offset: more ? _items.length : 0);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = more ? [..._items, ...result.items] : result.items;
        _total = result.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = _error(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
            title: Text(_categories[widget.categoryIndex].name),
            backgroundColor: _panel),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                DropdownButtonFormField<String>(
                    initialValue: _sort,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'เรียงลำดับ', border: OutlineInputBorder()),
                    items: _sorts.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _sort = value);
                      _load();
                    }),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: 'all',
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'ระดับความหายาก',
                        border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('ทั้งหมด')),
                      ..._rarities.entries.map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                    ],
                    onChanged: (value) {
                      setState(() => _rarity = value == 'all' ? null : value);
                      _load();
                    }),
              ])),
          Expanded(
              child: RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (_items.isNotEmpty)
                          SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverGrid(
                                  delegate: SliverChildBuilderDelegate(
                                      (_, i) => _ItemCard(_items[i]),
                                      childCount: _items.length),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 190,
                                          mainAxisExtent: 250,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 12))),
                        SliverToBoxAdapter(
                            child: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Center(
                                        child: CircularProgressIndicator()))
                                : _failure != null
                                    ? _Notice(_failure!,
                                        retry: () =>
                                            _load(more: _items.isNotEmpty))
                                    : _items.isEmpty
                                        ? _Notice(
                                            _categories[widget.categoryIndex]
                                                        .slots ==
                                                    null
                                                ? 'หมวดนี้ยังไม่พร้อมใช้งาน'
                                                : 'ไม่พบสินค้าที่ตรงกับตัวกรอง')
                                        : _items.length < _total
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                child: OutlinedButton(
                                                    onPressed: () =>
                                                        _load(more: true),
                                                    child: const Text(
                                                        'โหลดเพิ่มเติม')))
                                            : Padding(
                                                padding:
                                                    const EdgeInsets.all(24),
                                                child: Center(
                                                    child: Text(
                                                        '${_items.length} รายการ')))),
                      ]))),
        ])),
      );
}

class _ItemCard extends StatelessWidget {
  final ShopItem item;
  const _ItemCard(this.item);
  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: _panel,
          builder: (_) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.name, style: AppText.heading(size: 22)),
                    const SizedBox(height: 12),
                    Text(_rarities[item.rarity] ?? item.rarity,
                        style: const TextStyle(color: _accent)),
                    const SizedBox(height: 12),
                    Text(item.description),
                    const SizedBox(height: 16),
                    Text(item.owned ? 'มีแล้ว' : '${item.price} เหรียญ',
                        style: AppText.heading(color: AppColors.gold2)),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ปิด')),
                  ]))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withValues(alpha: .6))),
                child: item.image.isEmpty
                    ? const Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textTertiary)
                    : Image.network(item.image,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.textTertiary)))),
        const SizedBox(height: 8),
        Text(item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 12)),
        Text(_rarities[item.rarity] ?? item.rarity,
            style: AppText.body(size: 10, color: _accent)),
        Row(children: [
          const Icon(Icons.toll, size: 16, color: AppColors.gold2),
          const SizedBox(width: 5),
          Expanded(
              child: Text(item.owned ? 'มีแล้ว' : '${item.price}',
                  style: AppText.body(size: 12, color: AppColors.gold2)))
        ]),
      ]));
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback? retry;
  const _Notice(this.text, {this.retry});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Text(text,
            textAlign: TextAlign.center,
            style: AppText.body(size: 12, color: AppColors.textSecondary)),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('ลองอีกครั้ง')),
      ]));
}
