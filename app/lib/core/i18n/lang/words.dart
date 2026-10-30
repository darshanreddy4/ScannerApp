/// Text of the amount-in-words tool. Offered in Hindi, Arabic and the European languages; in the other languages it is shown in English.
library;

const Map<String, String> hiWords = {
  'Amount in words': 'राशि शब्दों में',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'चेक, इनवॉइस या रसीद के लिए राशि शब्दों में लिखें। यह इसी फ़ोन पर तैयार होता है।',
  'In figures': 'अंकों में',
  'No currency (number only)': 'कोई मुद्रा नहीं (केवल संख्या)',
  'Add the word "Only"': 'अंत में "मात्र" शब्द जोड़ें',
  'Stops anyone from adding more words after the amount.': 'ताकि कोई राशि के बाद और शब्द न जोड़ सके।',
  'Letters': 'अक्षर',
  'Capitalised': 'पहला अक्षर बड़ा',
  'UPPERCASE': 'सभी बड़े अक्षर',
  'lowercase': 'सभी छोटे अक्षर',
  'In words': 'शब्दों में',
  'Enter an amount to see it in words.': 'राशि शब्दों में देखने के लिए राशि डालें।',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'किसी कानूनी दस्तावेज़ में इस्तेमाल करने से पहले अरबी शब्दों की जाँच किसी मातृभाषी से करवा लें।',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'सुझाव: चेक पर शब्द ठीक वैसे ही लिखें जैसे दिखाए गए हैं और उनके बाद की खाली जगह पर लकीर खींच दें।',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'राशि मान्य नहीं है। 12,345.50 जैसी संख्याएँ लिखें, अधिकतम 999,999,999,999.99।',
  'Choose a currency to write the cents, or enter a whole number.': 'पैसे/सेंट लिखने के लिए मुद्रा चुनें, या पूरी संख्या डालें।',
  'For cheques and invoices': 'चेक और इनवॉइस के लिए',
  'English (lakh and crore)': 'अंग्रेज़ी (लाख और करोड़)',
  'English (million and billion)': 'अंग्रेज़ी (मिलियन और बिलियन)',
  'Indian rupee (INR)': 'भारतीय रुपया (INR)',
  'US dollar (USD)': 'अमेरिकी डॉलर (USD)',
  'Euro (EUR)': 'यूरो (EUR)',
  'Pound sterling (GBP)': 'पाउंड स्टर्लिंग (GBP)',
  'UAE dirham (AED)': 'यूएई दिरहम (AED)',
  'Saudi riyal (SAR)': 'सऊदी रियाल (SAR)',
};

const Map<String, String> arWords = {
  'Amount in words': 'المبلغ بالحروف',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'اكتب المبلغ بالحروف للشيك أو الفاتورة أو الإيصال. يتم ذلك على هذا الهاتف.',
  'In figures': 'بالأرقام',
  'No currency (number only)': 'بدون عملة (الرقم فقط)',
  'Add the word "Only"': 'أضف كلمة "فقط"',
  'Stops anyone from adding more words after the amount.': 'يمنع إضافة كلمات بعد المبلغ.',
  'Letters': 'الأحرف',
  'Capitalised': 'أحرف كبيرة للبداية',
  'UPPERCASE': 'كل الأحرف كبيرة',
  'lowercase': 'كل الأحرف صغيرة',
  'In words': 'بالحروف',
  'Enter an amount to see it in words.': 'أدخل مبلغاً لرؤيته بالحروف.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'اطلب من متحدث أصلي مراجعة الصياغة العربية قبل استخدامها في مستند قانوني.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'نصيحة: اكتب الكلمات على الشيك كما هي تماماً، واشطب أي مساحة فارغة بعدها بخط.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.': 'المبلغ غير صالح. استخدم أرقاماً مثل 12,345.50 حتى 999,999,999,999.99.',
  'Choose a currency to write the cents, or enter a whole number.': 'اختر عملة لكتابة الكسور، أو أدخل عدداً صحيحاً.',
  'For cheques and invoices': 'للشيكات والفواتير',
  'English (lakh and crore)': 'الإنجليزية (لاخ وكرور)',
  'English (million and billion)': 'الإنجليزية (مليون ومليار)',
  'Indian rupee (INR)': 'روبية هندية (INR)',
  'US dollar (USD)': 'دولار أمريكي (USD)',
  'Euro (EUR)': 'يورو (EUR)',
  'Pound sterling (GBP)': 'جنيه إسترليني (GBP)',
  'UAE dirham (AED)': 'درهم إماراتي (AED)',
  'Saudi riyal (SAR)': 'ريال سعودي (SAR)',
};

