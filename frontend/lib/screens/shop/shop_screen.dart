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
const _inventorySorts = {
  'newest': 'ได้รับล่าสุด',
  'rarity_desc': 'หายากมากก่อน',
  'rarity_asc': 'ทั่วไปก่อน',
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
    : 'โหลดข้อมูลไม่สำเร็จ กรุณาลองอีกครั้ง';

class ShopScreen extends ConsumerStatefulWidget {
  final bool wardrobe;
  const ShopScreen({super.key, this.wardrobe = false});
  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  final _sheet = DraggableScrollableController();
  late Future<List<ShopPage>> _catalog;
  late Future<int> _balance;
  int? _selected;
  bool _expanded = false;
  bool _saving = false;
  final Map<String, ShopItem> _changes = {};

  void _choose(ShopItem item) {
    if (_saving || item.slot == null) return;
    setState(() => _changes[item.slot!] = item);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(shopApiProvider).saveOutfit(_changes);
      if (!mounted) return;
      setState(() {
        _changes.clear();
        _reload();
      });
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(16, 0, 16, 86),
            content: Text('บันทึกการแต่งตัวแล้ว')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 86),
              content: Text(error is ApiException
                  ? error.message
                  : 'บันทึกไม่สำเร็จ กรุณาลองอีกครั้ง')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final api = ref.read(shopApiProvider);
    _catalog = Future.wait(_categories.map((c) => c.slots == null
        ? Future.value(const ShopPage([], 0))
        : widget.wardrobe
            ? api.inventory(c.slots!, limit: 8)
            : api.list(c.slots!, limit: 8)));
    _balance = widget.wardrobe ? Future.value(0) : api.balance();
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

  Future<void> _all(int index) async {
    final item = await Navigator.push<ShopItem>(
        context,
        MaterialPageRoute(
            builder: (_) => ShopCategoryScreen(
                categoryIndex: index,
                wardrobe: widget.wardrobe,
                selections: Map.of(_changes))));
    if (mounted && item != null) _choose(item);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final height = constraints.maxHeight;
          final minimum =
              ((widget.wardrobe ? 128 : 48) / height).clamp(.06, .4);
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
                  Text(widget.wardrobe ? 'แต่งตัว' : 'ร้านค้า',
                      style: AppText.heading(size: 22)),
                  const Spacer(),
                  if (!widget.wardrobe)
                    const Icon(Icons.toll, color: AppColors.gold2, size: 20),
                  const SizedBox(width: 8),
                  if (!widget.wardrobe)
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
                            label: widget.wardrobe
                                ? 'ย่อหรือขยายคลังแต่งตัว'
                                : 'ย่อหรือขยายร้านค้า',
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
                      if (widget.wardrobe)
                        SliverToBoxAdapter(
                            child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 8, 24, 0),
                                child: Text('ไอเทมของคุณ • เลือกแล้วกดบันทึก',
                                    style: AppText.body(
                                        size: 12, color: _accent)))),
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
                                            : widget.wardrobe
                                                ? 'ยังไม่มีไอเทมในหมวดนี้'
                                                : 'ยังไม่มีสินค้าในหมวดนี้')
                                      else
                                        SizedBox(
                                            height: widget.wardrobe ? 172 : 194,
                                            child: ListView.separated(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount: snapshot
                                                    .data![i].items.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 12),
                                                itemBuilder: (_, j) => SizedBox(
                                                    width: 112,
                                                    child: _ItemCard(snapshot.data![i].items[j],
                                                        wardrobe:
                                                            widget.wardrobe,
                                                        selected: _changes[snapshot.data![i].items[j].slot]
                                                                    ?.id ==
                                                                snapshot
                                                                    .data![i]
                                                                    .items[j]
                                                                    .id ||
                                                            (!_changes.containsKey(snapshot.data![i].items[j].slot) &&
                                                                snapshot
                                                                    .data![i]
                                                                    .items[j]
                                                                    .equipped),
                                                        onSelect: () =>
                                                            _choose(snapshot.data![i].items[j]))))),
                                    ])),
                              const SizedBox(height: 24),
                            ]));
                          }),
                    ])),
                    if (widget.wardrobe)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                  onPressed: _saving || _changes.isEmpty
                                      ? null
                                      : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.check),
                                  label: Text(_saving
                                      ? 'กำลังบันทึก...'
                                      : 'บันทึกการแต่งตัว'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: _bg,
                                      minimumSize: const Size(0, 48))))),
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
  final bool wardrobe;
  final Map<String, ShopItem> selections;
  const ShopCategoryScreen(
      {super.key,
      required this.categoryIndex,
      this.wardrobe = false,
      this.selections = const {}});
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
    if (widget.wardrobe) _sort = 'newest';
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
          : await (widget.wardrobe
                  ? ref.read(shopApiProvider).inventory
                  : ref.read(shopApiProvider).list)(slots,
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
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: _FilterField(
                        label: 'เรียงลำดับ',
                        value: _sort,
                        options: widget.wardrobe ? _inventorySorts : _sorts,
                        onChanged: (value) {
                          setState(() => _sort = value);
                          _load();
                        })),
                const SizedBox(width: 10),
                Expanded(
                    child: _FilterField(
                        label: 'ความหายาก',
                        value: _rarity ?? 'all',
                        options: {'all': 'ทั้งหมด', ..._rarities},
                        onChanged: (value) {
                          setState(
                              () => _rarity = value == 'all' ? null : value);
                          _load();
                        })),
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
                                      (_, i) => _ItemCard(_items[i],
                                          wardrobe: widget.wardrobe,
                                          selected:
                                              widget.selections[_items[i].slot]?.id ==
                                                      _items[i].id ||
                                                  (!widget.selections.containsKey(
                                                          _items[i].slot) &&
                                                      _items[i].equipped),
                                          onSelect: () => Navigator.pop(
                                              context, _items[i])),
                                      childCount: _items.length),
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 190,
                                          mainAxisExtent: widget.wardrobe ? 218 : 250,
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
                                        ? _Notice(_categories[
                                                        widget.categoryIndex]
                                                    .slots ==
                                                null
                                            ? 'หมวดนี้ยังไม่พร้อมใช้งาน'
                                            : widget.wardrobe
                                                ? 'ไม่พบไอเทมที่คุณมีในหมวดนี้'
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
  final bool wardrobe, selected;
  final VoidCallback? onSelect;
  const _ItemCard(this.item,
      {this.wardrobe = false, this.selected = false, this.onSelect});
  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: wardrobe
          ? onSelect
          : () => showModalBottomSheet<void>(
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
                    border: Border.all(
                        color:
                            selected ? _accent : _accent.withValues(alpha: .6),
                        width: selected ? 2.5 : 1)),
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
        if (wardrobe)
          Text(selected ? '✓ เลือกอยู่' : 'เลือกสวมใส่',
              style: AppText.body(
                  size: 12,
                  color: selected ? _accent : AppColors.textSecondary)),
        if (!wardrobe)
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

class _FilterField extends StatelessWidget {
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  const _FilterField(
      {required this.label,
      required this.value,
      required this.options,
      required this.onChanged});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label, style: AppText.body(size: 12, color: _accent))),
        DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            dropdownColor: _panel,
            icon:
                const Icon(Icons.expand_more_rounded, color: _accent, size: 20),
            style: AppText.body(size: 13),
            decoration: InputDecoration(
                filled: true,
                fillColor: _panel,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF514168))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accent, width: 2))),
            selectedItemBuilder: (context) => options.values
                .map((text) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(text,
                        maxLines: 1, overflow: TextOverflow.ellipsis)))
                .toList(),
            items: options.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            }),
      ]);
}
