import * as React from 'react';
import { GlassAnnotation } from './training-callouts';
const text:Record<string,[string,string,string]>={
 zh:['AI Coach 根据你的身体数据制定训练计划','查看重量与训练次数的进步','每一餐，帮你分析热量与营养成分'],
 'zh-Hant':['AI Coach 根據你的身體資料制定訓練計畫','查看重量與訓練次數的進步','每一餐，幫你分析熱量與營養成分'],
 en:['AI Coach builds your plan around your body','See your progress in weight and reps','Analyze calories and nutrients in every meal'],
 ja:['AI コーチが身体データに合うプランを作成','重量と回数の進歩を確認','毎食のカロリーと栄養素を分析'],
 ko:['AI 코치가 신체 데이터에 맞는 계획을 만들어요','중량과 반복 횟수의 성장을 확인하세요','매 끼니의 칼로리와 영양소를 분석하세요'],
 es:['Tu entrenador de IA adapta el plan a tu cuerpo','Consulta tus avances en peso y repeticiones','Analiza calorías y nutrientes de cada comida'],
 fr:['Votre coach IA adapte le programme à votre corps','Suivez vos progrès en charge et répétitions','Analysez les calories et nutriments de chaque repas'],
 de:['Dein KI-Coach plant passend zu deinen Körperdaten','Sieh deine Fortschritte bei Gewicht und Wiederholungen','Analysiere Kalorien und Nährstoffe jeder Mahlzeit'],
 it:['Il coach IA adatta il piano ai tuoi dati fisici','Segui i progressi di peso e ripetizioni','Analizza calorie e nutrienti di ogni pasto'],
 'pt-BR':['Seu coach de IA adapta o plano ao seu corpo','Veja seu progresso em carga e repetições','Analise calorias e nutrientes de cada refeição'],
 ru:['ИИ-план с учётом данных тела','Следите за прогрессом в весе и повторениях','Анализ калорий и нутриентов каждого блюда'],
 ar:['مدربك الذكي يضع خطة تناسب بيانات جسمك','تابع تقدمك في الأوزان والتكرارات','حلّل السعرات والعناصر الغذائية في كل وجبة']};
export function PageAnnotations({id,locale,screenX,cW}:{id:string;locale:string;screenX:number;cW:number}) {
 const copy=text[locale]||text.en, scale=cW/1320;
 if(id==='photo')return <GlassAnnotation text={copy[0]} locale={locale} screenX={screenX} scale={scale} x={80} y={1510} width={1160}/>;
 if(id==='library')return <GlassAnnotation text={copy[1]} locale={locale} screenX={screenX} scale={scale} x={80} y={2070} width={1160} above/>;
 if(id==='diet')return <GlassAnnotation text={copy[2]} locale={locale} screenX={screenX} scale={scale} x={80} y={1980} width={1160} above/>;
 return null;
}
