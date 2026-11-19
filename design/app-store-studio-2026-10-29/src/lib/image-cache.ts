"use client";
// Pre-loads images as base64 data URIs so html-to-image exports without
// non-deterministic image fetch races. Always use img(path) in render.

const cache = new Map<string, string>();
const failed = new Set<string>();

async function fetchAsDataUrl(path: string): Promise<string | null> {
  try {
    const resp = await fetch(path, { signal: AbortSignal.timeout(20000) });
    if (!resp.ok) return null;
    const blob = await resp.blob();
    return await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

export async function preloadImages(
  paths: string[],
  options: { retryFailed?: boolean } = {},
): Promise<void> {
  const pending = paths.filter(Boolean)
    .filter((p) => !cache.has(p) && (options.retryFailed || !failed.has(p)));
  // Keep bulk localized exports from decoding hundreds of full-resolution
  // captures concurrently on the 16 GB editing machine.
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(6, pending.length) }, async () => {
    while (next < pending.length) {
      const path = pending[next++];
      const data = await fetchAsDataUrl(path);
      if (data) {
        cache.set(path, data);
        failed.delete(path);
      } else {
        failed.add(path);
      }
    }
  }));
}

export function img(path: string | undefined): string {
  if (!path) return "";
  if (path.startsWith("data:")) return path;
  if (failed.has(path)) return "";
  return cache.get(path) || path;
}

export function setImage(path: string, dataUrl: string) {
  cache.set(path, dataUrl);
  failed.delete(path);
}

export function didFail(path: string | undefined): boolean {
  if (!path) return false;
  if (path.startsWith("data:")) return false;
  return failed.has(path);
}