const Map<String, String> esWords = {
  'Amount in words': 'Importe en letras',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Escribe un importe en letras para un cheque, una factura o un recibo. Se calcula en este teléfono.',
  'In figures': 'En cifras',
  'No currency (number only)': 'Sin moneda (solo el número)',
  'Add the word "Only"': 'Añadir la palabra "Solo"',
  'Stops anyone from adding more words after the amount.': 'Evita que alguien añada más palabras después del importe.',
  'Letters': 'Letras',
  'Capitalised': 'Con mayúscula inicial',
  'UPPERCASE': 'MAYÚSCULAS',
  'lowercase': 'minúsculas',
  'In words': 'En letras',
  'Enter an amount to see it in words.': 'Escribe un importe para verlo en letras.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Pide a un hablante nativo que revise el texto en árabe antes de usarlo en un documento legal.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Consejo: en un cheque, escribe las palabras tal como aparecen y tacha con una línea el espacio que quede después.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'El importe no es válido. Usa números como 12.345,50, hasta 999.999.999.999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Elige una moneda para escribir los céntimos, o escribe un número entero.',
  'For cheques and invoices': 'Para cheques y facturas',
  'English (lakh and crore)': 'Inglés (lakh y crore)',
  'English (million and billion)': 'Inglés (million y billion)',
  'Indian rupee (INR)': 'Rupia india (INR)',
  'US dollar (USD)': 'Dólar estadounidense (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Libra esterlina (GBP)',
  'UAE dirham (AED)': 'Dírham de los EAU (AED)',
  'Saudi riyal (SAR)': 'Riyal saudí (SAR)',
};

const Map<String, String> frWords = {
  'Amount in words': 'Montant en lettres',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Écrivez un montant en lettres pour un chèque, une facture ou un reçu. Il est calculé sur ce téléphone.',
  'In figures': 'En chiffres',
  'No currency (number only)': 'Sans devise (nombre seul)',
  'Add the word "Only"': 'Ajouter le mot « Seulement »',
  'Stops anyone from adding more words after the amount.': 'Empêche d\'ajouter des mots après le montant.',
  'Letters': 'Lettres',
  'Capitalised': 'Avec majuscules',
  'UPPERCASE': 'MAJUSCULES',
  'lowercase': 'minuscules',
  'In words': 'En lettres',
  'Enter an amount to see it in words.': 'Saisissez un montant pour le voir en lettres.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Faites relire le texte arabe par un locuteur natif avant de l\'utiliser dans un document juridique.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Astuce : sur un chèque, écrivez les mots tels quels et tirez un trait sur l\'espace resté libre après.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'Le montant n\'est pas valide. Utilisez des nombres comme 12 345,50, jusqu\'à 999 999 999 999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Choisissez une devise pour écrire les centimes, ou saisissez un nombre entier.',
  'For cheques and invoices': 'Pour chèques et factures',
  'English (lakh and crore)': 'Anglais (lakh et crore)',
  'English (million and billion)': 'Anglais (million et billion)',
  'Indian rupee (INR)': 'Roupie indienne (INR)',
  'US dollar (USD)': 'Dollar américain (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Livre sterling (GBP)',
  'UAE dirham (AED)': 'Dirham des EAU (AED)',
  'Saudi riyal (SAR)': 'Riyal saoudien (SAR)',
};

