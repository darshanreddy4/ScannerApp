import 'docx_builder.dart';

/// A ready-made starting point for a new Word file.
class DocTemplate {
  const DocTemplate({required this.id, required this.title, required this.hint, required this.group, required this.build});
  final String id;
  final String title;
  final String hint;

  /// For the picker: 'study' or 'work'.
  final String group;
  final List<DocItem> Function() build;
}

DocPara _title(String t) => DocPara(t, style: DocStyle.title);
DocPara _h1(String t) => DocPara(t, style: DocStyle.heading1);
DocPara _h2(String t) => DocPara(t, style: DocStyle.heading2);
DocPara _p(String t) => DocPara(t);
DocPara _bullet(String t) => DocPara(t, list: DocList.bullet);
DocPara _number(String t) => DocPara(t, list: DocList.number);
DocPara _label(String label, String value) => DocPara.runs([DocRun('$label: ', bold: true), DocRun(value)]);

final docTemplates = <DocTemplate>[
  DocTemplate(
    id: 'blank',
    title: 'Blank document',
    hint: 'Start from an empty page',
    group: 'study',
    build: () => [_p('')],
  ),
  DocTemplate(
    id: 'assignment',
    title: 'Assignment',
    hint: 'Cover page, introduction, body, conclusion',
    group: 'study',
    build: () => [
      DocPara('Assignment title', style: DocStyle.title, align: 'center'),
      DocPara('', align: 'center'),
      DocPara.runs([const DocRun('Name: ', bold: true), const DocRun('[Your name]')], align: 'center'),
      DocPara.runs([const DocRun('Roll number: ', bold: true), const DocRun('[Number]')], align: 'center'),
      DocPara.runs([const DocRun('Course: ', bold: true), const DocRun('[Course and subject]')], align: 'center'),
      DocPara.runs([const DocRun('Teacher: ', bold: true), const DocRun('[Teacher name]')], align: 'center'),
      DocPara.runs([const DocRun('Date: ', bold: true), const DocRun('[Date]')], align: 'center'),
      const DocPageBreak(),
      _h1('Introduction'),
      _p('Say what the assignment is about and what question you answer.'),
      _h1('Main part'),
      _h2('First point'),
      _p('Write your explanation here. Add facts, examples and where they come from.'),
      _h2('Second point'),
      _p('Write your explanation here.'),
      _h1('Conclusion'),
      _p('Sum up the answer in a few sentences.'),
      _h1('References'),
      _number('[Book, article or website]'),
    ],
  ),
  DocTemplate(
    id: 'study_notes',
    title: 'Study notes',
    hint: 'Key points, terms and review questions',
    group: 'study',
    build: () => [
      _title('Study notes'),
      _label('Subject', '[Subject]'),
      _label('Topic', '[Topic]'),
      _label('Date', '[Date]'),
      _h1('Key points'),
      _bullet('[Point one]'),
      _bullet('[Point two]'),
      _bullet('[Point three]'),
      _h1('Terms to remember'),
      const DocTable([
        ['Term', 'Meaning'],
        ['', ''],
        ['', ''],
        ['', ''],
      ]),
      _h1('Questions to review'),
      _number('[Question]'),
      _number('[Question]'),
      _h1('Summary'),
      _p('Write the topic in three or four sentences, in your own words.'),
    ],
  ),
  DocTemplate(
    id: 'weekly_plan',
    title: 'Weekly study plan',
    hint: 'Table for the days of the week',
    group: 'study',
    build: () => [
      _title('Weekly plan'),
      _label('Week of', '[Date]'),
      const DocTable([
        ['Day', 'Morning', 'Afternoon', 'Evening'],
        ['Monday', '', '', ''],
        ['Tuesday', '', '', ''],
        ['Wednesday', '', '', ''],
        ['Thursday', '', '', ''],
        ['Friday', '', '', ''],
        ['Saturday', '', '', ''],
        ['Sunday', '', '', ''],
      ]),
      _h2('Goals for this week'),
      _bullet('[Goal]'),
      _bullet('[Goal]'),
    ],
  ),
  DocTemplate(
    id: 'report',
    title: 'Report',
    hint: 'Summary, findings and recommendations',
    group: 'work',
    build: () => [
      _title('Report title'),
      _label('Prepared by', '[Name]'),
      _label('Date', '[Date]'),
      _h1('Summary'),
      _p('Give the main result in two or three sentences.'),
      _h1('Background'),
      _p('Explain why this report was written.'),
      _h1('Findings'),
      _bullet('[Finding one]'),
      _bullet('[Finding two]'),
      _bullet('[Finding three]'),
      _h1('Recommendations'),
      _number('[What should be done]'),
      _number('[What should be done]'),
      _h1('Next steps'),
      _p('Say who does what, and by when.'),
    ],
  ),
  DocTemplate(
    id: 'meeting_minutes',
    title: 'Meeting minutes',
    hint: 'Attendees, agenda, decisions, actions',
    group: 'work',
    build: () => [
      _title('Meeting minutes'),
      const DocTable([
        ['Date', '[Date]'],
        ['Time', '[Time]'],
        ['Place', '[Place or link]'],
        ['Attendees', '[Names]'],
      ], headerRow: false),
      _h1('Agenda'),
      _number('[Topic]'),
      _number('[Topic]'),
      _h1('Decisions'),
      _bullet('[Decision]'),
      _h1('Action items'),
      const DocTable([
        ['Task', 'Owner', 'Due date'],
        ['', '', ''],
        ['', '', ''],
        ['', '', ''],
      ]),
    ],
  ),
  DocTemplate(
    id: 'formal_letter',
    title: 'Formal letter',
    hint: 'Address, date, subject and closing',
    group: 'work',
    build: () => [
      _p('[Your name]\n[Your address]\n[Phone and email]'),
      _p('[Date]'),
      _p('[Name of the person or office]\n[Address]'),
      DocPara('Subject: [What the letter is about]', bold: true),
      _p('Dear Sir or Madam,'),
      _p('Begin with the reason you are writing.'),
      _p('Add the details the reader needs, in short paragraphs.'),
      _p('Close by saying what you would like to happen next, and thank the reader.'),
      _p('Yours sincerely,'),
      _p('[Your name]'),
    ],
  ),
  DocTemplate(
    id: 'leave_application',
    title: 'Leave application',
    hint: 'For school, college or work',
    group: 'work',
    build: () => [
      _p('To,\n[Principal, teacher or manager]\n[School, college or company]'),
      _p('Date: [Date]'),
      DocPara('Subject: Application for leave', bold: true),
      _p('Respected Sir or Madam,'),
      _p('I am writing to request leave from [start date] to [end date] ([number] days) because [reason].'),
      _p('I will complete the work I miss as soon as I return. Please grant me leave for this period.'),
      _p('Thank you.'),
      _p('Yours faithfully,\n[Your name]\n[Class, roll number or job title]'),
    ],
  ),
  DocTemplate(
    id: 'resume',
    title: 'Resume',
    hint: 'One page: summary, experience, education, skills',
    group: 'work',
    build: () => [
      DocPara('[Your name]', style: DocStyle.title),
      _p('[Phone]  |  [Email]  |  [City]'),
      _h1('Summary'),
      _p('Two sentences about who you are and the job you want.'),
      _h1('Experience'),
      DocPara.runs([const DocRun('[Job title], [Company]', bold: true), const DocRun('   [Start] to [End]')]),
      _bullet('[What you did and the result]'),
      _bullet('[What you did and the result]'),
      _h1('Education'),
      DocPara.runs([const DocRun('[Degree or course], [School or college]', bold: true), const DocRun('   [Year]')]),
      _h1('Skills'),
      _bullet('[Skill]'),
      _bullet('[Skill]'),
      _bullet('[Skill]'),
    ],
  ),
];

DocTemplate? docTemplateById(String id) => docTemplates.where((t) => t.id == id).firstOrNull;
