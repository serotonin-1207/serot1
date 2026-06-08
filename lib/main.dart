import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // 사진처럼 어두운 테마 적용
      home: const CalendarScreen(),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int _selectedTeamIndex = 0;
  final DateTime _currentMonth = DateTime(2026, 6, 1);
  final DateTime _referenceDate = DateTime(2026, 6, 7);

  String _calculateDuty(DateTime date, int teamIndex) {
    final diff = date
        .difference(
          DateTime(
            _referenceDate.year,
            _referenceDate.month,
            _referenceDate.day,
          ),
        )
        .inDays;
    final remainder = (diff % 3 + 3) % 3;
    return (remainder == teamIndex) ? '당' : '비';
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    int offset = firstDay.weekday % 7;

    return Scaffold(
      appBar: AppBar(title: const Text('6월 2026')),
      body: Column(
        children: [
          // 팀 선택 탭
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('1팀')),
              ButtonSegment(value: 1, label: Text('2팀')),
              ButtonSegment(value: 2, label: Text('3팀')),
            ],
            selected: {_selectedTeamIndex},
            onSelectionChanged: (newSelection) =>
                setState(() => _selectedTeamIndex = newSelection.first),
          ),
          const SizedBox(height: 10),
          // 요일 헤더
          Row(
            children: [
              '일',
              '월',
              '화',
              '수',
              '목',
              '금',
              '토',
            ].map((e) => Expanded(child: Center(child: Text(e)))).toList(),
          ),
          // 달력 본문
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.7,
              ),
              itemCount: lastDay.day + offset,
              itemBuilder: (context, i) {
                if (i < offset) return const SizedBox();
                final day = i - offset + 1;
                final date = DateTime(
                  _currentMonth.year,
                  _currentMonth.month,
                  day,
                );
                final status = _calculateDuty(date, _selectedTeamIndex);

                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$day',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const Spacer(),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: status == '당' ? Colors.red : Colors.white,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
