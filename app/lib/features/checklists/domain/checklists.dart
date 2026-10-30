import '../../../core/i18n/tr.dart';

/// The most lists kept, and the most steps in one list.
const maxChecklists = 30;
const maxChecklistItems = 40;
const maxChecklistTitle = 60;
const maxChecklistItemText = 120;
const maxChecklistNote = 200;

class ChecklistItem {
  const ChecklistItem({required this.id, required this.text, this.done = false, this.note = '', this.docId});

  /// Unique inside its list.
  final int id;
  final String text;
  final bool done;
  final String note;

  /// A document in the library that is the proof for this step.
  final String? docId;

  ChecklistItem copyWith({String? text, bool? done, String? note, Object? docId = _keep}) => ChecklistItem(
    id: id,
    text: text ?? this.text,
    done: done ?? this.done,
    note: note ?? this.note,
    docId: identical(docId, _keep) ? this.docId : docId as String?,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done, 'note': note, 'docId': docId};

  static ChecklistItem? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'], text = o['text'];
    if (id is! int || text is! String || text.trim().isEmpty) return null;
    return ChecklistItem(
      id: id,
      text: text,
      done: o['done'] == true,
      note: o['note'] is String ? o['note'] as String : '',
      docId: o['docId'] is String ? o['docId'] as String : null,
    );
  }
}

class Checklist {
  const Checklist({required this.id, required this.title, this.items = const [], this.due, this.createdAt = 0, this.templateId = ''});
  final String id;
  final String title;
  final List<ChecklistItem> items;

  /// The day the list should be finished by.
  final DateTime? due;

  /// Milliseconds since 1970.
  final int createdAt;

  /// The ready-made list this one started from, empty for a blank list.
  final String templateId;

  int get doneCount => items.where((i) => i.done).length;

  bool get isComplete => items.isNotEmpty && doneCount == items.length;

  double get progress => items.isEmpty ? 0 : doneCount / items.length;

  int get nextId => items.fold(0, (m, i) => i.id >= m ? i.id + 1 : m);

  Checklist copyWith({String? title, List<ChecklistItem>? items, Object? due = _keep}) => Checklist(
    id: id,
    title: title ?? this.title,
    items: items ?? this.items,
    due: identical(due, _keep) ? this.due : due as DateTime?,
    createdAt: createdAt,
    templateId: templateId,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'items': [for (final i in items) i.toJson()],
    'due': due == null ? null : _day(due!),
    'createdAt': createdAt,
    'templateId': templateId,
  };

  static Checklist? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'], title = o['title'], items = o['items'];
    if (id is! String || title is! String || title.trim().isEmpty || items is! List) return null;
    final due = o['due'];
    return Checklist(
      id: id,
      title: title,
      items: [for (final i in items) ?ChecklistItem.fromJson(i)],
      due: due is String ? DateTime.tryParse(due) : null,
      createdAt: o['createdAt'] is int ? o['createdAt'] as int : 0,
      templateId: o['templateId'] is String ? o['templateId'] as String : '',
    );
  }

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

enum DueState { none, later, soon, overdue, done }

/// Where a list stands against its day: finished, more than a week away, within a week, or past.
DueState dueStateOf(Checklist list, DateTime now) {
  if (list.isComplete) return DueState.done;
  final d = list.due;
  if (d == null) return DueState.none;
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day.isBefore(today)) return DueState.overdue;
  return day.difference(today).inDays <= 7 ? DueState.soon : DueState.later;
}

/// A step of a ready-made list; [region] limits it to one region's tool group (`india`, `usa`, `europe`, `gulf`).
class TemplateStep {
  const TemplateStep(this.text, {this.region = ''});
  final String text;
  final String region;
}

class ChecklistTemplate {
  const ChecklistTemplate(this.id, this.title, this.hint, this.steps);
  final String id;
  final String title;
  final String hint;
  final List<TemplateStep> steps;
}

