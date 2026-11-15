"""Build an audited offline macro catalog from USDA public-domain downloads.
Inputs are downloaded to /tmp; only a tiny, reproducible subset enters the app.
"""
import json, urllib.request, zipfile, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
URLS=[('sr','https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip'),('foundation','https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-04-30.zip')]
# Explicit IDs, preparation and conservative exact-match aliases. No fuzzy replacements.
CHOICES=[
('chicken_breast_cooked',171477,'cooked skinless chicken breast',['cooked chicken breast','熟鸡胸肉','熟雞胸肉']),
('chicken_breast_raw',2646170,'raw skinless chicken breast',['raw chicken breast','生鸡胸肉','生雞胸肉']),
('chicken_thigh_cooked',172388,'cooked skinless chicken thigh',['cooked chicken thigh','熟鸡腿肉','熟雞腿肉']),
('chicken_thigh_raw',2646171,'raw skinless chicken thigh',['raw chicken thigh','生鸡腿肉','生雞腿肉']),
('turkey_breast_cooked',171496,'cooked skinless turkey breast',['cooked turkey breast']),
('white_rice_cooked',168878,'cooked white rice',['cooked rice','cooked white rice','熟米饭','白米饭','白米飯','米饭','米飯']),
('white_rice_dry',2512381,'dry uncooked white rice',['dry rice','raw rice','生大米','生米','干米','乾米','干大米','乾大米']),
('brown_rice_cooked',169704,'cooked brown rice',['cooked brown rice','熟糙米饭','熟糙米飯']),
('brown_rice_dry',2512380,'dry uncooked brown rice',['dry brown rice','生糙米']),
('oats_dry',2346396,'dry rolled oats',['dry oats','dry rolled oats','干燕麦','乾燕麥']),
('oatmeal_cooked',173905,'oatmeal cooked in water',['cooked oatmeal','水煮燕麦','水煮燕麥']),
('egg_boiled',173424,'hard-boiled whole egg',['boiled egg','hard boiled egg','水煮蛋','煮鸡蛋','煮雞蛋']),
('egg_raw',171287,'raw whole egg',['raw egg','生鸡蛋','生雞蛋']),
('egg_white_raw',172183,'raw egg white',['raw egg white','生蛋清']),
('tofu_firm',172475,'plain firm calcium-set tofu',['firm tofu','老豆腐','硬豆腐']),
('tofu_soft',172449,'plain soft tofu',['soft tofu','嫩豆腐']),
('beef_ground_cooked',171793,'cooked ground beef 90% lean',['cooked lean ground beef']),
('beef_ground_raw',174030,'raw ground beef 90% lean',['raw lean ground beef']),
('pork_loin_cooked',167821,'cooked pork loin lean and fat',['cooked pork loin']),
('salmon_cooked',175168,'cooked farmed Atlantic salmon',['cooked salmon','熟三文鱼','熟三文魚']),
('salmon_raw',175167,'raw farmed Atlantic salmon',['raw salmon','生三文鱼','生三文魚']),
('shrimp_cooked',171971,'cooked peeled shrimp',['cooked shrimp','熟虾仁','熟蝦仁']),
('shrimp_raw',174210,'raw peeled shrimp',['raw shrimp','生虾仁','生蝦仁']),
('milk_whole',171265,'whole dairy milk',['whole milk','全脂牛奶']),
('milk_2percent',171267,'2% dairy milk',['2% milk']),
('milk_skim',171269,'skim dairy milk',['skim milk','脱脂牛奶','脫脂牛奶']),
('yogurt_greek_nonfat',170894,'plain nonfat Greek yogurt',['nonfat greek yogurt','无脂希腊酸奶','無脂希臘酸奶']),
('yogurt_greek_whole',171304,'plain whole-milk Greek yogurt',['whole milk greek yogurt']),
('cheddar',173414,'cheddar cheese',['cheddar cheese','切达奶酪','切達起司']),
('bread_white',174924,'plain white bread',['white bread','白面包','白麵包']),
('bread_whole_wheat',172688,'whole-wheat bread',['whole wheat bread','全麦面包','全麥麵包']),
('pasta_cooked',169737,'plain cooked pasta',['cooked pasta','熟意面','熟義大利麵']),
('potato_boiled',170440,'boiled peeled potato',['boiled potato','水煮土豆','水煮马铃薯','水煮馬鈴薯']),
('sweet_potato_boiled',168484,'boiled peeled sweet potato',['boiled sweet potato','水煮红薯','水煮地瓜']),
('broccoli_boiled',169967,'boiled drained broccoli',['boiled broccoli','水煮西兰花','水煮花椰菜']),
('spinach_boiled',168463,'boiled drained spinach',['boiled spinach','水煮菠菜']),
('lentils_cooked',172421,'cooked lentils',['cooked lentils','熟扁豆']),
('black_beans_cooked',173735,'cooked black beans',['cooked black beans','熟黑豆']),
('banana',173944,'banana edible flesh',['banana','香蕉']),
('apple',171688,'apple with skin edible portion',['apple','苹果','蘋果']),
('orange',169097,'orange edible flesh',['orange','橙子']),
('almonds',170567,'plain almonds',['almonds','almond','杏仁']),
('peanuts_roasted',173806,'dry roasted peanuts',['roasted peanuts','烤花生']),
('olive_oil',171413,'olive oil',['olive oil','橄榄油','橄欖油']),
('canola_oil',172336,'canola oil',['canola oil','菜籽油']),
('butter',173410,'salted butter',['butter','黄油','奶油']),
('sugar',169655,'granulated sugar',['sugar','白糖']),
('soy_sauce',174277,'soy sauce',['soy sauce','酱油','醬油'])]

