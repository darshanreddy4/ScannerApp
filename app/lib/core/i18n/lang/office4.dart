/// Text of finding and retyping text in scanned PDF pages, and of scatter and percentage charts.
library;

const Map<String, String> hiOffice4 = {
  'Find text in this scan': 'इस स्कैन में टेक्स्ट खोजें',
  'English and other Latin letters': 'अंग्रेज़ी और अन्य लैटिन अक्षर',
  'Hindi, Marathi (Devanagari)': 'हिंदी, मराठी (देवनागरी)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'किसी फ़्रेम वाली पंक्ति को दोबारा लिखने के लिए उस पर टैप करें। पुरानी लिखावट पर कागज़ के रंग की परत चढ़ा दी जाती है।',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'ये अक्षर बिल्ट-इन फ़ॉन्ट में नहीं हैं, इसलिए टेक्स्ट तस्वीर के रूप में लगाया जाता है। यह वैसा ही दिखता है, पर इसे चुना या खोजा नहीं जा सकता।',
  'The text on this page could not be read.': 'इस पेज का टेक्स्ट पढ़ा नहीं जा सका।',
  'Scatter': 'स्कैटर',
  'Show each point as a share of 100%': 'हर बिंदु को 100% के हिस्से के रूप में दिखाएँ',
};

const Map<String, String> esOffice4 = {
  'Find text in this scan': 'Buscar texto en este escaneo',
  'English and other Latin letters': 'Inglés y otras letras latinas',
  'Hindi, Marathi (Devanagari)': 'Hindi, maratí (devanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Toca una línea enmarcada para reescribirla. La escritura anterior se tapa con el color del papel.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Estas letras no están en las fuentes integradas, así que el texto se coloca como imagen. Se ve igual, pero no se puede seleccionar ni buscar.',
  'The text on this page could not be read.': 'No se pudo leer el texto de esta página.',
  'Scatter': 'Dispersión',
  'Show each point as a share of 100%': 'Mostrar cada punto como porcentaje de 100 %',
};

const Map<String, String> frOffice4 = {
  'Find text in this scan': 'Rechercher le texte de ce scan',
  'English and other Latin letters': 'Anglais et autres lettres latines',
  'Hindi, Marathi (Devanagari)': 'Hindi, marathi (dévanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Touchez une ligne encadrée pour la retaper. L\'ancienne écriture est recouverte de la couleur du papier.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Ces lettres ne figurent pas dans les polices intégrées : le texte est donc placé sous forme d\'image. Il s\'affiche pareil, mais ne peut être ni sélectionné ni recherché.',
  'The text on this page could not be read.': 'Le texte de cette page n\'a pas pu être lu.',
  'Scatter': 'Nuage de points',
  'Show each point as a share of 100%': 'Afficher chaque point en part de 100 %',
};

const Map<String, String> deOffice4 = {
  'Find text in this scan': 'Text in diesem Scan suchen',
  'English and other Latin letters': 'Englisch und andere lateinische Buchstaben',
  'Hindi, Marathi (Devanagari)': 'Hindi, Marathi (Devanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Eine umrahmte Zeile antippen, um sie neu zu schreiben. Die alte Schrift wird mit der Papierfarbe überdeckt.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Diese Buchstaben sind in den eingebauten Schriften nicht enthalten, deshalb wird der Text als Bild eingefügt. Er sieht gleich aus, kann aber nicht markiert oder durchsucht werden.',
  'The text on this page could not be read.': 'Der Text auf dieser Seite konnte nicht gelesen werden.',
  'Scatter': 'Streudiagramm',
  'Show each point as a share of 100%': 'Jeden Punkt als Anteil an 100 % zeigen',
};

const Map<String, String> ptOffice4 = {
  'Find text in this scan': 'Encontrar texto neste scan',
  'English and other Latin letters': 'Inglês e outras letras latinas',
  'Hindi, Marathi (Devanagari)': 'Hindi, marati (devanágari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Toque numa linha com moldura para reescrevê-la. A escrita antiga é coberta com a cor do papel.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Estas letras não estão nas fontes internas, por isso o texto é colocado como imagem. Parece igual, mas não pode ser selecionado nem pesquisado.',
  'The text on this page could not be read.': 'Não foi possível ler o texto desta página.',
  'Scatter': 'Dispersão',
  'Show each point as a share of 100%': 'Mostrar cada ponto como parte de 100%',
};

const Map<String, String> arOffice4 = {
  'Find text in this scan': 'البحث عن النص في هذا المسح',
  'English and other Latin letters': 'الإنجليزية وغيرها من الحروف اللاتينية',
  'Hindi, Marathi (Devanagari)': 'الهندية والماراثية (ديفاناغاري)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'اضغط على سطر محاط بإطار لإعادة كتابته. تتم تغطية الكتابة القديمة بلون الورق.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'هذه الحروف غير موجودة في الخطوط المدمجة، لذلك يوضع النص كصورة. يبدو كما هو لكن لا يمكن تحديده أو البحث فيه.',
  'The text on this page could not be read.': 'تعذّرت قراءة النص في هذه الصفحة.',
  'Scatter': 'مبعثر',
  'Show each point as a share of 100%': 'عرض كل نقطة كنسبة من 100%',
};