const checklistTemplates = <ChecklistTemplate>[
  ChecklistTemplate('rent', 'Renting a home', 'Before you sign and when you move in', [
    TemplateStep('Read the whole rental agreement before signing'),
    TemplateStep('Get a signed copy of the agreement'),
    TemplateStep('ID and address proof of every tenant'),
    TemplateStep('Proof of income or a job letter'),
    TemplateStep('Receipt for the deposit and the first rent'),
    TemplateStep('Photos of the home on move-in day'),
    TemplateStep('Meter readings for electricity, water and gas'),
    TemplateStep("Landlord's name, phone and bank details"),
    TemplateStep('Police verification of the tenant, if your city asks for it', region: 'india'),
    TemplateStep("Renter's insurance policy", region: 'usa'),
    TemplateStep('Registration of your new address with the town hall', region: 'europe'),
    TemplateStep('Tenancy contract registration (Ejari or Ejar)', region: 'gulf'),
  ]),
  ChecklistTemplate('job', 'Starting a new job', 'Papers to give and keep', [
    TemplateStep('Signed offer letter'),
    TemplateStep('ID proof and address proof'),
    TemplateStep('Education and training certificates'),
    TemplateStep('Experience or relieving letter from your last job'),
    TemplateStep('Passport-size photos'),
    TemplateStep('Bank account details for your salary'),
    TemplateStep('Emergency contact and health insurance details'),
    TemplateStep('PAN card, Aadhaar and your old PF or UAN number', region: 'india'),
    TemplateStep('Social Security number and documents for Form I-9', region: 'usa'),
    TemplateStep('Tax ID and social insurance number', region: 'europe'),
    TemplateStep('Emirates ID or Iqama, and the work permit', region: 'gulf'),
  ]),
  ChecklistTemplate('car', 'Buying a vehicle', 'Papers to check and collect', [
    TemplateStep('Sale invoice or bill of sale'),
    TemplateStep('Registration certificate or title'),
    TemplateStep('Insurance policy in your name'),
    TemplateStep("Seller's ID and a signed transfer form"),
    TemplateStep('Inspection or emissions certificate'),
    TemplateStep('Service history and spare keys'),
    TemplateStep('Loan papers, if you financed it'),
    TemplateStep('Transfer of the registration at the transport office (RTO)', region: 'india'),
    TemplateStep('Odometer statement', region: 'usa'),
    TemplateStep('Vehicle registration papers and the roadworthiness certificate', region: 'europe'),
    TemplateStep('Ownership transfer at the traffic department', region: 'gulf'),
  ]),
  ChecklistTemplate('move', 'Moving house', 'Addresses, bills and keys', [
    TemplateStep('Tell your bank and card providers the new address'),
    TemplateStep('Update the address on your ID and licence'),
    TemplateStep('Set up mail forwarding'),
    TemplateStep('Transfer or close electricity, water, gas and internet'),
    TemplateStep('Collect school and medical records'),
    TemplateStep('Keep moving and repair receipts'),
    TemplateStep('Photograph the old home when you leave'),
    TemplateStep('Return the keys and get a handover note'),
  ]),
  ChecklistTemplate('baby', 'Welcoming a baby', 'Certificates and cover for the family', [
    TemplateStep('Hospital birth record or discharge papers'),
    TemplateStep('Apply for the birth certificate'),
    TemplateStep("Parents' ID proofs and marriage certificate"),
    TemplateStep('Add the baby to your health insurance'),
    TemplateStep('Vaccination card'),
    TemplateStep('Aadhaar enrolment for the child', region: 'india'),
    TemplateStep('Social Security number for the baby', region: 'usa'),
    TemplateStep('Child benefit application', region: 'europe'),
    TemplateStep('Residence permit for the baby', region: 'gulf'),
  ]),
  ChecklistTemplate('wedding', 'Getting married', 'Proofs, certificate and name changes', [
    TemplateStep('Birth certificates and ID proofs of both'),
    TemplateStep('Address proofs of both'),
    TemplateStep('Passport-size photos'),
    TemplateStep('Apply for the marriage certificate'),
    TemplateStep('Update the name on your ID, passport and bank, if you change it'),
    TemplateStep('Add your partner to insurance and nominee forms'),
    TemplateStep('Wedding invitation card, often accepted as proof', region: 'india'),
    TemplateStep('Marriage licence from the county clerk', region: 'usa'),
    TemplateStep('Notice of marriage at the registry office', region: 'europe'),
    TemplateStep('Premarital medical certificate, if needed', region: 'gulf'),
  ]),
  ChecklistTemplate('visa', 'Applying for a visa', 'Documents most embassies ask for', [
    TemplateStep('Passport valid for at least 6 months'),
    TemplateStep('Recent passport photos in the right size'),
    TemplateStep('Completed application form'),
    TemplateStep('Flight and hotel bookings'),
    TemplateStep('Travel insurance'),
    TemplateStep('Bank statements for the last 3 to 6 months'),
    TemplateStep('Employer letter or proof of study'),
    TemplateStep('Copies of earlier visas'),
  ]),
  ChecklistTemplate('tax', 'Filing taxes', 'Gather the proofs before you start', [
    TemplateStep('Income proof: pay slips or income statements'),
    TemplateStep('Bank interest statements'),
    TemplateStep('Investment and insurance proofs'),
    TemplateStep('Receipts for deductions'),
    TemplateStep("Last year's tax return"),
    TemplateStep('Tax number and ID'),
    TemplateStep('Bank account for the refund'),
    TemplateStep('Form 16 and Form 26AS', region: 'india'),
    TemplateStep('W-2 and 1099 forms', region: 'usa'),
    TemplateStep('Annual tax statement from your employer', region: 'europe'),
  ]),
];

