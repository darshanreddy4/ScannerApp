/// Text of the reminder help screen. Offered in the languages that have the words tool; in the others it is shown in English.
library;

const Map<String, String> hiReminderHelp = {
  'Battery': 'बैटरी',
  'Battery settings': 'बैटरी सेटिंग',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Doculoom पर Force stop न करें: Android उसके अलार्म तब तक हटा देता है जब तक आप उसे दोबारा न खोलें। ज़्यादातर फ़ोन पर उसे हाल के ऐप्स से हटाना ठीक है।',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'सुनिश्चित करें कि Doculoom स्लीपिंग ऐप्स या डीप स्लीपिंग ऐप्स में नहीं है, और उसकी बैटरी खपत को Unrestricted रखें।',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Doculoom के लिए सूचनाएँ बंद हैं, इसलिए कुछ दिखाया नहीं जा सकता।',
  'Open background settings': 'बैकग्राउंड सेटिंग खोलें',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'बैटरी सेटिंग खोलें, Doculoom चुनें और Unrestricted या Do not optimise चुनें।',
  'Reminders are not available on this phone.': 'इस फ़ोन पर अनुस्मारक उपलब्ध नहीं हैं।',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'अनुस्मारक फ़ोन के अपने अलार्म सिस्टम में लगते हैं, इसलिए Doculoom बंद होने पर भी आते हैं, और रीस्टार्ट के बाद दोबारा लग जाते हैं। कुछ फ़ोन बैटरी बचाने के लिए बैकग्राउंड ऐप बंद कर देते हैं, तब अनुस्मारक देर से आ सकता है या छूट सकता है। ये कदम उसे ठीक करते हैं।',
  'Reminders not arriving?': 'अनुस्मारक नहीं आ रहे?',
  'Send a test in 2 minutes': '2 मिनट में परीक्षण भेजें',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'एक परीक्षण सूचना भेजें, Doculoom बंद करें और 2 मिनट रुकें। अगर वह आ गई, तो आपके अनुस्मारक भी आएँगे।',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Doculoom को मैन्युअल रूप से प्रबंधित पर रखें, और ऑटो-लॉन्च, सेकेंडरी लॉन्च और बैकग्राउंड में चलने की अनुमति दें।',
  'Step {n}: {title}': 'चरण {n}: {title}',
  'Test': 'परीक्षण',
  'Test set. Close Doculoom now and wait 2 minutes.': 'परीक्षण लग गया। अब Doculoom बंद करें और 2 मिनट रुकें।',
  'Test them and check the phone\'s battery settings': 'उन्हें जाँचें और फ़ोन की बैटरी सेटिंग देखें',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Doculoom के लिए Autostart चालू करें, और उसकी बैटरी सेटिंग में No restrictions चुनें।',
  '{maker} settings': '{maker} सेटिंग',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Doculoom को अपने आप शुरू होने और बैकग्राउंड में चलने दें, और बैकग्राउंड में अधिक बैटरी उपयोग की अनुमति दें।',
  'Allow Doculoom to start by itself and to run in the background.': 'Doculoom को अपने आप शुरू होने और बैकग्राउंड में चलने दें।',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Doculoom के लिए ऑटो-लॉन्च और बैकग्राउंड गतिविधि की अनुमति दें, और बैटरी सेविंग को उसे बंद न करने दें।',
};