const Map<String, String> deWords = {
  'Amount in words': 'Betrag in Worten',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Schreiben Sie einen Betrag in Worten für einen Scheck, eine Rechnung oder einen Beleg. Er wird auf diesem Telefon berechnet.',
  'In figures': 'In Ziffern',
  'No currency (number only)': 'Keine Währung (nur die Zahl)',
  'Add the word "Only"': 'Das Wort „Nur“ hinzufügen',
  'Stops anyone from adding more words after the amount.': 'Verhindert, dass jemand nach dem Betrag weitere Wörter anfügt.',
  'Letters': 'Buchstaben',
  'Capitalised': 'Mit Großbuchstaben am Anfang',
  'UPPERCASE': 'GROSSBUCHSTABEN',
  'lowercase': 'kleinbuchstaben',
  'In words': 'In Worten',
  'Enter an amount to see it in words.': 'Geben Sie einen Betrag ein, um ihn in Worten zu sehen.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Lassen Sie den arabischen Wortlaut von einem Muttersprachler prüfen, bevor Sie ihn in einem rechtlichen Dokument verwenden.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Tipp: Schreiben Sie auf einem Scheck die Worte genau so und ziehen Sie durch den freien Platz danach einen Strich.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'Der Betrag ist ungültig. Verwenden Sie Zahlen wie 12.345,50, bis 999.999.999.999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Wählen Sie eine Währung, um die Cent zu schreiben, oder geben Sie eine ganze Zahl ein.',
  'For cheques and invoices': 'Für Schecks und Rechnungen',
  'English (lakh and crore)': 'Englisch (Lakh und Crore)',
  'English (million and billion)': 'Englisch (Million und Billion)',
  'Indian rupee (INR)': 'Indische Rupie (INR)',
  'US dollar (USD)': 'US-Dollar (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Pfund Sterling (GBP)',
  'UAE dirham (AED)': 'VAE-Dirham (AED)',
  'Saudi riyal (SAR)': 'Saudi-Riyal (SAR)',
};

const Map<String, String> ptWords = {
  'Amount in words': 'Valor por extenso',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Escreva um valor por extenso para um cheque, uma fatura ou um recibo. É feito neste telefone.',
  'In figures': 'Em algarismos',
  'No currency (number only)': 'Sem moeda (só o número)',
  'Add the word "Only"': 'Adicionar a palavra "Somente"',
  'Stops anyone from adding more words after the amount.': 'Impede que alguém acrescente mais palavras depois do valor.',
  'Letters': 'Letras',
  'Capitalised': 'Com maiúscula inicial',
  'UPPERCASE': 'MAIÚSCULAS',
  'lowercase': 'minúsculas',
  'In words': 'Por extenso',
  'Enter an amount to see it in words.': 'Digite um valor para vê-lo por extenso.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Peça a um falante nativo para rever o texto em árabe antes de o usar num documento legal.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Dica: num cheque, escreva as palavras exatamente como aparecem e risque o espaço que sobrar depois delas.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'O valor não é válido. Use números como 12.345,50, até 999.999.999.999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Escolha uma moeda para escrever os cêntimos, ou digite um número inteiro.',
  'For cheques and invoices': 'Para cheques e faturas',
  'English (lakh and crore)': 'Inglês (lakh e crore)',
  'English (million and billion)': 'Inglês (million e billion)',
  'Indian rupee (INR)': 'Rupia indiana (INR)',
  'US dollar (USD)': 'Dólar americano (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Libra esterlina (GBP)',
  'UAE dirham (AED)': 'Dirham dos EAU (AED)',
  'Saudi riyal (SAR)': 'Riyal saudita (SAR)',
};

const Map<String, String> itWords = {
  'Amount in words': 'Importo in lettere',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Scrivi un importo in lettere per un assegno, una fattura o una ricevuta. Viene elaborato su questo telefono.',
  'In figures': 'In cifre',
  'No currency (number only)': 'Nessuna valuta (solo il numero)',
  'Add the word "Only"': 'Aggiungi la parola "Soltanto"',
  'Stops anyone from adding more words after the amount.': 'Impedisce di aggiungere altre parole dopo l\'importo.',
  'Letters': 'Lettere',
  'Capitalised': 'Con iniziale maiuscola',
  'UPPERCASE': 'MAIUSCOLO',
  'lowercase': 'minuscolo',
  'In words': 'In lettere',
  'Enter an amount to see it in words.': 'Inserisci un importo per vederlo in lettere.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Fai controllare il testo arabo a un madrelingua prima di usarlo in un documento legale.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Suggerimento: su un assegno scrivi le parole esattamente come mostrate e traccia una linea sullo spazio rimasto dopo.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'L\'importo non è valido. Usa numeri come 12.345,50, fino a 999.999.999.999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Scegli una valuta per scrivere i centesimi, oppure inserisci un numero intero.',
  'For cheques and invoices': 'Per assegni e fatture',
  'English (lakh and crore)': 'Inglese (lakh e crore)',
  'English (million and billion)': 'Inglese (million e billion)',
  'Indian rupee (INR)': 'Rupia indiana (INR)',
  'US dollar (USD)': 'Dollaro statunitense (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Sterlina (GBP)',
  'UAE dirham (AED)': 'Dirham degli Emirati (AED)',
  'Saudi riyal (SAR)': 'Riyal saudita (SAR)',
};