const Map<String, String> urOffice4 = {
  'Find text in this scan': 'اس سکین میں متن تلاش کریں',
  'English and other Latin letters': 'انگریزی اور دیگر لاطینی حروف',
  'Hindi, Marathi (Devanagari)': 'ہندی، مراٹھی (دیوناگری)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'دوبارہ لکھنے کے لیے فریم والی سطر پر ٹیپ کریں۔ پرانی تحریر کاغذ کے رنگ سے ڈھانپ دی جاتی ہے۔',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'یہ حروف بلٹ اِن فونٹس میں نہیں ہیں، اس لیے متن تصویر کی شکل میں لگایا جاتا ہے۔ یہ ویسا ہی نظر آتا ہے لیکن اسے منتخب یا تلاش نہیں کیا جا سکتا۔',
  'The text on this page could not be read.': 'اس صفحے کا متن پڑھا نہیں جا سکا۔',
  'Scatter': 'بکھراؤ',
  'Show each point as a share of 100%': 'ہر نقطے کو 100% کے حصے کے طور پر دکھائیں',
};

const Map<String, String> zhOffice4 = {
  'Find text in this scan': '在此扫描件中查找文字',
  'English and other Latin letters': '英语及其他拉丁字母',
  'Hindi, Marathi (Devanagari)': '印地语、马拉地语（天城文）',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.': '点按带框的行即可重新输入。原有文字会被纸张颜色覆盖。',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      '内置字体中没有这些字符，因此文字将以图片形式放置。外观相同，但无法选择或搜索。',
  'The text on this page could not be read.': '无法读取此页的文字。',
  'Scatter': '散点图',
  'Show each point as a share of 100%': '将每个点显示为 100% 中的占比',
};

const Map<String, String> jaOffice4 = {
  'Find text in this scan': 'このスキャンの文字を検出',
  'English and other Latin letters': '英語などのラテン文字',
  'Hindi, Marathi (Devanagari)': 'ヒンディー語・マラーティー語（デーヴァナーガリー）',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.': '枠で囲まれた行をタップすると書き直せます。元の文字は紙の色で覆われます。',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'これらの文字は内蔵フォントにないため、文字は画像として配置されます。見た目は同じですが、選択や検索はできません。',
  'The text on this page could not be read.': 'このページの文字を読み取れませんでした。',
  'Scatter': '散布図',
  'Show each point as a share of 100%': '各点を100%に対する割合で表示',
};

const Map<String, String> knOffice4 = {
  'Find text in this scan': 'ಈ ಸ್ಕ್ಯಾನ್‌ನಲ್ಲಿ ಪಠ್ಯವನ್ನು ಹುಡುಕಿ',
  'English and other Latin letters': 'ಇಂಗ್ಲಿಷ್ ಮತ್ತು ಇತರ ಲ್ಯಾಟಿನ್ ಅಕ್ಷರಗಳು',
  'Hindi, Marathi (Devanagari)': 'ಹಿಂದಿ, ಮರಾಠಿ (ದೇವನಾಗರಿ)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'ಮತ್ತೆ ಬರೆಯಲು ಚೌಕಟ್ಟಿನ ಸಾಲನ್ನು ಟ್ಯಾಪ್ ಮಾಡಿ. ಹಳೆಯ ಬರಹವನ್ನು ಕಾಗದದ ಬಣ್ಣದಿಂದ ಮುಚ್ಚಲಾಗುತ್ತದೆ.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'ಈ ಅಕ್ಷರಗಳು ಅಂತರ್ನಿರ್ಮಿತ ಫಾಂಟ್‌ಗಳಲ್ಲಿ ಇಲ್ಲ, ಆದ್ದರಿಂದ ಪಠ್ಯವನ್ನು ಚಿತ್ರವಾಗಿ ಇಡಲಾಗುತ್ತದೆ. ಅದು ಒಂದೇ ರೀತಿ ಕಾಣುತ್ತದೆ ಆದರೆ ಆಯ್ಕೆ ಮಾಡಲು ಅಥವಾ ಹುಡುಕಲು ಸಾಧ್ಯವಿಲ್ಲ.',
  'The text on this page could not be read.': 'ಈ ಪುಟದ ಪಠ್ಯವನ್ನು ಓದಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.',
  'Scatter': 'ಚದುರಿದ ಚಾರ್ಟ್',
  'Show each point as a share of 100%': 'ಪ್ರತಿ ಬಿಂದುವನ್ನು 100% ರ ಪಾಲಾಗಿ ತೋರಿಸಿ',
};