const Map<String, String> arReminderHelp = {
  'Battery': 'البطارية',
  'Battery settings': 'إعدادات البطارية',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'لا تستخدم «إيقاف إجباري» مع Doculoom: يزيل Android منبّهاته حتى تفتحه من جديد. أما إزالته من التطبيقات الأخيرة فلا بأس بها في معظم الهواتف.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'تأكد من أن Doculoom ليس ضمن التطبيقات النائمة أو التطبيقات في السبات العميق، واضبط استهلاكه للبطارية على «غير مقيّد».',
  'Notifications are off for Doculoom, so nothing can be shown.': 'الإشعارات متوقفة لـ Doculoom، لذلك لا يمكن عرض شيء.',
  'Open background settings': 'فتح إعدادات الخلفية',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'افتح إعدادات البطارية، واختر Doculoom، ثم اختر «غير مقيّد» أو «عدم التحسين».',
  'Reminders are not available on this phone.': 'التذكيرات غير متاحة على هذا الهاتف.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'تُضبط التذكيرات في نظام المنبّهات الخاص بالهاتف، لذا تصل حتى عندما يكون Doculoom مغلقًا، وتُضبط من جديد بعد إعادة التشغيل. بعض الهواتف توفّر البطارية بإيقاف التطبيقات في الخلفية، وحينها قد يتأخر التذكير أو لا يصل. تعالج هذه الخطوات ذلك.',
  'Reminders not arriving?': 'التذكيرات لا تصل؟',
  'Send a test in 2 minutes': 'إرسال اختبار بعد دقيقتين',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'أرسل إشعار اختبار، وأغلق Doculoom، وانتظر دقيقتين. إذا وصل فستصلك تذكيراتك أيضًا.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'اضبط Doculoom على «إدارة يدوية»، واسمح بالتشغيل التلقائي والتشغيل الثانوي والعمل في الخلفية.',
  'Step {n}: {title}': 'الخطوة {n}: {title}',
  'Test': 'اختبار',
  'Test set. Close Doculoom now and wait 2 minutes.': 'تم ضبط الاختبار. أغلق Doculoom الآن وانتظر دقيقتين.',
  'Test them and check the phone\'s battery settings': 'اختبرها وتحقق من إعدادات بطارية الهاتف',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'شغّل «التشغيل التلقائي» لـ Doculoom، واختر في إعدادات بطاريته «بلا قيود».',
  '{maker} settings': 'إعدادات {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'اسمح لـ Doculoom بالبدء تلقائيًا والعمل في الخلفية، واسمح باستهلاك أعلى للطاقة في الخلفية.',
  'Allow Doculoom to start by itself and to run in the background.': 'اسمح لـ Doculoom بالبدء تلقائيًا والعمل في الخلفية.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'اسمح لـ Doculoom بالتشغيل التلقائي والنشاط في الخلفية، ولا تدع توفير البطارية يغلقه.',
};

const Map<String, String> esReminderHelp = {
  'Battery': 'Batería',
  'Battery settings': 'Ajustes de batería',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'No uses Forzar detención con Doculoom: Android quita sus alarmas hasta que lo abras de nuevo. Cerrarlo desde las apps recientes está bien en la mayoría de teléfonos.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Asegúrate de que Doculoom no esté en Apps en suspensión ni en Suspensión profunda, y pon su uso de batería en Sin restricciones.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Las notificaciones de Doculoom están desactivadas, así que no se puede mostrar nada.',
  'Open background settings': 'Abrir ajustes en segundo plano',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Abre los ajustes de batería, elige Doculoom y selecciona Sin restricciones o No optimizar.',
  'Reminders are not available on this phone.': 'Los recordatorios no están disponibles en este teléfono.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Los recordatorios se programan en el sistema de alarmas del propio teléfono, así que llegan con Doculoom cerrado y se vuelven a programar tras reiniciar. Algunos teléfonos ahorran batería deteniendo apps en segundo plano y entonces un recordatorio puede llegar tarde o no llegar. Estos pasos lo solucionan.',
  'Reminders not arriving?': '¿No llegan los recordatorios?',
  'Send a test in 2 minutes': 'Enviar una prueba en 2 minutos',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Envía una notificación de prueba, cierra Doculoom y espera 2 minutos. Si llega, tus recordatorios también llegarán.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Pon Doculoom en gestión manual y permite el inicio automático, el inicio secundario y la ejecución en segundo plano.',
  'Step {n}: {title}': 'Paso {n}: {title}',
  'Test': 'Prueba',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Prueba programada. Cierra Doculoom ahora y espera 2 minutos.',
  'Test them and check the phone\'s battery settings': 'Pruébalos y revisa los ajustes de batería del teléfono',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Activa el inicio automático de Doculoom y, en sus ajustes de batería, elige Sin restricciones.',
  '{maker} settings': 'Ajustes de {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Permite que Doculoom se inicie solo y se ejecute en segundo plano, y permite un alto consumo de energía en segundo plano.',
  'Allow Doculoom to start by itself and to run in the background.': 'Permite que Doculoom se inicie solo y se ejecute en segundo plano.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Permite el inicio automático y la actividad en segundo plano de Doculoom, y no dejes que el ahorro de batería lo cierre.',
};