const Map<String, String> nlWords = {
  'Amount in words': 'Bedrag in woorden',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Schrijf een bedrag in woorden voor een cheque, een factuur of een bon. Het wordt op deze telefoon berekend.',
  'In figures': 'In cijfers',
  'No currency (number only)': 'Geen valuta (alleen het getal)',
  'Add the word "Only"': 'Het woord "Alleen" toevoegen',
  'Stops anyone from adding more words after the amount.': 'Voorkomt dat iemand na het bedrag nog woorden toevoegt.',
  'Letters': 'Letters',
  'Capitalised': 'Met hoofdletter',
  'UPPERCASE': 'HOOFDLETTERS',
  'lowercase': 'kleine letters',
  'In words': 'In woorden',
  'Enter an amount to see it in words.': 'Voer een bedrag in om het in woorden te zien.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Laat de Arabische tekst door een moedertaalspreker controleren voordat je hem in een juridisch document gebruikt.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Tip: schrijf op een cheque de woorden precies zoals getoond en trek een streep door de ruimte die erna overblijft.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'Het bedrag is ongeldig. Gebruik getallen zoals 12.345,50, tot 999.999.999.999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Kies een valuta om de centen te schrijven, of voer een geheel getal in.',
  'For cheques and invoices': 'Voor cheques en facturen',
  'English (lakh and crore)': 'Engels (lakh en crore)',
  'English (million and billion)': 'Engels (million en billion)',
  'Indian rupee (INR)': 'Indiase roepie (INR)',
  'US dollar (USD)': 'Amerikaanse dollar (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Pond sterling (GBP)',
  'UAE dirham (AED)': 'VAE-dirham (AED)',
  'Saudi riyal (SAR)': 'Saoedische riyal (SAR)',
};

const Map<String, String> plWords = {
  'Amount in words': 'Kwota słownie',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Zapisz kwotę słownie na czek, fakturę lub paragon. Powstaje na tym telefonie.',
  'In figures': 'Cyframi',
  'No currency (number only)': 'Bez waluty (tylko liczba)',
  'Add the word "Only"': 'Dodaj słowo „Tylko”',
  'Stops anyone from adding more words after the amount.': 'Nie pozwala nikomu dopisać kolejnych słów po kwocie.',
  'Letters': 'Litery',
  'Capitalised': 'Wielka litera',
  'UPPERCASE': 'WIELKIE LITERY',
  'lowercase': 'małe litery',
  'In words': 'Słownie',
  'Enter an amount to see it in words.': 'Wpisz kwotę, aby zobaczyć ją słownie.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Zanim użyjesz arabskiego tekstu w dokumencie prawnym, poproś o sprawdzenie go rodzimego użytkownika języka.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Wskazówka: na czeku wpisz słowa dokładnie tak, jak je pokazano, i przekreśl wolne miejsce po nich.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'Kwota jest nieprawidłowa. Użyj liczb, np. 12 345,50, do 999 999 999 999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Wybierz walutę, aby zapisać grosze, lub wpisz liczbę całkowitą.',
  'For cheques and invoices': 'Na czeki i faktury',
  'English (lakh and crore)': 'Angielski (lakh i crore)',
  'English (million and billion)': 'Angielski (million i billion)',
  'Indian rupee (INR)': 'Rupia indyjska (INR)',
  'US dollar (USD)': 'Dolar amerykański (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'Funt szterling (GBP)',
  'UAE dirham (AED)': 'Dirham ZEA (AED)',
  'Saudi riyal (SAR)': 'Rial saudyjski (SAR)',
};

