import 'dart:convert'; // 데이터 변환을 위한 부품
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <--- 로컬 저장 부품 도입

void main() {
  initializeDateFormatting('ko_KR', null).then((_) => runApp(const MyApp()));
}

enum EventPriority { normal, high, critical }

class MyEvent {
  String title;
  bool isDone;
  EventPriority priority;
  Color color;

  MyEvent({
    required this.title,
    this.isDone = false,
    this.priority = EventPriority.normal,
    this.color = const Color(0xFFE5F9E5),
  });

  // [저장용 기능] 스케줄 객체를 핸드폰에 저장할 수 있게 글자(Map)로 변환
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'isDone': isDone,
      'priority': priority.index,
      'color': color.value,
    };
  }

  // [불러오기용 기능] 핸드폰에서 읽어온 글자를 다시 스케줄 객체로 복원
  factory MyEvent.fromJson(Map<String, dynamic> json) {
    return MyEvent(
      title: json['title'],
      isDone: json['isDone'] ?? false,
      priority: EventPriority.values[json['priority'] ?? 0],
      color: Color(json['color'] ?? const Color(0xFFE5F9E5).value),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        primaryColor: const Color(0xFF007AFF),
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
  DateTime _focusedDay = DateTime(2026, 6, 8);
  final DateTime _today = DateTime(2026, 6, 8);

  Map<DateTime, List<MyEvent>> _events = {};
  bool _hideDoneEvents = false;

  @override
  void initState() {
    super.initState();
    _loadEvents(); // <--- 앱이 켜질 때 핸드폰 내부 저장소에서 데이터 자동 복원
  }

  // [핵심 로직] 핸드폰 하드에 저장된 장부 읽어오기
  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final String? eventsString = prefs.getString('saved_user_events');

    if (eventsString != null) {
      final Map<String, dynamic> decodedMap = jsonDecode(eventsString);
      final Map<DateTime, List<MyEvent>> loadedEvents = {};

      decodedMap.forEach((key, value) {
        final date = DateTime.parse(key);
        final list = (value as List)
            .map((item) => MyEvent.fromJson(item))
            .toList();
        loadedEvents[date] = list;
      });

      setState(() {
        _events = loadedEvents;
      });
    }
  }

  // [핵심 로직] 스케줄 변동(추가/수정/삭제)이 일어날 때마다 핸드폰 하드에 강제 인쇄(저장)
  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> tempMap = {};

    _events.forEach((key, value) {
      tempMap[key.toIso8601String()] = value.map((e) => e.toJson()).toList();
    });

    await prefs.setString('saved_user_events', jsonEncode(tempMap));
  }

  String getTeam(DateTime day) {
    final baseDate = DateTime(2026, 6, 7);
    final difference = day.difference(baseDate).inDays;
    int teamIdx = difference % 3;
    if (teamIdx < 0) {
      teamIdx += 3;
    }
    return '${teamIdx + 1}팀';
  }

  Color getTeamColor(String team) {
    if (team == '1팀') return const Color(0xFFE8F5E9);
    if (team == '2팀') return const Color(0xFFE5F0FF);
    return const Color(0xFFFFF4E5);
  }

  Color getTeamTextColor(String team) {
    if (team == '1팀') return Colors.green;
    if (team == '2팀') return Colors.blueAccent;
    return Colors.orangeAccent;
  }

  String? getHolidayName(DateTime day) {
    if (day.month == 1 && day.day == 1) return '신정';
    if (day.month == 3 && day.day == 1) return '삼일절';
    if (day.month == 5 && day.day == 5) return '어린이날';
    if (day.month == 6 && day.day == 6) return '현충일';
    if (day.month == 8 && day.day == 15) return '광복절';
    if (day.month == 10 && day.day == 3) return '개천절';
    if (day.month == 10 && day.day == 9) return '한글날';
    if (day.month == 12 && day.day == 25) return '크리스마스';
    if (day.year == 2026 && day.month == 2 && (day.day >= 16 && day.day <= 18))
      return '설날 연휴';
    if (day.year == 2026 && day.month == 5 && day.day == 24) return '부처님오신날';
    if (day.year == 2026 && day.month == 9 && (day.day >= 24 && day.day <= 27))
      return '추석 연휴';
    return null;
  }

  String getPriorityStars(EventPriority priority) {
    if (priority == EventPriority.high) return '★ ';
    if (priority == EventPriority.critical) return '★★ ';
    return '';
  }

  void _showAddEventDialog({
    DateTime? targetDate,
    MyEvent? existingEvent,
    VoidCallback? onSaved,
  }) {
    DateTime selectedDate = targetDate ?? _today;
    final textController = TextEditingController(
      text: existingEvent?.title ?? '',
    );

    EventPriority selectedPriority =
        existingEvent?.priority ?? EventPriority.normal;
    Color selectedColor = existingEvent?.color ?? const Color(0xFFE5F9E5);

    final List<Color> colorOptions = [
      const Color(0xFFE5F9E5),
      const Color(0xFFE5F0FF),
      const Color(0xFFFFE5E5),
      const Color(0xFFFFF9E5),
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            existingEvent == null ? '새 스케줄 추가' : '스케줄 수정',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existingEvent == null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_today,
                        color: Color(0xFF007AFF),
                      ),
                      title: Text(
                        '날짜: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                      ),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    '중요도 설정',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('보통', style: TextStyle(fontSize: 12)),
                        selected: selectedPriority == EventPriority.normal,
                        onSelected: (val) => setDialogState(
                          () => selectedPriority = EventPriority.normal,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text(
                          '중요★',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: selectedPriority == EventPriority.high,
                        onSelected: (val) => setDialogState(
                          () => selectedPriority = EventPriority.high,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text(
                          '매우중요★★',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: selectedPriority == EventPriority.critical,
                        onSelected: (val) => setDialogState(
                          () => selectedPriority = EventPriority.critical,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    '배경 색상 선택',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: colorOptions.map((color) {
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = color),
                        child: Container(
                          width: 45,
                          height: 35,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedColor == color
                                  ? const Color(0xFF007AFF)
                                  : Colors.grey.withValues(alpha: 0.3),
                              width: selectedColor == color ? 2.5 : 1,
                            ),
                          ),
                          child: selectedColor == color
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Color(0xFF007AFF),
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: textController,
                    maxLines: 4,
                    minLines: 2,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: '스케줄 내용을 입력하세요\n(엔터로 줄바꿈 가능)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  setState(() {
                    if (existingEvent == null) {
                      final dateKey = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                      );
                      if (_events[dateKey] == null) {
                        _events[dateKey] = [];
                      }
                      _events[dateKey]!.add(
                        MyEvent(
                          title: textController.text.trim(),
                          priority: selectedPriority,
                          color: selectedColor,
                        ),
                      );
                    } else {
                      existingEvent.title = textController.text.trim();
                      existingEvent.priority = selectedPriority;
                      existingEvent.color = selectedColor;
                    }
                  });
                  _saveEvents(); // <--- [저장 연동] 데이터가 추가/수정되면 즉시 폰 저장소 갱신
                  if (onSaved != null) {
                    onSaved();
                  }
                }
                Navigator.pop(context);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              '스케줄 삭제',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text('이 스케줄을 정말로 삭제하시겠습니까?\n삭제된 데이터는 복구할 수 없습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '삭제',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showScheduleBoardDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setBoardState) {
          List<DateTime> sortedDates = _events.keys.toList();
          sortedDates.sort();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assignment, color: Color(0xFF007AFF)),
                    SizedBox(width: 6),
                    Text(
                      '📋 스마트 스케줄 보드',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle,
                    color: Color(0xFF007AFF),
                    size: 28,
                  ),
                  onPressed: () {
                    _showAddEventDialog(
                      targetDate: _focusedDay,
                      onSaved: () => setBoardState(() {}),
                    );
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 480,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    margin: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '  ✔️ 완료된 항목 숨기기',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                        Switch(
                          activeThumbColor: const Color(0xFF007AFF),
                          value: _hideDoneEvents,
                          onChanged: (val) {
                            setBoardState(() {
                              _hideDoneEvents = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: sortedDates.isEmpty
                        ? const Center(child: Text('등록된 모든 스케줄이 비어있습니다.'))
                        : ListView.builder(
                            itemCount: sortedDates.length,
                            itemBuilder: (context, dateIndex) {
                              final date = sortedDates[dateIndex];
                              final allList = _events[date] ?? [];

                              final displayList = _hideDoneEvents
                                  ? allList.where((e) => !e.isDone).toList()
                                  : allList;

                              if (displayList.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'yyyy년 MM월 dd일 (${getTeam(date)})',
                                      ).format(date),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                  ),
                                  ...List.generate(displayList.length, (
                                    evtIndex,
                                  ) {
                                    final event = displayList[evtIndex];
                                    return Card(
                                      color: event.isDone
                                          ? Colors.grey[200]
                                          : event.color,
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                        leading: Checkbox(
                                          activeColor: Colors.grey,
                                          value: event.isDone,
                                          onChanged: (val) {
                                            setState(
                                              () => event.isDone = val ?? false,
                                            );
                                            _saveEvents(); // <--- [체크 저장] 완료 체크 상태도 영구 저장
                                            setBoardState(() {});
                                          },
                                        ),
                                        title: Text(
                                          '${getPriorityStars(event.priority)}${event.title}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: event.isDone
                                                ? Colors.grey
                                                : (event.priority ==
                                                          EventPriority.critical
                                                      ? Colors.red[800]
                                                      : Colors.black87),
                                            decoration: event.isDone
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.orange,
                                                size: 18,
                                              ),
                                              onPressed: () {
                                                _showAddEventDialog(
                                                  existingEvent: event,
                                                  onSaved: () =>
                                                      setBoardState(() {}),
                                                );
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.redAccent,
                                                size: 18,
                                              ),
                                              onPressed: () async {
                                                bool confirm =
                                                    await _showDeleteConfirmDialog();
                                                if (confirm) {
                                                  setState(() {
                                                    allList.remove(event);
                                                    if (allList.isEmpty) {
                                                      _events.remove(date);
                                                    }
                                                  });
                                                  _saveEvents(); // <--- [삭제 저장] 삭제 내역 기기 저장소 갱신
                                                  setBoardState(() {});
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
                                  const Divider(),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showManageEventsDialog(DateTime day) {
    final dateKey = DateTime(day.year, day.month, day.day);
    final dayEvents = _events[dateKey] ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          '${day.day}일의 스케줄 상세 확인',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: dayEvents.isEmpty
              ? const Text('등록된 일정이 없습니다.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: dayEvents.length,
                  itemBuilder: (context, index) {
                    final event = dayEvents[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            event.isDone
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${getPriorityStars(event.priority)}${event.title}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                decoration: event.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: event.isDone
                                    ? Colors.grey
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showScheduleBoardDialog();
            },
            child: const Text(
              '편집 보드 열기',
              style: TextStyle(color: Color(0xFF007AFF)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('yyyy년 M월').format(_focusedDay),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF007AFF),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.assignment, size: 16),
                        label: const Text(
                          '스케줄 보드',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _showScheduleBoardDialog,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          size: 30,
                          color: Color(0xFF007AFF),
                        ),
                        onPressed: () => _showAddEventDialog(),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          size: 26,
                          color: Colors.black54,
                        ),
                        onPressed: () => setState(
                          () => _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month - 1,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          size: 26,
                          color: Colors.black54,
                        ),
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
            Expanded(
              child: TableCalendar(
                locale: 'ko_KR',
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                headerVisible: false,
                daysOfWeekHeight: 30,
                rowHeight: 105,
                calendarStyle: const CalendarStyle(outsideDaysVisible: true),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  weekendStyle: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                onDaySelected: (selectedDay, focusedDay) =>
                    _showManageEventsDialog(selectedDay),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) =>
                      _buildCell(day, false),
                  todayBuilder: (context, day, focusedDay) =>
                      _buildCell(day, true),
                  outsideBuilder: (context, day, focusedDay) =>
                      _buildCell(day, false, isOutside: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(DateTime day, bool isToday, {bool isOutside = false}) {
    String team = getTeam(day);
    bool isSunday = day.weekday == DateTime.sunday;
    bool isSaturday = day.weekday == DateTime.saturday;
    bool isTargetToday = day.year == 2026 && day.month == 6 && day.day == 8;

    String? holidayName = getHolidayName(day);
    bool isHoliday = holidayName != null;

    final dateKey = DateTime(day.year, day.month, day.day);
    List<MyEvent> dayEvents = _events[dateKey] ?? [];

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: isTargetToday
            ? Border.all(color: const Color(0xFF007AFF), width: 2.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: isTargetToday
                ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5, top: 4, right: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isOutside
                        ? Colors.grey.withValues(alpha: 0.3)
                        : (isSunday || isHoliday
                              ? Colors.red
                              : (isSaturday ? Colors.blue : Colors.black87)),
                  ),
                ),
                if (isHoliday && !isOutside)
                  Text(
                    holidayName,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: List.generate(dayEvents.length, (index) {
                    final event = dayEvents[index];
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: event.isDone ? Colors.grey[200] : event.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${getPriorityStars(event.priority)}${event.title}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: event.isDone
                              ? Colors.grey
                              : (event.priority == EventPriority.critical
                                    ? Colors.red[800]
                                    : Colors.green[900]),
                          decoration: event.isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isOutside ? Colors.transparent : getTeamColor(team),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                isOutside ? '' : team,
                style: TextStyle(
                  fontSize: 10,
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