const Map<String, String> frReminderHelp = {
  'Battery': 'Batterie',
  'Battery settings': 'Réglages de la batterie',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'N\'utilisez pas Forcer l\'arrêt sur Doculoom : Android supprime ses alarmes jusqu\'à sa prochaine ouverture. Le fermer depuis les applications récentes est sans risque sur la plupart des téléphones.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Vérifiez que Doculoom n\'est pas dans les applications en veille ou en veille prolongée, et réglez son utilisation de la batterie sur Sans restriction.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Les notifications de Doculoom sont désactivées, donc rien ne peut s\'afficher.',
  'Open background settings': 'Ouvrir les réglages d\'arrière-plan',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Ouvrez les réglages de la batterie, choisissez Doculoom et sélectionnez Sans restriction ou Ne pas optimiser.',
  'Reminders are not available on this phone.': 'Les rappels ne sont pas disponibles sur ce téléphone.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Les rappels sont programmés dans le système d\'alarmes du téléphone, donc ils arrivent même quand Doculoom est fermé, et ils sont reprogrammés après un redémarrage. Certains téléphones économisent la batterie en arrêtant les applications en arrière-plan, et un rappel peut alors arriver en retard ou pas du tout. Ces étapes y remédient.',
  'Reminders not arriving?': 'Les rappels n\'arrivent pas ?',
  'Send a test in 2 minutes': 'Envoyer un test dans 2 minutes',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Envoyez une notification de test, fermez Doculoom et attendez 2 minutes. Si elle arrive, vos rappels arriveront aussi.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Réglez Doculoom sur gestion manuelle et autorisez le lancement automatique, le lancement secondaire et l\'exécution en arrière-plan.',
  'Step {n}: {title}': 'Étape {n} : {title}',
  'Test': 'Test',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Test programmé. Fermez Doculoom maintenant et attendez 2 minutes.',
  'Test them and check the phone\'s battery settings': 'Testez-les et vérifiez les réglages de batterie du téléphone',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Activez le démarrage automatique de Doculoom et, dans ses réglages de batterie, choisissez Sans restriction.',
  '{maker} settings': 'Réglages {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Autorisez Doculoom à démarrer seul et à s\'exécuter en arrière-plan, et autorisez une forte consommation en arrière-plan.',
  'Allow Doculoom to start by itself and to run in the background.': 'Autorisez Doculoom à démarrer seul et à s\'exécuter en arrière-plan.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Autorisez le lancement automatique et l\'activité en arrière-plan de Doculoom, et ne laissez pas l\'économie de batterie le fermer.',
};

