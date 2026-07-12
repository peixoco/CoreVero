import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // O @corevero/core é TypeScript puro sem build próprio — o Next transpila-o.
  transpilePackages: ["@corevero/core"],
};

export default nextConfig;