const Map<String, String> mrOffice4 = {
  'Find text in this scan': 'या स्कॅनमधील मजकूर शोधा',
  'English and other Latin letters': 'इंग्रजी आणि इतर लॅटिन अक्षरे',
  'Hindi, Marathi (Devanagari)': 'हिंदी, मराठी (देवनागरी)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'पुन्हा लिहिण्यासाठी चौकटीतील ओळीवर टॅप करा. जुने लेखन कागदाच्या रंगाने झाकले जाते.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'ही अक्षरे अंगभूत फॉन्टमध्ये नाहीत, म्हणून मजकूर चित्र म्हणून ठेवला जातो. तो सारखाच दिसतो पण निवडता किंवा शोधता येत नाही.',
  'The text on this page could not be read.': 'या पानावरील मजकूर वाचता आला नाही.',
  'Scatter': 'विखुरलेला आलेख',
  'Show each point as a share of 100%': 'प्रत्येक बिंदू 100% चा हिस्सा म्हणून दाखवा',
};

const Map<String, String> itOffice4 = {
  'Find text in this scan': 'Trova il testo in questa scansione',
  'English and other Latin letters': 'Inglese e altre lettere latine',
  'Hindi, Marathi (Devanagari)': 'Hindi, marathi (devanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Tocca una riga incorniciata per riscriverla. La scrittura originale viene coperta con il colore della carta.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Queste lettere non sono nei caratteri integrati, quindi il testo viene inserito come immagine. Ha lo stesso aspetto ma non può essere selezionato né cercato.',
  'The text on this page could not be read.': 'Impossibile leggere il testo di questa pagina.',
  'Scatter': 'Dispersione',
  'Show each point as a share of 100%': 'Mostra ogni punto come quota del 100%',
};

const Map<String, String> nlOffice4 = {
  'Find text in this scan': 'Tekst in deze scan zoeken',
  'English and other Latin letters': 'Engels en andere Latijnse letters',
  'Hindi, Marathi (Devanagari)': 'Hindi, Marathi (Devanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Tik op een omkaderde regel om die opnieuw te typen. De oude tekst wordt bedekt met de kleur van het papier.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Deze letters staan niet in de ingebouwde lettertypen, dus de tekst wordt als afbeelding geplaatst. Het ziet er hetzelfde uit, maar kan niet worden geselecteerd of doorzocht.',
  'The text on this page could not be read.': 'De tekst op deze pagina kon niet worden gelezen.',
  'Scatter': 'Spreidingsdiagram',
  'Show each point as a share of 100%': 'Elk punt tonen als aandeel van 100%',
};

const Map<String, String> plOffice4 = {
  'Find text in this scan': 'Znajdź tekst w tym skanie',
  'English and other Latin letters': 'Angielski i inne litery łacińskie',
  'Hindi, Marathi (Devanagari)': 'Hindi, marathi (dewanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Dotknij linii w ramce, aby ją napisać od nowa. Stare pismo zostaje zakryte kolorem papieru.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Tych liter nie ma we wbudowanych czcionkach, więc tekst zostanie umieszczony jako obraz. Wygląda tak samo, ale nie można go zaznaczyć ani przeszukać.',
  'The text on this page could not be read.': 'Nie udało się odczytać tekstu na tej stronie.',
  'Scatter': 'Punktowy',
  'Show each point as a share of 100%': 'Pokaż każdy punkt jako udział w 100%',
};

const Map<String, String> trOffice4 = {
  'Find text in this scan': 'Bu taramada metni bul',
  'English and other Latin letters': 'İngilizce ve diğer Latin harfleri',
  'Hindi, Marathi (Devanagari)': 'Hintçe, Marathi (Devanagari)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Yeniden yazmak için çerçeveli bir satıra dokunun. Eski yazı kâğıdın rengiyle kapatılır.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Bu harfler yerleşik yazı tiplerinde yok, bu yüzden metin resim olarak yerleştirilir. Aynı görünür ama seçilemez ve aranamaz.',
  'The text on this page could not be read.': 'Bu sayfadaki metin okunamadı.',
  'Scatter': 'Dağılım',
  'Show each point as a share of 100%': 'Her noktayı 100\'ün payı olarak göster',
};

const Map<String, String> ruOffice4 = {
  'Find text in this scan': 'Найти текст в этом скане',
  'English and other Latin letters': 'Английский и другие латинские буквы',
  'Hindi, Marathi (Devanagari)': 'Хинди, маратхи (деванагари)',
  'Tap a framed line to retype it. The old writing is covered with the colour of the paper.':
      'Нажмите на строку в рамке, чтобы набрать её заново. Старый текст закрашивается цветом бумаги.',
  'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.':
      'Этих букв нет во встроенных шрифтах, поэтому текст вставляется как изображение. Выглядит так же, но его нельзя выделить или найти поиском.',
  'The text on this page could not be read.': 'Не удалось прочитать текст на этой странице.',
  'Scatter': 'Точечная',
  'Show each point as a share of 100%': 'Показывать каждую точку как долю от 100%',
};
