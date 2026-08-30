/**
 * A DER reader scoped to one job: pulling the App Attest nonce out of the
 * credential certificate's `1.2.840.113635.100.8.2` extension, whose value is
 *
 *   SEQUENCE { [1] { OCTET STRING nonce } }
 *
 * Certificate parsing and signature verification are `node:crypto`'s job; this
 * only reaches into the extension body.
 */

export type DerNode = {
  tag: number;
  /** Body only, without tag and length. */
  content: Uint8Array;
};

export function readDer(bytes: Uint8Array, offset = 0): { node: DerNode; end: number } {
  if (offset + 2 > bytes.length) throw new Error("der: truncated");
  const tag = bytes[offset]!;
  let cursor = offset + 1;
  const first = bytes[cursor]!;
  cursor += 1;

  let length: number;
  if (first < 0x80) {
    length = first;
  } else {
    const count = first & 0x7f;
    if (count === 0 || count > 4) throw new Error("der: unsupported length");
    length = 0;
    for (let index = 0; index < count; index += 1) {
      length = (length << 8) | bytes[cursor]!;
      cursor += 1;
    }
  }

  const end = cursor + length;
  if (end > bytes.length) throw new Error("der: length exceeds input");
  return { node: { tag, content: bytes.subarray(cursor, end) }, end };
}

/** Walks `SEQUENCE { [1] { OCTET STRING } }` and returns the octet string. */
export function nonceFromExtension(extension: Uint8Array): Uint8Array {
  const { node: sequence } = readDer(extension);
  if (sequence.tag !== 0x30) throw new Error("der: expected SEQUENCE");

  const { node: context } = readDer(sequence.content);
  // Context-specific, constructed, tag number 1.
  if (context.tag !== 0xa1) throw new Error("der: expected [1]");

  const { node: octets } = readDer(context.content);
  if (octets.tag !== 0x04) throw new Error("der: expected OCTET STRING");
  return octets.content;
}
