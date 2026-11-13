"use client";
import * as React from "react";

/** Candidate-only scope; canonical headlines keep their existing accent phrases. */
export const CandidateHeadlineScope = React.createContext(false);
export function candidateHeadlinePhrase(enabled:boolean,id:string,locale:string,text:string):string|undefined {
  if (!enabled || id !== "recovery" || locale !== "en") return undefined;
  return text.match(/muscle\s+recovery/i)?.[0];
}
