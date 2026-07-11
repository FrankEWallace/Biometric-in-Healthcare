/** @type {import('next').NextConfig} */
const nextConfig = {
  // Emit a self-contained server bundle (.next/standalone) so the production
  // Docker image can run without the full node_modules tree.
  output: "standalone",
  compiler: {
    removeConsole: process.env.NODE_ENV === "production",
  },
  // Allows dev-mode access (HMR, RSC navigation) from this LAN IP, needed
  // since the dashboard is also reached from other devices on the network.
  allowedDevOrigins: ["192.168.100.194"],
};

export default nextConfig;
