import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF5F7FA), // 배경색 (연한 회색)
      ),
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
  DateTime _focusedDay = DateTime.now(); // 현재 보고 있는 달
  final DateTime _today = DateTime.now(); // 실제 오늘 날짜

  // 근무 팀 계산 로직 (예시: 날짜별로 1팀, 2팀, 3팀 순환)
  String getTeam(DateTime day) {
    final difference = day.difference(DateTime(2024, 1, 1)).inDays;
    int teamIdx = (difference % 3) + 1;
    return '$teamIdx팀';
  }

  // 팀별 색상 지정
  Color getTeamColor(String team) {
    if (team == '1팀') return const Color(0xFFFFE5E5); // 연한 빨강
    if (team == '2팀') return const Color(0xFFE5F0FF); // 연한 파랑
    return const Color(0xFFFFF4E5); // 연한 주황 (3팀)
  }

  Color getTeamTextColor(String team) {
    if (team == '1팀') return Colors.redAccent;
    if (team == '2팀') return Colors.blueAccent;
    return Colors.orangeAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 헤더 (연도/월 및 이동 버튼)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('yyyy년 M월').format(_focusedDay),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 30),
                        onPressed: () => setState(
                          () => _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month - 1,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 30),
                        onPressed: () => setState(
                          () => _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month + 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 2. 달력 본체
            Expanded(
              child: TableCalendar(
                locale: 'ko_KR',
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                headerVisible: false, // 기본 헤더 숨김 (우리가 만든 것 사용)
                daysOfWeekHeight: 40,
                calendarStyle: const CalendarStyle(outsideDaysVisible: true),
                // 요일 스타일
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                  weekendStyle: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // 날짜 칸 커스텀 빌더
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) =>
                      _buildCell(day, false),
                  todayBuilder: (context, day, focusedDay) =>
                      _buildCell(day, true),
                  outsideBuilder: (context, day, focusedDay) =>
                      _buildCell(day, false, isOutside: true),
                  weekendBuilder: (context, day, focusedDay) =>
                      _buildCell(day, false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 날짜 칸을 그리는 함수
  Widget _buildCell(DateTime day, bool isToday, {bool isOutside = false}) {
    String team = getTeam(day);
    bool isSunday = day.weekday == DateTime.sunday;
    bool isSaturday = day.weekday == DateTime.saturday;

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isToday
            ? Border.all(color: Colors.redAccent, width: 2)
            : null, // 오늘 날짜 강조
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 4),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isOutside
                    ? Colors.grey.withOpacity(0.3)
                    : (isSunday
                          ? Colors.red
                          : (isSaturday ? Colors.blue : Colors.black)),
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isOutside ? Colors.transparent : getTeamColor(team),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                isOutside ? '' : team,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: getTeamTextColor(team),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