const Map<String, String> deReminderHelp = {
  'Battery': 'Akku',
  'Battery settings': 'Akku-Einstellungen',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Verwenden Sie bei Doculoom nicht „Beenden erzwingen“: Android entfernt dann seine Alarme, bis Sie die App wieder öffnen. Das Wegwischen aus den letzten Apps ist bei den meisten Telefonen in Ordnung.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Stellen Sie sicher, dass Doculoom nicht unter „Nicht verwendete Apps“ oder „Apps im Tiefschlaf“ steht, und setzen Sie die Akkunutzung auf „Unbegrenzt“.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Benachrichtigungen sind für Doculoom ausgeschaltet, daher kann nichts angezeigt werden.',
  'Open background settings': 'Hintergrundeinstellungen öffnen',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Öffnen Sie die Akku-Einstellungen, wählen Sie Doculoom und dann „Unbegrenzt“ oder „Nicht optimieren“.',
  'Reminders are not available on this phone.': 'Erinnerungen sind auf diesem Telefon nicht verfügbar.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Erinnerungen werden im eigenen Alarmsystem des Telefons gesetzt, kommen also auch bei geschlossenem Doculoom an und werden nach einem Neustart neu gesetzt. Manche Telefone sparen Akku, indem sie Apps im Hintergrund stoppen; dann kann eine Erinnerung zu spät kommen oder ausbleiben. Diese Schritte beheben das.',
  'Reminders not arriving?': 'Erinnerungen kommen nicht an?',
  'Send a test in 2 minutes': 'Test in 2 Minuten senden',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Senden Sie eine Testbenachrichtigung, schließen Sie Doculoom und warten Sie 2 Minuten. Kommt sie an, kommen Ihre Erinnerungen auch an.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Stellen Sie Doculoom auf manuelle Verwaltung und erlauben Sie Autostart, sekundären Start und Ausführung im Hintergrund.',
  'Step {n}: {title}': 'Schritt {n}: {title}',
  'Test': 'Test',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Test gesetzt. Schließen Sie Doculoom jetzt und warten Sie 2 Minuten.',
  'Test them and check the phone\'s battery settings': 'Testen Sie sie und prüfen Sie die Akku-Einstellungen',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Schalten Sie Autostart für Doculoom ein und wählen Sie in den Akku-Einstellungen „Keine Einschränkungen“.',
  '{maker} settings': '{maker}-Einstellungen',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Erlauben Sie Doculoom, selbst zu starten und im Hintergrund zu laufen, und erlauben Sie hohen Stromverbrauch im Hintergrund.',
  'Allow Doculoom to start by itself and to run in the background.': 'Erlauben Sie Doculoom, selbst zu starten und im Hintergrund zu laufen.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Erlauben Sie Doculoom Autostart und Hintergrundaktivität und lassen Sie es nicht vom Energiesparen schließen.',
};

const Map<String, String> ptReminderHelp = {
  'Battery': 'Bateria',
  'Battery settings': 'Definições da bateria',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Não use Forçar paragem no Doculoom: o Android remove os seus alarmes até o abrir de novo. Fechá-lo nas apps recentes não faz mal na maioria dos telemóveis.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Certifique-se de que o Doculoom não está em Apps em suspensão nem em Suspensão profunda, e defina a sua utilização da bateria como Sem restrições.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'As notificações do Doculoom estão desativadas, por isso nada pode ser mostrado.',
  'Open background settings': 'Abrir definições de segundo plano',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Abra as definições da bateria, escolha o Doculoom e selecione Sem restrições ou Não otimizar.',
  'Reminders are not available on this phone.': 'Os lembretes não estão disponíveis neste telemóvel.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Os lembretes são definidos no sistema de alarmes do próprio telemóvel, por isso chegam com o Doculoom fechado e são definidos de novo após reiniciar. Alguns telemóveis poupam bateria parando apps em segundo plano, e um lembrete pode chegar tarde ou não chegar. Estes passos resolvem isso.',
  'Reminders not arriving?': 'Os lembretes não chegam?',
  'Send a test in 2 minutes': 'Enviar um teste em 2 minutos',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Envie uma notificação de teste, feche o Doculoom e espere 2 minutos. Se chegar, os seus lembretes também chegarão.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Defina o Doculoom para gestão manual e permita o arranque automático, o arranque secundário e a execução em segundo plano.',
  'Step {n}: {title}': 'Passo {n}: {title}',
  'Test': 'Teste',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Teste definido. Feche o Doculoom agora e espere 2 minutos.',
  'Test them and check the phone\'s battery settings': 'Teste-os e verifique as definições de bateria do telemóvel',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Ative o arranque automático do Doculoom e, nas suas definições de bateria, escolha Sem restrições.',
  '{maker} settings': 'Definições {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Permita que o Doculoom arranque sozinho e seja executado em segundo plano, e permita um consumo de energia elevado em segundo plano.',
  'Allow Doculoom to start by itself and to run in the background.': 'Permita que o Doculoom arranque sozinho e seja executado em segundo plano.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Permita o arranque automático e a atividade em segundo plano do Doculoom e não deixe a poupança de bateria fechá-lo.',
};

