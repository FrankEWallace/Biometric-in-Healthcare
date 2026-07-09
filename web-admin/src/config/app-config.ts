import packageJson from "../../package.json";

const currentYear = new Date().getFullYear();

export const APP_CONFIG = {
  name: "Sovereign Security Admin",
  version: packageJson.version,
  copyright: `© ${currentYear}, Sovereign Security.`,
  meta: {
    title: "Sovereign Security — Admin Dashboard",
    description:
      "Staff, patient visit, and audit administration for the Sovereign Security fingerprint patient identification system.",
  },
};
