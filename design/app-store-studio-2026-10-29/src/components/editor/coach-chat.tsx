"use client";
import * as React from "react";
import type { ChatPlanCard, ChatThread, Theme } from "@/lib/types";
import { pickText } from "@/lib/locale";
import { MuscleMap } from "./muscle-map";

// Bubbles are laid out at a 1320-wide reference canvas and scaled for other
// canvases, so the same numbers hold for every iPhone export size.
//
// The report block and the routine cards copy the App's own components:
//   - report -> CoachScreen.bodyPhotoFocusMuscles (MuscleVisualBlock 130pt +
//               "Suggested focus" + accent muscle names)
//   - card   -> WorkoutCard with showsExercisePills / compactLayout
//              (10pt heavy kicker + 16pt bold title + 12pt monospaced count +
//               ExercisePill 10/11pt on MasoColor.surfaceHi, radius 16)
// Sizes below are those App points multiplied by the poster's type scale, then
// compressed vertically so the whole photo -> report -> routine story fits one
// screen.
//
// The three generated days sit side by side under the reply — the App shows
// them in a horizontal carousel, but a poster has to prove the whole week at a
// glance, so the same cards are split three ways instead of cropped.
const REF_W = 1320;

function rgba(hex: string, alpha: number) {
  const h = hex.replace("#", "");
  const full = h.length === 3 ? h.split("").map((c) => c + c).join("") : h;
  const n = parseInt(full, 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}

const EYEBROW: Record<string, string> = {
  en: "AI COACH",
  zh: "AI 教练",
  "zh-Hant": "AI 教練",
  ja: "AI コーチ",
  ko: "AI 코치",
  es: "ENTRENADOR IA",
  fr: "COACH IA",
  de: "KI-COACH",
  it: "COACH IA",
  "pt-BR": "COACH IA",
  ru: "ИИ-ТРЕНЕР",
  ar: "المدرب الذكي",
};

/** App's AddToPlansButton label ("Save to routines" in Localizable.strings). */
const SAVE_LABEL: Record<string, string> = {
  en: "Save to workout plans",
  zh: "存入训练计划",
  "zh-Hant": "存入訓練計畫",
  ja: "トレーニングプランに保存",
  ko: "운동 계획에 저장",
  es: "Guardar a los planes de entrenamiento",
  fr: "Enregistrer dans les programmes d’entraînement",
  de: "Auf Trainingspläne speichern",
  it: "Salva nei programmi di allenamento",
  "pt-BR": "Gravar nos planos de treino",
  ru: "Сохранить в планы тренировок",
  ar: "حفظ في خطط التمرين",
};

/** Minimal stand-in for SF Symbol "figure.strengthtraining.traditional". */
function StrengthIcon({ size, color }: { size: number; color: string }) {
  // Barbell silhouette: two plates + bar, drawn to sit on the kicker baseline.
  const u = size / 24;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden style={{ flex: "none" }}>
      <g stroke={color} strokeWidth={2.6 * u} strokeLinecap="round">
        <path d="M6 8.5v7M9.5 6.5v11M14.5 6.5v11M18 8.5v7" />
        <path d="M9.5 12h5" strokeWidth={2.2 * u} />
      </g>
    </svg>
  );
}


/** App's PlanSourceBadge(.ai): sparkles + "AI", accent on an accent-18% capsule. */
function SourceBadge({ k, accent }: { k: number; accent: string }) {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 5 * k,
        fontSize: 21 * k,
        fontWeight: 800,
        letterSpacing: 0.6 * k,
        lineHeight: 1,
        color: accent,
        background: rgba(accent, 0.18),
        border: `${1 * k}px solid ${rgba(accent, 0.45)}`,
        borderRadius: 999,
        padding: `${4 * k}px ${10 * k}px`,
        flex: "none",
      }}
    >
      <svg width={16 * k} height={16 * k} viewBox="0 0 24 24" fill="currentColor" aria-hidden style={{ flex: "none" }}>
        <path d="M12 2l1.9 5.4L19 9.3l-5.1 1.9L12 16.6l-1.9-5.4L5 9.3l5.1-1.9L12 2z" />
        <path d="M18.5 14l.95 2.55L22 17.5l-2.55.95L18.5 21l-.95-2.55L15 17.5l2.55-.95L18.5 14z" opacity="0.85" />
      </svg>
      AI
    </span>
  );
}

