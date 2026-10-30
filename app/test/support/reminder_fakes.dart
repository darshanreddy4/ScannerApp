import 'package:doculoom/features/reminders/data/reminder_platform.dart';
import 'package:doculoom/features/reminders/domain/reminder_plan.dart';

/// A phone whose notification permission and alarms are controlled by the test.
class FakeReminderPlatform implements ReminderPlatform {
  FakeReminderPlatform({this.access = ReminderAccess.granted, this.afterAsk});

  ReminderAccess access;

  /// What the person answers when asked; stays [access] when null.
  ReminderAccess? afterAsk;
  final scheduled = <List<Reminder>>[];
  final shown = <Reminder>[];
  var cancels = 0;
  var requests = 0;
  var settingsOpened = 0;
  var tests = 0;
  var batteryOpened = 0;
  var autostartOpened = 0;
  String makerName = '';

  @override
  Future<ReminderAccess> status() async => access;

  @override
  Future<ReminderAccess> request() async {
    requests++;
    if (afterAsk != null) access = afterAsk!;
    return access;
  }

  @override
  Future<void> schedule(List<Reminder> reminders) async => scheduled.add(reminders);

  @override
  Future<void> showNow(Reminder reminder) async => shown.add(reminder);

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> scheduleTest() async {
    tests++;
    return true;
  }

  @override
  Future<bool> openBatterySettings() async {
    batteryOpened++;
    return true;
  }

  @override
  Future<bool> openAutostartSettings() async {
    autostartOpened++;
    return true;
  }

  @override
  Future<String> maker() async => makerName;
}
