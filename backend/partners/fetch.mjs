// Apple uses node-fetch's buffer() for OCSP. Keep online revocation checks intact.
export default async function runtimeFetch(input, init) {
    const url = new URL(input);
    const response = await globalThis.fetch(url, {...init, signal: init?.signal ?? AbortSignal.timeout(30000)});
    if (!response.ok) console.error("partner_upstream_status",new URL(input).hostname,response.status);
    return {
        ok: response.ok, status: response.status, statusText: response.statusText,
        headers: response.headers, url: response.url,
        json: () => response.json(), text: () => response.text(),
        arrayBuffer: () => response.arrayBuffer(),
        buffer: async () => Buffer.from(await response.arrayBuffer())
    };
}
export const Headers = globalThis.Headers;
export const Request = globalThis.Request;
export const Response = globalThis.Response;
