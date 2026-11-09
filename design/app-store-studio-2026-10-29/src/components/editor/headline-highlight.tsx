import * as React from "react";
// Accent phrase per slide per locale. Every value MUST be an exact substring of
// that locale's headline (scripts/check-headline-highlights.mjs enforces this);
// a locale with no entry renders the headline in plain foreground colour.
//
// ko/es/fr/de/it/pt-BR/ru/ar phrases match the draft copy in
// app-store-screenshots.json. They are for owner review. approvedLocales is
// still only zh / zh-Hant / en / ja.
const highlights: Record<string, Record<string, string>> = {
  plan: {
    en: "One photo",
    zh: "一张照片",
    "zh-Hant": "一張照片",
    ja: "写真1枚",
    ko: "사진 한 장",
    es: "Una foto",
    fr: "Une photo",
    de: "Ein Foto",
    it: "Una foto",
    "pt-BR": "Uma foto",
    ru: "Одно фото",
    ar: "صورة واحدة",
  },
  recovery: {
    en: "recovered",
    zh: "一眼看清",
    "zh-Hant": "一眼看清",
    ja: "ひと目でわかる",
    ko: "한눈에",
    es: "de un vistazo",
    fr: "d'un coup d'œil",
    de: "auf einen Blick",
    it: "a colpo d'occhio",
    "pt-BR": "num relance",
    ru: "с одного взгляда",
    ar: "بنظرة",
  },
  training: {
    en: "You'll know",
    zh: "立刻提醒",
    "zh-Hant": "立刻提醒",
    ja: "すぐ知らせる",
    ko: "바로 알려",
    es: "Lo vas a ver",
    fr: "Vous le voyez",
    de: "Du siehst es",
    it: "Lo vedi subito",
    "pt-BR": "Você vê na hora",
    ru: "Вы это увидите",
    ar: "ستعرف فورًا",
  },
  diet: {
    en: "Nutrition and sleep",
    zh: "饮食与睡眠",
    "zh-Hant": "飲食與睡眠",
    ja: "食事と睡眠",
    ko: "식단과 수면",
    es: "sueño",
    fr: "sommeil",
    de: "Schlaf",
    it: "sonno",
    "pt-BR": "sono",
    ru: "сон",
    ar: "النوم",
  },
  devices: {
    en: "One app",
    zh: "一个 App",
    "zh-Hant": "一個 App",
    ja: "同じ App",
    ko: "같은 App",
    es: "una sola app",
    fr: "une seule app",
    de: "eine App",
    it: "una sola app",
    "pt-BR": "um só app",
    ru: "одно приложение",
    ar: "تطبيق واحد",
  },
  watch: {
    en: "your wrist",
    zh: "抬腕",
    "zh-Hant": "抬腕",
    ja: "手首から",
    ko: "손목에서",
    es: "desde la muñeca",
    fr: "au poignet",
    de: "am Handgelenk",
    it: "dal polso",
    "pt-BR": "no pulso",
    ru: "с запястья",
    ar: "من معصمك",
  },
};

export function HighlightedHeadline({ id, locale, text }: { id: string; locale: string; text: string }) {
  const word = highlights[id]?.[locale];
  const at = word ? text.toLocaleLowerCase().indexOf(word.toLocaleLowerCase()) : -1;
  if (at < 0 || !word) return <>{text}</>;
  return (
    <>
      {text.slice(0, at)}
      <span style={{ color: "#1ED760" }}>{text.slice(at, at + word.length)}</span>
      {text.slice(at + word.length)}
    </>
  );
}
