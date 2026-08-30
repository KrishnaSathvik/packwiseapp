import { createHmac } from "node:crypto";

/**
 * PackWise has no accounts, so the provider-facing identifier is install-scoped
 * rather than a user identity system.
 *
 *   random install identifier   (generated and persisted on device)
 *         ↓ sent as safetyIdentifier
 *   HMAC-SHA256 with a server secret
 *         ↓
 *   safety_identifier sent to the provider
 *
 * The HMAC means the raw install token — and later, the App Attest key ID —
 * never leaves the server. It gives abuse correlation without attaching
 * anything personal.
 */
export function deriveSafetyIdentifier(installIdentifier: string, secret: string): string {
  if (secret.length === 0) {
    throw new Error("safety identifier secret must not be empty");
  }
  return createHmac("sha256", secret).update(installIdentifier).digest("base64url").slice(0, 43);
}