/// Ready-made lists, the ones with steps for [region] first.
List<ChecklistTemplate> orderedTemplates(String region) {
  bool has(ChecklistTemplate t) => t.steps.any((s) => s.region == region);
  return [...checklistTemplates.where(has), ...checklistTemplates.where((t) => !has(t))];
}

/// A new list from [template] with the steps for everyone and for [region], in the language chosen now.
Checklist checklistFromTemplate(ChecklistTemplate template, {required String region, required String id, required DateTime now}) {
  final steps = template.steps.where((s) => s.region.isEmpty || s.region == region).toList();
  return Checklist(
    id: id,
    title: tr(template.title),
    templateId: template.id,
    createdAt: now.millisecondsSinceEpoch,
    items: [for (var i = 0; i < steps.length; i++) ChecklistItem(id: i, text: tr(steps[i].text))],
  );
}

class ChecklistProblem {
  const ChecklistProblem(this.template, [this.values = const {}]);
  final String template;
  final Map<String, Object> values;

  String get text => trf(template, values);
}

ChecklistProblem? titleProblem(String title) {
  final t = title.trim();
  if (t.isEmpty) return const ChecklistProblem('Enter a name for the list.');
  if (t.length > maxChecklistTitle) return const ChecklistProblem('The name is too long (60 characters at most).');
  return null;
}

ChecklistProblem? stepProblem(String text, {String note = ''}) {
  if (text.trim().isEmpty) return const ChecklistProblem('Write what has to be done.');
  if (text.trim().length > maxChecklistItemText) return const ChecklistProblem('The step is too long (120 characters at most).');
  if (note.trim().length > maxChecklistNote) return const ChecklistProblem('The note is too long (200 characters at most).');
  return null;
}

/// The list as plain text to send to someone: a box per step, with notes.
String checklistAsText(Checklist list) {
  final b = StringBuffer(list.title)..writeln();
  for (final i in list.items) {
    b.writeln('${i.done ? '[x]' : '[ ]'} ${i.text}');
    if (i.note.trim().isNotEmpty) b.writeln('    ${i.note.trim()}');
  }
  return b.toString().trimRight();
}
