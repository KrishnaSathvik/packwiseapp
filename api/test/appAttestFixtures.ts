import {
  createHash,
  createSign,
  generateKeyPairSync,
  type KeyObject,
} from "node:crypto";

import { encodeOID } from "../src/integrity/appAttest.ts";

/**
 * Mints a synthetic App Attest chain: a root CA, a credential certificate
 * carrying the attestation nonce extension, and CBOR attestation/assertion
 * objects signed by real P-256 keys.
 *
 * This exercises the verifier's actual cryptography — chain verification,
 * nonce binding, key-ID derivation, signature checking — against a root we
 * control. It proves the protocol is implemented correctly. It does not prove
 * Apple accepts a real attestation; that stays a signed-device verification.
 */

const NONCE_EXTENSION_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = "appattest\0\0\0\0\0\0\0";
const AAGUID_DEVELOPMENT = "appattestdevelop";

// ---------------------------------------------------------------- DER writing

function length(value: number): number[] {
  if (value < 0x80) return [value];
  const bytes: number[] = [];
  let remaining = value;
  while (remaining > 0) {
    bytes.unshift(remaining & 0xff);
    remaining >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

function tlv(tag: number, content: Uint8Array | number[]): Uint8Array {
  const body = Uint8Array.from(content);
  return Uint8Array.from([tag, ...length(body.length), ...body]);
}

function sequence(...parts: Uint8Array[]): Uint8Array {
  return tlv(0x30, concat(...parts));
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function integer(value: number): Uint8Array {
  const bytes = [value & 0xff];
  return tlv(0x02, bytes[0]! >= 0x80 ? [0x00, ...bytes] : bytes);
}

function utcTime(date: Date): Uint8Array {
  const text = date.toISOString().replace(/[-:T]/g, "").slice(2, 14) + "Z";
  return tlv(0x17, [...Buffer.from(text, "ascii")]);
}

function commonName(name: string): Uint8Array {
  return sequence(
    tlv(0x31, sequence(encodeOID("2.5.4.3"), tlv(0x0c, [...Buffer.from(name, "utf8")]))),
  );
}

const ECDSA_SHA256 = sequence(encodeOID("1.2.840.10045.4.3.2"));

function bitString(content: Uint8Array): Uint8Array {
  return tlv(0x03, concat(Uint8Array.from([0x00]), content));
}

/** A minimal but structurally valid X.509 v3 certificate. */
function certificate(options: {
  serial: number;
  subject: string;
  issuer: string;
  subjectKey: KeyObject;
  issuerKey: KeyObject;
  isCA: boolean;
  nonceExtension?: Uint8Array;
}): Buffer {
  const spki = new Uint8Array(options.subjectKey.export({ type: "spki", format: "der" }));

  const extensions: Uint8Array[] = [];
  if (options.isCA) {
    extensions.push(
      sequence(
        encodeOID("2.5.29.19"),
        tlv(0x01, [0xff]),
        tlv(0x04, sequence(tlv(0x01, [0xff]))),
      ),
    );
  }
  if (options.nonceExtension) {
    extensions.push(
      sequence(
        encodeOID(NONCE_EXTENSION_OID),
        tlv(0x04, sequence(tlv(0xa1, tlv(0x04, options.nonceExtension)))),
      ),
    );
  }

  const tbs = sequence(
    tlv(0xa0, tlv(0x02, [0x02])), // version v3
    integer(options.serial),
    ECDSA_SHA256,
    commonName(options.issuer),
    sequence(utcTime(new Date(Date.now() - 86_400_000)), utcTime(new Date(Date.now() + 86_400_000))),
    commonName(options.subject),
    spki,
    ...(extensions.length > 0 ? [tlv(0xa3, sequence(...extensions))] : []),
  );

  const signer = createSign("SHA256");
  signer.update(Buffer.from(tbs));
  signer.end();
  const signature = signer.sign(options.issuerKey);

  return Buffer.from(sequence(tbs, ECDSA_SHA256, bitString(new Uint8Array(signature))));
}

function pem(der: Buffer): string {
  const body = der.toString("base64").match(/.{1,64}/g)?.join("\n") ?? "";
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----\n`;
}

// ---------------------------------------------------------------- CBOR writing

function cborLength(major: number, value: number): number[] {
  if (value < 24) return [(major << 5) | value];
  if (value < 0x100) return [(major << 5) | 24, value];
  if (value < 0x10000) return [(major << 5) | 25, value >> 8, value & 0xff];
  return [(major << 5) | 26, (value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

function cborBytes(value: Uint8Array): Uint8Array {
  return Uint8Array.from([...cborLength(2, value.length), ...value]);
}

function cborText(value: string): Uint8Array {
  const encoded = Buffer.from(value, "utf8");
  return Uint8Array.from([...cborLength(3, encoded.length), ...encoded]);
}

function cborArray(items: Uint8Array[]): Uint8Array {
  return concat(Uint8Array.from(cborLength(4, items.length)), ...items);
}

function cborMap(entries: [string, Uint8Array][]): Uint8Array {
  return concat(
    Uint8Array.from(cborLength(5, entries.length)),
    ...entries.flatMap(([key, value]) => [cborText(key), value]),
  );
}

// ------------------------------------------------------------------- fixtures

export const TEST_APP_ID = "ABCDE12345.com.packwise.app";

export function authenticatorData(options: {
  appID: string;
  counter: number;
  aaguid?: string;
  credentialID?: Uint8Array;
}): Uint8Array {
  const header = new Uint8Array(37);
  header.set(createHash("sha256").update(options.appID, "utf8").digest(), 0);
  header[32] = 0x40;
  new DataView(header.buffer).setUint32(33, options.counter);
  if (!options.aaguid || !options.credentialID) return header;

  const credentialLength = new Uint8Array(2);
  new DataView(credentialLength.buffer).setUint16(0, options.credentialID.length);
  return concat(
    header,
    Uint8Array.from(Buffer.from(options.aaguid, "latin1")),
    credentialLength,
    options.credentialID,
  );
}

export type AttestFixture = {
  rootPEM: string;
  appID: string;
  keyID: string;
  attestation: string;
  challenge: string;
  credentialKey: KeyObject;
  /** Signs a request body the way the device would. */
  assertion(options: { body: unknown; counter: number; appID?: string }): string;
};

function keyIdentifier(publicKey: KeyObject): string {
  const spki = publicKey.export({ type: "spki", format: "der" });
  return createHash("sha256").update(spki.subarray(spki.length - 65)).digest("base64");
}

export type TestRoot = ReturnType<typeof makeRoot>;

/**
 * A root CA that several fixtures can share. Without this every fixture mints
 * its own root, and the verifier — correctly — rejects on the chain before it
 * ever reaches the check under test.
 */
export function makeRoot() {
  return generateKeyPairSync("ec", { namedCurve: "prime256v1" });
}

export function makeAttestFixture(
  options: {
    appID?: string;
    challenge?: string;
    environment?: "development" | "production";
    root?: TestRoot;
  } = {},
): AttestFixture {
  const appID = options.appID ?? TEST_APP_ID;
  const challenge = options.challenge ?? "challenge-fixture-0001";
  const environment = options.environment ?? "production";

  const root = options.root ?? makeRoot();
  const credential = generateKeyPairSync("ec", { namedCurve: "prime256v1" });

  const keyID = keyIdentifier(credential.publicKey);
  const credentialID = Buffer.from(keyID, "base64");

  const authData = authenticatorData({
    appID,
    counter: 0,
    aaguid: environment === "production" ? AAGUID_PRODUCTION : AAGUID_DEVELOPMENT,
    credentialID,
  });

  const nonce = createHash("sha256")
    .update(authData)
    .update(createHash("sha256").update(challenge, "utf8").digest())
    .digest();

  const rootCert = certificate({
    serial: 1,
    subject: "PackWise Test Root",
    issuer: "PackWise Test Root",
    subjectKey: root.publicKey,
    issuerKey: root.privateKey,
    isCA: true,
  });

  const credentialCert = certificate({
    serial: 2,
    subject: "PackWise Test Credential",
    issuer: "PackWise Test Root",
    subjectKey: credential.publicKey,
    issuerKey: root.privateKey,
    isCA: false,
    nonceExtension: new Uint8Array(nonce),
  });

  const attestation = Buffer.from(
    cborMap([
      ["fmt", cborText("apple-appattest")],
      ["attStmt", cborMap([["x5c", cborArray([cborBytes(new Uint8Array(credentialCert))])]])],
      ["authData", cborBytes(authData)],
    ]),
  ).toString("base64");

  return {
    rootPEM: pem(rootCert),
    appID,
    keyID,
    attestation,
    challenge,
    credentialKey: credential.privateKey,
    assertion({ body, counter, appID: overrideAppID }) {
      const data = authenticatorData({ appID: overrideAppID ?? appID, counter });
      const clientData = Buffer.from(JSON.stringify(body ?? {}), "utf8");
      const payload = createHash("sha256")
        .update(data)
        .update(createHash("sha256").update(clientData).digest())
        .digest();

      const signer = createSign("SHA256");
      signer.update(payload);
      signer.end();
      const signature = signer.sign(credential.privateKey);

      return Buffer.from(
        cborMap([
          ["signature", cborBytes(new Uint8Array(signature))],
          ["authenticatorData", cborBytes(data)],
        ]),
      ).toString("base64");
    },
  };
}