const Map<String, String> trWords = {
  'Amount in words': 'Yazıyla tutar',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Çek, fatura veya makbuz için tutarı yazıyla yazın. Bu telefonda hesaplanır.',
  'In figures': 'Rakamla',
  'No currency (number only)': 'Para birimi yok (yalnızca sayı)',
  'Add the word "Only"': 'Sonuna "Sadece" sözcüğünü ekle',
  'Stops anyone from adding more words after the amount.': 'Tutardan sonra kimsenin yeni sözcük eklemesini engeller.',
  'Letters': 'Harfler',
  'Capitalised': 'İlk harf büyük',
  'UPPERCASE': 'BÜYÜK HARF',
  'lowercase': 'küçük harf',
  'In words': 'Yazıyla',
  'Enter an amount to see it in words.': 'Tutarı yazıyla görmek için bir tutar girin.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Arapça ifadeyi yasal bir belgede kullanmadan önce ana dili Arapça olan biriyle kontrol ettirin.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'İpucu: Çekin üzerine sözcükleri gösterildiği gibi yazın ve ardından kalan boşluğu bir çizgiyle kapatın.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'Tutar geçerli değil. 12.345,50 gibi sayılar kullanın, en fazla 999.999.999.999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Kuruşları yazmak için bir para birimi seçin veya tam sayı girin.',
  'For cheques and invoices': 'Çekler ve faturalar için',
  'English (lakh and crore)': 'İngilizce (lakh ve crore)',
  'English (million and billion)': 'İngilizce (million ve billion)',
  'Indian rupee (INR)': 'Hindistan rupisi (INR)',
  'US dollar (USD)': 'ABD doları (USD)',
  'Euro (EUR)': 'Euro (EUR)',
  'Pound sterling (GBP)': 'İngiliz sterlini (GBP)',
  'UAE dirham (AED)': 'BAE dirhemi (AED)',
  'Saudi riyal (SAR)': 'Suudi riyali (SAR)',
};

const Map<String, String> ruWords = {
  'Amount in words': 'Сумма прописью',
  'Write an amount in words for a cheque, an invoice or a receipt. It is worked out on this phone.':
      'Запишите сумму прописью для чека, счёта или квитанции. Всё считается на этом телефоне.',
  'In figures': 'Цифрами',
  'No currency (number only)': 'Без валюты (только число)',
  'Add the word "Only"': 'Добавить слово «Только»',
  'Stops anyone from adding more words after the amount.': 'Не даёт дописать лишние слова после суммы.',
  'Letters': 'Буквы',
  'Capitalised': 'С заглавной буквы',
  'UPPERCASE': 'ПРОПИСНЫЕ',
  'lowercase': 'строчные',
  'In words': 'Прописью',
  'Enter an amount to see it in words.': 'Введите сумму, чтобы увидеть её прописью.',
  'Check the Arabic wording with a native speaker before you use it on a legal document.':
      'Прежде чем использовать арабский текст в юридическом документе, попросите проверить его носителя языка.',
  'Tip: on a cheque, write the words exactly as shown and draw a line through any space left after them.':
      'Совет: на чеке пишите слова точно так, как показано, а оставшееся после них место зачеркните линией.',
  'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.':
      'Сумма недействительна. Используйте числа вида 12 345,50, не более 999 999 999 999,99.',
  'Choose a currency to write the cents, or enter a whole number.': 'Выберите валюту, чтобы записать копейки/центы, или введите целое число.',
  'For cheques and invoices': 'Для чеков и счетов',
  'English (lakh and crore)': 'Английский (лакх и крор)',
  'English (million and billion)': 'Английский (миллион и миллиард)',
  'Indian rupee (INR)': 'Индийская рупия (INR)',
  'US dollar (USD)': 'Доллар США (USD)',
  'Euro (EUR)': 'Евро (EUR)',
  'Pound sterling (GBP)': 'Фунт стерлингов (GBP)',
  'UAE dirham (AED)': 'Дирхам ОАЭ (AED)',
  'Saudi riyal (SAR)': 'Саудовский риял (SAR)',
};