const Map<String, String> itReminderHelp = {
  'Battery': 'Batteria',
  'Battery settings': 'Impostazioni batteria',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Non usare Arresta forzatamente su Doculoom: Android rimuove i suoi allarmi finché non lo riapri. Chiuderlo dalle app recenti va bene sulla maggior parte dei telefoni.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Assicurati che Doculoom non sia in App in stop o App in stop profondo e imposta il suo uso della batteria su Senza limitazioni.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Le notifiche di Doculoom sono disattivate, quindi non si può mostrare nulla.',
  'Open background settings': 'Apri impostazioni in background',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Apri le impostazioni della batteria, scegli Doculoom e seleziona Senza limitazioni o Non ottimizzare.',
  'Reminders are not available on this phone.': 'I promemoria non sono disponibili su questo telefono.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'I promemoria sono impostati nel sistema di allarmi del telefono, quindi arrivano anche con Doculoom chiuso e vengono reimpostati dopo un riavvio. Alcuni telefoni risparmiano batteria fermando le app in background e un promemoria può arrivare in ritardo o non arrivare. Questi passaggi lo risolvono.',
  'Reminders not arriving?': 'I promemoria non arrivano?',
  'Send a test in 2 minutes': 'Invia un test tra 2 minuti',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Invia una notifica di prova, chiudi Doculoom e aspetta 2 minuti. Se arriva, arriveranno anche i tuoi promemoria.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Imposta Doculoom su gestione manuale e consenti l\'avvio automatico, l\'avvio secondario e l\'esecuzione in background.',
  'Step {n}: {title}': 'Passaggio {n}: {title}',
  'Test': 'Prova',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Prova impostata. Chiudi Doculoom ora e aspetta 2 minuti.',
  'Test them and check the phone\'s battery settings': 'Provali e controlla le impostazioni della batteria del telefono',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Attiva l\'avvio automatico per Doculoom e nelle sue impostazioni della batteria scegli Nessuna limitazione.',
  '{maker} settings': 'Impostazioni {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Consenti a Doculoom di avviarsi da solo e di funzionare in background, e consenti un elevato consumo in background.',
  'Allow Doculoom to start by itself and to run in the background.': 'Consenti a Doculoom di avviarsi da solo e di funzionare in background.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Consenti l\'avvio automatico e l\'attività in background di Doculoom e non lasciare che il risparmio batteria lo chiuda.',
};

const Map<String, String> nlReminderHelp = {
  'Battery': 'Batterij',
  'Battery settings': 'Batterijinstellingen',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Gebruik geen Geforceerd stoppen voor Doculoom: Android verwijdert dan zijn alarmen totdat u de app weer opent. Wegvegen uit recente apps is op de meeste telefoons prima.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Zorg dat Doculoom niet bij Slapende apps of Diep slapende apps staat en zet het batterijgebruik op Onbeperkt.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Meldingen zijn uitgeschakeld voor Doculoom, dus er kan niets worden getoond.',
  'Open background settings': 'Achtergrondinstellingen openen',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Open de batterijinstellingen, kies Doculoom en selecteer Onbeperkt of Niet optimaliseren.',
  'Reminders are not available on this phone.': 'Herinneringen zijn niet beschikbaar op deze telefoon.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Herinneringen worden ingesteld in het eigen alarmsysteem van de telefoon, dus ze komen aan als Doculoom gesloten is en worden na een herstart opnieuw ingesteld. Sommige telefoons besparen batterij door apps op de achtergrond te stoppen, en dan kan een herinnering te laat komen of ontbreken. Deze stappen lossen dat op.',
  'Reminders not arriving?': 'Komen de herinneringen niet aan?',
  'Send a test in 2 minutes': 'Test sturen over 2 minuten',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Stuur een testmelding, sluit Doculoom en wacht 2 minuten. Komt die aan, dan komen uw herinneringen ook aan.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Zet Doculoom op handmatig beheer en sta automatisch starten, secundair starten en op de achtergrond draaien toe.',
  'Step {n}: {title}': 'Stap {n}: {title}',
  'Test': 'Test',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Test ingesteld. Sluit Doculoom nu en wacht 2 minuten.',
  'Test them and check the phone\'s battery settings': 'Test ze en controleer de batterijinstellingen van de telefoon',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Zet Autostart aan voor Doculoom en kies in de batterij-instellingen Geen beperkingen.',
  '{maker} settings': '{maker}-instellingen',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Sta toe dat Doculoom zelf start en op de achtergrond draait, en sta hoog stroomverbruik op de achtergrond toe.',
  'Allow Doculoom to start by itself and to run in the background.': 'Sta toe dat Doculoom zelf start en op de achtergrond draait.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Sta automatisch starten en activiteit op de achtergrond van Doculoom toe en laat batterijbesparing het niet sluiten.',
};