/**
 * One generated day of the week, three across — the App's own WorkoutCard, not
 * a look-alike: PlanSourceBadge("AI") beside the DAY kicker, 16pt-bold title
 * with the detail chevron, monospaced "N exercises · M sets", the muscle
 * block, ExercisePill(part + name) chips and the AddToPlansButton that the
 * Coach puts under every generated day (CoachScreen -> PlanCardCarousel ->
 * WorkoutCard with compactLayout, prominentStart: false, addAction = save).
 * The App shows these cards full-width in a carousel; a poster cannot afford
 * three full-height cards, so the anatomy is kept and the width split three
 * ways — every element keeps its App order, only the point sizes are scaled.
 */
function GridPlanCard({
  card,
  k,
  accent,
  locale,
  index,
}: {
  card: ChatPlanCard;
  k: number;
  accent: string;
  locale: string;
  index: number;
}) {
  const pad = 26 * k;
  const kickerIcon = 22 * k;
  const kickerText = 24 * k;
  const titleText = 42 * k;
  const metaText = 26 * k;
  const mapSide = 175 * k;
  const pillText = 20 * k;
  const pillPart = 18 * k;
  // The App renders every pill of the plan (LimitedFlowLayout, no "+N"), so the
  // poster does too; the cap only exists as a guard for longer future plans.
  const maxPills = 6;

  const pills = card.pills.slice(0, maxPills);
  const hidden = card.pills.length - pills.length;

  return (
    <div
      data-chat-plan={index + 1}
      style={{
        flex: "1 1 0",
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        padding: pad,
        borderRadius: 30 * k,
        background: "rgba(255, 255, 255, 0.06)",
        border: `${1.2 * k}px solid rgba(255, 255, 255, 0.10)`,
        backdropFilter: `blur(${16 * k}px)`,
        WebkitBackdropFilter: `blur(${16 * k}px)`,
        boxShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 14px 34px rgba(0, 0, 0, 0.22)",
      }}
    >
      {/* Kicker row — figure.strengthtraining + DAY n, PlanSourceBadge at the end. */}
      <div style={{ display: "flex", alignItems: "center", gap: 7 * k, color: accent, minHeight: 26 * k }}>
        <StrengthIcon size={kickerIcon} color={accent} />
        <span
          style={{
            fontSize: kickerText,
            fontWeight: 800,
            letterSpacing: (2.4 / 24) * kickerText,
            textTransform: "uppercase",
            lineHeight: 1,
            whiteSpace: "nowrap",
          }}
        >
          {pickText(card.kicker, locale)}
        </span>
        <span style={{ marginLeft: "auto", display: "inline-flex" }}>
          <SourceBadge k={k} accent={accent} />
        </span>
      </div>

      {/* Title + detail chevron (WorkoutCard title row). The block always reserves
          two lines: "Chest + Triceps" wraps in English while the CJK titles do not,
          and without the reservation that single wrapped card would push its own
          muscle map 49 px below the other two. */}
      <div style={{ display: "flex", alignItems: "flex-start", gap: 6 * k, marginTop: 12 * k }}>
        <div
          style={{
            flex: 1,
            minWidth: 0,
            fontSize: titleText,
            fontWeight: 700,
            color: "#FFFFFF",
            lineHeight: 1.16,
            minHeight: 2 * titleText * 1.16,
          }}
        >
          {pickText(card.title, locale)}
        </div>
        <svg
          width={22 * k}
          height={22 * k}
          viewBox="0 0 24 24"
          fill="none"
          stroke="rgba(255, 255, 255, 0.42)"
          strokeWidth={2.6}
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden
          style={{ flex: "none", marginTop: 8 * k }}
        >
          <path d="M9 5l7 7-7 7" />
        </svg>
      </div>

      <div
        style={{
          marginTop: 5 * k,
          fontSize: metaText,
          fontWeight: 400,
          color: "#B3B3B3",
          lineHeight: 1.2,
          fontVariantNumeric: "tabular-nums",
        }}
      >
        {pickText(card.meta, locale)}
      </div>

      {/* Muscle block then pills, stacked straight under the counters so all
          three cards share one map band; the App's card grows instead, but a
          poster row has to line its landmarks up. */}
      <div style={{ marginTop: 10 * k, flex: "none" }}>
        <div style={{ height: mapSide, display: "flex", alignItems: "center", justifyContent: "center", flex: "none" }}>
          <MuscleMap muscles={card.muscles} side={mapSide} accent={accent} stroke={0.5 * k} />
        </div>

      {/* ExercisePill: part (accent) + exercise name, on MasoColor.surfaceHi. */}
      <div style={{ display: "flex", flexWrap: "wrap", gap: 7 * k, marginTop: 12 * k }}>
        {pills.map((pill, i) => (
          <span
            key={i}
            style={{
              display: "inline-flex",
              alignItems: "baseline",
              gap: 5 * k,
              background: "#262626",
              borderRadius: 999,
              padding: `${7 * k}px ${12 * k}px`,
              maxWidth: "100%",
              overflow: "hidden",
            }}
          >
            <span
              style={{
                fontSize: pillPart,
                fontWeight: 600,
                color: accent,
                lineHeight: 1.15,
                flex: "none",
              }}
            >
              {pickText(pill.part, locale)}
            </span>
            <span
              style={{
                fontSize: pillText,
                fontWeight: 600,
                color: "rgba(255, 255, 255, 0.9)",
                lineHeight: 1.15,
                minWidth: 0,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {pickText(pill.name, locale)}
            </span>
          </span>
        ))}
        {hidden > 0 && (
          <span
            style={{
              fontSize: pillPart,
              fontWeight: 700,
              color: "rgba(255, 255, 255, 0.55)",
              background: "rgba(38, 38, 38, 0.7)",
              borderRadius: 999,
              padding: `${7 * k}px ${12 * k}px`,
              lineHeight: 1.15,
              whiteSpace: "nowrap",
              fontVariantNumeric: "tabular-nums",
            }}
          >
            +{hidden}
          </span>
        )}
      </div>
      </div>

      {/* addAction pinned to the card's bottom edge, like the App's card footer. */}
      <div style={{ marginTop: "auto", paddingTop: 14 * k, minWidth: 0, maxWidth: "100%" }}>
        <SaveCapsule label={SAVE_LABEL[locale] || SAVE_LABEL.en} k={k} />
      </div>
    </div>
  );
}

/** App's AddToPlansButton at card width: plus glyph + "Save to workout plans". */
function SaveCapsule({ label, k }: { label: string; k: number }) {
  return (
    <span
      data-chat-save="1"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 8 * k,
        width: "100%",
        fontSize: 20 * k,
        fontWeight: 600,
        color: "#FFFFFF",
        background: "#262626",
        border: `${1 * k}px solid rgba(255, 255, 255, 0.10)`,
        borderRadius: 999,
        padding: `${10 * k}px ${12 * k}px`,
        lineHeight: 1.1,
        boxSizing: "border-box",
        minWidth: 0,
        maxWidth: "100%",
        overflow: "hidden",
        textAlign: "center",
        boxShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.10)",
      }}
    >
      <svg
        width={20 * k}
        height={20 * k}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={2.6}
        strokeLinecap="round"
        aria-hidden
        style={{ flex: "none" }}
      >
        <path d="M12 5v14M5 12h14" />
      </svg>
      <span style={{ minWidth: 0, textAlign: "center" }}>{label}</span>
    </span>
  );
}

