/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  outputFileTracingRoot: process.cwd(),
  // The circular "N" on exported posters was Next's dev indicator, painted
  // over the full-bleed /render route. Production has none; this also keeps
  // `next dev` captures clean.
  devIndicators: false,
};

export default nextConfig;