const Map<String, String> plReminderHelp = {
  'Battery': 'Bateria',
  'Battery settings': 'Ustawienia baterii',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Nie używaj opcji Wymuś zatrzymanie dla Doculoom: Android usuwa wtedy jego alarmy, dopóki nie otworzysz aplikacji ponownie. Zamknięcie z listy ostatnich aplikacji jest na większości telefonów w porządku.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Upewnij się, że Doculoom nie znajduje się w Uśpionych aplikacjach ani w Głęboko uśpionych aplikacjach, i ustaw jego użycie baterii na Bez ograniczeń.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Powiadomienia Doculoom są wyłączone, więc nic nie można pokazać.',
  'Open background settings': 'Otwórz ustawienia działania w tle',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Otwórz ustawienia baterii, wybierz Doculoom i wybierz Bez ograniczeń lub Nie optymalizuj.',
  'Reminders are not available on this phone.': 'Przypomnienia nie są dostępne na tym telefonie.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Przypomnienia są ustawiane w systemie alarmów telefonu, więc docierają, gdy Doculoom jest zamknięty, i są ustawiane ponownie po restarcie. Niektóre telefony oszczędzają baterię, zatrzymując aplikacje w tle, i wtedy przypomnienie może się spóźnić lub nie dotrzeć. Te kroki to naprawiają.',
  'Reminders not arriving?': 'Przypomnienia nie docierają?',
  'Send a test in 2 minutes': 'Wyślij test za 2 minuty',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Wyślij powiadomienie testowe, zamknij Doculoom i poczekaj 2 minuty. Jeśli dotrze, Twoje przypomnienia też dotrą.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Ustaw Doculoom na zarządzanie ręczne i zezwól na autostart, uruchamianie dodatkowe i działanie w tle.',
  'Step {n}: {title}': 'Krok {n}: {title}',
  'Test': 'Test',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Test ustawiony. Zamknij teraz Doculoom i poczekaj 2 minuty.',
  'Test them and check the phone\'s battery settings': 'Przetestuj je i sprawdź ustawienia baterii telefonu',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Włącz autostart dla Doculoom, a w jego ustawieniach baterii wybierz Bez ograniczeń.',
  '{maker} settings': 'Ustawienia {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Zezwól Doculoom na samodzielne uruchamianie i działanie w tle oraz na wysokie zużycie energii w tle.',
  'Allow Doculoom to start by itself and to run in the background.': 'Zezwól Doculoom na samodzielne uruchamianie i działanie w tle.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Zezwól Doculoom na autostart i aktywność w tle i nie pozwól, by oszczędzanie baterii go zamykało.',
};