def build():
 foods={};sources=[]
 for kind,url in URLS:
  path=Path('/tmp')/('masso-usda-'+kind+'.zip')
  if not path.exists(): urllib.request.urlretrieve(url,path)
  blob=path.read_bytes();sources.append({'url':url,'sha256':hashlib.sha256(blob).hexdigest()})
  with zipfile.ZipFile(path) as z:
   data=json.loads(z.read(next(n for n in z.namelist() if n.endswith('.json'))))
  for food in next(v for v in data.values() if isinstance(v,list)):
   if isinstance(food,dict):foods[food['fdcId']]=food
 entries=[]
 for key,fdc,name,aliases in CHOICES:
  food=foods[fdc];values={n['nutrient']['id']:n.get('amount') for n in food['foodNutrients']}
  macro={k:values[i] for k,i in [('protein',1003),('carbs',1005),('fat',1004)]}
  assert all(isinstance(v,(int,float)) and 0<=v<=100 for v in macro.values()),(key,macro)
  entries.append(dict(id=key,fdcID=fdc,name=name,aliases=aliases,per100g=macro))
 payload=json.dumps(entries,ensure_ascii=False,separators=(',',':'))
 out=ROOT/'Maso/Models/MealFoodCatalog.swift'
 out.write_text('''// Generated by scripts/build_meal_food_catalog.py; USDA FoodData Central public domain.
// Do not hand-edit nutrient values. See docs/meal-nutrition-optimization.md for provenance.
import Foundation

enum MealFoodCatalog {
    static let version = "usda-sr2018-foundation2026-v1"
    static let foods: [MealReferenceFood] = {
        let json = #"""
'''+payload+'''
"""#
        return (try? JSONDecoder().decode([MealReferenceFood].self, from: Data(json.utf8))) ?? []
    }()
    static let byID = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
}
''')
 (ROOT/'docs/meal-food-catalog-provenance.json').write_text(json.dumps(dict(sources=sources,foods=[{'id':k,'fdcID':f,'description':foods[f]['description'],'dataType':foods[f]['dataType']} for k,f,_,_ in CHOICES]),ensure_ascii=False,indent=2))
 print('Generated',len(entries),'foods;',out.stat().st_size,'bytes')
if __name__=='__main__':build()