/** Batch save under the cards — the App's AddToPlansButton pill at poster size. */
function SavePill({ label, k, accent }: { label: string; k: number; accent: string }) {
  return (
    <span
      data-chat-cta="1"
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 14 * k,
        fontSize: 38 * k,
        fontWeight: 700,
        color: "#FFFFFF",
        background: rgba("#FFFFFF", 0.10),
        border: `${1.5 * k}px solid rgba(255, 255, 255, 0.18)`,
        borderRadius: 999,
        padding: `${18 * k}px ${34 * k}px`,
        whiteSpace: "nowrap",
        backdropFilter: `blur(${16 * k}px)`,
        WebkitBackdropFilter: `blur(${16 * k}px)`,
        boxShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.16), 0 12px 30px rgba(0, 0, 0, 0.24)",
      }}
    >
      <svg
        width={30 * k}
        height={30 * k}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={2.6}
        strokeLinecap="round"
        aria-hidden
        style={{ flex: "none" }}
      >
        <path d="M12 5v14M5 12h14" />
      </svg>
      {label}
    </span>
  );
}
export function CoachChat({
  chat,
  cW,
  theme,
  locale,
}: {
  chat: ChatThread;
  cW: number;
  theme: Theme;
  locale: string;
}) {
  const k = cW / REF_W;
  const rtl = locale === "ar" || locale === "he" || locale === "fa";
  const rootRef = React.useRef<HTMLDivElement>(null);
  const innerRef = React.useRef<HTMLDivElement>(null);
  React.useLayoutEffect(() => {
    const root = rootRef.current;
    const inner = innerRef.current;
    if (!root || !inner || !chat.height) return;
    const available = root.clientHeight;
    inner.style.transform = "none";
    inner.style.width = "100%";
    const needed = inner.scrollHeight;
    const next = needed > available + 1 ? Math.max(0.72, available / needed) : 1;
    inner.style.transform = next < 1 ? `scale(${next})` : "none";
    inner.style.transformOrigin = rtl ? "top right" : "top left";
    inner.dataset.chatFit = next.toFixed(3);
  }, [locale, cW, rtl, chat]);
  const accent = theme.accent;

  const body = 52 * k;
  const eyebrow = 24 * k;
  const chipText = 40 * k;
  const ctaText = 44 * k;
  const footText = 36 * k;

  // Message styling copies CoachScreen: the user turn is a right-aligned
  // VStack(alignment: .trailing, spacing: 4) of [body photo, CoachUserTextBubble]
  // — accent text on an accent-12% bubble — while an assistant turn has **no**
  // bubble at all, just leading-aligned text plus its attachments. Dropping the
  // assistant bubble is also what puts the report and the plan cards on the same
  // left edge: both start exactly at the thread's left edge.
  const photoW = 440 * k;
  const photoR = 40 * k;
  const userPadX = 44 * k;
  const userPadY = 30 * k;
  const userRadius = 52 * k;
  const photoGap = 16 * k;

  // Attached-photo grid: the App's CoachUserPhotoGrid shows the front and back
  // shots side by side, cropped to 5:6 portraits.
  const gridPhotoW = 292 * k;
  const gridPhotoH = 355 * k;
  const gridPhotoGap = 14 * k;
  const gridPhotoR = 24 * k;

  // Compact report: label + accent chips, no muscle diagram.
  const focusLabel = 34 * k;
  const focusChip = 38 * k;
  const focusNote = 32 * k;

  // Vertical rhythm. The two pairs that must read as one unit — coach reply ->
  // plan cards, plan cards -> batch save — get the tight end of the scale; the
  // turn change gets the loosest.
  const gapReply = 34 * k;
  const gapPills = 40 * k;
  const gapTurns = 56 * k;

  // Report block (body-photo analysis).
  const reportMap = 320 * k;
  const reportLabel = 32 * k;
  const reportName = 40 * k;
  const reportNote = 32 * k;

  return (
    <div
      ref={rootRef}
      data-chat-root="1"
      dir={rtl ? "rtl" : "ltr"}
      style={{
        position: "absolute",
        left: chat.x * k,
        top: chat.y * k,
        width: chat.width * k,
        height: chat.height ? chat.height * k : undefined,
        overflow: "hidden",
        pointerEvents: "none",
      }}
    >
    <div
      ref={innerRef}
      style={{
        display: "flex",
        flexDirection: "column",
        width: "100%",
        // Leftover height stays below the thread. Do not spread it between blocks.
        justifyContent: "flex-start",
        transformOrigin: rtl ? "top right" : "top left",
      }}
    >
      {chat.bubbles.map((bubble, index) => {
        const isUser = bubble.role === "user";
        const text = pickText(bubble.text, locale);
        const cards = bubble.plans ?? (bubble.plan ? [bubble.plan] : []);
        const photos = bubble.photos ?? (bubble.photo ? [bubble.photo] : []);
        return (
          <React.Fragment key={index}>
            <div
              data-chat-bubble={index}
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: isUser ? "flex-end" : "stretch",
                gap: photoGap,
                marginTop: index === 0 ? 0 : gapTurns,
              }}
            >
              {photos.length > 1 ? (
                <div data-chat-photos="1" style={{ display: "flex", gap: gridPhotoGap, flex: "none" }}>
                  {photos.map((src, i) => (
                    <img
                      key={i}
                      src={src}
                      alt=""
                      draggable={false}
                      style={{
                        width: gridPhotoW,
                        height: gridPhotoH,
                        borderRadius: gridPhotoR,
                        objectFit: "cover",
                        flex: "none",
                        border: "1.5px solid rgba(255, 255, 255, 0.12)",
                      }}
                    />
                  ))}
                </div>
              ) : (
                photos.length === 1 && (
                  <img
                    src={photos[0]}
                    alt=""
                    draggable={false}
                    style={{
                      width: photoW,
                      aspectRatio: "1280 / 728",
                      borderRadius: photoR,
                      objectFit: "cover",
                      flex: "none",
                      border: "1.5px solid rgba(255, 255, 255, 0.12)",
                    }}
                  />
                )
              )}
              <div
                data-chat-message={isUser ? "user" : "assistant"}
                style={{
                  display: "flex",
                  flexDirection: "column",
                  gap: 18 * k,
                  minWidth: 0,
                  maxWidth: "100%",
                  ...(isUser
                    ? {
                        background: rgba(accent, 0.12),
                        borderRadius: userRadius,
                        padding: `${userPadY}px ${userPadX}px`,
                      }
                    : null),
                }}
              >
                {!isUser && (
                  <div
                    style={{
                      fontSize: eyebrow,
                      fontWeight: 800,
                      letterSpacing: 1.5 * k,
                      color: accent,
                      lineHeight: 1,
                    }}
                  >
                    {EYEBROW[locale] || EYEBROW.en}
                  </div>
                )}
                <div
                  style={{
                    fontSize: body,
                    fontWeight: isUser ? 600 : 500,
                    lineHeight: 1.42,
                    color: isUser ? accent : "#E8E8E8",
                    whiteSpace: "pre-line",
                    textAlign: "start",
                  }}
                >
                  {text}
                </div>

                {bubble.subtext && (
                  <div
                    data-chat-subtext="1"
                    style={{
                      fontSize: footText,
                      fontWeight: 600,
                      lineHeight: 1.25,
                      marginTop: -10 * k,
                      color: isUser ? rgba(accent, 0.66) : "rgba(255, 255, 255, 0.58)",
                      fontVariantNumeric: "tabular-nums",
                    }}
                  >
                    {pickText(bubble.subtext, locale)}
                  </div>
                )}

                {bubble.report &&
                  (bubble.report.compact ? (
                    <div
                      data-chat-report="compact"
                      style={{ display: "flex", flexDirection: "column", gap: 14 * k, marginTop: 4 * k }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: 14 * k, flexWrap: "wrap" }}>
                        <span
                          style={{
                            fontSize: focusLabel,
                            fontWeight: 500,
                            color: "rgba(255, 255, 255, 0.62)",
                            letterSpacing: 0.6 * k,
                            lineHeight: 1.2,
                          }}
                        >
                          {pickText(bubble.report.label, locale)}
                        </span>
                        {bubble.report.names.map((name, i) => (
                          <span
                            key={i}
                            style={{
                              display: "inline-flex",
                              alignItems: "center",
                              gap: 10 * k,
                              fontSize: focusChip,
                              fontWeight: 600,
                              color: "#8CF0B0",
                              background: rgba(accent, 0.14),
                              border: `1.5px solid ${rgba(accent, 0.34)}`,
                              borderRadius: 999,
                              padding: `${10 * k}px ${24 * k}px`,
                              whiteSpace: "nowrap",
                            }}
                          >
                            <span
                              style={{
                                width: 12 * k,
                                height: 12 * k,
                                borderRadius: 999,
                                background: accent,
                                flex: "none",
                              }}
                            />
                            {pickText(name, locale)}
                          </span>
                        ))}
                      </div>
                      {bubble.report.note && (
                        <div
                          style={{
                            fontSize: focusNote,
                            fontWeight: 500,
                            color: "rgba(255, 255, 255, 0.34)",
                            lineHeight: 1.4,
                          }}
                        >
                          {pickText(bubble.report.note, locale)}
                        </div>
                      )}
                    </div>
                  ) : (
                    <div
                      data-chat-report="1"
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 30 * k,
                        marginTop: 4 * k,
                      }}
                    >
                      <div style={{ flex: "none" }}>
                        <MuscleMap muscles={bubble.report.muscles} side={reportMap} accent={accent} stroke={0.7 * k} />
                      </div>
                      <div style={{ display: "flex", flexDirection: "column", gap: 10 * k, minWidth: 0 }}>
                        <div
                          style={{
                            fontSize: reportLabel,
                            fontWeight: 600,
                            color: "rgba(255, 255, 255, 0.62)",
                            lineHeight: 1.2,
                          }}
                        >
                          {pickText(bubble.report.label, locale)}
                        </div>
                        <div style={{ display: "flex", flexDirection: "column" }}>
                          {bubble.report.names.map((name, i) => (
                            <span
                              key={i}
                              style={{
                                fontSize: reportName,
                                fontWeight: 600,
                                color: accent,
                                lineHeight: 1.3,
                              }}
                            >
                              {pickText(name, locale)}
                            </span>
                          ))}
                        </div>
                        {bubble.report.note && (
                          <div
                            style={{
                              fontSize: reportNote,
                              fontWeight: 500,
                              color: "rgba(255, 255, 255, 0.58)",
                              lineHeight: 1.35,
                              marginTop: 2 * k,
                            }}
                          >
                            {pickText(bubble.report.note, locale)}
                          </div>
                        )}
                      </div>
                    </div>
                  ))}

                {!!bubble.chips?.length && (
                  <div style={{ display: "flex", flexWrap: "wrap", gap: 14 * k, marginTop: 6 * k }}>
                    {bubble.chips.map((chip, i) => (
                      <span
                        key={i}
                        style={{
                          fontSize: chipText,
                          fontWeight: 700,
                          color: "#B8F5CE",
                          background: rgba(accent, 0.14),
                          border: `1.5px solid ${rgba(accent, 0.32)}`,
                          borderRadius: 999,
                          padding: `${8 * k}px ${20 * k}px`,
                          whiteSpace: "nowrap",
                        }}
                      >
                        {pickText(chip, locale)}
                      </span>
                    ))}
                  </div>
                )}
                {bubble.cta && !bubble.ctaAfterCards && (
                  <div style={{ marginTop: 10 * k }}>
                    <span
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        fontSize: ctaText,
                        fontWeight: 800,
                        color: "#0B0B0B",
                        background: accent,
                        borderRadius: 999,
                        padding: `${14 * k}px ${34 * k}px`,
                        whiteSpace: "nowrap",
                      }}
                    >
                      {pickText(bubble.cta, locale)}
                    </span>
                  </div>
                )}
              </div>
            </div>

            {/* The generated days, side by side — the App's WorkoutCard anatomy
                (kicker + AI badge, title, monospaced count, muscle map,
                ExercisePill row, AddToPlansButton) split three ways. */}
            {!!cards.length && (
              <div
                data-chat-plan-grid="1"
                style={{
                  alignSelf: "stretch",
                  marginTop: gapReply,
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "stretch",
                  gap: 22 * k,
                }}
              >
                {cards.map((card, i) => (
                  <GridPlanCard key={i} card={card} k={k} accent={accent} locale={locale} index={i} />
                ))}
              </div>
            )}
            {/* Saving the batch is the App's AddToPlansButton: it sits under the
                last routine card, not inside the message bubble. */}
            {bubble.ctaAfterCards && bubble.cta && (
              <div data-chat-cta-row="1" style={{ alignSelf: "flex-start", marginTop: gapPills }}>
                <SavePill label={pickText(bubble.cta, locale)} k={k} accent={accent} />
              </div>
            )}
          </React.Fragment>
        );
      })}

      {!!chat.footnotes?.length && (
        <div
          data-chat-footnotes="1"
          style={{
            display: "flex",
            flexWrap: "wrap",
            justifyContent: "flex-start",
            gap: 16 * k,
            paddingTop: gapPills,
          }}
        >
          {chat.footnotes.map((note, i) => (
            <span
              key={i}
              style={{
                fontSize: footText,
                fontWeight: 700,
                color: "rgba(255, 255, 255, 0.62)",
                background: "rgba(255, 255, 255, 0.05)",
                border: "1.5px solid rgba(255, 255, 255, 0.10)",
                borderRadius: 999,
                padding: `${10 * k}px ${24 * k}px`,
                whiteSpace: "nowrap",
              }}
            >
              {pickText(note, locale)}
            </span>
          ))}
        </div>
      )}
    </div>
    </div>
  );
}