const Map<String, String> trReminderHelp = {
  'Battery': 'Pil',
  'Battery settings': 'Pil ayarları',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Doculoom için Zorla durdur kullanmayın: Android, siz uygulamayı yeniden açana kadar alarmlarını siler. Son uygulamalardan kaydırarak kapatmak çoğu telefonda sorun değildir.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Doculoom\'un Uyuyan uygulamalar veya Derin uyuyan uygulamalar listesinde olmadığından emin olun ve pil kullanımını Kısıtlanmamış yapın.',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Doculoom için bildirimler kapalı, bu yüzden hiçbir şey gösterilemez.',
  'Open background settings': 'Arka plan ayarlarını aç',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Pil ayarlarını açın, Doculoom\'u seçin ve Kısıtlanmamış ya da Optimize etme seçeneğini işaretleyin.',
  'Reminders are not available on this phone.': 'Hatırlatıcılar bu telefonda kullanılamıyor.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Hatırlatıcılar telefonun kendi alarm sisteminde kurulur; bu yüzden Doculoom kapalıyken de gelir ve yeniden başlatmadan sonra tekrar kurulur. Bazı telefonlar pil tasarrufu için arka plandaki uygulamaları durdurur ve bu durumda hatırlatıcı gecikebilir ya da gelmeyebilir. Bu adımlar bunu çözer.',
  'Reminders not arriving?': 'Hatırlatıcılar gelmiyor mu?',
  'Send a test in 2 minutes': '2 dakika içinde test gönder',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Bir test bildirimi gönderin, Doculoom\'u kapatın ve 2 dakika bekleyin. Gelirse hatırlatıcılarınız da gelir.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Doculoom\'u elle yönetilen olarak ayarlayın; otomatik başlatmaya, ikincil başlatmaya ve arka planda çalışmaya izin verin.',
  'Step {n}: {title}': 'Adım {n}: {title}',
  'Test': 'Deneme',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Test kuruldu. Şimdi Doculoom\'u kapatın ve 2 dakika bekleyin.',
  'Test them and check the phone\'s battery settings': 'Test edin ve telefonun pil ayarlarını kontrol edin',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Doculoom için Otomatik başlatmayı açın ve pil ayarlarında Kısıtlama yok\'u seçin.',
  '{maker} settings': '{maker} ayarları',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Doculoom\'un kendiliğinden başlamasına ve arka planda çalışmasına, ayrıca arka planda yüksek güç kullanımına izin verin.',
  'Allow Doculoom to start by itself and to run in the background.': 'Doculoom\'un kendiliğinden başlamasına ve arka planda çalışmasına izin verin.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Doculoom için otomatik başlatmaya ve arka plan etkinliğine izin verin, pil tasarrufunun onu kapatmasına izin vermeyin.',
};

const Map<String, String> ruReminderHelp = {
  'Battery': 'Батарея',
  'Battery settings': 'Настройки батареи',
  'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.':
      'Не используйте «Принудительно остановить» для Doculoom: Android удаляет его будильники, пока вы не откроете приложение снова. Смахнуть его из недавних на большинстве телефонов можно.',
  'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.':
      'Убедитесь, что Doculoom не в списке спящих или глубоко спящих приложений, и задайте для него расход батареи «Без ограничений».',
  'Notifications are off for Doculoom, so nothing can be shown.': 'Уведомления для Doculoom отключены, поэтому ничего показать нельзя.',
  'Open background settings': 'Открыть настройки фоновой работы',
  'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.':
      'Откройте настройки батареи, выберите Doculoom и задайте «Без ограничений» или «Не оптимизировать».',
  'Reminders are not available on this phone.': 'Напоминания недоступны на этом телефоне.',
  'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.':
      'Напоминания ставятся в системе будильников самого телефона, поэтому приходят и при закрытом Doculoom, а после перезагрузки ставятся заново. Некоторые телефоны экономят батарею, останавливая фоновые приложения, и тогда напоминание может опоздать или не прийти. Эти шаги это исправляют.',
  'Reminders not arriving?': 'Напоминания не приходят?',
  'Send a test in 2 minutes': 'Отправить тест через 2 минуты',
  'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.':
      'Отправьте тестовое уведомление, закройте Doculoom и подождите 2 минуты. Если оно придёт, придут и ваши напоминания.',
  'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.':
      'Включите для Doculoom ручное управление и разрешите автозапуск, вторичный запуск и работу в фоне.',
  'Step {n}: {title}': 'Шаг {n}: {title}',
  'Test': 'Тест',
  'Test set. Close Doculoom now and wait 2 minutes.': 'Тест назначен. Закройте Doculoom и подождите 2 минуты.',
  'Test them and check the phone\'s battery settings': 'Проверьте их и настройки батареи телефона',
  'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.':
      'Включите для Doculoom автозапуск и в его настройках батареи выберите «Без ограничений».',
  '{maker} settings': 'Настройки {maker}',
  'Allow Doculoom to start by itself and to run in the background, and allow high background power use.':
      'Разрешите Doculoom запускаться самостоятельно и работать в фоне, а также разрешите повышенный расход энергии в фоне.',
  'Allow Doculoom to start by itself and to run in the background.': 'Разрешите Doculoom запускаться самостоятельно и работать в фоне.',
  'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.':
      'Разрешите Doculoom автозапуск и фоновую активность и не позволяйте экономии батареи закрывать его.',
};
