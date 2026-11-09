#!/usr/bin/env python3
"""Fill draft marketing copy and the slightly opened devices fan.

Approved zh / zh-Hant / en / ja headlines stay, except the devices page,
whose headline now says multiple devices (zh is exactly 多设备，随你练).
The devices subtitle names iPhone, iPad, iPhone Duo and Apple Watch.
  * en training subtitle gets an explicit line break, same words

ko, es, fr, de, it, pt-BR, ru, ar are drafts for review, not upload approval.
approvedLocales is left unchanged.
"""
from __future__ import annotations

import json
from pathlib import Path

P = Path(__file__).resolve().parents[3] / "design/app-store-studio-2026-10-29/app-store-screenshots.json"
L = ["ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]


def put(field: dict, values: dict) -> None:
    field.update(values)


def main() -> None:
    doc = json.loads(P.read_text())
    slides = {slide["id"]: slide for slide in doc["slidesByDevice"]["iphone"]}

    put(slides["plan"]["label"], {
        "ko": "01 / AI 코치",
        "es": "01 / COACH IA",
        "fr": "01 / COACH IA",
        "de": "01 / KI-COACH",
        "it": "01 / COACH IA",
        "pt-BR": "01 / COACH IA",
        "ru": "01 / ИИ-ТРЕНЕР",
        "ar": "01 / المدرب الذكي",
    })
    put(slides["plan"]["headline"], {
        "ko": "사진 한 장으로,\n일주일 계획",
        "es": "Una foto,\nuna semana lista",
        "fr": "Une photo,\nune semaine prête",
        "de": "Ein Foto,\neine Woche geplant",
        "it": "Una foto,\nuna settimana pronta",
        "pt-BR": "Uma foto,\numa semana pronta",
        "ru": "Одно фото —\nплан на неделю",
        "ar": "صورة واحدة،\nخطة أسبوع",
    })
    put(slides["plan"]["textElements"][0]["text"], {
        "ko": "몸 사진을 보고, 요청도 반영합니다.\n일수, 시간, 중점까지 그대로 짭니다.",
        "es": "Lee la foto y tu pedido:\ndías, duración y prioridades.",
        "fr": "Lit la photo et votre consigne :\njours, durée, priorités.",
        "de": "Liest das Foto und deine Vorgabe:\nTage, Dauer, Schwerpunkte.",
        "it": "Legge la foto e la tua richiesta:\ngiorni, durata, priorità.",
        "pt-BR": "Lê a foto e o seu pedido:\ndias, duração e prioridades.",
        "ru": "Смотрит фото и ваш запрос:\nдни, длительность, акцент.",
        "ar": "يقرأ صورة الجسم وطلبك:\nالأيام والمدة والأولويات.",
    })

    put(slides["recovery"]["label"], {
        "zh-Hant": "02 / 肌肉恢復",
        "ja": "02 / 回復",
        "ko": "02 / 근육 회복",
        "es": "02 / RECUPERACIÓN",
        "fr": "02 / RÉCUPÉRATION",
        "de": "02 / ERHOLUNG",
        "it": "02 / RECUPERO",
        "pt-BR": "02 / RECUPERAÇÃO",
        "ru": "02 / ВОССТАНОВЛЕНИЕ",
        "ar": "02 / التعافي",
    })
    put(slides["recovery"]["headline"], {
        "ko": "근육 회복,\n한눈에",
        "es": "La recuperación,\nde un vistazo",
        "fr": "La récupération,\nd'un coup d'œil",
        "de": "Erholung sehen,\nauf einen Blick",
        "it": "Il recupero,\na colpo d'occhio",
        "pt-BR": "A recuperação,\nnum relance",
        "ru": "Восстановление,\nс одного взгляда",
        "ar": "تعافي العضلات،\nبنظرة",
    })
    put(slides["recovery"]["textElements"][0]["text"], {
        "ko": "3D 근육 그림으로 부위별 회복 상태를 봅니다.\n다음에 어디를 할지 참고하세요.",
        "es": "Un mapa 3D muestra qué zona se ha recuperado\ny cuál conviene entrenar después.",
        "fr": "Une carte 3D montre ce qui a récupéré\net quoi entraîner ensuite.",
        "de": "Eine 3D-Karte zeigt, was erholt ist\nund was als Nächstes dran ist.",
        "it": "Una mappa 3D mostra cosa ha recuperato\ne cosa allenare dopo.",
        "pt-BR": "Um mapa 3D mostra o que recuperou\ne o que treinar em seguida.",
        "ru": "3D-карта показывает, что восстановилось\nи что тренировать дальше.",
        "ar": "خريطة ثلاثية الأبعاد تُظهر حالة التعافي\nوما الذي يُدرَّب بعدها.",
    })

    put(slides["training"]["label"], {
        "zh-Hant": "03 / 訓練與心率",
        "ja": "03 / トレーニングと心拍",
        "ko": "03 / 운동과 심박",
        "es": "03 / ENTRENO Y PULSO",
        "fr": "03 / EFFORT ET FRÉQUENCE",
        "de": "03 / TRAINING & PULS",
        "it": "03 / ALLENAMENTO E BATTITO",
        "pt-BR": "03 / TREINO E FREQUÊNCIA",
        "ru": "03 / ТРЕНИРОВКА И ПУЛЬС",
        "ar": "03 / التمرين والنبض",
    })
    put(slides["training"]["headline"], {
        "ko": "심박이 높으면,\n바로 알려 줍니다",
        "es": "¿Pasaste tu límite?\nLo vas a ver",
        "fr": "Au-dessus de votre limite ?\nVous le voyez",
        "de": "Über dein Limit?\nDu siehst es",
        "it": "Oltre il tuo limite?\nLo vedi subito",
        "pt-BR": "Passou do seu limite?\nVocê vê na hora",
        "ru": "Выше вашего порога?\nВы это увидите",
        "ar": "فوق حدك؟\nستعرف فورًا",
    })
    put(slides["training"]["textElements"][0]["text"], {
        "en": "Turns red past your own limit;\nheart-rate shifts can also auto-log sets or skip rest (optional, undoable).",
        "ko": "정한 상한을 넘으면 붉게 표시됩니다.\n심박으로 세트를 기록하거나 휴식을 건너뛰는 기능은 선택이며, 취소할 수 있습니다.",
        "es": "Se pone en rojo al pasar tu límite.\nEl pulso también puede anotar series o saltar el descanso (opcional, se puede deshacer).",
        "fr": "Passe au rouge au-delà de votre limite.\nLe rythme peut aussi noter les séries ou sauter le repos (optionnel, annulable).",
        "de": "Wird rot, wenn du dein Limit überschreitest.\nDer Puls kann Sätze loggen oder die Pause überspringen (optional, widerrufbar).",
        "it": "Diventa rosso oltre il tuo limite.\nIl battito può anche segnare le serie o saltare il riposo (facoltativo, annullabile).",
        "pt-BR": "Fica vermelho acima do seu limite.\nA frequência também pode anotar séries ou pular o descanso (opcional, dá para desfazer).",
        "ru": "Краснеет, если выше вашего порога.\nПульс может записать подход или пропустить отдых (по желанию, можно отменить).",
        "ar": "يحمرّ إذا تجاوزت حدك.\nيمكن للنبض أن يسجّل المجموعات أو يتخطى الراحة (اختياري، ويمكن التراجع).",
    })

    put(slides["diet"]["label"], {
        "ko": "04 / 식단과 수면",
        "es": "04 / NUTRICIÓN Y SUEÑO",
        "fr": "04 / NUTRITION ET SOMMEIL",
        "de": "04 / ERNÄHRUNG & SCHLAF",
        "it": "04 / CIBO E SONNO",
        "pt-BR": "04 / NUTRIÇÃO E SONO",
        "ru": "04 / ПИТАНИЕ И СОН",
        "ar": "04 / التغذية والنوم",
    })
    put(slides["diet"]["headline"], {
        "ko": "식단과 수면,\n함께 관리",
        "es": "Nutrición y sueño,\njuntos",
        "fr": "Nutrition et sommeil,\nensemble",
        "de": "Ernährung und Schlaf,\nim Blick",
        "it": "Alimentazione e sonno,\ninsieme",
        "pt-BR": "Nutrição e sono,\njuntos",
        "ru": "Питание и сон,\nвместе",
        "ar": "التغذية والنوم،\nمعًا",
    })
    put(slides["diet"]["textElements"][0]["text"], {
        "ko": "끼니마다 열량과 영양을 기록합니다.\n수면 시간과 회복 상태를 봅니다.",
        "es": "Registra calorías y nutrientes de cada comida.\nMira la duración del sueño y la recuperación.",
        "fr": "Notez les calories et nutriments de chaque repas.\nVoyez la durée du sommeil et la récupération.",
        "de": "Erfasse Kalorien und Nährstoffe jeder Mahlzeit.\nSieh Schlafdauer und Erholung.",
        "it": "Registra calorie e nutrienti di ogni pasto.\nControlla durata del sonno e recupero.",
        "pt-BR": "Registre calorias e nutrientes de cada refeição.\nVeja a duração do sono e a recuperação.",
        "ru": "Записывайте калории и нутриенты каждого приёма.\nСмотрите длительность сна и восстановление.",
        "ar": "سجّل سعرات كل وجبة ومغذياتها.\nتابع مدة النوم والتعافي.",
    })

    put(slides["devices"]["label"], {
        "ko": "05 / 모든 기기",
        "es": "05 / DISPOSITIVOS",
        "fr": "05 / APPAREILS",
        "de": "05 / GERÄTE",
        "it": "05 / DISPOSITIVI",
        "pt-BR": "05 / DISPOSITIVOS",
        "ru": "05 / УСТРОЙСТВА",
        "ar": "05 / الأجهزة",
    })
    put(slides["devices"]["headline"], {
        "en": "Multiple devices,\ntrain your way",
        "zh": "多设备，\n随你练",
        "zh-Hant": "多裝置，\n想練就練",
        "ja": "複数デバイス、\n好きなように",
        "ko": "여러 기기,\n내 방식대로",
        "es": "Varios dispositivos,\na tu manera",
        "fr": "Plusieurs appareils,\nà votre façon",
        "de": "Mehrere Geräte,\nwie du willst",
        "it": "Più dispositivi,\ncome vuoi",
        "pt-BR": "Vários dispositivos,\ndo seu jeito",
        "ru": "Много устройств\nкак вам удобно",
        "ar": "أجهزة متعددة،\nكما تشاء",
    })
    put(slides["devices"]["textElements"][0]["text"], {
        "en": "Supports iPhone, iPad,\niPhone Duo, and Apple Watch.",
        "zh": "支持 iPhone、iPad、\niPhone Duo 和 Apple Watch",
        "zh-Hant": "支援 iPhone、iPad、\niPhone Duo 和 Apple Watch",
        "ja": "iPhone、iPad、iPhone Duo、\nApple Watch に対応",
        "ko": "iPhone, iPad, iPhone Duo,\nApple Watch 지원",
        "es": "En iPhone, iPad, iPhone Duo\ny Apple Watch.",
        "fr": "Sur iPhone, iPad, iPhone Duo\net Apple Watch.",
        "de": "Für iPhone, iPad, iPhone Duo\nund Apple Watch.",
        "it": "Su iPhone, iPad, iPhone Duo\ne Apple Watch.",
        "pt-BR": "No iPhone, iPad, iPhone Duo\ne no Apple Watch.",
        "ru": "На iPhone, iPad, iPhone Duo\nи Apple Watch.",
        "ar": "يدعم iPhone وiPad\nوiPhone Duo وApple Watch.",
    })
    slides["devices"]["lineup"]["slots"] = [
        {"id": "watch", "x": 115, "y": 2244, "width": 270, "height": 424.29, "rotation": -14, "zIndex": 4},
        {"id": "iphone", "x": 210, "y": 1705, "width": 420, "height": 858.67, "rotation": -4, "zIndex": 3},
        {"id": "duo", "x": 355, "y": 1348, "width": 560, "height": 781.55, "rotation": 6, "zIndex": 2},
        {"id": "ipad", "x": 390, "y": 868, "width": 780, "height": 1018.39, "rotation": 13, "zIndex": 1},
    ]

    fill_chat(slides["plan"]["chat"])
    # Drafts stay unapproved until the owner reviews them.
    doc["pendingLocales"] = [locale for locale in doc["locales"] if locale not in doc["approvedLocales"]]
    P.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print("updated", P)


def fill_chat(chat: dict) -> None:
    user, coach = chat["bubbles"]
    put(user["text"], {
        "ko": "운동 계획 짜 줘",
        "es": "Ármame un plan de entrenamiento",
        "fr": "Fais-moi un programme",
        "de": "Erstell mir einen Trainingsplan",
        "it": "Fammi un programma",
        "pt-BR": "Monte um plano de treino",
        "ru": "Составь план тренировок",
        "ar": "رتّب لي خطة تدريب",
    })
    put(user["subtext"], {
        "ko": "주 3일 · 회당 45분",
        "es": "3 días · 45 min",
        "fr": "3 jours · 45 min",
        "de": "3 Tage · je 45 Min.",
        "it": "3 giorni · 45 min",
        "pt-BR": "3 dias · 45 min",
        "ru": "3 дня · по 45 мин",
        "ar": "\u20663\u2069 أيام · \u206645\u2069 دقيقة",
    })
    put(coach["text"], {
        "ko": "정면은 가슴 중·하부가 두껍고, 상부는 얇습니다.\n어깨 앞쪽과 팔 선은 분명합니다.\n후면 중간 등은 평평하고, 광배의 폭이 부족합니다.\n다리는 유지하고, 가슴과 등을 먼저 채웁니다.",
        "es": "De frente: pecho más lleno abajo, arriba más fino.\nHombros y brazos se marcan.\nEspalda media plana; dorsales piden ancho.\nPiernas van bien: primero pecho y espalda.",
        "fr": "De face : pecs plus pleins en bas, plus fins en haut.\nÉpaules et bras sont nets.\nMilieu du dos plat, dorsaux à élargir.\nJambes stables — pecs et dos d'abord.",
        "de": "Vorne: Brust unten voller, oben dünner.\nSchultern und Arme sind klar.\nMitte Rücken flach, Latissimus schmal.\nBeine passen — zuerst Brust und Rücken.",
        "it": "Davanti: petto più pieno in basso, più sottile in alto.\nSpalle e braccia sono definite.\nSchiena media piatta, dorsali da allargare.\nGambe ok — prima petto e schiena.",
        "pt-BR": "De frente: peito mais cheio embaixo, fino em cima.\nOmbros e braços aparecem.\nMeio das costas plano; dorsais pedem largura.\nPernas no ritmo — peito e costas primeiro.",
        "ru": "Спереди: грудь полнее снизу, сверху тоньше.\nПлечи и руки читаются.\nСередина спины плоская, широчайшие узкие.\nНоги в порядке — сначала грудь и спина.",
        "ar": "من الأمام: الصدر أسمك بالأسفل وأرفع بالأعلى.\nالكتف الأمامي والذراع واضحان.\nمنتصف الظهر مسطّح، وعرض الظهر قليل.\nالساقان مناسبتان — ابدأ بالصدر والظهر.",
    })
    report = coach["report"]
    put(report["label"], {
        "ko": "추천 중점",
        "es": "Prioridad sugerida",
        "fr": "Priorité suggérée",
        "de": "Vorschlag",
        "it": "Focus suggerito",
        "pt-BR": "Foco sugerido",
        "ru": "Что усилить",
        "ar": "تركيز مقترح",
    })
    put(report["names"][0], {
        "ko": "가슴", "es": "Pecho", "fr": "Pecs", "de": "Brust", "it": "Petto", "pt-BR": "Peito", "ru": "Грудь", "ar": "صدر",
    })
    put(report["names"][1], {
        "ko": "등", "es": "Espalda", "fr": "Dos", "de": "Rücken", "it": "Schiena", "pt-BR": "Costas", "ru": "Спина", "ar": "ظهر",
    })
    put(report["note"], {
        "ko": "빛과 자세에 따라 달라집니다. 훈련 중점 참고용입니다.",
        "es": "La luz y la postura limitan esta lectura.",
        "fr": "Lumière et posture limitent cette lecture.",
        "de": "Licht und Haltung begrenzen diese Einschätzung.",
        "it": "Luce e postura limitano questa lettura.",
        "pt-BR": "Luz e postura limitam esta leitura.",
        "ru": "Свет и поза ограничивают эту оценку.",
        "ar": "الإضاءة والوقفة تحدّان هذه القراءة.",
    })
    put(coach["cta"], {
        "ko": "내 운동 계획에 저장",
        "es": "Guardar en mis planes",
        "fr": "Enregistrer dans mes plans",
        "de": "In meine Pläne sichern",
        "it": "Salva nei miei piani",
        "pt-BR": "Salvar nos meus planos",
        "ru": "Сохранить в мои планы",
        "ar": "حفظ في خططي",
    })

    days = [
        {
            "kicker": {"ko": "1일차", "es": "Día 1", "fr": "Jour 1", "de": "Tag 1", "it": "Giorno 1", "pt-BR": "Dia 1", "ru": "День 1", "ar": "اليوم \u20661\u2069"},
            "title": {"ko": "가슴 + 삼두", "es": "Pecho + tríceps", "fr": "Pecs + triceps", "de": "Brust + Trizeps", "it": "Petto + tricipiti", "pt-BR": "Peito + tríceps", "ru": "Грудь + трицепс", "ar": "صدر + تراي"},
            "meta": {"ko": "6개 동작 · 19세트", "es": "6 ejercicios · 19 series", "fr": "6 exercices · 19 séries", "de": "6 Übungen · 19 Sätze", "it": "6 esercizi · 19 serie", "pt-BR": "6 exercícios · 19 séries", "ru": "6 упражнений · 19 подходов", "ar": "\u20666\u2069 حركات · \u206619\u2069 مجموعات"},
            "part": ["Chest", "Chest", "Chest", "Chest", "Triceps", "Triceps"],
            "name": ["Bench Press", "Incline Bench", "Dumbbell Bench", "Cable Fly", "Close-Grip Bench", "Pushdown"],
        },
        {
            "kicker": {"ko": "2일차", "es": "Día 2", "fr": "Jour 2", "de": "Tag 2", "it": "Giorno 2", "pt-BR": "Dia 2", "ru": "День 2", "ar": "اليوم \u20662\u2069"},
            "title": {"ko": "등 + 이두", "es": "Espalda + bíceps", "fr": "Dos + biceps", "de": "Rücken + Bizeps", "it": "Schiena + bicipiti", "pt-BR": "Costas + bíceps", "ru": "Спина + бицепс", "ar": "ظهر + باي"},
            "meta": {"ko": "5개 동작 · 16세트", "es": "5 ejercicios · 16 series", "fr": "5 exercices · 16 séries", "de": "5 Übungen · 16 Sätze", "it": "5 esercizi · 16 serie", "pt-BR": "5 exercícios · 16 séries", "ru": "5 упражнений · 16 подходов", "ar": "\u20665\u2069 حركات · \u206616\u2069 مجموعات"},
            "part": ["Back", "Back", "Back", "Biceps", "Biceps"],
            "name": ["Pull-Up", "Barbell Row", "Lat Pulldown", "Barbell Curl", "Hammer Curl"],
        },
        {
            "kicker": {"ko": "3일차", "es": "Día 3", "fr": "Jour 3", "de": "Tag 3", "it": "Giorno 3", "pt-BR": "Dia 3", "ru": "День 3", "ar": "اليوم \u20663\u2069"},
            "title": {"ko": "하체 + 코어", "es": "Piernas + core", "fr": "Jambes + gainage", "de": "Beine + Core", "it": "Gambe + core", "pt-BR": "Pernas + core", "ru": "Ноги + кор", "ar": "أرجل + جذع"},
            "meta": {"ko": "5개 동작 · 15세트", "es": "5 ejercicios · 15 series", "fr": "5 exercices · 15 séries", "de": "5 Übungen · 15 Sätze", "it": "5 esercizi · 15 serie", "pt-BR": "5 exercícios · 15 séries", "ru": "5 упражнений · 15 подходов", "ar": "\u20665\u2069 حركات · \u206615\u2069 مجموعات"},
            "part": ["Legs", "Legs", "Core"],
            "name": ["Back Squat", "Romanian Deadlift", "Hanging Leg Raise"],
        },
    ]
    parts = {
        "Chest": {"ko": "가슴", "es": "Pecho", "fr": "Pecs", "de": "Brust", "it": "Petto", "pt-BR": "Peito", "ru": "Грудь", "ar": "صدر"},
        "Back": {"ko": "등", "es": "Espalda", "fr": "Dos", "de": "Rücken", "it": "Schiena", "pt-BR": "Costas", "ru": "Спина", "ar": "ظهر"},
        "Triceps": {"ko": "삼두", "es": "Tríceps", "fr": "Triceps", "de": "Trizeps", "it": "Tricipiti", "pt-BR": "Tríceps", "ru": "Трицепс", "ar": "تراي"},
        "Biceps": {"ko": "이두", "es": "Bíceps", "fr": "Biceps", "de": "Bizeps", "it": "Bicipiti", "pt-BR": "Bíceps", "ru": "Бицепс", "ar": "باي"},
        "Legs": {"ko": "하체", "es": "Piernas", "fr": "Jambes", "de": "Beine", "it": "Gambe", "pt-BR": "Pernas", "ru": "Ноги", "ar": "أرجل"},
        "Core": {"ko": "코어", "es": "Core", "fr": "Gainage", "de": "Core", "it": "Core", "pt-BR": "Core", "ru": "Кор", "ar": "جذع"},
    }
    names = {
        "Bench Press": {"ko": "벤치프레스", "es": "Press banca", "fr": "Développé couché", "de": "Bankdrücken", "it": "Panca piana", "pt-BR": "Supino reto", "ru": "Жим лёжа", "ar": "ضغط بنش"},
        "Incline Bench": {"ko": "인클라인 벤치", "es": "Press inclinado", "fr": "Développé incliné", "de": "Schrägbank", "it": "Panca inclinata", "pt-BR": "Supino inclinado", "ru": "Жим наклон", "ar": "ضغط مائل"},
        "Dumbbell Bench": {"ko": "덤벨 벤치", "es": "Press mancuernas", "fr": "Développé haltères", "de": "KH-Bankdrücken", "it": "Panca manubri", "pt-BR": "Supino halteres", "ru": "Жим гантелей", "ar": "ضغط دمبل"},
        "Cable Fly": {"ko": "케이블 플라이", "es": "Aperturas", "fr": "Écarté poulie", "de": "Kabel-Flys", "it": "Croci ai cavi", "pt-BR": "Crucifixo", "ru": "Сведение", "ar": "فراشة"},
        "Close-Grip Bench": {"ko": "내로우 벤치", "es": "Press cerrado", "fr": "Développé serré", "de": "Engbankdrücken", "it": "Panca stretta", "pt-BR": "Supino fechado", "ru": "Узкий жим", "ar": "ضغط ضيق"},
        "Pushdown": {"ko": "푸시다운", "es": "Jalón tríceps", "fr": "Pushdown", "de": "Trizepsdrücken", "it": "Pushdown", "pt-BR": "Tríceps pulley", "ru": "Разгибание", "ar": "دفع تراي"},
        "Pull-Up": {"ko": "풀업", "es": "Dominadas", "fr": "Tractions", "de": "Klimmzüge", "it": "Trazioni", "pt-BR": "Barra fixa", "ru": "Подтягивания", "ar": "عقلة"},
        "Barbell Row": {"ko": "바벨 로우", "es": "Remo barra", "fr": "Rowing barre", "de": "Langhantelrudern", "it": "Rematore", "pt-BR": "Remada curvada", "ru": "Тяга штанги", "ar": "تجديف"},
        "Lat Pulldown": {"ko": "랫풀다운", "es": "Jalón pecho", "fr": "Tirage vertical", "de": "Latzug", "it": "Lat machine", "pt-BR": "Puxada alta", "ru": "Тяга блока", "ar": "سحب عالي"},
        "Barbell Curl": {"ko": "바벨 컬", "es": "Curl barra", "fr": "Curl barre", "de": "LH-Curls", "it": "Curl bilanciere", "pt-BR": "Rosca direta", "ru": "Подъём на бицепс", "ar": "ثني بار"},
        "Hammer Curl": {"ko": "해머 컬", "es": "Curl martillo", "fr": "Curl marteau", "de": "Hammercurls", "it": "Curl martello", "pt-BR": "Rosca martelo", "ru": "Молот", "ar": "مطرقة"},
        "Back Squat": {"ko": "백 스쿼트", "es": "Sentadilla", "fr": "Squat barre", "de": "Kniebeuge", "it": "Squat", "pt-BR": "Agachamento", "ru": "Приседания", "ar": "سكوات"},
        "Romanian Deadlift": {"ko": "루마니안 데드", "es": "Peso rumano", "fr": "Soulevé roumain", "de": "Rumänisches KH", "it": "Stacco rumeno", "pt-BR": "Stiff", "ru": "Румынская тяга", "ar": "رفعة رومانية"},
        "Hanging Leg Raise": {"ko": "행잉 레그레이즈", "es": "Elevación piernas", "fr": "Relevé de jambes", "de": "Beinheben", "it": "Leg raise", "pt-BR": "Elevação pernas", "ru": "Подъём ног", "ar": "رفع رجلين"},
    }
    for card, day in zip(coach["plans"], days):
        put(card["kicker"], day["kicker"])
        put(card["title"], day["title"])
        put(card["meta"], day["meta"])
        for pill, part, name in zip(card["pills"], day["part"], day["name"]):
            put(pill["part"], parts[part])
            put(pill["name"], names[name])


if __name__ == "__main__":
    main()
