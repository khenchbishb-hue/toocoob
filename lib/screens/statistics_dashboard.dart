import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/statistics_repository.dart';

class StatisticsDashboardPage extends StatefulWidget {
  const StatisticsDashboardPage({super.key});

  @override
  State<StatisticsDashboardPage> createState() =>
      _StatisticsDashboardPageState();
}

class _StatisticsDashboardPageState extends State<StatisticsDashboardPage>
    with SingleTickerProviderStateMixin {
  final StatsRepository _repository = StatsRepository();
  late final TabController _tabController;
  StatsPeriod _period = StatsPeriod.month;
  DateTime _anchor = DateTime.now();
  static const Color _bg = Color(0xFF061225);
  static const Color _panel = Color(0xFF0D1F3A);
  static const Color _panelSoft = Color(0xFF122A4A);
  static const Color _textPrimary = Color(0xFFEAF2FF);
  static const Color _textMuted = Color(0xFF9DB2D4);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _periodLabel(StatsPeriod period) {
    switch (period) {
      case StatsPeriod.all:
        return 'Бүх хугацаа';
      case StatsPeriod.month:
        return 'Сар';
      case StatsPeriod.quarter:
        return 'Улирал';
      case StatsPeriod.year:
        return 'Жил';
    }
  }

  Future<List<StatsSession>> _loadFiltered() async {
    final all = await _repository.loadSessions();
    return _repository.filterByPeriod(all, _period, _anchor);
  }

  String _rangeLabel() {
    if (_period == StatsPeriod.all) return 'Бүх хугацаа';
    if (_period == StatsPeriod.month) {
      return '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}';
    }
    if (_period == StatsPeriod.quarter) {
      final q = ((_anchor.month - 1) ~/ 3) + 1;
      return '${_anchor.year} Q$q';
    }
    return '${_anchor.year}';
  }

  Future<Uint8List> _buildPeriodPdfBytes(List<StatsSession> sessions) async {
    final baseFontData =
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldFontData =
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final baseFont = pw.Font.ttf(baseFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    final moneyByPlayer = _repository.aggregateMoneyByPlayer(sessions);
    final moneyByGame = _repository.aggregateMoneyByGame(sessions);
    final sessionByGame = _repository.countSessionsByGame(sessions);

    final sortedPlayers = moneyByPlayer.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedGames = moneyByGame.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topWin = sortedPlayers.isNotEmpty ? sortedPlayers.first : null;
    final topLose = sortedPlayers.isNotEmpty ? sortedPlayers.last : null;

    final playerTable = List<List<String>>.generate(sortedPlayers.length, (i) {
      final e = sortedPlayers[i];
      return ['${i + 1}', e.key, '${e.value}'];
    });

    final gameTable = List<List<String>>.generate(sortedGames.length, (i) {
      final e = sortedGames[i];
      return [
        '${i + 1}',
        e.key,
        '${e.value}',
        '${sessionByGame[e.key] ?? 0}',
      ];
    });

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        build: (context) => [
          pw.Text(
            'TOOCOOB - СТАТИСТИК ТАЙЛАН',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Хугацаа: ${_rangeLabel()}'),
          pw.Text('Тоглолтын тоо: ${sessions.length}'),
          if (topWin != null)
            pw.Text('Хамгийн их ашиг: ${topWin.key} | ₮${topWin.value}'),
          if (topLose != null)
            pw.Text('Хамгийн их алдагдал: ${topLose.key} | ₮${topLose.value}'),
          pw.SizedBox(height: 12),
          pw.Text('Тоглогчийн дүн',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'Тоглогч', 'Хураагдсан мөнгө (₮)'],
            data: playerTable,
            headerStyle: pw.TextStyle(font: boldFont),
            cellStyle: pw.TextStyle(font: baseFont),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Тоглоомын дүн',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'Тоглоом', 'Нийт мөнгө (₮)', 'Тайлангийн тоо'],
            data: gameTable,
            headerStyle: pw.TextStyle(font: boldFont),
            cellStyle: pw.TextStyle(font: baseFont),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _printPeriodReport() async {
    final sessions = await _loadFiltered();
    final bytes = await _buildPeriodPdfBytes(sessions);
    await Printing.layoutPdf(
      name: 'toocoob_statistics_${_rangeLabel()}',
      onLayout: (_) async => bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 18,
        title: const Text(
          'СТАТИСТИК ХЯНАЛТЫН САМБАР',
          style: TextStyle(
            color: _textPrimary,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        iconTheme: const IconThemeData(color: _textPrimary),
      ),
      body: FutureBuilder<List<StatsSession>>(
        future: _loadFiltered(),
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? <StatsSession>[];
          final moneyByPlayer = _repository.aggregateMoneyByPlayer(sessions);
          final moneyByGame = _repository.aggregateMoneyByGame(sessions);
          final sessionsByGame = _repository.countSessionsByGame(sessions);

          final sortedPlayers = moneyByPlayer.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final sortedGames = moneyByGame.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final sortedSessionCounts = sessionsByGame.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final topWin = sortedPlayers.isNotEmpty ? sortedPlayers.first : null;
          final topLose = sortedPlayers.isNotEmpty ? sortedPlayers.last : null;
          final totalMoney =
              sortedPlayers.fold<int>(0, (sum, e) => sum + e.value);

          final gamesPlayedByPlayer = <String, int>{};
          for (final s in sessions) {
            for (final p in s.players) {
              final key = '${p.displayName} (@${p.username})';
              gamesPlayedByPlayer[key] = (gamesPlayedByPlayer[key] ?? 0) + 1;
            }
          }
          final mostActive = gamesPlayedByPlayer.entries.isNotEmpty
              ? (gamesPlayedByPlayer.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .first
              : null;

          return Column(
            children: [
              _buildControlPanel(),
              Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x3348B3FF)),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: _textPrimary,
                  unselectedLabelColor: _textMuted,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF19C2FF), Color(0xFF5887FF)],
                    ),
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Нэгдсэн'),
                    Tab(text: 'Тоглоом'),
                    Tab(text: 'Төрөл'),
                    Tab(text: 'Тоглогч'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildKpiCard(
                                'Хугацаа', _rangeLabel(), Icons.schedule, 0),
                            _buildKpiCard('Тайлан', '${sessions.length}',
                                Icons.receipt_long, 1),
                            _buildKpiCard('Нийт дүн', '₮$totalMoney',
                                Icons.account_balance_wallet, 2),
                            _buildKpiCard(
                              'Хамгийн их ашиг',
                              topWin == null
                                  ? '-'
                                  : '${topWin.key}\n₮${topWin.value}',
                              Icons.trending_up,
                              3,
                            ),
                            _buildKpiCard(
                              'Хамгийн их алдагдал',
                              topLose == null
                                  ? '-'
                                  : '${topLose.key}\n₮${topLose.value}',
                              Icons.trending_down,
                              4,
                            ),
                            _buildKpiCard(
                              'Хамгийн идэвхтэй',
                              mostActive == null
                                  ? '-'
                                  : '${mostActive.key}\n${mostActive.value} тоглолт',
                              Icons.emoji_events,
                              5,
                            ),
                          ],
                        ),
                      ],
                    ),
                    _buildRankList(
                      entries: sortedGames,
                      valueBuilder: (e) => '₮${e.value}',
                    ),
                    _buildRankList(
                      entries: sortedSessionCounts,
                      valueBuilder: (e) => '${e.value} тоглолт',
                    ),
                    _buildRankList(
                      entries: sortedPlayers,
                      valueBuilder: (e) => '₮${e.value}',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF143C6B), Color(0xFF0D223E)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Анализ: ${_rangeLabel()}',
              style: const TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          _glassAction(
            icon: Icons.picture_as_pdf,
            tooltip: 'PDF тайлан',
            onTap: _printPeriodReport,
          ),
          const SizedBox(width: 8),
          _glassAction(
            icon: Icons.calendar_month,
            tooltip: 'Огноо сонгох',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _anchor,
                firstDate: DateTime(2020, 1, 1),
                lastDate: DateTime(2100, 12, 31),
              );
              if (picked == null) return;
              setState(() {
                _anchor = picked;
              });
            },
          ),
          const SizedBox(width: 8),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0x3AFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<StatsPeriod>(
                value: _period,
                dropdownColor: _panel,
                style: const TextStyle(color: _textPrimary),
                iconEnabledColor: _textPrimary,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _period = value;
                  });
                },
                items: StatsPeriod.values
                    .map(
                      (p) => DropdownMenuItem<StatsPeriod>(
                        value: p,
                        child: Text(
                          _periodLabel(p),
                          style: const TextStyle(color: _textPrimary),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassAction({
    required IconData icon,
    required String tooltip,
    required Future<void> Function() onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0x3AFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _textPrimary, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, int index) {
    const gradients = [
      [Color(0xFF14B8A6), Color(0xFF0D9488)],
      [Color(0xFF22C55E), Color(0xFF16A34A)],
      [Color(0xFF3B82F6), Color(0xFF2563EB)],
      [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
      [Color(0xFFF97316), Color(0xFFEA580C)],
      [Color(0xFFEC4899), Color(0xFFDB2777)],
    ];
    final gradient = gradients[index % gradients.length];

    return SizedBox(
      width: 280,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradient.first, gradient.last],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankList({
    required List<MapEntry<String, int>> entries,
    required String Function(MapEntry<String, int>) valueBuilder,
  }) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'Өгөгдөл алга байна.',
          style: TextStyle(color: _textMuted),
        ),
      );
    }

    final maxValue = entries.first.value.abs() == 0 ? 1 : entries.first.value;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final ratio = (entry.value.abs() / maxValue.abs()).clamp(0.0, 1.0);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _panelSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x2A7AB8FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index < 3
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF1E3A5F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueBuilder(entry),
                    style: const TextStyle(
                      color: Color(0xFF84CC16),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: ratio,
                  backgroundColor: const Color(0xFF10223D),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF22D3EE)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
