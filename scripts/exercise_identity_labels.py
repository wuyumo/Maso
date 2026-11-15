# Explicit localizations for the actual name suffix, not inferred from filenames.
LANGS=['en','zh-Hans','zh-Hant','ja','ko','es','fr','de','it','pt-BR','ru','ar']
LABELS={
'barbell':['Barbell','杠铃','槓鈴','バーベル','바벨','Barra','Barre','Langhantel','Bilanciere','Barra','Штанга','بار'],
'dumbbell':['Dumbbell','哑铃','啞鈴','ダンベル','덤벨','Mancuernas','Haltères','Kurzhantel','Manubri','Halteres','Гантели','دمبل'],
'kettlebell':['Kettlebell','壶铃','壺鈴','ケトルベル','케틀벨','Pesa rusa','Kettlebell','Kettlebell','Kettlebell','Kettlebell','Гиря','كيتل بيل'],
'cable':['Cable','绳索','繩索','ケーブル','케이블','Polea','Poulie','Kabelzug','Cavo','Polia','Блок','كابل'],
'machine':['Machine','器械','器械','マシン','머신','Máquina','Machine','Maschine','Macchina','Máquina','Тренажёр','جهاز'],
'smith_machine':['Smith Machine','史密斯机','史密斯機','スミスマシン','스미스 머신','Máquina Smith','Machine Smith','Smith-Maschine','Multipower','Máquina Smith','Смит','جهاز سميث'],
'band':['Band','弹力带','彈力帶','バンド','밴드','Banda','Élastique','Widerstandsband','Elastico','Elástico','Резинка','شريط مقاومة'],
'ez_bar':['EZ-Bar','EZ 杠','EZ 槓','EZバー','EZ바','Barra EZ','Barre EZ','SZ-Stange','Bilanciere EZ','Barra EZ','EZ-гриф','بار EZ'],
'axle_bar':['Axle Bar','粗杆杠铃','粗桿槓鈴','アクスルバー','액슬 바','Barra gruesa','Barre épaisse','Axle-Stange','Axle bar','Barra grossa','Толстый гриф','بار سميك'],
'safety_squat_bar':['Safety Bar','安全深蹲杠','安全深蹲槓','セーフティバー','세이프티 바','Barra de seguridad','Barre de sécurité','Safety-Bar','Safety bar','Barra de segurança','Безопасный гриф','بار أمان'],
'weight_plate':['Weight Plate','杠铃片','槓鈴片','プレート','원판','Disco','Disque','Hantelscheibe','Disco','Anilha','Блин','قرص أوزان'],
'weight_belt':['Weight Belt','负重腰带','負重腰帶','ディップベルト','중량 벨트','Cinturón de lastre','Ceinture lestée','Dip-Gürtel','Cintura con pesi','Cinto de lastro','Пояс с отягощением','حزام أوزان'],
'bench':['Bench','训练凳','訓練凳','ベンチ','벤치','Banco','Banc','Bank','Panca','Banco','Скамья','مقعد'],
'pull_up_bar':['Pull-Up Bar','单杠','單槓','懸垂バー','철봉','Barra de dominadas','Barre de traction','Klimmzugstange','Sbarra','Barra fixa','Турник','عارضة عقلة'],
'dip_bars':['Parallel Bars','双杠','雙槓','平行棒','평행봉','Paralelas','Barres parallèles','Barren','Parallele','Paralelas','Брусья','متوازي'],
'rings':['Rings','吊环','吊環','リング','링','Anillas','Anneaux','Ringe','Anelli','Argolas','Кольца','حلقات'],
'box':['Box','训练箱','訓練箱','ボックス','박스','Cajón','Box','Box','Box','Caixa','Тумба','صندوق'],
'ball':['Stability Ball','健身球','健身球','バランスボール','짐볼','Pelota de estabilidad','Swiss ball','Gymnastikball','Fitball','Bola suíça','Фитбол','كرة توازن'],
'medicine_ball':['Medicine Ball','药球','藥球','メディシンボール','메디신볼','Balón medicinal','Médecine-ball','Medizinball','Palla medica','Medicine ball','Медбол','كرة طبية'],
'foam_roller':['Foam Roller','泡沫轴','滾筒','フォームローラー','폼롤러','Rodillo','Rouleau','Faszienrolle','Foam roller','Rolo de espuma','Ролик','أسطوانة إسفنجية'],
'landmine':['Landmine','地雷管','地雷管','ランドマイン','랜드마인','Landmine','Landmine','Landmine','Landmine','Landmine','Лэндмайн','لاندماين'],
'roman_chair':['Roman Chair','罗马椅','羅馬椅','ローマンチェア','로만 체어','Banco romano','Banc à lombaires','Römische Bank','Panca romana','Banco romano','Римский стул','كرسي روماني'],
'gripper':['Hand Gripper','握力器','握力器','ハンドグリッパー','악력기','Pinza de mano','Pince de musculation','Handtrainer','Hand grip','Hand grip','Кистевой эспандер','مقوي قبضة'],
'jump_rope':['Jump Rope','跳绳','跳繩','縄跳び','줄넘기','Comba','Corde à sauter','Springseil','Corda','Corda','Скакалка','حبل قفز'],
'battle_rope':['Battle Rope','战绳','戰繩','バトルロープ','배틀로프','Cuerdas de batalla','Battle rope','Battle Rope','Battle rope','Corda naval','Канаты','حبل تدريب'],
'treadmill':['Treadmill','跑步机','跑步機','トレッドミル','러닝머신','Cinta','Tapis de course','Laufband','Tapis roulant','Esteira','Беговая дорожка','جهاز مشي'],
'rower':['Rowing Machine','划船机','划船機','ローイングマシン','로잉머신','Remo','Rameur','Rudergerät','Vogatore','Remo ergométrico','Гребной тренажёр','جهاز تجديف'],
'bike':['Stationary Bike','健身车','健身車','エアロバイク','실내 자전거','Bicicleta estática','Vélo stationnaire','Ergometer','Cyclette','Bicicleta ergométrica','Велотренажёр','دراجة ثابتة'],
'spin_bike':['Spin Bike','动感单车','飛輪車','スピンバイク','스핀 바이크','Bicicleta de spinning','Vélo de spinning','Spinning-Bike','Spin bike','Bicicleta de spinning','Спин-байк','دراجة سبين'],
'air_bike':['Air Bike','风阻单车','風阻單車','エアバイク','에어 바이크','Bicicleta de aire','Air bike','Air Bike','Air bike','Air bike','Аэробайк','دراجة هوائية'],
'elliptical':['Elliptical','椭圆机','橢圓機','クロストレーナー','일립티컬','Elíptica','Elliptique','Crosstrainer','Ellittica','Elíptico','Эллипс','جهاز إليبتيكال'],
'stairmaster':['Stair Climber','爬楼机','爬樓機','ステアクライマー','스텝밀','Escaladora','Escalier mécanique','Treppensteiger','Stair climber','Escada ergométrica','Степпер','جهاز صعود الدرج'],
'ski_erg':['Ski Erg','滑雪机','滑雪機','スキーエルゴ','스키에르그','Ski erg','Ski erg','SkiErg','Ski erg','Ski erg','Лыжный эргометр','جهاز تزلج'],
'sled':['Sled','雪橇','雪橇','スレッド','슬레드','Trineo','Traîneau','Schlitten','Slitta','Trenó','Сани','زلاجة'],
'sliders':['Sliders','滑盘','滑盤','スライダー','슬라이더','Discos deslizantes','Disques glissants','Gleitscheiben','Dischi scorrevoli','Discos deslizantes','Слайдеры','أقراص انزلاق'],
'yoga_strap':['Yoga Strap','瑜伽带','瑜伽帶','ヨガストラップ','요가 스트랩','Correa de yoga','Sangle de yoga','Yogagurt','Cinghia yoga','Faixa de yoga','Ремень для йоги','حزام يوغا'],
'chains':['Chains','铁链','鐵鏈','チェーン','체인','Cadenas','Chaînes','Ketten','Catene','Correntes','Цепи','سلاسل'],
'push_up_handles':['Push-Up Handles','俯卧撑支架','伏地挺身架','プッシュアップバー','푸시업 바','Soportes de flexiones','Poignées de pompes','Liegestützgriffe','Maniglie per piegamenti','Barras de flexão','Упоры','مقابض ضغط'],
'pvc_pipe':['PVC Pipe','PVC 杆','PVC 桿','PVCパイプ','PVC 봉','Tubo de PVC','Tube PVC','PVC-Stab','Tubo PVC','Tubo de PVC','ПВХ-палка','عصا PVC'],
'rice_bucket':['Rice Bucket','米桶','米桶','ライスバケット','쌀통','Cubo de arroz','Seau de riz','Reiseimer','Secchio di riso','Balde de arroz','Ведро с рисом','دلو أرز'],
'sledgehammer':['Sledgehammer','大锤','大鎚','ハンマー','슬레지해머','Mazo','Masse','Vorschlaghammer','Mazza','Marreta','Кувалда','مطرقة ثقيلة'],
'fat_grip':['Fat Grip','加粗握把','加粗握把','ファットグリップ','팻 그립','Agarre grueso','Poignée épaisse','Fat Grip','Impugnatura spessa','Pegada grossa','Толстый хват','قبضة سميكة'],
'wrist_roller':['Wrist Roller','腕力器','腕力器','リストローラー','리스트 롤러','Rodillo de muñeca','Rouleau de poignet','Unterarmroller','Wrist roller','Rolo de punho','Кистевой ролик','بكرة معصم'],
'towel':['Towel','毛巾','毛巾','タオル','수건','Toalla','Serviette','Handtuch','Asciugamano','Toalha','Полотенце','منشفة'],
'rack':['Rack','训练架','訓練架','ラック','랙','Rack','Rack','Rack','Rack','Rack','Стойка','حامل'],
'trx':['TRX','TRX','TRX','TRX','TRX','TRX','TRX','TRX','TRX','TRX','TRX','TRX'],
'trap_bar':['Trap Bar','六角杠','六角槓','トラップバー','트랩 바','Barra hexagonal','Trap bar','Trap-Bar','Trap bar','Barra hexagonal','Трэп-гриф','بار سداسي'],
'other':['Equipment','器材','器材','器具','기구','Equipo','Matériel','Gerät','Attrezzo','Equipamento','Оборудование','معدات'],
}
LABELS['ab_wheel']=['Ab Wheel','健腹轮','健腹輪','アブローラー','복근 롤러','Rueda abdominal','Roue abdominale','Bauchroller','Ruota addominale','Roda abdominal','Ролик для пресса','عجلة بطن']
LABELS['rope']=['Rope Attachment','绳把','繩把','ロープアタッチメント','로프 손잡이','Agarre de cuerda','Corde de tirage','Seilgriff','Corda per cavi','Corda de polia','Канатная рукоять','مقبض حبل']
LABELS['v_bar']=['V-Bar','V 把','V 把','Vバー','V바','Barra V','Poignée V','V-Griff','Barra V','Barra V','V-рукоять','مقبض V']
LABELS['t_bar']=['T-Bar','T 杠','T 槓','Tバー','T바','Barra T','Barre T','T-Stange','Barra T','Barra T','Т-гриф','بار T']
LABELS['wall']=['Wall','墙面','牆面','壁','벽','Pared','Mur','Wand','Parete','Parede','Стена','جدار']
LABELS['partner']=['Partner','同伴辅助','同伴輔助','パートナー','파트너','Compañero','Partenaire','Partner','Partner','Parceiro','Партнёр','شريك']
ALIASES={'body_only':None,'barbell':'barbell','dumbbell':'dumbbell','kettlebell':'kettlebell','cable':'cable','smith_machine':'smith_machine','band':'band','resistance_band':'band','ez_bar':'ez_bar','ez_curl_bar':'ez_bar','gymnastic_rings':'rings','rings':'rings','dip_bar':'dip_bars','dip_bars':'dip_bars','parallel_bars':'dip_bars','weight_belt':'weight_belt','dip_belt':'weight_belt','bench_flat':'bench','bench_incline':'bench','bench_decline':'bench','preacher_bench':'bench','plyo_box':'box','platform':'box','swiss_ball':'ball','medicine_ball':'medicine_ball','foam_roller':'foam_roller','hyperextension_bench':'roman_chair','grip_crusher':'gripper','rowing_machine':'rower','stationary_bike':'bike','spin_bike':'spin_bike','assault_bike':'air_bike','arc_trainer':'elliptical','squat_rack':'rack','power_rack':'rack','t_bar':'barbell','captains_chair':'machine','ghd_machine':'machine','prowler':'sled'}
for k in LABELS:ALIASES.setdefault(k,k)
PRIORITY=['barbell','dumbbell','kettlebell','ez_bar','trap_bar','safety_squat_bar','axle_bar','cable','smith_machine','band','weight_plate','weight_belt','chains','medicine_ball','machine','rings','trx','landmine','roman_chair','pull_up_bar','dip_bars','gripper','bench','box']
def primary(e):
 types=set()
 for raw in e['equipment']:
  t=ALIASES.get(raw,'machine' if raw.endswith('_machine') else 'UNKNOWN')
  assert t!='UNKNOWN',(e['id'],raw)
  if t:types.add(t)
 if not types:return None
 return min(types,key=lambda t:PRIORITY.index(t) if t in PRIORITY else len(PRIORITY))
