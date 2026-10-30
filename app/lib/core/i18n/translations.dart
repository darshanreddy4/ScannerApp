import 'lang/ar.dart';
import 'lang/cvdesigns.dart';
import 'lang/sharepdf.dart';
import 'lang/coinsv2.dart';
import 'lang/taxsuite.dart';
import 'lang/reminderhelp.dart';
import 'lang/packet.dart';
import 'lang/cards.dart';
import 'lang/checklists.dart';
import 'lang/de.dart';
import 'lang/europe.dart';
import 'lang/es.dart';
import 'lang/fr.dart';
import 'lang/hi.dart';
import 'lang/it.dart';
import 'lang/ja.dart';
import 'lang/kn.dart';
import 'lang/mr.dart';
import 'lang/nl.dart';
import 'lang/pl.dart';
import 'lang/pt.dart';
import 'lang/ru.dart';
import 'lang/tr.dart';
import 'lang/stamps.dart';
import 'lang/words.dart';
import 'lang/upi.dart';
import 'lang/ur.dart';
import 'lang/zh.dart';

/// The languages the app text is translated into (English is the text in the code).
const translationLanguages = ['hi', 'es', 'fr', 'de', 'pt', 'ar', 'ur', 'zh', 'ja', 'kn', 'mr', 'it', 'nl', 'pl', 'tr', 'ru'];

/// For each language, the English text and its translation. Text that is not here is shown in English. Every language has the same
/// entries (a test checks it), and a translation keeps the {names} of the English text.
const Map<String, Map<String, String>> translations = {
  'hi': {
    ...hiTexts,
    ...hiWords,
    ...hiStamps,
    ...hiCards,
    ...hiLists,
    ...hiPacket,
    ...hiCvDesigns,
    ...hiSharePdf,
    ...hiCoinsV2,
    ...hiTaxSuite,
    ...hiReminderHelp,
    ...hiUpi,
  },
  'es': {
    ...esTexts,
    ...esEurope,
    ...esWords,
    ...esStamps,
    ...esCards,
    ...esLists,
    ...esPacket,
    ...esCvDesigns,
    ...esSharePdf,
    ...esCoinsV2,
    ...esTaxSuite,
    ...esReminderHelp,
  },
  'fr': {
    ...frTexts,
    ...frEurope,
    ...frWords,
    ...frStamps,
    ...frCards,
    ...frLists,
    ...frPacket,
    ...frCvDesigns,
    ...frSharePdf,
    ...frCoinsV2,
    ...frTaxSuite,
    ...frReminderHelp,
  },
  'de': {
    ...deTexts,
    ...deEurope,
    ...deWords,
    ...deStamps,
    ...deCards,
    ...deLists,
    ...dePacket,
    ...deCvDesigns,
    ...deSharePdf,
    ...deCoinsV2,
    ...deTaxSuite,
    ...deReminderHelp,
  },
  'pt': {
    ...ptTexts,
    ...ptEurope,
    ...ptWords,
    ...ptStamps,
    ...ptCards,
    ...ptLists,
    ...ptPacket,
    ...ptCvDesigns,
    ...ptSharePdf,
    ...ptCoinsV2,
    ...ptTaxSuite,
    ...ptReminderHelp,
  },
  'ar': {
    ...arTexts,
    ...arWords,
    ...arStamps,
    ...arCards,
    ...arLists,
    ...arPacket,
    ...arCvDesigns,
    ...arSharePdf,
    ...arCoinsV2,
    ...arTaxSuite,
    ...arReminderHelp,
  },
  'ur': urTexts,
  'zh': zhTexts,
  'ja': jaTexts,
  'kn': {...knTexts, ...knUpi},
  'mr': {...mrTexts, ...mrUpi},
  'it': {
    ...itTexts,
    ...itEurope,
    ...itWords,
    ...itStamps,
    ...itCards,
    ...itLists,
    ...itPacket,
    ...itCvDesigns,
    ...itSharePdf,
    ...itCoinsV2,
    ...itTaxSuite,
    ...itReminderHelp,
  },
  'nl': {
    ...nlTexts,
    ...nlEurope,
    ...nlWords,
    ...nlStamps,
    ...nlCards,
    ...nlLists,
    ...nlPacket,
    ...nlCvDesigns,
    ...nlSharePdf,
    ...nlCoinsV2,
    ...nlTaxSuite,
    ...nlReminderHelp,
  },
  'pl': {
    ...plTexts,
    ...plEurope,
    ...plWords,
    ...plStamps,
    ...plCards,
    ...plLists,
    ...plPacket,
    ...plCvDesigns,
    ...plSharePdf,
    ...plCoinsV2,
    ...plTaxSuite,
    ...plReminderHelp,
  },
  'tr': {
    ...trTexts,
    ...trEurope,
    ...trWords,
    ...trStamps,
    ...trCards,
    ...trLists,
    ...trPacket,
    ...trCvDesigns,
    ...trSharePdf,
    ...trCoinsV2,
    ...trTaxSuite,
    ...trReminderHelp,
  },
  'ru': {
    ...ruTexts,
    ...ruEurope,
    ...ruWords,
    ...ruStamps,
    ...ruCards,
    ...ruLists,
    ...ruPacket,
    ...ruCvDesigns,
    ...ruSharePdf,
    ...ruCoinsV2,
    ...ruTaxSuite,
    ...ruReminderHelp,
  },
};
