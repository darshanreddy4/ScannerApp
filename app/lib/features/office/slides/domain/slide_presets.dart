/// One slide of a starter presentation. [texts] go into the text boxes of the layout in order.
class SlideSpec {
  const SlideSpec(this.layout, this.texts);

  /// A layout type: title, obj (title and content), secHead, twoObj or titleOnly.
  final String layout;
  final List<String> texts;
}

/// A ready-made presentation to start from: a colour theme and slides with suggested headings.
class DeckPreset {
  const DeckPreset({required this.id, required this.title, required this.hint, required this.group, required this.themeId, required this.slides});
  final String id;
  final String title;
  final String hint;

  /// For the picker: 'study' or 'work'.
  final String group;
  final String themeId;
  final List<SlideSpec> slides;
}

const deckPresets = <DeckPreset>[
  DeckPreset(
    id: 'school_project',
    title: 'School project',
    hint: 'Introduction, main points, conclusion',
    group: 'study',
    themeId: 'ocean',
    slides: [
      SlideSpec('title', ['Project title', 'Your name | Class | Date']),
      SlideSpec('obj', ['What this is about', 'The question or topic\nWhy it matters\nWhat you found out']),
      SlideSpec('secHead', ['Main part', 'The facts, one idea at a time']),
      SlideSpec('twoObj', ['Two sides of the topic', 'First side\nPoint\nPoint', 'Second side\nPoint\nPoint']),
      SlideSpec('obj', ['Key facts', 'Fact with a number or example\nFact with a number or example\nFact with a number or example']),
      SlideSpec('obj', ['Conclusion', 'The answer in one sentence\nWhat you learned']),
      SlideSpec('obj', ['Sources', 'Book, article or website\nBook, article or website']),
      SlideSpec('title', ['Thank you', 'Any questions?']),
    ],
  ),
  DeckPreset(
    id: 'book_report',
    title: 'Book or topic report',
    hint: 'Summary, characters, review',
    group: 'study',
    themeId: 'classroom',
    slides: [
      SlideSpec('title', ['Title of the book or topic', 'Author or source | Your name']),
      SlideSpec('obj', ['Summary', 'Where and when it happens\nWhat happens\nHow it ends']),
      SlideSpec('twoObj', ['People and ideas', 'Main characters or ideas\nName: who they are', 'What they want\nWhat changes']),
      SlideSpec('obj', ['My favourite part', 'What it is\nWhy I liked it']),
      SlideSpec('obj', ['My opinion', 'What worked well\nWhat could be better\nRating and who should read it']),
      SlideSpec('title', ['Thank you', 'Questions and comments']),
    ],
  ),
  DeckPreset(
    id: 'study_summary',
    title: 'Study summary',
    hint: 'Revise a chapter or exam topic',
    group: 'study',
    themeId: 'forest',
    slides: [
      SlideSpec('title', ['Subject: chapter', 'Revision summary']),
      SlideSpec('obj', ['What to remember', 'Main idea\nKey words\nFormulas or dates']),
      SlideSpec('twoObj', ['Compare', 'Idea A\nWhat it means\nExample', 'Idea B\nWhat it means\nExample']),
      SlideSpec('obj', ['Practice questions', 'Question\nQuestion\nQuestion']),
      SlideSpec('obj', ['Quick recap', 'Three things to remember']),
    ],
  ),
  DeckPreset(
    id: 'business_pitch',
    title: 'Business pitch',
    hint: 'Problem, solution, plan, ask',
    group: 'work',
    themeId: 'slate',
    slides: [
      SlideSpec('title', ['Company or idea name', 'One line that says what you do']),
      SlideSpec('obj', ['The problem', 'Who has it\nHow big it is\nWhat they do today']),
      SlideSpec('obj', ['Our solution', 'What it is\nWhy it is better\nHow it works']),
      SlideSpec('twoObj', ['Market and customers', 'Who buys\nHow many\nWhy now', 'Competitors\nHow we are different']),
      SlideSpec('obj', ['Plan and numbers', 'Next 12 months\nCosts and income\nGoals']),
      SlideSpec('obj', ['The ask', 'What you need\nWhat it will be used for']),
      SlideSpec('title', ['Thank you', 'Name | Phone | Email']),
    ],
  ),
  DeckPreset(
    id: 'team_update',
    title: 'Team update',
    hint: 'Progress, risks and next steps',
    group: 'work',
    themeId: 'midnight',
    slides: [
      SlideSpec('title', ['Team update', 'Month or project | Name']),
      SlideSpec('obj', ['Agenda', 'Progress\nRisks\nNext steps']),
      SlideSpec('twoObj', ['Progress', 'Done\nItem\nItem', 'In progress\nItem\nItem']),
      SlideSpec('obj', ['Risks and help needed', 'Risk and what we do about it\nWhat we need from others']),
      SlideSpec('obj', ['Next steps', 'Action | Owner | Date\nAction | Owner | Date']),
    ],
  ),
  DeckPreset(
    id: 'quarter_review',
    title: 'Results review',
    hint: 'Goals, results and lessons',
    group: 'work',
    themeId: 'office',
    slides: [
      SlideSpec('title', ['Results review', 'Period | Team']),
      SlideSpec('obj', ['Goals', 'Goal and target\nGoal and target\nGoal and target']),
      SlideSpec('twoObj', ['Results', 'What went well\nNumber and why', 'What did not\nNumber and why']),
      SlideSpec('obj', ['What we learned', 'Lesson\nLesson']),
      SlideSpec('obj', ['Plan for next period', 'Priority one\nPriority two\nPriority three']),
    ],
  ),
  DeckPreset(
    id: 'training',
    title: 'Training or lesson',
    hint: 'Goals, steps, practice, summary',
    group: 'work',
    themeId: 'berry',
    slides: [
      SlideSpec('title', ['Lesson title', 'Trainer or teacher | Date']),
      SlideSpec('obj', ['By the end you can', 'Goal\nGoal\nGoal']),
      SlideSpec('obj', ['Step by step', 'Step one\nStep two\nStep three']),
      SlideSpec('secHead', ['Practice', 'Try it yourself']),
      SlideSpec('obj', ['Summary', 'The main points in three lines']),
    ],
  ),
];

DeckPreset? deckPresetById(String id) => deckPresets.where((p) => p.id == id).firstOrNull;
