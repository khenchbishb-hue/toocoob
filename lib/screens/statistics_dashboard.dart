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
      appBar: AppBar(
        title: const Text('Статистик'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Нэгдсэн'),
            Tab(text: 'Тоглоомоор'),
            Tab(text: 'Төрлөөр'),
            Tab(text: 'Тоглогчоор'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _printPeriodReport,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF тайлан',
          ),
          IconButton(
            onPressed: () async {
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
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Огноо сонгох',
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<StatsPeriod>(
              value: _period,
              dropdownColor: Colors.white,
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
                      child: Text(_periodLabel(p)),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(width: 12),
        ],
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

          return TabBarView(
            controller: _tabController,
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildKpiCard('Хугацаа', _rangeLabel(), Icons.schedule),
                      _buildKpiCard(
                          'Тайлан', '${sessions.length}', Icons.receipt_long),
                      _buildKpiCard('Нийт дүн', '₮$totalMoney',
                          Icons.account_balance_wallet),
                      _buildKpiCard(
                        'Хамгийн их ашиг',
                        topWin == null
                            ? '-'
                            : '${topWin.key}\n₮${topWin.value}',
                        Icons.trending_up,
                      ),
                      _buildKpiCard(
                        'Хамгийн их алдагдал',
                        topLose == null
                            ? '-'
                            : '${topLose.key}\n₮${topLose.value}',
                        Icons.trending_down,
                      ),
                      _buildKpiCard(
                        'Хамгийн идэвхтэй',
                        mostActive == null
                            ? '-'
                            : '${mostActive.key}\n${mostActive.value} тоглолт',
                        Icons.emoji_events,
                      ),
                    ],
                  ),
                ],
              ),
              ListView.builder(
                itemCount: sortedGames.length,
                itemBuilder: (context, index) {
                  final e = sortedGames[index];
                  return ListTile(
                    title: Text(e.key),
                    trailing: Text('₮${e.value}'),
                  );
                },
              ),
              ListView.builder(
                itemCount: sortedSessionCounts.length,
                itemBuilder: (context, index) {
                  final e = sortedSessionCounts[index];
                  return ListTile(
                    title: Text(e.key),
                    trailing: Text('${e.value} тоглолт'),
                  );
                },
              ),
              ListView.builder(
                itemCount: sortedPlayers.length,
                itemBuilder: (context, index) {
                  final e = sortedPlayers[index];
                  return ListTile(
                    title: Text(e.key),
                    trailing: Text('₮${e.value}'),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(value),
            ],
          ),
        ),
      ),
    );
  }
}
