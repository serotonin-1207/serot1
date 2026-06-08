import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
    'title': title,
    'isDone': isDone,
    'priority': priority.index,
    'color': color.toARGB32(),
  };

  factory MyEvent.fromJson(Map<String, dynamic> json) => MyEvent(
    title: json['title'] ?? '',
    isDone: json['isDone'] ?? false,
    priority: EventPriority.values[json['priority'] ?? 0],
    color: Color(json['color'] ?? const Color(0xFFE5F9E5).toARGB32()),
  );
}

// ============================== 앱 + 테마 ==============================
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('setting_dark_mode') ?? false;
    if (mounted) {
      setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
    }
  }

  Future<void> _toggleTheme(bool isDark) async {
    setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setting_dark_mode', isDark);
  }

  ThemeData _lightTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    primaryColor: const Color(0xFF007AFF),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF007AFF),
      brightness: Brightness.light,
    ),
  );

  ThemeData _darkTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1C1C1E),
    primaryColor: const Color(0xFF0A84FF),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0A84FF),
      brightness: Brightness.dark,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      home: CalendarScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleTheme;
  const CalendarScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedDay;
  late final DateTime _today;

  Map<DateTime, List<MyEvent>> _events = {};
  bool _hideDoneEvents = false;

  // 계급별 단가 (2026년 엑셀 기준)
  static const List<String> _ranks = ['소방사', '소방교', '소방장', '소방위', '소방경'];
  String _myRank = '소방위';
  final Map<String, int> _otRates = {
    '소방사': 11175,
    '소방교': 12584,
    '소방장': 12934,
    '소방위': 13779,
    '소방경': 15082,
  };
  final Map<String, int> _nightRates = {
    '소방사': 3725,
    '소방교': 4195,
    '소방장': 4311,
    '소방위': 4593,
    '소방경': 5027,
  };

  // 수당 정산용
  int _myTeam = 2;
  int _statutoryOverride = 0;
  int _dayLeave = 0;
  int _nightLeave = 0;
  int _dutyLeave = 0;
  final TextEditingController _extraController = TextEditingController(
    text: '0',
  );

  // 공휴일 API
  String _holidayApiKey = '';
  final Map<int, Map<String, String>> _holidaysByYear = {};
  final Set<int> _loadingYears = {};

  String _calcOtResult = "0 원";
  String _calcNightResult = "0 원";
  String _calcTotalResult = "0 원";
  Map<String, int> _currentMonthStats = {
    "weekdays": 0,
    "holidays": 0,
    "1팀": 0,
    "2팀": 0,
    "3팀": 0,
  };

  // 테마 색상
  bool get _isDark => widget.isDarkMode;
  Color get _surface => _isDark ? const Color(0xFF2C2C2E) : Colors.white;
  Color get _cellBg => _isDark ? const Color(0xFF2C2C2E) : Colors.white;
  Color get _panelBg =>
      _isDark ? const Color(0xFF26262A) : const Color(0xFFF5F7FA);
  Color get _border =>
      _isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
  Color get _textMain => _isDark ? const Color(0xFFEDEDED) : Colors.black87;
  Color get _textSub => _isDark ? const Color(0xFF9A9A9F) : Colors.grey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _focusedDay = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  // ============================== 로딩/저장 ==============================
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _myRank = prefs.getString('my_rank') ?? '소방위';
    final otJson = prefs.getString('ot_rates');
    if (otJson != null) {
      (jsonDecode(otJson) as Map<String, dynamic>).forEach((k, v) {
        if (_otRates.containsKey(k)) {
          _otRates[k] = (v as num).toInt();
        }
      });
    }
    final nightJson = prefs.getString('night_rates');
    if (nightJson != null) {
      (jsonDecode(nightJson) as Map<String, dynamic>).forEach((k, v) {
        if (_nightRates.containsKey(k)) {
          _nightRates[k] = (v as num).toInt();
        }
      });
    }
    _holidayApiKey = prefs.getString('setting_holiday_api_key') ?? '';
    _myTeam = prefs.getInt('setting_my_team') ?? 2;
    _statutoryOverride = prefs.getInt('setting_statutory') ?? 0;
    _dayLeave = prefs.getInt('leave_day') ?? 0;
    _nightLeave = prefs.getInt('leave_night') ?? 0;
    _dutyLeave = prefs.getInt('leave_duty') ?? 0;
    _extraController.text = (prefs.getInt('work_extra') ?? 0).toString();

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
      _events = loadedEvents;
    }

    _updateMonthData();
    _ensureHolidaysLoaded(_focusedDay.year);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_rank', _myRank);
    await prefs.setString('ot_rates', jsonEncode(_otRates));
    await prefs.setString('night_rates', jsonEncode(_nightRates));
    await prefs.setString('setting_holiday_api_key', _holidayApiKey);
    await prefs.setInt('setting_my_team', _myTeam);
    await prefs.setInt('setting_statutory', _statutoryOverride);
    await prefs.setInt('leave_day', _dayLeave);
    await prefs.setInt('leave_night', _nightLeave);
    await prefs.setInt('leave_duty', _dutyLeave);
    await prefs.setInt('work_extra', int.tryParse(_extraController.text) ?? 0);

    final Map<String, dynamic> tempMap = {};
    _events.forEach((key, value) {
      tempMap[key.toIso8601String()] = value.map((e) => e.toJson()).toList();
    });
    await prefs.setString('saved_user_events', jsonEncode(tempMap));
  }

  // ============================== 공휴일 API ==============================
  Future<void> _ensureHolidaysLoaded(int year, {bool force = false}) async {
    final bool notify = force;
    if (!force &&
        (_holidaysByYear.containsKey(year) || _loadingYears.contains(year))) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final cached = prefs.getString('holiday_cache_$year');
      if (cached != null) {
        try {
          final Map<String, dynamic> m = jsonDecode(cached);
          _holidaysByYear[year] = m.map((k, v) => MapEntry(k, v.toString()));
          if (mounted) {
            _updateMonthData();
          }
          return;
        } catch (_) {}
      }
    }

    if (_holidayApiKey.trim().isEmpty) {
      if (notify) {
        _snack('먼저 [달력 API]에서 인증키를 입력하세요.');
      }
      return;
    }

    _loadingYears.add(year);
    try {
      final map = await _fetchHolidaysFromApi(year);
      if (map != null) {
        _holidaysByYear[year] = map;
        await prefs.setString('holiday_cache_$year', jsonEncode(map));
        if (mounted) {
          _updateMonthData();
        }
        if (notify) {
          _snack('$year년 공휴일 ${map.length}건을 불러왔어요.');
        }
      } else if (notify) {
        _snack('공휴일 불러오기 실패 — 인증키를 확인하세요.');
      }
    } catch (_) {
      if (notify) {
        _snack('네트워크 오류 — 잠시 후 다시 시도하세요.');
      }
    } finally {
      _loadingYears.remove(year);
    }
  }

  Future<Map<String, String>?> _fetchHolidaysFromApi(int year) async {
    final key = _holidayApiKey.trim();
    final uri = Uri.parse(
      'https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo'
      '?serviceKey=$key&solYear=$year&numOfRows=100&_type=json',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      return null;
    }

    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      return null;
    }
    final items = body?['response']?['body']?['items'];
    if (items == null || items == '') {
      return {};
    }
    final itemNode = items['item'];
    if (itemNode == null) {
      return {};
    }
    final List list = itemNode is List ? itemNode : [itemNode];

    final Map<String, String> result = {};
    for (final it in list) {
      if (it == null) {
        continue;
      }
      if ((it['isHoliday'] ?? 'Y').toString() != 'Y') {
        continue;
      }
      final loc = it['locdate']?.toString() ?? '';
      if (loc.length != 8) {
        continue;
      }
      final formatted =
          '${loc.substring(0, 4)}-${loc.substring(4, 6)}-${loc.substring(6, 8)}';
      result[formatted] = (it['dateName'] ?? '공휴일').toString();
    }
    return result;
  }

  void _snack(String msg) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================== 계산 ==============================
  void _updateMonthData() {
    setState(() {
      _calculateMonthStats();
      _runOvertimeCalculator();
    });
  }

  void _calculateMonthStats() {
    int weekdays = 0;
    int holidaysCount = 0;
    Map<String, int> teamCounts = {"1팀": 0, "2팀": 0, "3팀": 0};

    DateTime firstDay = DateTime(_focusedDay.year, _focusedDay.month, 1);
    DateTime lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    for (int i = 0; i <= lastDay.day - 1; i++) {
      DateTime day = firstDay.add(Duration(days: i));
      String team = getTeam(day);
      teamCounts[team] = (teamCounts[team] ?? 0) + 1;
      bool isSunday = day.weekday == DateTime.sunday;
      bool isSaturday = day.weekday == DateTime.saturday;
      bool isHoliday = getHolidayName(day) != null;
      if (isSunday || isSaturday || isHoliday) {
        holidaysCount++;
      } else {
        weekdays++;
      }
    }

    _currentMonthStats = {
      "weekdays": weekdays,
      "holidays": holidaysCount,
      "1팀": teamCounts["1팀"] ?? 0,
      "2팀": teamCounts["2팀"] ?? 0,
      "3팀": teamCounts["3팀"] ?? 0,
    };
  }

  void _runOvertimeCalculator() {
    final int dutyCount = _currentMonthStats['$_myTeam팀'] ?? 0;
    final int statutory = _statutoryOverride > 0
        ? _statutoryOverride
        : (_currentMonthStats["weekdays"] ?? 0) * 8;
    final int extra = int.tryParse(_extraController.text) ?? 0;

    final int baseWorked = dutyCount * 24 + extra;
    final int baseNight = dutyCount * 8;

    // 연가 차감: 주간 시간외-1 / 야간 시간외-7·야간-8 / 당번 시간외-8·야간-8
    final int otCut = _dayLeave * 1 + _nightLeave * 7 + _dutyLeave * 8;
    final int nightCut = _nightLeave * 8 + _dutyLeave * 8;

    int recognizedOt = baseWorked - statutory - otCut;
    int nightHours = baseNight - nightCut;
    if (recognizedOt < 0) {
      recognizedOt = 0;
    }
    if (nightHours < 0) {
      nightHours = 0;
    }

    final int otPay = recognizedOt * (_otRates[_myRank] ?? 0);
    final int nightPay = nightHours * (_nightRates[_myRank] ?? 0);
    final int totalPay = otPay + nightPay;

    final f = NumberFormat('#,###');
    _calcOtResult = "${f.format(otPay)} 원 ($recognizedOt시간)";
    _calcNightResult = "${f.format(nightPay)} 원 ($nightHours시간)";
    _calcTotalResult = "${f.format(totalPay)} 원";
  }

  void _changeLeave(String type, int delta) {
    setState(() {
      if (type == 'day') {
        _dayLeave = (_dayLeave + delta).clamp(0, 99);
      } else if (type == 'night') {
        _nightLeave = (_nightLeave + delta).clamp(0, 99);
      } else {
        _dutyLeave = (_dutyLeave + delta).clamp(0, 99);
      }
      _runOvertimeCalculator();
    });
    _saveData();
  }

  // ============================== UI 도우미 ==============================
  String getTeam(DateTime day) {
    final baseDate = DateTime(2026, 6, 7);
    final difference = DateTime(
      day.year,
      day.month,
      day.day,
    ).difference(baseDate).inDays;
    int teamIdx = difference % 3;
    if (teamIdx < 0) {
      teamIdx += 3;
    }
    return '${teamIdx + 1}팀';
  }

  Color getTeamColor(String team) {
    if (_isDark) {
      if (team == '1팀') {
        return const Color(0xFF21372B);
      }
      if (team == '2팀') {
        return const Color(0xFF1F2E48);
      }
      return const Color(0xFF3A2F1E);
    }
    if (team == '1팀') {
      return const Color(0xFFE8F5E9);
    }
    if (team == '2팀') {
      return const Color(0xFFE5F0FF);
    }
    return const Color(0xFFFFF4E5);
  }

  Color getTeamTextColor(String team) {
    if (_isDark) {
      if (team == '1팀') {
        return const Color(0xFF7DDA94);
      }
      if (team == '2팀') {
        return const Color(0xFF6FA8FF);
      }
      return const Color(0xFFFFC078);
    }
    if (team == '1팀') {
      return Colors.green;
    }
    if (team == '2팀') {
      return Colors.blueAccent;
    }
    return Colors.orangeAccent;
  }

  String? getHolidayName(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    final apiMap = _holidaysByYear[day.year];
    if (apiMap != null && apiMap.containsKey(key)) {
      return apiMap[key];
    }
    return _fixedHolidayName(day);
  }

  String? _fixedHolidayName(DateTime day) {
    final fixedHolidays = {
      '01-01': '신정',
      '03-01': '삼일절',
      '05-01': '근로자의날',
      '05-05': '어린이날',
      '06-06': '현충일',
      '08-15': '광복절',
      '10-03': '개천절',
      '10-09': '한글날',
      '12-25': '크리스마스',
    };
    String monthDay = DateFormat('MM-dd').format(day);
    if (fixedHolidays.containsKey(monthDay)) {
      return fixedHolidays[monthDay];
    }
    if (day.year == 2026) {
      if (day.month == 2 && (day.day >= 16 && day.day <= 18)) {
        return '설날 연휴';
      }
      if (day.month == 5 && day.day == 24) {
        return '부처님오신날';
      }
      if (day.month == 9 && (day.day >= 24 && day.day <= 27)) {
        return '추석 연휴';
      }
    }
    return null;
  }

  String getPriorityStars(EventPriority priority) {
    if (priority == EventPriority.high) {
      return '★ ';
    }
    if (priority == EventPriority.critical) {
      return '★★ ';
    }
    return '';
  }

  Color _eventBg(MyEvent e) {
    if (e.isDone) {
      return _isDark ? const Color(0xFF3A3A3C) : Colors.grey[200]!;
    }
    if (_isDark) {
      return Color.alphaBlend(
        e.color.withValues(alpha: 0.22),
        const Color(0xFF2C2C2E),
      );
    }
    return e.color;
  }

  // ============================== 팝업 ==============================
  void _showRateSettingsDialog() {
    final otCtrls = {
      for (final r in _ranks)
        r: TextEditingController(text: _otRates[r].toString()),
    };
    final nightCtrls = {
      for (final r in _ranks)
        r: TextEditingController(text: _nightRates[r].toString()),
    };
    final statController = TextEditingController(
      text: _statutoryOverride.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.payments, color: Color(0xFF007AFF)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '💰 계급별 수당 단가 설정',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        '계급',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '시간외 단가',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '야간 단가',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ..._ranks.map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textMain,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: otCtrls[r],
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: '원',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: nightCtrls[r],
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: '원',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 6),
                const Text(
                  '법정(복무조례상) 근무시간 — 0이면 달력 자동(근무일×8)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: statController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixText: '시간',
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
              for (final r in _ranks) {
                _otRates[r] = int.tryParse(otCtrls[r]!.text) ?? _otRates[r]!;
                _nightRates[r] =
                    int.tryParse(nightCtrls[r]!.text) ?? _nightRates[r]!;
              }
              _statutoryOverride = int.tryParse(statController.text) ?? 0;
              _saveData();
              _updateMonthData();
              Navigator.pop(context);
            },
            child: const Text('적용 및 저장'),
          ),
        ],
      ),
    );
  }

  void _showHolidayApiDialog() {
    final apiKeyController = TextEditingController(text: _holidayApiKey);
    final bool hasKey = _holidayApiKey.trim().isNotEmpty;
    final loadedYears = _holidaysByYear.keys.toList()..sort();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.event_available, color: Color(0xFF007AFF)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '📅 달력 API (공휴일 연동)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '공공데이터포털 특일정보 인증키',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: apiKeyController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Encoding 인증키 붙여넣기',
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _panelBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '발급 방법',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '① data.go.kr 로그인\n② "한국천문연구원_특일 정보" 검색 → 활용신청\n③ 발급된 "Encoding 인증키"를 위에 붙여넣기',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    hasKey ? Icons.check_circle : Icons.info_outline,
                    size: 16,
                    color: hasKey ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasKey
                          ? '키 입력됨 · 불러온 연도: ${loadedYears.isEmpty ? "없음" : loadedYears.join(", ")}'
                          : '키 미입력 — 기본 공휴일(고정)만 표시됩니다.',
                      style: TextStyle(fontSize: 11, color: _textSub),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('저장 및 불러오기'),
            onPressed: () {
              _holidayApiKey = apiKeyController.text.trim();
              _saveData();
              Navigator.pop(context);
              _ensureHolidaysLoaded(_focusedDay.year, force: true);
            },
          ),
        ],
      ),
    );
  }

  void _showMonthPicker() {
    int y = _focusedDay.year;
    int m = _focusedDay.month;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            '이동할 연·월 선택',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: y,
                items: [
                  for (int yy = 2020; yy <= 2030; yy++)
                    DropdownMenuItem(value: yy, child: Text('$yy년')),
                ],
                onChanged: (v) => setS(() => y = v ?? y),
              ),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: m,
                items: [
                  for (int mm = 1; mm <= 12; mm++)
                    DropdownMenuItem(value: mm, child: Text('$mm월')),
                ],
                onChanged: (v) => setS(() => m = v ?? m),
              ),
            ],
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
                _focusedDay = DateTime(y, m);
                Navigator.pop(context);
                _updateMonthData();
                _ensureHolidaysLoaded(y);
              },
              child: const Text('이동'),
            ),
          ],
        ),
      ),
    );
  }

  void _goToToday() {
    _focusedDay = DateTime(_today.year, _today.month, _today.day);
    _updateMonthData();
    _ensureHolidaysLoaded(_focusedDay.year);
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
                  _saveData();
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
          List<DateTime> sortedDates = _events.keys.toList()..sort();
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Row(
                    children: [
                      Icon(Icons.assignment, color: Color(0xFF007AFF)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '📋 스마트 스케줄 보드',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle,
                    color: Color(0xFF007AFF),
                    size: 28,
                  ),
                  onPressed: () => _showAddEventDialog(
                    targetDate: _focusedDay,
                    onSaved: () => setBoardState(() {}),
                  ),
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
                      color: _isDark
                          ? const Color(0xFF3A3A3C)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '  ✔️ 완료된 항목 숨기기',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _textSub,
                          ),
                        ),
                        Switch(
                          activeThumbColor: const Color(0xFF007AFF),
                          value: _hideDoneEvents,
                          onChanged: (val) =>
                              setBoardState(() => _hideDoneEvents = val),
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
                                      color: _eventBg(event),
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
                                            _saveData();
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
                                                      ? (_isDark
                                                            ? const Color(
                                                                0xFFFF7B7B,
                                                              )
                                                            : Colors.red[800])
                                                      : _textMain),
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
                                              onPressed: () =>
                                                  _showAddEventDialog(
                                                    existingEvent: event,
                                                    onSaved: () =>
                                                        setBoardState(() {}),
                                                  ),
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
                                                  _saveData();
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
                                color: event.isDone ? Colors.grey : _textMain,
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

  // ============================== 빌드 ==============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(children: [_buildSidebar(), _buildCalendarArea()]),
      ),
    );
  }

  Widget _buildSidebar() {
    final int dutyCount = _currentMonthStats['$_myTeam팀'] ?? 0;
    final int statutory = _statutoryOverride > 0
        ? _statutoryOverride
        : (_currentMonthStats["weekdays"] ?? 0) * 8;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 18, bottom: 5),
              child: Text(
                '📊 이번 달 근무 통계',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textMain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Text(
                '평일: ${_currentMonthStats["weekdays"]}일  |  휴일: ${_currentMonthStats["holidays"]}일',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _textSub,
                ),
              ),
            ),
            _buildTeamStatRow('1팀', _currentMonthStats["1팀"] ?? 0),
            _buildTeamStatRow('2팀', _currentMonthStats["2팀"] ?? 0),
            _buildTeamStatRow('3팀', _currentMonthStats["3팀"] ?? 0),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 24),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '💰 초과근무 수당 정산',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textMain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '내 팀 선택',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _textSub,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _buildTeamSelector(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: Text(
                '이번 달 당번 $dutyCount일 · 법정 $statutory시간',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF007AFF),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '계급 선택',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _textSub,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _buildRankSelector(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '🏖️ 연가 사용 (버튼으로 횟수 입력)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _textSub,
                ),
              ),
            ),
            const SizedBox(height: 2),
            _buildLeaveCounter('주간연가', '🌞', _dayLeave, 'day'),
            _buildLeaveCounter('야간연가', '🌙', _nightLeave, 'night'),
            _buildLeaveCounter('당번연가', '📅', _dutyLeave, 'duty'),
            _buildCalcInput('추가 근무(보강·교육) 시간', _extraController),
            const SizedBox(height: 8),

            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _panelBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '예상 수당 상세 명세 ($_myRank)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _textSub,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 시간외 수당:',
                    style: TextStyle(fontSize: 11, color: _textSub),
                  ),
                  Text(
                    '  $_calcOtResult',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _textMain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• 야간 수당:',
                    style: TextStyle(fontSize: 11, color: _textSub),
                  ),
                  Text(
                    '  $_calcNightResult',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _textMain,
                    ),
                  ),
                  const Divider(),
                  const Text(
                    '이번 달 총 수당 합계',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                  Text(
                    _calcTotalResult,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [1, 2, 3].map((t) {
          final sel = _myTeam == t;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _myTeam = t;
                  _runOvertimeCalculator();
                });
                _saveData();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? getTeamColor('$t팀') : Colors.transparent,
                  border: Border.all(
                    color: sel ? getTeamTextColor('$t팀') : _border,
                    width: sel ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$t팀',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: sel ? getTeamTextColor('$t팀') : _textSub,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRankSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: _ranks.map((r) {
          final sel = _myRank == r;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _myRank = r;
                  _runOvertimeCalculator();
                });
                _saveData();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF007AFF) : Colors.transparent,
                  border: Border.all(
                    color: sel ? const Color(0xFF007AFF) : _border,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    r,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: sel ? Colors.white : _textSub,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLeaveCounter(
    String label,
    String emoji,
    int value,
    String type,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$emoji $label',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: _textMain,
              ),
            ),
          ),
          _roundBtn(Icons.remove, () => _changeLeave(type, -1)),
          Container(
            width: 46,
            alignment: Alignment.center,
            child: Text(
              '$value회',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: value > 0 ? const Color(0xFF007AFF) : _textSub,
              ),
            ),
          ),
          _roundBtn(Icons.add, () => _changeLeave(type, 1)),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(
            0xFF007AFF,
          ).withValues(alpha: _isDark ? 0.28 : 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF007AFF)),
      ),
    );
  }

  Widget _buildCalendarArea() {
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showMonthPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('yyyy년 M월').format(_focusedDay),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _textMain,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: _textSub),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: _isDark ? '라이트 모드' : '다크 모드',
                          icon: Icon(
                            _isDark ? Icons.light_mode : Icons.dark_mode,
                            size: 20,
                            color: _textSub,
                          ),
                          onPressed: () => widget.onToggleTheme(!_isDark),
                        ),
                        TextButton(
                          onPressed: _goToToday,
                          child: const Text(
                            '오늘',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _surface,
                            foregroundColor: _textSub,
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.payments, size: 16),
                          label: const Text(
                            '수당 단가 설정',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _showRateSettingsDialog,
                        ),
                        const SizedBox(width: 5),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _surface,
                            foregroundColor: const Color(0xFF007AFF),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.event_available, size: 16),
                          label: const Text(
                            '달력 API',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _showHolidayApiDialog,
                        ),
                        const SizedBox(width: 5),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _surface,
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
                          icon: Icon(
                            Icons.chevron_left,
                            size: 26,
                            color: _textSub,
                          ),
                          onPressed: () {
                            _focusedDay = DateTime(
                              _focusedDay.year,
                              _focusedDay.month - 1,
                            );
                            _updateMonthData();
                            _ensureHolidaysLoaded(_focusedDay.year);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.chevron_right,
                            size: 26,
                            color: _textSub,
                          ),
                          onPressed: () {
                            _focusedDay = DateTime(
                              _focusedDay.year,
                              _focusedDay.month + 1,
                            );
                            _updateMonthData();
                            _ensureHolidaysLoaded(_focusedDay.year);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildLegend(),
          Expanded(
            child: TableCalendar(
              locale: 'ko_KR',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              headerVisible: false,
              daysOfWeekHeight: 30,
              rowHeight: 105,
              shouldFillViewport: true,
              calendarStyle: const CalendarStyle(outsideDaysVisible: true),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: _textSub,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                weekendStyle: TextStyle(
                  color: _textSub,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
                _updateMonthData();
                _ensureHolidaysLoaded(_focusedDay.year);
              },
              onDaySelected: (selectedDay, focusedDay) =>
                  _showManageEventsDialog(selectedDay),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) => _buildCell(day),
                todayBuilder: (context, day, focusedDay) => _buildCell(day),
                outsideBuilder: (context, day, focusedDay) =>
                    _buildCell(day, isOutside: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    Widget chip(Color c, String label, {bool ring = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: ring ? Colors.transparent : c,
            borderRadius: BorderRadius.circular(3),
            border: ring
                ? Border.all(color: const Color(0xFF007AFF), width: 2)
                : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: _textSub,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          chip(getTeamColor('1팀'), '1팀'),
          chip(getTeamColor('2팀'), '2팀'),
          chip(getTeamColor('3팀'), '3팀'),
          chip(Colors.red, '공휴일'),
          chip(Colors.transparent, '오늘', ring: true),
        ],
      ),
    );
  }

  Widget _buildTeamStatRow(String teamName, int days) {
    String teamKey = teamName.startsWith('2') ? '2팀' : teamName;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: getTeamColor(teamKey),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            teamName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: getTeamTextColor(teamKey),
            ),
          ),
          Text(
            '$days일 근무',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _textMain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalcInput(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: _textSub,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 35,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 13, color: _textMain),
              onChanged: (val) {
                setState(() => _runOvertimeCalculator());
                _saveData();
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(DateTime day, {bool isOutside = false}) {
    String team = getTeam(day);
    bool isSunday = day.weekday == DateTime.sunday;
    bool isSaturday = day.weekday == DateTime.saturday;
    bool isTargetToday = isSameDay(day, _today);
    String? holidayName = getHolidayName(day);
    bool isHoliday = holidayName != null;
    final dateKey = DateTime(day.year, day.month, day.day);
    List<MyEvent> dayEvents = _events[dateKey] ?? [];

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _cellBg,
        borderRadius: BorderRadius.circular(10),
        border: isTargetToday
            ? Border.all(color: const Color(0xFF007AFF), width: 2.5)
            : Border.all(color: _border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: isTargetToday
                ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: _isDark ? 0.2 : 0.02),
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
                        ? _textSub.withValues(alpha: 0.4)
                        : (isSunday || isHoliday
                              ? Colors.red
                              : (isSaturday ? Colors.blue : _textMain)),
                  ),
                ),
                if (isHoliday && !isOutside)
                  Flexible(
                    child: Text(
                      holidayName,
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        color: _eventBg(event),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${getPriorityStars(event.priority)}${event.title}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: event.isDone
                              ? _textSub
                              : (event.priority == EventPriority.critical
                                    ? (_isDark
                                          ? const Color(0xFFFF7B7B)
                                          : Colors.red[800])
                                    : (_isDark
                                          ? const Color(0xFFAEE0B8)
                                          : Colors.green[900])),
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
